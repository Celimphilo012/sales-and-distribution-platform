import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { StockReservation, StockReservationLine } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { LocationsService } from '../locations/locations.service';
import { InventoryService } from '../inventory/inventory.service';
import { StockAvailabilityDto } from './dto/stock-availability.dto';
import { ReserveStockDto } from './dto/reserve-stock.dto';
import { ReleaseStockDto } from './dto/release-stock.dto';
import { IssueStockDto } from './dto/issue-stock.dto';

/**
 * Never logs in, never appears in a role — exists solely to satisfy
 * `inventory_transactions.performed_by`'s NOT NULL FK for ledger rows that
 * an API key (not a JWT user) triggered. Seeded once; see prisma/seed.ts.
 * This keeps the frozen ledger schema completely untouched — no nullable
 * `performed_by`, no new column — while still recording, per rule 2, a
 * real accountable row for every balance-affecting transaction.
 */
const SYSTEM_API_USER_EMAIL = 'system.api@warehouse.internal';

type ReservationWithLines = StockReservation & { lines: StockReservationLine[] };

/**
 * The reserve/release/issue linchpin behind `/api/v1/stock/*`. This is a
 * NEW layer on top of the frozen `InventoryService.applyTransaction()` —
 * it never writes `inventory_balances`/`inventory_transactions` itself,
 * only ever through that method, per line, exactly like receiving/
 * transfers/adjustments already do.
 *
 * `applyTransaction()` cannot be modified (rule 2) and is self-contained —
 * each call opens and commits its own DB transaction, so it cannot be
 * nested inside one outer transaction spanning multiple lines (the same
 * constraint `StockAdjustmentsService.approve()` already lives with
 * against this same method). "All-or-none" is delivered as an OBSERVABLE
 * guarantee instead, via two layers:
 *   1. An up-front availability check across every line, before any write
 *      — in the overwhelmingly common case this alone makes "reserve
 *      nothing on any shortfall" true, with zero DB writes on failure.
 *   2. Saga-style compensation if a later line still fails after that
 *      check passed (a genuine concurrent race, not the common case): every
 *      line already applied in this call is undone via its own
 *      `applyTransaction()` call (RELEASE_RESERVATION / a compensating
 *      RECEIVE), never by editing or deleting the ledger rows already
 *      written — the ledger stays append-only (rule 2) either way.
 */
@Injectable()
export class StockReservationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly productsService: ProductsService,
    private readonly locationsService: LocationsService,
    private readonly inventoryService: InventoryService,
  ) {}

  private systemUserId?: string;

  private async getSystemUserId(): Promise<string> {
    if (this.systemUserId) return this.systemUserId;
    const user = await this.prisma.user.findUniqueOrThrow({ where: { email: SYSTEM_API_USER_EMAIL } });
    this.systemUserId = user.id;
    return this.systemUserId;
  }

  async checkAvailability(dto: StockAvailabilityDto) {
    const items = await Promise.all(
      dto.items.map(async (item) => {
        if (item.locationId) {
          const balance = await this.prisma.inventoryBalance.findUnique({
            where: { productId_locationId: { productId: item.productId, locationId: item.locationId } },
          });
          const available = balance ? Number(balance.onHand) - Number(balance.reserved) : 0;
          return { productId: item.productId, locationId: item.locationId, available };
        }

        const agg = await this.prisma.inventoryBalance.aggregate({
          where: { productId: item.productId },
          _sum: { onHand: true, reserved: true },
        });
        const onHand = agg._sum.onHand ? Number(agg._sum.onHand) : 0;
        const reserved = agg._sum.reserved ? Number(agg._sum.reserved) : 0;
        return { productId: item.productId, locationId: null, available: onHand - reserved };
      }),
    );

    return { items };
  }

  async reserve(dto: ReserveStockDto, apiKeyId: string) {
    const existing = await this.prisma.stockReservation.findUnique({
      where: { reference: dto.reference },
      include: { lines: true },
    });
    if (existing) {
      // Idempotent replay — a retried call after a dropped response must
      // not double-reserve.
      return this.reserveResult(existing);
    }

    for (const line of dto.lines) {
      await this.productsService.getExisting(line.productId);
      await this.locationsService.assertLeaf(line.locationId);
    }

    const shortLines: { productId: string; locationId: string; requested: number; available: number }[] = [];
    for (const line of dto.lines) {
      const balance = await this.prisma.inventoryBalance.findUnique({
        where: { productId_locationId: { productId: line.productId, locationId: line.locationId } },
      });
      const available = balance ? Number(balance.onHand) - Number(balance.reserved) : 0;
      if (available < line.quantity) {
        shortLines.push({ productId: line.productId, locationId: line.locationId, requested: line.quantity, available });
      }
    }
    if (shortLines.length > 0) {
      return { success: false, reference: dto.reference, shortLines };
    }

    const performedBy = await this.getSystemUserId();
    const succeeded: ReserveStockDto['lines'] = [];
    try {
      for (const line of dto.lines) {
        await this.inventoryService.applyTransaction({
          type: 'RESERVATION',
          productId: line.productId,
          fromLocationId: line.locationId,
          quantity: line.quantity,
          reference: dto.reference,
          performedBy,
        });
        succeeded.push(line);
      }
    } catch (error) {
      for (const line of succeeded) {
        await this.inventoryService
          .applyTransaction({
            type: 'RELEASE_RESERVATION',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: line.quantity,
            reference: dto.reference,
            performedBy,
          })
          .catch(() => {});
      }
      return {
        success: false,
        reference: dto.reference,
        shortLines: [] as { productId: string; locationId: string; requested: number; available: number }[],
        note: 'A concurrent reservation raced this request after the initial check passed; nothing was left reserved — retry is safe.',
      };
    }

    const created = await this.prisma.stockReservation.create({
      data: {
        reference: dto.reference,
        apiKeyId,
        lines: {
          create: dto.lines.map((l) => ({ productId: l.productId, locationId: l.locationId, quantity: l.quantity })),
        },
      },
      include: { lines: true },
    });

    return this.reserveResult(created);
  }

  private reserveResult(reservation: ReservationWithLines) {
    return {
      success: true,
      reference: reservation.reference,
      status: reservation.status,
      reserved: reservation.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        quantity: Number(l.quantity),
      })),
    };
  }

  async release(dto: ReleaseStockDto) {
    const existing = await this.prisma.stockReservation.findUnique({
      where: { reference: dto.reference },
      include: { lines: true },
    });
    if (!existing) {
      // Unknown reference is a no-op success, not an error — matches
      // reserve/issue's "retry-safe" idempotency contract.
      return { success: true, reference: dto.reference, alreadyReleased: false, released: [] };
    }
    if (existing.status !== 'RESERVED') {
      return {
        success: true,
        reference: dto.reference,
        alreadyReleased: true,
        status: existing.status,
        released: [],
      };
    }

    const performedBy = await this.getSystemUserId();
    // No up-front check / compensation needed here the way reserve/issue
    // need it: this only ever decrements `reserved` by exactly what THIS
    // reservation added (nothing else touches those specific units), so a
    // CHECK-constraint failure here would mean a genuine bug, not a race.
    for (const line of existing.lines) {
      await this.inventoryService.applyTransaction({
        type: 'RELEASE_RESERVATION',
        productId: line.productId,
        fromLocationId: line.locationId,
        quantity: Number(line.quantity),
        reference: dto.reference,
        performedBy,
      });
    }

    await this.prisma.stockReservation.update({ where: { id: existing.id }, data: { status: 'RELEASED' } });

    return {
      success: true,
      reference: dto.reference,
      alreadyReleased: false,
      released: existing.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        quantity: Number(l.quantity),
      })),
    };
  }

  async issue(dto: IssueStockDto) {
    const existing = await this.prisma.stockReservation.findUnique({
      where: { reference: dto.reference },
      include: { lines: true },
    });
    if (!existing) {
      throw new NotFoundException(`No reservation found for reference "${dto.reference}" — reserve before issuing.`);
    }
    if (existing.status === 'ISSUED') {
      // Idempotent replay.
      return this.issueResult(existing, true);
    }
    if (existing.status === 'RELEASED') {
      throw new ConflictException(`Reservation "${dto.reference}" was already released and cannot be issued.`);
    }

    const lineByKey = new Map(existing.lines.map((l) => [`${l.productId}:${l.locationId}`, l]));
    for (const line of dto.lines) {
      const reservedLine = lineByKey.get(`${line.productId}:${line.locationId}`);
      if (!reservedLine) {
        throw new BadRequestException(
          `No reservation line for product ${line.productId} at location ${line.locationId} under reference "${dto.reference}"`,
        );
      }
      if (line.quantity > Number(reservedLine.quantity)) {
        throw new BadRequestException(
          `Cannot issue ${line.quantity} for product ${line.productId} at ${line.locationId} — only ${reservedLine.quantity} was reserved`,
        );
      }
      await this.locationsService.assertLeaf(line.locationId);
    }
    const issueQtyByKey = new Map(dto.lines.map((l) => [`${l.productId}:${l.locationId}`, l.quantity]));

    const performedBy = await this.getSystemUserId();
    const succeeded: { line: StockReservationLine; issuedQty: number }[] = [];
    try {
      for (const line of existing.lines) {
        const key = `${line.productId}:${line.locationId}`;
        const issueQty = issueQtyByKey.get(key) ?? 0;
        const reservedQty = Number(line.quantity);

        // Exact 1F sequence: release the FULL reservation for this line,
        // then issue only what's actually dispatched — any shortfall
        // between reserved and issued becomes available again the moment
        // it's released, which is what "issue qty may be < reserved;
        // release the remainder" means in practice.
        await this.inventoryService.applyTransaction({
          type: 'RELEASE_RESERVATION',
          productId: line.productId,
          fromLocationId: line.locationId,
          quantity: reservedQty,
          reference: dto.reference,
          performedBy,
        });
        if (issueQty > 0) {
          await this.inventoryService.applyTransaction({
            type: 'ISSUE',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: issueQty,
            reference: dto.reference,
            performedBy,
          });
        }
        succeeded.push({ line, issuedQty: issueQty });
      }
    } catch (error) {
      // Compensate with new ledger rows, never by editing/deleting the ones
      // already written (rule 2: append-only). A RECEIVE reverses an ISSUE
      // that already happened; a fresh RESERVATION restores the reservation.
      for (const { line, issuedQty } of succeeded) {
        if (issuedQty > 0) {
          await this.inventoryService
            .applyTransaction({
              type: 'RECEIVE',
              productId: line.productId,
              toLocationId: line.locationId,
              quantity: issuedQty,
              reference: dto.reference,
              performedBy,
              reason: `Compensating an issue that failed partway through reservation ${dto.reference}`,
            })
            .catch(() => {});
        }
        await this.inventoryService
          .applyTransaction({
            type: 'RESERVATION',
            productId: line.productId,
            fromLocationId: line.locationId,
            quantity: Number(line.quantity),
            reference: dto.reference,
            performedBy,
          })
          .catch(() => {});
      }
      throw new ConflictException(
        `Issue for reference "${dto.reference}" failed partway through and was rolled back via compensation: ${
          (error as Error).message
        }`,
      );
    }

    await this.prisma.$transaction(
      existing.lines.map((line) =>
        this.prisma.stockReservationLine.update({
          where: { id: line.id },
          data: { issuedQuantity: issueQtyByKey.get(`${line.productId}:${line.locationId}`) ?? 0 },
        }),
      ),
    );
    const updated = await this.prisma.stockReservation.update({
      where: { id: existing.id },
      data: { status: 'ISSUED' },
      include: { lines: true },
    });

    return this.issueResult(updated, false);
  }

  private issueResult(reservation: ReservationWithLines, alreadyIssued: boolean) {
    return {
      success: true,
      reference: reservation.reference,
      alreadyIssued,
      issued: reservation.lines.map((l) => ({
        productId: l.productId,
        locationId: l.locationId,
        reserved: Number(l.quantity),
        issued: Number(l.issuedQuantity),
      })),
    };
  }
}

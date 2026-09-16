import { Body, Controller, HttpCode, HttpStatus, Post, Req, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { ApiKeyGuard } from '../common/guards/api-key.guard';
import { RequireScopes } from '../common/decorators/require-scopes.decorator';
import { StockReservationsService } from './stock-reservations.service';
import { StockAvailabilityDto } from './dto/stock-availability.dto';
import { ReserveStockDto } from './dto/reserve-stock.dto';
import { ReleaseStockDto } from './dto/release-stock.dto';
import { IssueStockDto } from './dto/issue-stock.dto';

/**
 * System-to-system stock operations — authenticated by API key, scoped per
 * route. Every mutating call here only ever moves stock through
 * `InventoryService.applyTransaction()` (rule 2); this controller/service
 * layer never touches `inventory_balances`/`inventory_transactions` itself.
 *
 * "Insufficient stock" and "already released/issued" are normal, expected
 * business outcomes for a reservation API, not protocol errors — they're
 * returned as `200` with a `success: false` (or `alreadyReleased`/
 * `alreadyIssued`) discriminator in the body, not a thrown exception. That
 * keeps the response shape (including the short-line detail) entirely under
 * this controller's control rather than passing through the shared
 * `AllExceptionsFilter`, which only forwards `message`/`error` from a
 * thrown exception's body and would otherwise drop the structured detail.
 */
@ApiTags('external-stock')
@UseGuards(ApiKeyGuard)
@Controller('api/v1/stock')
export class ExternalStockController {
  constructor(private readonly stockReservationsService: StockReservationsService) {}

  @Post('availability')
  @HttpCode(HttpStatus.OK)
  @RequireScopes('stock:read')
  availability(@Body() dto: StockAvailabilityDto) {
    return this.stockReservationsService.checkAvailability(dto);
  }

  @Post('reserve')
  @HttpCode(HttpStatus.OK)
  @RequireScopes('stock:reserve')
  reserve(@Body() dto: ReserveStockDto, @Req() req: Request) {
    req.auditEntity = 'stock_reservations';
    req.auditEntityId = dto.reference;
    req.auditAction = 'RESERVE';
    return this.stockReservationsService.reserve(dto, req.apiKey!.id);
  }

  @Post('release')
  @HttpCode(HttpStatus.OK)
  @RequireScopes('stock:reserve')
  release(@Body() dto: ReleaseStockDto, @Req() req: Request) {
    req.auditEntity = 'stock_reservations';
    req.auditEntityId = dto.reference;
    req.auditAction = 'RELEASE';
    return this.stockReservationsService.release(dto);
  }

  @Post('issue')
  @HttpCode(HttpStatus.OK)
  @RequireScopes('stock:issue')
  issue(@Body() dto: IssueStockDto, @Req() req: Request) {
    req.auditEntity = 'stock_reservations';
    req.auditEntityId = dto.reference;
    req.auditAction = 'ISSUE';
    return this.stockReservationsService.issue(dto);
  }
}

import { BadGatewayException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  WarehouseAvailabilityResult,
  WarehouseCatalogue,
  WarehouseIssueResult,
  WarehouseProduct,
  WarehouseReleaseResult,
  WarehouseReserveResult,
  WarehouseStockLine,
} from './warehouse-api.types';

interface CatalogueQuery {
  categoryId?: string;
  status?: 'ACTIVE' | 'INACTIVE';
  includeInactive?: boolean;
  search?: string;
}

/**
 * The SOLE path from this app to /warehouse (ARCHITECTURE.md §A2 — this app
 * is a CLIENT of the warehouse's API-key-protected external API, never a
 * peer with DB access; no other file in this codebase should call the
 * warehouse directly). Every request attaches X-API-Key and a base URL from
 * env.
 *
 * Centralised error handling distinguishes two kinds of failure a caller
 * must NOT conflate:
 *   - a network/HTTP-level failure (warehouse unreachable, wrong/revoked
 *     key, wrong scope, malformed request) — the request either never
 *     completed or came back non-200. This client THROWS for these:
 *     ServiceUnavailableException when the warehouse could not be reached
 *     at all, BadGatewayException when it responded but with an error
 *     status (its message carries the warehouse's own reason, e.g. "Invalid
 *     or inactive API key" or "API key lacks the required scope").
 *   - a normal BUSINESS outcome the warehouse reports as HTTP 200 with a
 *     discriminator field (insufficient stock, already released/issued).
 *     This client NEVER throws for these — it returns the typed
 *     (discriminated-union, where relevant) result as-is. Callers MUST
 *     branch on the discriminator themselves; assuming 200 = success is a
 *     caller bug, not something this client can paper over.
 */
@Injectable()
export class WarehouseApiClient {
  private readonly baseUrl: string;
  private readonly apiKey: string;

  constructor(private readonly configService: ConfigService) {
    this.baseUrl = this.configService.get<string>('WAREHOUSE_API_URL') ?? 'http://localhost:3100';
    this.apiKey = this.configService.get<string>('WAREHOUSE_API_KEY') ?? '';
  }

  getCatalogue(query: CatalogueQuery = {}): Promise<WarehouseCatalogue> {
    return this.request<WarehouseCatalogue>('GET', '/api/v1/catalogue', undefined, query as Record<string, unknown>);
  }

  /**
   * Step 3 only exposed a LIST endpoint on the external catalogue API — no
   * by-id read. Fetch the full catalogue including inactive products (so
   * "inactive" and "doesn't exist" can be told apart with a precise error)
   * and find it client-side.
   */
  async getProduct(productId: string): Promise<WarehouseProduct> {
    const { products } = await this.getCatalogue({ includeInactive: true });
    const product = products.find((p) => p.id === productId);
    if (!product) {
      throw new NotFoundException(`Product ${productId} not found in the warehouse catalogue`);
    }
    return product;
  }

  checkAvailability(items: { productId: string; locationId?: string }[]): Promise<WarehouseAvailabilityResult> {
    return this.request('POST', '/api/v1/stock/availability', { items });
  }

  reserve(reference: string, lines: WarehouseStockLine[]): Promise<WarehouseReserveResult> {
    return this.request('POST', '/api/v1/stock/reserve', { reference, lines });
  }

  release(reference: string): Promise<WarehouseReleaseResult> {
    return this.request('POST', '/api/v1/stock/release', { reference });
  }

  issue(reference: string, lines: WarehouseStockLine[]): Promise<WarehouseIssueResult> {
    return this.request('POST', '/api/v1/stock/issue', { reference, lines });
  }

  private async request<T>(
    method: 'GET' | 'POST',
    path: string,
    body?: unknown,
    query?: Record<string, unknown>,
  ): Promise<T> {
    const url = new URL(path, this.baseUrl);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
      }
    }

    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers: {
          'X-API-Key': this.apiKey,
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch (error) {
      // The request never completed at all — DNS/connection refused/
      // timeout. Distinct from an HTTP error response (below): the caller
      // knows nothing was attempted on the warehouse side, so a retry is
      // always safe regardless of idempotency.
      throw new ServiceUnavailableException(
        `Warehouse API is unreachable at ${this.baseUrl} (${(error as Error).message}). This action is safe to retry.`,
      );
    }

    const payload = await response.json().catch(() => undefined);

    if (!response.ok) {
      const reason = (payload && (payload.message ?? payload.error)) ?? response.statusText;
      throw new BadGatewayException(
        `Warehouse API request failed (${response.status} ${response.statusText}): ` +
          (Array.isArray(reason) ? reason.join('; ') : reason),
      );
    }

    return payload as T;
  }
}

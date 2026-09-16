// Response shapes for the warehouse's external API (ARCHITECTURE.md §A2 /
// warehouse's own step-3 contract). Decimal fields come back as JSON
// STRINGS, not numbers (per ARCHITECTURE.md §E's API-contract note) —
// callers must Number() them; these types reflect that as-received shape.

export interface WarehouseCategory {
  id: string;
  name: string;
  parentId: string | null;
  isActive: boolean;
}

export interface WarehouseProductImage {
  id: string;
  url: string;
  sortOrder: number;
  isPrimary: boolean;
}

export interface WarehouseProduct {
  id: string;
  sku: string;
  name: string;
  description: string | null;
  categoryId: string;
  sellingPrice: string;
  costPrice: string | null;
  uom: string;
  minStockLevel: string;
  status: 'ACTIVE' | 'INACTIVE';
  category: { id: string; name: string };
  images: WarehouseProductImage[];
}

export interface WarehouseCatalogue {
  categories: WarehouseCategory[];
  products: WarehouseProduct[];
}

export interface WarehouseAvailabilityItem {
  productId: string;
  locationId: string | null;
  available: number;
}

export interface WarehouseAvailabilityResult {
  items: WarehouseAvailabilityItem[];
}

export interface WarehouseStockLine {
  productId: string;
  locationId: string;
  quantity: number;
}

export interface WarehouseReserveSuccess {
  success: true;
  reference: string;
  status: string;
  reserved: WarehouseStockLine[];
}

export interface WarehouseReserveShortfall {
  success: false;
  reference: string;
  shortLines: { productId: string; locationId: string; requested: number; available: number }[];
  note?: string;
}

// Discriminated union on `success` — callers MUST branch on it rather than
// assume an HTTP 200 means the reservation happened.
export type WarehouseReserveResult = WarehouseReserveSuccess | WarehouseReserveShortfall;

export interface WarehouseReleaseResult {
  success: true;
  reference: string;
  alreadyReleased: boolean;
  released: WarehouseStockLine[];
}

export interface WarehouseIssueResult {
  success: true;
  reference: string;
  alreadyIssued: boolean;
  issued: { productId: string; locationId: string; reserved: number; issued: number }[];
}

import { AttributeDataType } from '@prisma/client';

/**
 * Seed data for `attribute_types` — mirrors how `permission-catalog.ts`
 * seeds permissions. This is the extensibility mechanism: adding a new
 * attribute (e.g. "Country of Origin") later is a `POST /attribute-types`
 * call (a data row), never a change to this file or a migration. The six
 * below are just the initial catalog.
 */
export interface AttributeTypeDefinition {
  name: string;
  code: string;
  dataType: AttributeDataType;
  unit?: string;
}

export const ATTRIBUTE_TYPE_CATALOG: AttributeTypeDefinition[] = [
  { name: 'Colour', code: 'COLOUR', dataType: 'TEXT' },
  { name: 'Size', code: 'SIZE', dataType: 'TEXT' },
  { name: 'Weight', code: 'WEIGHT', dataType: 'NUMBER', unit: 'kg' },
  { name: 'Brand', code: 'BRAND', dataType: 'TEXT' },
  { name: 'Material', code: 'MATERIAL', dataType: 'TEXT' },
  { name: 'Dimensions', code: 'DIMENSIONS', dataType: 'TEXT', unit: 'cm' },
];

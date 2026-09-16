import { ApiProperty } from '@nestjs/swagger';
import { IsNumber, IsPositive, IsUUID } from 'class-validator';

// Shared by create and edit-draft.
//
// TEMPORARY DEVIATION (step 4 of the system split, ARCHITECTURE.md §A2):
// unitPrice used to be snapshotted server-side from the product's current
// selling price (rule 8: never trust client input for pricing) — that
// required a live, in-process lookup against this app's own `products`
// table. That table no longer exists here; the catalogue lives in
// warehouse_db now. Rather than add a live warehouse-API lookup in this
// step (explicitly out of scope until step 5), unitPrice is client-supplied
// for now. Step 5 must replace this with a server-side snapshot fetched
// from GET /api/v1/catalogue (and re-validate the product is ACTIVE there),
// restoring rule 8.
export class OrderItemInputDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 5, description: 'Quantity ordered, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;

  @ApiProperty({
    example: 12.5,
    description:
      'TEMPORARY (step 4): client-supplied unit price, snapshotted onto the order line as-is. ' +
      'Step 5 replaces this with a server-side snapshot from the warehouse catalogue API.',
  })
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  unitPrice: number;
}

import { ApiProperty } from '@nestjs/swagger';
import { IsNumber, IsPositive, IsUUID } from 'class-validator';

// Shared by create and edit-draft — unit_price is never client-supplied
// (it's snapshotted server-side from the product's current selling price,
// rule 8: never trust client input for pricing).
export class OrderItemInputDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 5, description: 'Quantity ordered, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;
}

import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsNumber,
  IsUUID,
  Min,
  ValidateNested,
} from 'class-validator';

export class SubmitStockCountItemDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 95, description: 'Physically counted quantity, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  countedQty: number;
}

export class SubmitStockCountDto {
  @ApiProperty({
    type: [SubmitStockCountItemDto],
    description:
      'Must cover exactly the set of products snapshotted when the count was started — no missing, no extra.',
  })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SubmitStockCountItemDto)
  items: SubmitStockCountItemDto[];
}

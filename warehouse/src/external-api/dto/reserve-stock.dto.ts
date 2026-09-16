import { ApiProperty } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsNumber, IsPositive, IsString, IsUUID, MinLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class ReserveStockLineDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ description: 'Must be a leaf location' })
  @IsUUID('4')
  locationId: string;

  @ApiProperty({ example: 10, description: 'Quantity to reserve, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;
}

export class ReserveStockDto {
  @ApiProperty({ example: 'ORDER-10042', description: "The caller's own id — reserve/release/issue are idempotent on this" })
  @IsString()
  @MinLength(1)
  reference: string;

  @ApiProperty({ type: [ReserveStockLineDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => ReserveStockLineDto)
  lines: ReserveStockLineDto[];
}

import { ApiProperty } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsNumber, IsPositive, IsString, IsUUID, MinLength, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class IssueStockLineDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ description: 'Must match a location reserved under this reference' })
  @IsUUID('4')
  locationId: string;

  @ApiProperty({
    example: 8,
    description: 'Quantity actually dispatched — may be less than what was reserved for this line; the remainder is released, not issued',
  })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;
}

export class IssueStockDto {
  @ApiProperty({ example: 'ORDER-10042', description: 'The reference used when reserving' })
  @IsString()
  @MinLength(1)
  reference: string;

  @ApiProperty({
    type: [IssueStockLineDto],
    description: 'Lines to actually dispatch. Any reserved line omitted here is fully released, not issued.',
  })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => IssueStockLineDto)
  lines: IssueStockLineDto[];
}

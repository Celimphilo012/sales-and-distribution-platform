import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsOptional, IsString, IsUUID, ValidateNested } from 'class-validator';
import { OrderItemInputDto } from './order-item-input.dto';

export class CreateOrderDto {
  @ApiProperty()
  @IsUUID('4')
  customerId: string;

  @ApiPropertyOptional({ description: 'Free-text delivery address/instructions' })
  @IsOptional()
  @IsString()
  deliveryInfo?: string;

  @ApiProperty({ type: [OrderItemInputDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderItemInputDto)
  items: OrderItemInputDto[];
}

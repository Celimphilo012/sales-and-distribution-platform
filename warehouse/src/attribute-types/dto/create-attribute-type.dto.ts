import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AttributeDataType } from '@prisma/client';
import { IsEnum, IsOptional, IsString, MinLength } from 'class-validator';

export class CreateAttributeTypeDto {
  @ApiProperty({ example: 'Country of Origin' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'COUNTRY_OF_ORIGIN', description: 'Unique, stable machine code' })
  @IsString()
  @MinLength(1)
  code: string;

  @ApiPropertyOptional({ enum: AttributeDataType, default: 'TEXT' })
  @IsOptional()
  @IsEnum(AttributeDataType)
  dataType?: AttributeDataType;

  @ApiPropertyOptional({ example: 'kg', description: 'Display unit, e.g. kg/cm — optional' })
  @IsOptional()
  @IsString()
  unit?: string;
}

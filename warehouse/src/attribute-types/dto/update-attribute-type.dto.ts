import { ApiPropertyOptional } from '@nestjs/swagger';
import { AttributeDataType } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateAttributeTypeDto {
  @ApiPropertyOptional({ example: 'Country of Origin' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({ example: 'COUNTRY_OF_ORIGIN' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({ enum: AttributeDataType })
  @IsOptional()
  @IsEnum(AttributeDataType)
  dataType?: AttributeDataType;

  @ApiPropertyOptional({ example: 'kg' })
  @IsOptional()
  @IsString()
  unit?: string;

  @ApiPropertyOptional({ description: 'Reactivate (true) or deactivate (false) this attribute type' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MinLength } from 'class-validator';

export class CreateCustomerDto {
  @ApiProperty({ example: 'Thandeka Dlamini' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiPropertyOptional({ example: '+268 7612 3456' })
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional({ description: 'Free-text location description (area, landmark, GPS note, etc.)' })
  @IsOptional()
  @IsString()
  locationText?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}

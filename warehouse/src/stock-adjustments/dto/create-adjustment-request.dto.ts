import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { AdjustmentBucket, AdjustmentDirection } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsNumber, IsOptional, IsPositive, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateAdjustmentRequestDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ description: 'Must be a leaf location' })
  @IsUUID('4')
  locationId: string;

  @ApiProperty({ enum: AdjustmentBucket, description: 'Which balance bucket this adjustment corrects' })
  @IsEnum(AdjustmentBucket)
  bucket: AdjustmentBucket;

  @ApiProperty({ example: 5, description: 'Magnitude of the correction, up to 3 decimal places (always positive — see direction)' })
  // The create route now also accepts multipart/form-data (to carry an
  // optional photo alongside it), where every field arrives as a string —
  // explicit here rather than relying on the global pipe's implicit
  // conversion, since this DTO started life JSON-only.
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  delta: number;

  @ApiProperty({ enum: AdjustmentDirection })
  @IsEnum(AdjustmentDirection)
  direction: AdjustmentDirection;

  @ApiProperty({ example: 'Damaged carton found during put-away', description: 'Mandatory — why this correction is needed' })
  @IsString()
  @MinLength(1)
  reason: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  reference?: string;
}

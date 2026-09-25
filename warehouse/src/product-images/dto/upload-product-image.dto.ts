import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsInt, IsOptional, Min } from 'class-validator';

/**
 * The non-file fields alongside a `POST .../images/upload` multipart
 * request. The file itself arrives via `@UploadedFile()`, not this DTO —
 * multer populates `req.file` before this body is validated, same pattern
 * as the stock-adjustment photo upload.
 */
export class UploadProductImageDto {
  @ApiPropertyOptional({ example: 0, default: 0 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ default: false, description: 'Marks this as the product\'s primary image' })
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isPrimary?: boolean;
}

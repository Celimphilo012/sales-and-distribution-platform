import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsInt, IsOptional, IsString, Min, MinLength } from 'class-validator';

export class CreateProductImageDto {
  @ApiProperty({
    example: 'https://cdn.example.com/products/bev-cola-330/1.jpg',
    description:
      'Opaque reference to the image (external URL, CDN path, or local storage path). ' +
      'Storage backend is not fixed by this API — see ARCHITECTURE.md open decisions.',
  })
  @IsString()
  @MinLength(1)
  url: string;

  @ApiPropertyOptional({ example: 0, default: 0 })
  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @ApiPropertyOptional({ default: false, description: 'Marks this as the product\'s primary image' })
  @IsOptional()
  @IsBoolean()
  isPrimary?: boolean;
}

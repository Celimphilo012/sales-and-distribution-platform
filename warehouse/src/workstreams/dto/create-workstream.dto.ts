import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateWorkstreamDto {
  @ApiProperty({ description: 'Warehouse this workstream belongs to' })
  @IsUUID('4')
  warehouseId: string;

  @ApiProperty({ example: 'Retail' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'RETAIL' })
  @IsString()
  @MinLength(1)
  code: string;

  @ApiPropertyOptional({ example: 'Retail-facing catalogue' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({
    example: 'https://cdn.example.com/workstreams/retail.jpg',
    description: 'Opaque reference to the image (external URL, CDN path, or local storage path) — same convention as product images; storage backend is not fixed by this API.',
  })
  @IsOptional()
  @IsString()
  imageUrl?: string;

  @ApiPropertyOptional({ example: 'Jane Doe', description: 'Contact person for this workstream' })
  @IsOptional()
  @IsString()
  contactName?: string;

  @ApiPropertyOptional({ example: 'jane.doe@example.com' })
  @IsOptional()
  @IsString()
  contactEmail?: string;

  @ApiPropertyOptional({ example: '+268 7612 3456' })
  @IsOptional()
  @IsString()
  contactPhone?: string;
}

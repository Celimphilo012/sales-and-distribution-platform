import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateWorkstreamDto {
  @ApiPropertyOptional({ example: 'Retail' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({ example: 'RETAIL' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({ example: 'Retail-facing catalogue' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({
    example: 'https://cdn.example.com/workstreams/retail.jpg',
    description: 'Opaque reference to the image — send an empty string to clear it.',
  })
  @IsOptional()
  @IsString()
  imageUrl?: string;

  @ApiPropertyOptional({ example: 'Jane Doe', description: 'Contact person for this workstream — send an empty string to clear it.' })
  @IsOptional()
  @IsString()
  contactName?: string;

  @ApiPropertyOptional({
    example: 'jane.doe@example.com',
    description: 'Send an empty string to clear it — not strictly validated as an email so clearing works the same way as description/imageUrl.',
  })
  @IsOptional()
  @IsString()
  contactEmail?: string;

  @ApiPropertyOptional({ example: '+268 7612 3456' })
  @IsOptional()
  @IsString()
  contactPhone?: string;

  @ApiPropertyOptional({ description: 'Reactivate (true) or deactivate (false) this workstream' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

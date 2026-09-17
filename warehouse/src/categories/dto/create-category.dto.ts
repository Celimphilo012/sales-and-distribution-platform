import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateCategoryDto {
  @ApiProperty({ example: 'Beverages' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiPropertyOptional({ description: 'Parent category id, for nested categories' })
  @IsOptional()
  @IsUUID('4')
  parentId?: string;

  @ApiProperty({
    description:
      'Workstream this category belongs to. If parentId is set, must match the parent category\'s workstream.',
  })
  @IsUUID('4')
  workstreamId: string;
}

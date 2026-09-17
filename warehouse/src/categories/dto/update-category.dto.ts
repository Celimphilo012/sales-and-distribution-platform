import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class UpdateCategoryDto {
  @ApiPropertyOptional({ example: 'Beverages' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({
    description: 'Parent category id. Pass null to move this category to the root.',
    nullable: true,
  })
  @IsOptional()
  @IsUUID('4')
  parentId?: string | null;

  @ApiPropertyOptional({ description: 'Reactivate (true) or soft-delete (false) this category' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @ApiPropertyOptional({
    description:
      'Move this category to a different workstream. Rejected if the category has sub-categories (move them first) or if it would mismatch the (possibly also-updated) parent\'s workstream.',
  })
  @IsOptional()
  @IsUUID('4')
  workstreamId?: string;
}

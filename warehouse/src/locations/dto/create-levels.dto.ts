import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';
import { IsInt, IsOptional, IsPositive, IsString, MinLength } from 'class-validator';

// Convenience for bulk-populating a warehouse structure (e.g. "add 5 shelf
// levels to this rack"). Loops plain inserts — deliberately no upper bound
// on `count` (rule 5: never hard-code rack/shelf/level/bin counts).
export class CreateLevelsDto {
  @ApiProperty({ example: 5, description: 'Number of sibling child locations to create. No upper limit.' })
  @IsInt()
  @IsPositive()
  count: number;

  @ApiPropertyOptional({ example: 'LEVEL', default: 'LEVEL' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  locationType?: string;

  @ApiPropertyOptional({ example: 'Level', default: 'Level', description: 'Each created location is named "{namePrefix} {n}"' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  namePrefix?: string;

  @ApiPropertyOptional({
    example: 'L',
    description: 'Each created location\'s code is "{parent code}-{codePrefix}{n}" (defaults to the first letter of locationType)',
  })
  @IsOptional()
  @IsString()
  @MinLength(1)
  codePrefix?: string;

  @ApiPropertyOptional({ example: 1, default: 1, description: 'First n used when numbering names/codes' })
  @IsOptional()
  @IsInt()
  @IsPositive()
  startIndex?: number;
}

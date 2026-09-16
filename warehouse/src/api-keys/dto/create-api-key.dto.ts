import { ApiProperty } from '@nestjs/swagger';
import { ArrayMinSize, ArrayUnique, IsArray, IsIn, IsString, MinLength } from 'class-validator';
import { API_KEY_SCOPES, ApiKeyScope } from '../../common/decorators/require-scopes.decorator';

export class CreateApiKeyDto {
  @ApiProperty({ example: 'Back-office integration', description: 'A human-readable label for this key' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ enum: API_KEY_SCOPES, isArray: true, example: API_KEY_SCOPES })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsIn(API_KEY_SCOPES, { each: true })
  scopes: ApiKeyScope[];
}

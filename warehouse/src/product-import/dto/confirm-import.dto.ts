import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

export class ConfirmImportDto {
  @ApiProperty({ description: 'The importSessionId returned by POST /products/import/preview' })
  @IsUUID('4')
  importSessionId: string;
}

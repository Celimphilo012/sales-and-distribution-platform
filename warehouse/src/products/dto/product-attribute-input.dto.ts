import { ApiProperty } from '@nestjs/swagger';
import { IsDefined, IsUUID } from 'class-validator';

// `value` is intentionally untyped by class-validator beyond "present" —
// its real shape (string vs number) depends on the referenced attribute
// type's dataType, which only the service can look up. A NUMBER-type value
// is sent as a plain JSON number here (same "number on write" convention as
// sellingPrice/costPrice/minStockLevel); a TEXT-type value is a string.
export class ProductAttributeInputDto {
  @ApiProperty({ description: 'The attribute type this value is for' })
  @IsUUID('4')
  attributeTypeId: string;

  @ApiProperty({
    description: "The value — a number for a NUMBER-dataType attribute, a string otherwise",
    oneOf: [{ type: 'string' }, { type: 'number' }],
  })
  @IsDefined()
  value: string | number;
}

import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

/** Self-service password change — distinct from `UpdateUserDto.password`, which is an admin reset with no current-password check. */
export class ChangePasswordDto {
  @ApiProperty({ example: 'MyCurrentPassword123!' })
  @IsString()
  currentPassword: string;

  @ApiProperty({ example: 'MyNewPassword456!', minLength: 8 })
  @IsString()
  @MinLength(8)
  newPassword: string;
}

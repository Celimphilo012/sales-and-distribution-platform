import { Body, Controller, Get, HttpCode, HttpStatus, Post, Req, SetMetadata, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthenticatedUser, CurrentUser } from '../common/decorators/current-user.decorator';
import { IS_PUBLIC_KEY, Public } from '../common/decorators/public.decorator';
import { AuthGuard } from '../common/guards/auth.guard';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';

@ApiTags('auth')
@Public()
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto, @Req() req: Request) {
    const result = await this.authService.login(dto);
    req.auditEntityId = result.user.id;
    req.auditAction = 'LOGIN';
    return result;
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  async refresh(@Body() dto: RefreshTokenDto, @Req() req: Request) {
    const result = await this.authService.refresh(dto.refreshToken);
    req.auditEntityId = result.user.id;
    req.auditAction = 'REFRESH';
    return result;
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout(@Body() dto: RefreshTokenDto, @Req() req: Request) {
    req.auditAction = 'LOGOUT';
    return this.authService.logout(dto.refreshToken);
  }

  /**
   * The caller's own identity + effective permissions. Requires a valid
   * access token but no specific permission — a logged-in user may always
   * read their own profile. The controller-level `@Public()` is overridden
   * here with an explicit `false` (handler metadata wins over class
   * metadata in `AuthGuard`'s `getAllAndOverride` lookup), so this is the
   * one route in this controller that actually runs `AuthGuard`; no
   * `PermissionGuard` since nothing is gated here beyond "is authenticated".
   */
  @Get('me')
  @SetMetadata(IS_PUBLIC_KEY, false)
  @UseGuards(AuthGuard)
  @ApiBearerAuth()
  me(@CurrentUser() user: AuthenticatedUser) {
    return this.authService.me(user.id);
  }
}

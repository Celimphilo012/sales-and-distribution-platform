import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ApiKeysService } from './api-keys.service';
import { CreateApiKeyDto } from './dto/create-api-key.dto';

/**
 * Admin-only JWT-guarded management for the external API's keys — separate
 * from the keys themselves, which authenticate via `ApiKeyGuard` on the
 * `/api/v1/*` routes. Gated behind `users.manage` (an existing admin
 * permission) rather than a new one, per the step 3 brief.
 */
@ApiTags('api-keys')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('users.manage')
@Controller('api-keys')
export class ApiKeysController {
  constructor(private readonly apiKeysService: ApiKeysService) {}

  @Get()
  findAll() {
    return this.apiKeysService.findAll();
  }

  @Post()
  async create(@Body() dto: CreateApiKeyDto, @CurrentUser() user: AuthenticatedUser, @Req() req: Request) {
    const created = await this.apiKeysService.create(dto, user.id);
    req.auditEntityId = created.id;
    return created;
  }

  @Post(':id/revoke')
  async revoke(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.apiKeysService.getExisting(id);
    req.auditAction = 'REVOKE';
    return this.apiKeysService.revoke(id);
  }
}

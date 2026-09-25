import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { WorkstreamManagersService } from './workstream-managers.service';

/**
 * "Which workstreams am I scoped to?" — no `@RequirePermissions()`, any
 * authenticated user may read their own assignments (same self-service
 * shape as `GET /users/me`). Separate from `WorkstreamManagersController`
 * (which is the admin-side "who manages this workstream", gated
 * `workstreams.assign`) since this is the other direction and needs no
 * special permission at all.
 */
@ApiTags('workstream-managers')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('users/me/workstreams')
export class MyWorkstreamsController {
  constructor(private readonly workstreamManagersService: WorkstreamManagersService) {}

  @Get()
  findMine(@CurrentUser() user: AuthenticatedUser) {
    return this.workstreamManagersService.listForUser(user.id);
  }
}

import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { WorkstreamManagersService } from './workstream-managers.service';
import { AssignWorkstreamManagerDto } from './dto/assign-workstream-manager.dto';

/**
 * Who can manage a given workstream's catalogue — separate from the
 * workstream record itself (`workstreams.manage`) and from the catalogue
 * mutations this assignment actually scopes (`products.manage`, enforced in
 * CategoriesService/ProductsService via `WorkstreamManagersService.
 * assertScopedAccess`). Gated `workstreams.assign` throughout — deciding
 * WHO can touch a workstream is an admin-level action distinct from doing
 * the catalogue work itself.
 */
@ApiTags('workstream-managers')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('workstreams/:workstreamId/managers')
export class WorkstreamManagersController {
  constructor(private readonly workstreamManagersService: WorkstreamManagersService) {}

  @Get()
  @RequirePermissions('workstreams.assign')
  findAll(@Param('workstreamId', ParseUUIDPipe) workstreamId: string) {
    return this.workstreamManagersService.listForWorkstream(workstreamId);
  }

  @Post()
  @RequirePermissions('workstreams.assign')
  async assign(
    @Param('workstreamId', ParseUUIDPipe) workstreamId: string,
    @Body() dto: AssignWorkstreamManagerDto,
    @Req() req: Request,
  ) {
    req.auditEntity = 'workstream_managers';
    const row = await this.workstreamManagersService.assign(workstreamId, dto.userId);
    req.auditEntityId = row.id;
    return row;
  }

  @Delete(':userId')
  @RequirePermissions('workstreams.assign')
  async unassign(
    @Param('workstreamId', ParseUUIDPipe) workstreamId: string,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Req() req: Request,
  ) {
    req.auditEntity = 'workstream_managers';
    return this.workstreamManagersService.unassign(workstreamId, userId);
  }
}

import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CatalogueService } from './catalogue.service';
import { ListCatalogueQueryDto } from './dto/list-catalogue-query.dto';

/**
 * STEP R3a: the ordering FRONTEND-facing catalogue read, gated by a real
 * user JWT (`AuthGuard`/`PermissionGuard`) — NOT the warehouse's API-key
 * boundary (that stays system-to-system only, ARCHITECTURE.md §A2). Gated
 * on `orders.create` rather than a new permission key: everyone who can
 * build/edit an order (CONSULTANT holds both `orders.create` and
 * `orders.edit_own_draft` together — confirmed in the real
 * ROLE_PERMISSION_MAP) needs to browse the catalogue to pick products; no
 * one needs catalogue browsing without also being able to create an order.
 */
@ApiTags('catalogue')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('orders.create')
@Controller('catalogue')
export class CatalogueController {
  constructor(private readonly catalogueService: CatalogueService) {}

  @Get()
  list(@Query() query: ListCatalogueQueryDto) {
    return this.catalogueService.list(query);
  }
}

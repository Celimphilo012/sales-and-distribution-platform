import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { LocationsService } from './locations.service';
import { CreateLocationDto } from './dto/create-location.dto';
import { CreateChildLocationDto } from './dto/create-child-location.dto';
import { UpdateLocationDto } from './dto/update-location.dto';
import { MoveLocationDto } from './dto/move-location.dto';
import { CreateLevelsDto } from './dto/create-levels.dto';
import { ListLocationsQueryDto } from './dto/list-locations-query.dto';

@ApiTags('locations')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@RequirePermissions('warehouse.structure.manage')
@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get()
  findAll(@Query() query: ListLocationsQueryDto) {
    return this.locationsService.findAll(query);
  }

  @Get(':id')
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.locationsService.findOne(id);
  }

  @Get(':id/children')
  children(@Param('id', ParseUUIDPipe) id: string, @Query('includeInactive') includeInactive?: string) {
    return this.locationsService.children(id, includeInactive === 'true');
  }

  @Get(':id/subtree')
  subtree(@Param('id', ParseUUIDPipe) id: string, @Query('includeInactive') includeInactive?: string) {
    return this.locationsService.subtree(id, includeInactive === 'true');
  }

  @Post()
  create(@Body() dto: CreateLocationDto) {
    return this.locationsService.create(dto);
  }

  @Post(':id/children')
  async addChild(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateChildLocationDto,
    @Req() req: Request,
  ) {
    const child = await this.locationsService.addChild(id, dto);
    req.auditEntityId = child.id;
    return child;
  }

  @Post(':id/levels')
  async generateLevels(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateLevelsDto,
    @Req() req: Request,
  ) {
    req.auditAction = 'GENERATE_LEVELS';
    return this.locationsService.generateLevels(id, dto);
  }

  @Post(':id/move')
  async move(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MoveLocationDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.locationsService.getExisting(id);
    req.auditAction = 'MOVE';
    return this.locationsService.move(id, dto);
  }

  @Patch(':id')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateLocationDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.locationsService.getExisting(id);
    return this.locationsService.update(id, dto);
  }

  @Delete(':id')
  async remove(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.locationsService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.locationsService.remove(id);
  }
}

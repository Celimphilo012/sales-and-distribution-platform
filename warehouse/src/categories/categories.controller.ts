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
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { CategoriesService } from './categories.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';
import { ListCategoriesQueryDto } from './dto/list-categories-query.dto';

@ApiTags('categories')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('categories')
export class CategoriesController {
  constructor(private readonly categoriesService: CategoriesService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Query() query: ListCategoriesQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.categoriesService.findAll(query, user.id);
  }

  @Get(':id')
  @RequirePermissions('catalogue.view')
  findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.categoriesService.findOne(id, user.id);
  }

  @Post()
  @RequirePermissions('products.manage')
  create(@Body() dto: CreateCategoryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.categoriesService.create(dto, user.id);
  }

  @Patch(':id')
  @RequirePermissions('products.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCategoryDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.categoriesService.getExisting(id);
    return this.categoriesService.update(id, dto, user.id);
  }

  @Delete(':id')
  @RequirePermissions('products.manage')
  async remove(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.categoriesService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.categoriesService.remove(id, user.id);
  }
}

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
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Request, Response } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { createImageMulterOptions } from '../common/uploads/image-storage';
import { WorkstreamsService, WORKSTREAM_IMAGE_UPLOAD_SUBDIR } from './workstreams.service';
import { CreateWorkstreamDto } from './dto/create-workstream.dto';
import { UpdateWorkstreamDto } from './dto/update-workstream.dto';
import { ListWorkstreamsQueryDto } from './dto/list-workstreams-query.dto';

// Catalogue-organization layer (Warehouse -> Workstream -> Category ->
// sub-category -> Product) — gated with the SAME permissions as
// categories/products: `catalogue.view` to read, `products.manage` to
// create/edit/deactivate. Purely organizational — never read by inventory/
// ledger code.
@ApiTags('workstreams')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('workstreams')
export class WorkstreamsController {
  constructor(private readonly workstreamsService: WorkstreamsService) {}

  @Get()
  @RequirePermissions('catalogue.view')
  findAll(@Query() query: ListWorkstreamsQueryDto, @CurrentUser() user: AuthenticatedUser) {
    return this.workstreamsService.findAll(query, user.id);
  }

  @Get(':id')
  @RequirePermissions('catalogue.view')
  findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.workstreamsService.findOne(id, user.id);
  }

  @Post()
  @RequirePermissions('workstreams.manage')
  create(@Body() dto: CreateWorkstreamDto) {
    return this.workstreamsService.create(dto);
  }

  @Patch(':id')
  @RequirePermissions('workstreams.manage')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateWorkstreamDto,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    return this.workstreamsService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions('workstreams.manage')
  async remove(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    req.auditAction = 'DEACTIVATE';
    return this.workstreamsService.remove(id);
  }

  @Post(':id/image/upload')
  @RequirePermissions('workstreams.manage')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', createImageMulterOptions(WORKSTREAM_IMAGE_UPLOAD_SUBDIR)))
  async uploadImage(
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() file: Express.Multer.File,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    return this.workstreamsService.uploadImage(id, file.filename);
  }

  @Delete(':id/image')
  @RequirePermissions('workstreams.manage')
  async removeImage(@Param('id', ParseUUIDPipe) id: string, @Req() req: Request) {
    req.auditOldValue = await this.workstreamsService.getExisting(id);
    return this.workstreamsService.removeImage(id);
  }

  @Get(':id/image/file')
  @RequirePermissions('catalogue.view')
  async getImageFile(@Param('id', ParseUUIDPipe) id: string, @Res() res: Response) {
    const { path, contentType } = await this.workstreamsService.getImageFile(id);
    res.setHeader('Content-Type', contentType);
    res.sendFile(path);
  }
}

import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  ParseUUIDPipe,
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
import { StockAdjustmentsService } from './stock-adjustments.service';
import { CreateAdjustmentRequestDto } from './dto/create-adjustment-request.dto';
import { ApproveAdjustmentDto } from './dto/approve-adjustment.dto';
import { RejectAdjustmentDto } from './dto/reject-adjustment.dto';
import { ListAdjustmentsQueryDto } from './dto/list-adjustments-query.dto';
import {
  adjustmentPhotoContentType,
  adjustmentPhotoFilePath,
  adjustmentPhotoMulterOptions,
} from './adjustment-photo-storage';

@ApiTags('inventory-adjustments')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('inventory/adjustments')
export class StockAdjustmentsController {
  constructor(private readonly stockAdjustmentsService: StockAdjustmentsService) {}

  @Get()
  @RequirePermissions('inventory.view')
  findAll(@Query() query: ListAdjustmentsQueryDto) {
    return this.stockAdjustmentsService.findAll(query);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @RequirePermissions('inventory.adjust.request')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('photo', adjustmentPhotoMulterOptions))
  async create(
    @Body() dto: CreateAdjustmentRequestDto,
    @UploadedFile() photo: Express.Multer.File | undefined,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    const adjustment = await this.stockAdjustmentsService.createRequest({
      ...dto,
      requestedBy: user.id,
      photoPath: photo?.filename,
    });
    req.auditEntity = 'stock_adjustments';
    req.auditEntityId = adjustment.id;
    // multipart fields all arrive as strings and the file itself isn't
    // meaningful in an audit trail — enrich what AuditInterceptor reads as
    // newValue with the parsed DTO plus just whether a photo was attached.
    req.body = { ...dto, hasPhoto: Boolean(photo) };
    return adjustment;
  }

  @Get(':id/photo')
  @RequirePermissions('inventory.view')
  async getPhoto(@Param('id', ParseUUIDPipe) id: string, @Res() res: Response) {
    const adjustment = await this.stockAdjustmentsService.getExisting(id);
    if (!adjustment.photoPath) {
      throw new NotFoundException(`Stock adjustment ${id} has no photo attached`);
    }
    res.setHeader('Content-Type', adjustmentPhotoContentType(adjustment.photoPath));
    res.sendFile(adjustmentPhotoFilePath(adjustment.photoPath));
  }

  @Post(':id/approve')
  @RequirePermissions('inventory.adjust.approve')
  async approve(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ApproveAdjustmentDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditEntity = 'stock_adjustments';
    req.auditOldValue = await this.stockAdjustmentsService.getExisting(id);
    req.auditAction = 'APPROVE';
    return this.stockAdjustmentsService.approve(id, user.id, dto.reviewNote);
  }

  @Post(':id/reject')
  @RequirePermissions('inventory.adjust.approve')
  async reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RejectAdjustmentDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditEntity = 'stock_adjustments';
    req.auditOldValue = await this.stockAdjustmentsService.getExisting(id);
    req.auditAction = 'REJECT';
    return this.stockAdjustmentsService.reject(id, user.id, dto.reviewNote);
  }
}

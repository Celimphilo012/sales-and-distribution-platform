import { BadRequestException, Body, Controller, Get, Post, Req, Res, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Request, Response } from 'express';
import { memoryStorage } from 'multer';
import { AuthGuard } from '../common/guards/auth.guard';
import { PermissionGuard } from '../common/guards/permission.guard';
import { RequirePermissions } from '../common/decorators/require-permissions.decorator';
import { ProductImportService } from './product-import.service';
import { ConfirmImportDto } from './dto/confirm-import.dto';

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024; // 5MB — a spreadsheet import has no business being bigger than this; multer rejects anything over before it reaches parsing.

@ApiTags('product-import')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('products/import')
export class ProductImportController {
  constructor(private readonly productImportService: ProductImportService) {}

  @Get('template')
  @RequirePermissions('products.manage')
  async downloadTemplate(@Res() res: Response) {
    const buffer = await this.productImportService.buildTemplate();
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', 'attachment; filename="product-import-template.xlsx"');
    res.send(buffer);
  }

  @Post('preview')
  @RequirePermissions('products.manage')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', { storage: memoryStorage(), limits: { fileSize: MAX_UPLOAD_BYTES } }))
  async preview(@UploadedFile() file: Express.Multer.File | undefined, @Req() req: Request) {
    if (!file) {
      throw new BadRequestException('No file uploaded — attach a .xlsx or .csv file as "file"');
    }
    const result = await this.productImportService.preview(file, req.user!.id);
    req.auditEntity = 'products';
    req.auditEntityId = result.importSessionId;
    req.auditAction = 'IMPORT_PREVIEW';
    // The real request body is empty (this is a multipart file upload, no
    // JSON fields) — put the summary in what the AuditInterceptor reads as
    // newValue, so the preview itself leaves a trace even if never confirmed.
    req.body = { fileName: file.originalname, summary: result.summary };
    return result;
  }

  @Post('confirm')
  @RequirePermissions('products.manage')
  async confirm(@Body() dto: ConfirmImportDto, @Req() req: Request) {
    const result = await this.productImportService.confirm(dto.importSessionId, req.user!.id);
    req.auditEntity = 'products';
    req.auditEntityId = dto.importSessionId;
    req.auditAction = 'IMPORT';
    // Enriches what the AuditInterceptor writes as newValue — "who imported"
    // comes from request.user automatically; this adds how many and which
    // file, per the task's audit requirement.
    req.body = {
      fileName: result.fileName,
      created: result.created,
      updated: result.updated,
      failedCount: result.failed.length,
      failed: result.failed,
    };
    return result;
  }
}

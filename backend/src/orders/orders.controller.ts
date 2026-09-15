import {
  Body,
  Controller,
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
import { OrdersService } from './orders.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { UpdateOrderDto } from './dto/update-order.dto';
import { TransitionNoteDto } from './dto/transition-note.dto';
import { RejectOrderDto } from './dto/reject-order.dto';
import { ReserveOrderDto } from './dto/reserve-order.dto';
import { ListOrdersQueryDto } from './dto/list-orders-query.dto';
import { PickOrderDto } from './dto/pick-order.dto';
import { PackOrderDto } from './dto/pack-order.dto';

@ApiTags('orders')
@ApiBearerAuth()
@UseGuards(AuthGuard, PermissionGuard)
@Controller('orders')
export class OrdersController {
  constructor(private readonly ordersService: OrdersService) {}

  // Gated by the minimal common key (everyone with any order visibility
  // has orders.view_own); whether the result is scoped to "own" or widened
  // to everyone is decided by an in-service orders.view_team check, since
  // PermissionGuard only supports AND across its declared keys, not OR.
  @Get()
  @RequirePermissions('orders.view_own')
  async findAll(@Query() query: ListOrdersQueryDto, @CurrentUser() user: AuthenticatedUser) {
    const canViewTeam = await this.ordersService.hasPermission(user.id, 'orders.view_team');
    return this.ordersService.findAll(query, canViewTeam ? undefined : user.id);
  }

  @Get(':id')
  @RequirePermissions('orders.view_own')
  async findOne(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() user: AuthenticatedUser) {
    const canViewTeam = await this.ordersService.hasPermission(user.id, 'orders.view_team');
    return this.ordersService.findOneScoped(id, canViewTeam ? undefined : user.id);
  }

  @Post()
  @RequirePermissions('orders.create')
  create(@Body() dto: CreateOrderDto, @CurrentUser() user: AuthenticatedUser) {
    return this.ordersService.create(dto, user.id);
  }

  @Patch(':id')
  @RequirePermissions('orders.edit_own_draft')
  async update(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateOrderDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditOldValue = await this.ordersService.getExisting(id);
    return this.ordersService.update(id, dto, user.id);
  }

  @Post(':id/submit')
  @RequirePermissions('orders.submit')
  async submit(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'SUBMIT';
    return this.ordersService.submit(id, user.id, dto.note);
  }

  @Post(':id/approve')
  @RequirePermissions('orders.approve')
  async approve(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'APPROVE';
    return this.ordersService.approve(id, user.id, dto.note);
  }

  @Post(':id/reject')
  @RequirePermissions('orders.reject')
  async reject(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RejectOrderDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'REJECT';
    return this.ordersService.reject(id, user.id, dto.note);
  }

  @Post(':id/reserve')
  @RequirePermissions('orders.approve')
  async reserve(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReserveOrderDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'RESERVE';
    return this.ordersService.reserve(id, dto, user.id);
  }

  @Post(':id/cancel')
  @RequirePermissions('orders.approve')
  async cancel(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'CANCEL';
    return this.ordersService.cancel(id, user.id, dto.note);
  }

  @Post(':id/pick')
  @RequirePermissions('fulfilment.pick')
  async pick(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: PickOrderDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'PICK';
    return this.ordersService.pick(id, dto, user.id);
  }

  @Post(':id/pack')
  @RequirePermissions('fulfilment.pack')
  async pack(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: PackOrderDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'PACK';
    return this.ordersService.pack(id, dto, user.id);
  }

  @Post(':id/ready')
  @RequirePermissions('fulfilment.dispatch')
  async ready(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'READY';
    return this.ordersService.ready(id, user.id, dto.note);
  }

  @Post(':id/dispatch')
  @RequirePermissions('fulfilment.dispatch')
  async dispatch(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'DISPATCH';
    return this.ordersService.dispatch(id, user.id, dto.note);
  }

  @Post(':id/deliver')
  @RequirePermissions('fulfilment.dispatch')
  async deliver(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'DELIVER';
    return this.ordersService.deliver(id, user.id, dto.note);
  }

  // No permission key was named in the task for /complete specifically;
  // reusing fulfilment.dispatch keeps it in the same hands as /deliver —
  // the natural continuation of the same fulfilment workflow, and the
  // only fulfilment.* key WAREHOUSE already holds for this tail end.
  @Post(':id/complete')
  @RequirePermissions('fulfilment.dispatch')
  async complete(
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TransitionNoteDto,
    @CurrentUser() user: AuthenticatedUser,
    @Req() req: Request,
  ) {
    req.auditAction = 'COMPLETE';
    return this.ordersService.complete(id, user.id, dto.note);
  }
}

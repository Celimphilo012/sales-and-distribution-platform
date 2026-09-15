import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateCustomerDto } from './dto/create-customer.dto';
import { UpdateCustomerDto } from './dto/update-customer.dto';
import { ListCustomersQueryDto } from './dto/list-customers-query.dto';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(query: ListCustomersQueryDto = {}) {
    return this.prisma.customer.findMany({
      where: {
        status: query.includeInactive ? undefined : 'ACTIVE',
        OR: query.search
          ? [{ name: { contains: query.search } }, { phone: { contains: query.search } }]
          : undefined,
      },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const customer = await this.prisma.customer.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException(`Customer ${id} not found`);
    return customer;
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  create(dto: CreateCustomerDto) {
    return this.prisma.customer.create({ data: dto });
  }

  async update(id: string, dto: UpdateCustomerDto) {
    await this.getExisting(id);
    return this.prisma.customer.update({ where: { id }, data: dto });
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Reference data is soft-deleted (rule 10) — orders keep a valid
    // historical customer reference even after deactivation.
    return this.prisma.customer.update({ where: { id }, data: { status: 'INACTIVE' } });
  }
}

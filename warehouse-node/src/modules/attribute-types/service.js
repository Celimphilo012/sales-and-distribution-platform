'use strict';

const { Prisma } = require('@prisma/client');
const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

function createAttributeTypesService({ prisma, cache, config }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  function translateUniqueViolation(error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return conflict('An attribute type with this code already exists');
    }
    return error;
  }

  const findAll = (query = {}) =>
    cache.wrap(
      `attribute-types:list:${query.includeInactive ? 'all' : 'active'}`,
      { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] },
      () =>
        prisma.attributeType.findMany({
          where: { isActive: query.includeInactive ? undefined : true },
          orderBy: { name: 'asc' },
        }),
    );

  async function getExisting(id) {
    const attributeType = await prisma.attributeType.findUnique({ where: { id } });
    if (!attributeType) throw notFound(`Attribute type ${id} not found`);
    return attributeType;
  }

  async function create(dto) {
    try {
      const created = await prisma.attributeType.create({
        data: { name: dto.name, code: dto.code, dataType: dto.dataType ?? 'TEXT', unit: dto.unit },
      });
      await invalidate();
      return created;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function update(id, dto) {
    await getExisting(id);
    try {
      const updated = await prisma.attributeType.update({
        where: { id },
        data: {
          name: dto.name ?? undefined,
          code: dto.code ?? undefined,
          dataType: dto.dataType ?? undefined,
          unit: dto.unit,
          isActive: dto.isActive ?? undefined,
        },
      });
      await invalidate();
      return updated;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function remove(id) {
    await getExisting(id);
    // Reference data is soft-deleted (rule 10) — products keep a valid historical attribute-type reference.
    const removed = await prisma.attributeType.update({ where: { id }, data: { isActive: false } });
    await invalidate();
    return removed;
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove };
}

module.exports = { createAttributeTypesService };

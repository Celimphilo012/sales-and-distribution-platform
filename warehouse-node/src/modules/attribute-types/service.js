'use strict';

const { conflict } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { isUniqueViolation } = require('../../core/db');
const { cols } = require('../../core/models');

function createAttributeTypesService({ db, models, cache, config }) {
  const invalidate = () => cache.invalidate(TAGS.CATALOGUE);

  function translateUniqueViolation(error) {
    return isUniqueViolation(error) ? conflict('An attribute type with this code already exists') : error;
  }

  const findAll = (query = {}) =>
    cache.wrap(
      `attribute-types:list:${query.includeInactive ? 'all' : 'active'}`,
      { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.CATALOGUE] },
      () =>
        db.query(
          `SELECT ${cols('attributeType', 'a')} FROM attribute_types a
            ${query.includeInactive ? '' : 'WHERE a.is_active = true'}
            ORDER BY a.name ASC`,
        ),
    );

  const getExisting = (id) => models.getById('attributeType', id, 'Attribute type');

  async function create(dto) {
    try {
      const created = await models.insert('attributeType', {
        name: dto.name,
        code: dto.code,
        dataType: dto.dataType ?? 'TEXT',
        unit: dto.unit,
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
      const updated = await models.update(
        'attributeType',
        id,
        {
          name: dto.name ?? undefined,
          code: dto.code ?? undefined,
          dataType: dto.dataType ?? undefined,
          unit: dto.unit,
          isActive: dto.isActive ?? undefined,
        },
        'Attribute type',
      );
      await invalidate();
      return updated;
    } catch (error) {
      throw translateUniqueViolation(error);
    }
  }

  async function remove(id) {
    await getExisting(id);
    // Reference data is soft-deleted (rule 10) — products keep a valid historical attribute-type reference.
    const removed = await models.update('attributeType', id, { isActive: false }, 'Attribute type');
    await invalidate();
    return removed;
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove };
}

module.exports = { createAttributeTypesService };

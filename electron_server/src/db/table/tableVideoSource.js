const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');
const path = require('path');

class tableVideoSource {
  constructor() {
    this.tableName = 'video_source';
  }

  async ensureColumns(knex) {
    const result = await knex.raw(`PRAGMA table_info(${this.tableName})`).catch(() => []);
    const rows = Array.isArray(result) ? result : result?.rows || [];
    const names = new Set((rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean));

    const toAdd = [];
    if (!names.has('media_type')) {
      toAdd.push({ name: 'media_type', add: table => table.string('media_type') });
    }
    if (!names.has('match_nfo')) {
      toAdd.push({ name: 'match_nfo', add: table => table.integer('match_nfo').defaultTo(0) });
    }
    if (!names.has('library_id')) {
      toAdd.push({ name: 'library_id', add: table => table.integer('library_id').notNullable().defaultTo(0) });
    }

    if (toAdd.length > 0) {
      await knex.schema.alterTable(this.tableName, table => {
        for (const col of toAdd) col.add(table);
      });
      for (const col of toAdd) {
        Logger.info(`✅ Added column ${col.name} to table ${this.tableName}`);
      }
    }

    if (names.has('media_type')) {
      await knex(this.tableName)
        .whereNull('media_type')
        .orWhere('media_type', '')
        .update({ media_type: 'movie' })
        .catch(() => {});
    }
    if (names.has('match_nfo')) {
      await knex(this.tableName)
        .whereNull('match_nfo')
        .update({ match_nfo: 0 })
        .catch(() => {});
    }
    await this.backfillLibraryId(knex);
  }

  // 老数据没有 library_id：按 media_type 挂到同类型的内置库上
  async backfillLibraryId(knex) {
    const libRows = await knex('video_library')
      .where({ is_default: 1 })
      .select('id', 'lib_type')
      .catch(() => []);
    const libIdByType = new Map();
    for (const r of libRows || []) {
      const type = r && r.lib_type ? String(r.lib_type) : '';
      const id = Number(r && r.id) || 0;
      if (type && id) libIdByType.set(type, id);
    }
    if (libIdByType.size === 0) return;

    const rows = await knex(this.tableName)
      .where(qb => qb.whereNull('library_id').orWhere('library_id', 0))
      .select('id', 'media_type')
      .catch(() => []);
    if (!rows || rows.length === 0) return;

    const buckets = new Map(); // libId -> [sourceId]
    for (const r of rows) {
      const sourceId = Number(r && r.id) || 0;
      if (!sourceId) continue;
      const mt = r && r.media_type ? String(r.media_type).trim() : '';
      const libId = libIdByType.get(mt === 'tv' ? 'tv' : 'movie') || 0;
      if (!libId) continue;
      if (!buckets.has(libId)) buckets.set(libId, []);
      buckets.get(libId).push(sourceId);
    }

    for (const [libId, ids] of buckets) {
      await knex(this.tableName)
        .whereIn('id', ids)
        .update({ library_id: libId })
        .catch(() => {});
    }
    Logger.info(`✅ video_source.library_id backfilled for ${rows.length} rows`);
  }

  async createTable(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    }

    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.integer('scan_when_start').defaultTo(0);
        table.integer('scan_when_change').defaultTo(1);
        table.integer('is_show').defaultTo(1);
        table.datetime('ctime');
        table.integer('scan_interval').defaultTo(0);
        table.integer('scan_interval_ms').defaultTo(0);
        table.string('media_type').notNullable();
        table.integer('library_id').notNullable().defaultTo(0); //所属影视库
        table.integer('match_nfo').defaultTo(0);
        table.string('scan_interval_config');
        table.integer('last_scan_time').defaultTo(0);
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    } else {
      await this.ensureColumns(knex);
    }
  }

  async getScanWhenStartPaths(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    }

    const rows = await knex(this.tableName)
      .select('path')
      .where({ scan_when_start: 1 })
      .catch(err => {
        Logger.error('❌ video source query failed:', err);
        return [];
      });

    const unique = new Set();
    for (const row of rows || []) {
      const p = row && row.path ? String(row.path) : '';
      if (p) unique.add(p);
    }
    return Array.from(unique);
  }

  async getMatchNfoPaths(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    }

    const rows = await knex(this.tableName)
      .select('path')
      .where({ match_nfo: 1 })
      .catch(err => {
        Logger.error('❌ video source match_nfo query failed:', err);
        return [];
      });

    const unique = new Set();
    for (const row of rows || []) {
      const p = row && row.path ? path.resolve(String(row.path)) : '';
      if (p) unique.add(p);
    }
    return Array.from(unique);
  }

  async createIndexes(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    }

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    const targetIndexes = [{ columns: ['path'], name: 'idx_video_source_path', unique: true }];

    for (const index of targetIndexes) {
      if (!indexNames.includes(index.name)) {
        await knex.schema.alterTable(this.tableName, table => {
          if (index.unique) {
            table.unique(index.columns, index.name);
          } else {
            table.index(index.columns, index.name);
          }
        });
        Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
      }
    }
  }
}

const tableVideoSourceInstance = new tableVideoSource();

module.exports = tableVideoSourceInstance;

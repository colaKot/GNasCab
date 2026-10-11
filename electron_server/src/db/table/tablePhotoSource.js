const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

class tablePhotoSource {
  constructor() {
    this.tableName = 'photo_source';
  }

  /**
   * 补齐历史库缺失的列。
   * uid = 源目录归属用户（0 = 无归属，不参与任何人的可见性计算）
   */
  async ensureColumns(knex) {
    const info = await knex.raw(`PRAGMA table_info('${this.tableName}')`).catch(() => null);
    const rows = Array.isArray(info) ? info : ((info?.rows || info) ?? []);
    const colNames = new Set((rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean));

    if (!colNames.has('uid')) {
      try {
        await knex.raw(`ALTER TABLE ${this.tableName} ADD COLUMN uid INTEGER NOT NULL DEFAULT 0`);
        Logger.info(`✅ Added column uid to table ${this.tableName}`);
      } catch (err) {
        Logger.error(`❌ Add column uid failed on ${this.tableName}:`, err);
      }
    }
  }

  async createTable(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }

    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.string('path').notNullable();
        table.integer('uid').notNullable().defaultTo(0);
        table.integer('scan_when_start').defaultTo(0);
        table.integer('scan_when_change').defaultTo(1);
        table.integer('is_show').defaultTo(1);
        table.datetime('ctime');
        table.integer('scan_interval').defaultTo(0);
        table.integer('scan_interval_ms').defaultTo(0);
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
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }

    const rows = await knex(this.tableName)
      .select('path')
      .where({ scan_when_start: 1 })
      .catch(err => {
        Logger.error('❌ photo source query failed:', err);
        return [];
      });

    const unique = new Set();
    for (const row of rows || []) {
      const p = row && row.path ? String(row.path) : '';
      if (p) unique.add(p);
    }
    return Array.from(unique);
  }

  async createIndexes(connection = null) {
    let knex;
    if (connection) {
      knex = connection.knex;
    } else {
      knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
    }

    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const indexNames = Array.isArray(existingIndexes) ? existingIndexes.map(row => row.name) : (existingIndexes?.rows || []).map(row => row.name);

    await this.ensureColumns(knex);

    // 旧的 path 全局唯一索引会挡住「不同用户各自添加同一目录」，必须移除
    if (indexNames.includes('idx_photo_source_path')) {
      await knex.raw('DROP INDEX IF EXISTS idx_photo_source_path').catch(() => {});
      Logger.info(`✅ Dropped legacy index idx_photo_source_path on table ${this.tableName}`);
    }

    // 同一用户下 path 唯一；不同用户可各自添加同一目录
    if (!indexNames.includes('idx_photo_source_uid_path')) {
      await knex
        .raw(`CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_source_uid_path ON ${this.tableName}(uid, path)`)
        .catch(err => Logger.error(`❌ Create index idx_photo_source_uid_path failed:`, err));
      Logger.info(`✅ Created index idx_photo_source_uid_path on table ${this.tableName}`);
    }
  }
}

const tablePhotoSourceInstance = new tablePhotoSource();

module.exports = tablePhotoSourceInstance;

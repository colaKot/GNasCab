const knexUtil = require('../knexUtil');
const dbUtil = require('../dbUtil');
const Logger = require('../../utils/logger');

/**
 * 同步任务运行记录表
 * 客户端每完成一轮同步会通过 /api/sync/report 回写一条记录。
 */
class tableSyncRecord {
  static STATUS_RUNNING = 'running';
  static STATUS_SUCCESS = 'success';
  static STATUS_FAILED = 'failed';
  static STATUS_STOPPED = 'stopped';

  static MAX_ROWS_PER_TASK = 300;

  constructor() {
    this.tableName = 'sync_record';
  }

  async createTable(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const tableExists = await knex.schema.hasTable(this.tableName);
    if (!tableExists) {
      await knex.schema.createTable(this.tableName, table => {
        table.increments('id').primary();
        table.integer('task_id').notNullable();
        table.timestamp('start_time').notNullable();
        table.timestamp('end_time').nullable();
        table.text('status').notNullable();
        table.integer('upload_count').nullable();
        table.integer('download_count').nullable();
        table.integer('delete_count').nullable();
        table.integer('skip_count').nullable();
        table.integer('fail_count').nullable();
        table.integer('bytes_transferred').nullable();
        table.text('error_list').nullable();
        table.integer('duration_ms').nullable();
      });
      Logger.info(`✅ Table ${this.tableName} created`);
    }
  }

  async createIndexes(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const existingIndexes = await knex.raw(`SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='${this.tableName}'`);
    const rows = Array.isArray(existingIndexes) ? existingIndexes : existingIndexes?.rows || [];
    const indexNames = rows.map(row => row.name);

    const targetIndexes = [
      { columns: ['task_id'], name: 'idx_sync_record_task_id', unique: false },
      { columns: ['task_id', 'start_time'], name: 'idx_sync_record_task_start', unique: false },
    ];

    for (const index of targetIndexes) {
      if (indexNames.includes(index.name)) continue;
      await knex.schema.alterTable(this.tableName, table => {
        table.index(index.columns, index.name);
      });
      Logger.info(`✅ Created index ${index.name} on table ${this.tableName}`);
    }

    await this.createTriggers({ knex });
  }

  async createTriggers(connection = null) {
    const knex = connection && connection.knex ? connection.knex : knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const triggerName = 'trg_sync_delete_records';
    const existing = await knex.raw("SELECT name FROM sqlite_master WHERE type='trigger' AND name=?", [triggerName]);
    const triggerExists = Array.isArray(existing) ? existing.length > 0 : (existing?.rows || []).length > 0;
    if (triggerExists) return;

    await knex.raw(`
      CREATE TRIGGER ${triggerName}
      AFTER DELETE ON sync_task
      FOR EACH ROW
      BEGIN
        DELETE FROM ${this.tableName} WHERE task_id = OLD.id;
      END;
    `);
    Logger.info(`✅ Created trigger ${triggerName} on sync_task`);
  }
}

const instance = new tableSyncRecord();
instance.STATUS_RUNNING = tableSyncRecord.STATUS_RUNNING;
instance.STATUS_SUCCESS = tableSyncRecord.STATUS_SUCCESS;
instance.STATUS_FAILED = tableSyncRecord.STATUS_FAILED;
instance.STATUS_STOPPED = tableSyncRecord.STATUS_STOPPED;
instance.MAX_ROWS_PER_TASK = tableSyncRecord.MAX_ROWS_PER_TASK;

module.exports = instance;

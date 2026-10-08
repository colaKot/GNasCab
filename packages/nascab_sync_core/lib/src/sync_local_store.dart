import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync_models.dart';

/// 同步基线本地存储
///
/// 基线 = 上一次同步结束后「本地文件」的状态快照。
/// 服务端据此区分「新增文件」与「被删除的文件」，实现删除传播与冲突判定。
class SyncLocalStore {
  static final SyncLocalStore instance = SyncLocalStore._();
  SyncLocalStore._();

  Database? _db;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    final base = await getApplicationSupportDirectory();
    final dbPath = p.join(base.path, 'sync.db');
    final factory = databaseFactoryFfi;
    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS sync_baseline ('
            'task_id INTEGER NOT NULL,'
            'rel_path TEXT NOT NULL,'
            'size INTEGER NOT NULL,'
            'mtime_ms INTEGER NOT NULL,'
            'updated_at_ms INTEGER NOT NULL,'
            'PRIMARY KEY (task_id, rel_path)'
            ')',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sync_baseline_task '
            'ON sync_baseline(task_id)',
          );
        },
      ),
    );
    return _db!;
  }

  /// 读取某任务的本地基线
  Future<List<LocalFileEntry>> loadBaseline(int taskId) async {
    try {
      final db = await _openDb();
      final rows = await db.query(
        'sync_baseline',
        columns: ['rel_path', 'size', 'mtime_ms'],
        where: 'task_id = ?',
        whereArgs: [taskId],
      );
      return rows
          .map((r) => LocalFileEntry(
                relPath: r['rel_path']?.toString() ?? '',
                size: int.tryParse(r['size']?.toString() ?? '') ?? 0,
                mtimeMs: int.tryParse(r['mtime_ms']?.toString() ?? '') ?? 0,
              ))
          .where((e) => e.relPath.isNotEmpty)
          .toList();
    } catch (e) {
      print('读取同步基线失败: $e');
      return <LocalFileEntry>[];
    }
  }

  /// 全量覆盖某任务的基线
  Future<void> saveBaseline(int taskId, List<LocalFileEntry> entries) async {
    try {
      final db = await _openDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        await txn.delete('sync_baseline', where: 'task_id = ?', whereArgs: [taskId]);
        final batch = txn.batch();
        for (final e in entries) {
          batch.insert(
            'sync_baseline',
            {
              'task_id': taskId,
              'rel_path': e.relPath,
              'size': e.size,
              'mtime_ms': e.mtimeMs,
              'updated_at_ms': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      print('保存同步基线失败: $e');
    }
  }

  /// 删除任务时清理对应基线
  Future<void> clearBaseline(int taskId) async {
    try {
      final db = await _openDb();
      await db.delete('sync_baseline', where: 'task_id = ?', whereArgs: [taskId]);
    } catch (e) {
      print('清理同步基线失败: $e');
    }
  }

  /// 清空全部基线。
  ///
  /// 退出登录 / 切换账号时调用：基线属于「某个账号的某台设备」，
  /// 换账号后旧基线只会让服务端做出错误的删除判定。
  Future<void> clearAll() async {
    try {
      final db = await _openDb();
      await db.delete('sync_baseline');
    } catch (e) {
      print('清空同步基线失败: $e');
    }
  }
}

const path = require('path');

class PhotoSourceService {
  constructor(knex) {
    this.knex = knex;
    this.tableName = 'photo_source';
  }

  normalizeUid(uid) {
    const n = Number(uid);
    return Number.isFinite(n) && n > 0 ? n : 0;
  }

  /**
   * 列出源目录。传 uid 只列该用户自己的；传 null/undefined 列全部（仅内部/迁移使用）
   */
  async listSources(uid) {
    const query = this.knex(this.tableName).select('*').orderBy('id', 'asc');
    if (uid !== null && uid !== undefined) {
      query.where({ uid: this.normalizeUid(uid) });
    }
    return query;
  }

  /**
   * 校验源目录归属。非属主且非管理员时抛 403
   */
  assertOwner(row, uid, allowAnyOwner = false) {
    if (allowAnyOwner) return;
    if (this.normalizeUid(uid) !== this.normalizeUid(row && row.uid)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }
  }

  normalizePath(inputPath) {
    const p = String(inputPath || '').trim();
    if (!p) return '';
    return path.resolve(p);
  }

  isParentPath(parentPath, childPath) {
    const parent = String(parentPath || '');
    const child = String(childPath || '');
    if (!parent || !child) return false;
    if (parent === child) return false;

    const parentWithSep = parent.endsWith(path.sep) ? parent : `${parent}${path.sep}`;
    return child.startsWith(parentWithSep);
  }

  isChildPath(parentPath, childPath) {
    return this.isParentPath(parentPath, childPath);
  }

  async addSource(inputPath, uid) {
    const owner = this.normalizeUid(uid);
    if (!owner) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const normalizedPath = this.normalizePath(inputPath);
    if (!normalizedPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    // 父子目录冲突只在同一用户名下判断，不同用户各加各的互不影响
    const rows = await this.knex(this.tableName).where({ uid: owner }).select('id', 'path').orderBy('id', 'asc');

    const exact = rows.find(r => r.path === normalizedPath);
    if (exact) {
      throw new Error('photo.PHOTO_SOURCE_EXISTS');
    }

    const parentRow = rows.find(r => this.isParentPath(r.path, normalizedPath));
    if (parentRow) {
      const err = new Error('photo.PHOTO_SOURCE_PARENT_EXISTS');
      err.args = [normalizedPath, parentRow.path];
      throw err;
    }

    const childRows = rows.filter(r => this.isChildPath(normalizedPath, r.path));
    if (childRows.length > 0) {
      const keep = childRows[0];
      const removeIds = childRows.slice(1).map(r => r.id);

      const row = await this.knex.transaction(async trx => {
        await trx(this.tableName).where({ id: keep.id }).update({
          path: normalizedPath,
          scan_when_start: 1,
        });
        if (removeIds.length > 0) {
          await trx(this.tableName).whereIn('id', removeIds).delete();
        }
        return trx(this.tableName).where({ id: keep.id }).first();
      });

      return { row, action: 'update' };
    }

    const row = await this.knex.transaction(async trx => {
      const [id] = await trx(this.tableName).insert({
        path: normalizedPath,
        uid: owner,
        scan_when_start: 1,
        ctime: new Date(),
      });
      return trx(this.tableName).where({ id }).first();
    });

    return { row, action: 'insert' };
  }

  async deleteSource({ id, path: inputPath, uid, allowAnyOwner = false }) {
    const owner = this.normalizeUid(uid);
    const deleteById = Number(id);
    const deleteByPath = this.normalizePath(inputPath);
    const shouldDeleteById = Number.isFinite(deleteById) && deleteById > 0;
    const shouldDeleteByPath = !shouldDeleteById && !!deleteByPath;
    if (!shouldDeleteById && !shouldDeleteByPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    return this.knex.transaction(async trx => {
      const target = shouldDeleteById
        ? await trx(this.tableName).where({ id: deleteById }).first('id', 'path', 'uid')
        : await trx(this.tableName).where({ path: deleteByPath, uid: owner }).first('id', 'path', 'uid');

      if (!target || !target.id) return 0;

      this.assertOwner(target, owner, allowAnyOwner);

      const affected = await trx(this.tableName).where({ id: target.id }).delete();
      if (!affected) return 0;

      const resolved = target.path ? String(target.path) : '';
      if (!resolved) return affected;

      // 隔离后同一物理路径可能被多个用户的源目录共同覆盖：
      // 只有「删完之后再没有任何 source 覆盖该路径」时才清理索引，避免误删别人的照片
      const remainingRows = await trx(this.tableName).select('path').catch(() => []);
      const remaining = (remainingRows || [])
        .map(r => (r && r.path ? String(r.path) : ''))
        .filter(Boolean);

      const scanPrefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;
      const indexQuery = trx('photo_index').where(qb => {
        qb.where('path', resolved).orWhere('path', 'like', `${scanPrefix}%`);
      });

      if (remaining.length > 0) {
        indexQuery.whereNot(qb => {
          for (const keep of remaining) {
            const keepPrefix = keep.endsWith(path.sep) ? keep : `${keep}${path.sep}`;
            qb.orWhere(function () {
              this.where('path', keep).orWhere('path', 'like', `${keepPrefix}%`);
            });
          }
        });
      }

      await indexQuery.delete().catch(() => {});

      //清除来源目录本身的索引
      const parentDir = path.dirname(resolved);
      const folderName = path.basename(resolved);
      if (parentDir && folderName) {
        await trx('photo_index')
          .where({ path: parentDir, filename: folderName })
          .delete()
          .catch(() => {});
      }
      return affected;
    });
  }

  async updateSource(id, payload = {}, uid, allowAnyOwner = false) {
    const sourceId = Number(id);
    if (!Number.isFinite(sourceId) || sourceId <= 0) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const existing = await this.knex(this.tableName).where({ id: sourceId }).first('id', 'uid');
    if (!existing || !existing.id) {
      throw new Error('common.NOT_FOUND');
    }
    this.assertOwner(existing, uid, allowAnyOwner);

    const data = {};

    if (payload.scan_when_start !== undefined) data.scan_when_start = Number(payload.scan_when_start);
    if (payload.scan_when_change !== undefined) data.scan_when_change = Number(payload.scan_when_change);
    if (payload.is_show !== undefined) data.is_show = Number(payload.is_show);
    if (payload.scan_interval !== undefined) data.scan_interval = Number(payload.scan_interval);
    if (payload.scan_interval_ms !== undefined) data.scan_interval_ms = Number(payload.scan_interval_ms);
    if (payload.scan_interval_config !== undefined) data.scan_interval_config = String(payload.scan_interval_config);
    if (payload.last_scan_time !== undefined) data.last_scan_time = Number(payload.last_scan_time);

    if (Object.keys(data).length === 0) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const affected = await this.knex(this.tableName).where({ id: sourceId }).update(data);
    if (!affected) {
      throw new Error('common.NOT_FOUND');
    }

    const row = await this.knex(this.tableName).where({ id: sourceId }).first();
    return row;
  }

  async relocateSource(id, newPath, uid, allowAnyOwner = false) {
    const sourceId = Number(id);
    if (!Number.isFinite(sourceId) || sourceId <= 0) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    const normalizedNewPath = this.normalizePath(newPath);
    if (!normalizedNewPath) {
      throw new Error('validation.VALIDATION_ERROR');
    }

    return this.knex.transaction(async trx => {
      const source = await trx(this.tableName).where({ id: sourceId }).first('id', 'path', 'uid');
      if (!source || !source.id) {
        throw new Error('common.NOT_FOUND');
      }

      this.assertOwner(source, uid, allowAnyOwner);

      const oldPath = source.path ? this.normalizePath(source.path) : '';
      if (!oldPath) {
        throw new Error('validation.VALIDATION_ERROR');
      }

      if (oldPath === normalizedNewPath) {
        return { source_id: sourceId, old_path: oldPath, new_path: normalizedNewPath, updated: 0 };
      }

      // 冲突只在同一用户名下判断
      const rows = await trx(this.tableName).select('id', 'path', 'uid').orderBy('id', 'asc');
      const otherRows = (rows || []).filter(
        r => Number(r.id) !== sourceId && this.normalizeUid(r.uid) === this.normalizeUid(source.uid)
      );

      const exact = otherRows.find(r => r.path === normalizedNewPath);
      if (exact) {
        throw new Error('photo.PHOTO_SOURCE_EXISTS');
      }

      const parentRow = otherRows.find(r => this.isParentPath(r.path, normalizedNewPath));
      if (parentRow) {
        const err = new Error('photo.PHOTO_SOURCE_PARENT_EXISTS');
        err.args = [normalizedNewPath, parentRow.path];
        throw err;
      }

      const childRows = otherRows.filter(r => this.isChildPath(normalizedNewPath, r.path));
      if (childRows.length > 0) {
        const err = new Error('photo.PHOTO_SOURCE_PARENT_EXISTS');
        err.args = [childRows[0].path, normalizedNewPath];
        throw err;
      }

      await trx(this.tableName).where({ id: sourceId }).update({ path: normalizedNewPath });

      const oldPrefix = oldPath.endsWith(path.sep) ? oldPath : `${oldPath}${path.sep}`;
      const newPrefix = normalizedNewPath.endsWith(path.sep) ? normalizedNewPath : `${normalizedNewPath}${path.sep}`;

      // 若旧路径仍被别人的源目录覆盖，物理索引不能跟着改，否则会连带影响对方看到的照片
      const stillCovered = await trx(this.tableName)
        .whereNot({ id: sourceId })
        .where(qb => qb.where('path', oldPath).orWhere('path', 'like', `${oldPrefix}%`))
        .first('id')
        .catch(() => null);
      if (stillCovered && stillCovered.id) {
        return {
          source_id: sourceId,
          old_path: oldPath,
          new_path: normalizedNewPath,
          updated: 1,
          updated_index_paths: 0,
          updated_root_dir_index: 0,
        };
      }

      await trx('photo_scan_task')
        .where({ scan_path: oldPath })
        .update({ scan_path: normalizedNewPath })
        .catch(() => {});

      const now = Date.now();

      const updatedDirect = await trx('photo_index')
        .where({ path: oldPath })
        .update({ path: normalizedNewPath, check_time: now })
        .catch(() => 0);

      const startAt = oldPrefix.length + 1;
      const updatedSubtree = await trx('photo_index')
        .where('path', 'like', `${oldPrefix}%`)
        .update({
          path: trx.raw(`? || substr(path, ?)`, [newPrefix, startAt]),
          check_time: now,
        })
        .catch(() => 0);

      const oldParent = path.dirname(oldPath);
      const oldName = path.basename(oldPath);
      const newParent = path.dirname(normalizedNewPath);
      const newName = path.basename(normalizedNewPath);

      const updatedRootDirIndex = await trx('photo_index')
        .where({ path: oldParent, filename: oldName, is_file: 0 })
        .update({ path: newParent, filename: newName, check_time: now })
        .catch(() => 0);

      return {
        source_id: sourceId,
        old_path: oldPath,
        new_path: normalizedNewPath,
        updated: 1,
        updated_index_paths: Number(updatedDirect || 0) + Number(updatedSubtree || 0),
        updated_root_dir_index: Number(updatedRootDirIndex || 0),
      };
    });
  }
}

module.exports = PhotoSourceService;

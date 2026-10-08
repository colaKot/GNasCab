'use strict';
/**
 * 影视库（video_library）自检脚本
 *
 * 用临时 sqlite 库跑真实的建表 / 迁移 / 服务层 SQL，不需要 Electron、不碰用户真实数据。
 * 覆盖：
 *   1. video_library 建表 + 内置「电影/电视剧」seed（幂等）
 *   2. video_source 老表补 library_id 列 + 按 media_type 回填
 *   3. addSource 必须带 library_id，media_type 由库类型派生
 *   4. 库名冲突 / 内置库禁删 / 有来源禁删 / 改名
 *   5. listLibrariesWithCounts 的条目统计（含 image）
 *
 * 用法：cd electron_server && node ../tool/video-library-selftest.js
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const SERVER = path.join(ROOT, 'electron_server');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nascab-videolib-'));
const dbFile = path.join(tmpDir, 'nascab_video_test.db');

let pass = 0;
let fail = 0;
function check(name, ok, extra = '') {
  if (ok) {
    pass += 1;
    console.log(`  ✓ ${name}`);
  } else {
    fail += 1;
    console.log(`  ✗ ${name}${extra ? ` → ${extra}` : ''}`);
  }
}

async function expectThrow(name, fn, expectedMessage) {
  try {
    await fn();
    check(name, false, '未抛出异常');
  } catch (err) {
    const msg = err && err.message ? String(err.message) : String(err);
    check(name, msg === expectedMessage, `期望 ${expectedMessage}，实际 ${msg}`);
  }
}

async function main() {
  const knex = require(path.join(SERVER, 'node_modules', 'knex'))({
    client: 'better-sqlite3',
    connection: { filename: dbFile },
    useNullAsDefault: true,
  });

  const tableVideoLibrary = require(path.join(SERVER, 'src/db/table/tableVideoLibrary'));
  const tableVideoSource = require(path.join(SERVER, 'src/db/table/tableVideoSource'));
  const VideoLibraryService = require(path.join(SERVER, 'src/api/modules/video/library/videoLibraryService'));
  const VideoSourceService = require(path.join(SERVER, 'src/api/modules/video/source/videoSourceService'));

  console.log('\n[1] video_library 建表 + 内置库 seed');
  await tableVideoLibrary.createTable({ knex });
  await tableVideoLibrary.createIndexes({ knex });
  let libs = await knex('video_library').select('*').orderBy('sort', 'asc');
  check('内置库数量 = 2', libs.length === 2, `实际 ${libs.length}`);
  check('内置库 1 = 电影/movie', libs[0] && libs[0].lib_type === 'movie' && Number(libs[0].is_default) === 1);
  check('内置库 2 = 电视剧/tv', libs[1] && libs[1].lib_type === 'tv' && Number(libs[1].is_default) === 1);

  console.log('\n[2] 老库迁移：video_source 补 library_id 并回填');
  // 先造一张“老版本”的表（没有 library_id 列）
  await knex.schema.createTable('video_source', table => {
    table.increments('id').primary();
    table.string('path').notNullable();
    table.integer('scan_when_start').defaultTo(0);
    table.integer('scan_when_change').defaultTo(1);
    table.integer('is_show').defaultTo(1);
    table.datetime('ctime');
    table.integer('scan_interval').defaultTo(0);
    table.integer('scan_interval_ms').defaultTo(0);
    table.string('media_type').notNullable();
    table.integer('match_nfo').defaultTo(0);
    table.string('scan_interval_config');
    table.integer('last_scan_time').defaultTo(0);
  });
  await knex('video_source').insert([
    { path: path.join(tmpDir, 'movies'), media_type: 'movie', scan_when_start: 1 },
    { path: path.join(tmpDir, 'shows'), media_type: 'tv', scan_when_start: 1 },
    { path: path.join(tmpDir, 'pics'), media_type: 'image', scan_when_start: 1 },
    { path: path.join(tmpDir, 'mix'), media_type: 'mixed', scan_when_start: 1 },
  ]);
  await tableVideoSource.createTable({ knex });
  await tableVideoSource.createIndexes({ knex });

  const cols = await knex.raw('PRAGMA table_info(video_source)');
  const colRows = Array.isArray(cols) ? cols : cols.rows || [];
  check('已补出 library_id 列', colRows.some(r => r.name === 'library_id'));

  const movieLib = libs[0];
  const tvLib = libs[1];
  const migrated = await knex('video_source').select('media_type', 'library_id');
  const byType = new Map(migrated.map(r => [String(r.media_type), Number(r.library_id)]));
  check('movie 来源回填到电影库', byType.get('movie') === Number(movieLib.id), String(byType.get('movie')));
  check('tv 来源回填到电视剧库', byType.get('tv') === Number(tvLib.id), String(byType.get('tv')));
  check('历史 image/mixed 来源回退到电影库', byType.get('image') === Number(movieLib.id) && byType.get('mixed') === Number(movieLib.id));

  console.log('\n[3] 影视库增删改');
  const libService = new VideoLibraryService(knex);
  const imageLib = await libService.addLibrary({ name: '我的图片', lib_type: 'image' });
  check('新建 image 库成功', !!imageLib && imageLib.lib_type === 'image');
  await expectThrow('库名重复被拒', () => libService.addLibrary({ name: '我的图片', lib_type: 'image' }), 'video.VIDEO_LIBRARY_NAME_EXISTS');
  await expectThrow('非法类型被拒', () => libService.addLibrary({ name: '非法库', lib_type: 'audio' }), 'validation.VALIDATION_ERROR');
  await expectThrow('内置库禁删', () => libService.deleteLibrary(movieLib.id), 'video.VIDEO_LIBRARY_BUILTIN_CANNOT_DELETE');

  const renamed = await libService.renameLibrary(imageLib.id, { name: '图片库改名' });
  check('改名成功', renamed && renamed.name === '图片库改名');
  const afterRename = await libService.getLibraryById(imageLib.id);
  check('改名后 lib_type 未变', afterRename && afterRename.lib_type === 'image');

  console.log('\n[4] addSource 绑定影视库');
  const sourceService = new VideoSourceService(knex);
  await expectThrow('缺 library_id 被拒', () => sourceService.addSource({ path: path.join(tmpDir, 'new1') }), 'video.VIDEO_SOURCE_LIBRARY_REQUIRED');
  await expectThrow('库不存在被拒', () => sourceService.addSource({ path: path.join(tmpDir, 'new2'), library_id: 99999 }), 'video.VIDEO_LIBRARY_NOT_FOUND');

  const r1 = await sourceService.addSource({ path: path.join(tmpDir, 'new_movie'), library_id: movieLib.id });
  check('movie 库来源 media_type = movie', r1.row && r1.row.media_type === 'movie' && Number(r1.row.library_id) === Number(movieLib.id));
  // 即使客户端硬塞 media_type，也以库类型为准
  const r2 = await sourceService.addSource({ path: path.join(tmpDir, 'new_tv_as_movie'), library_id: tvLib.id, media_type: 'image' });
  check('media_type 以库类型为准（传 image 仍写 tv）', r2.row && r2.row.media_type === 'tv');
  const r3 = await sourceService.addSource({ path: path.join(tmpDir, 'new_mixed'), library_id: imageLib.id });
  check('image 库来源 media_type = image', r3.row && r3.row.media_type === 'image');

  const listed = await sourceService.listSources();
  const listedRow = listed.find(r => Number(r.id) === Number(r1.row.id));
  check('source/list 带出 library_name', !!listedRow && listedRow.library_name === movieLib.name);
  check('source/list 带出 library_type', !!listedRow && listedRow.library_type === 'movie');

  console.log('\n[5] 有来源的库禁删');
  await expectThrow('有来源禁删', () => libService.deleteLibrary(imageLib.id), 'video.VIDEO_LIBRARY_HAS_SOURCE');
  const emptyLib = await libService.addLibrary({ name: '空库', lib_type: 'mixed' });
  const delResult = await libService.deleteLibrary(emptyLib.id);
  check('空库可删除', delResult && delResult.affected === 1);

  console.log('\n[6] listLibrariesWithCounts 条目统计');
  const admin = { id: 1, type: 'admin' };
  await knex.schema.createTable('video_index', table => {
    table.increments('id').primary();
    table.string('path').notNullable();
    table.string('filename').notNullable();
    table.string('media_type').defaultTo('');
    table.integer('is_file').defaultTo(1);
  });
  const movieRoot = path.join(tmpDir, 'new_movie');
  const imageRoot = path.join(tmpDir, 'new_mixed');
  await knex('video_index').insert([
    { path: movieRoot, filename: 'a.mkv', media_type: 'movie', is_file: 1 },
    { path: movieRoot, filename: 'b.mkv', media_type: 'movie', is_file: 1 },
    { path: movieRoot, filename: 'disc', media_type: 'bdmv', is_file: 0 },
    { path: imageRoot, filename: '1.jpg', media_type: 'image', is_file: 1 },
    { path: imageRoot, filename: '2.jpg', media_type: 'image', is_file: 1 },
    { path: imageRoot, filename: '3.mp4', media_type: 'movie', is_file: 1 },
  ]);

  const withCounts = await libService.listLibrariesWithCounts(admin);
  const movieLibInfo = withCounts.find(l => Number(l.id) === Number(movieLib.id));
  const imageLibInfo = withCounts.find(l => Number(l.id) === Number(imageLib.id));
  check('电影库 movie 计数 = 3（含 bdmv）', movieLibInfo && movieLibInfo.counts.movie === 3, movieLibInfo && JSON.stringify(movieLibInfo.counts));
  check('电影库 total = 3', movieLibInfo && movieLibInfo.counts.total === 3);
  check('图片库 image 计数 = 2', imageLibInfo && imageLibInfo.counts.image === 2, imageLibInfo && JSON.stringify(imageLibInfo.counts));
  check('图片库 movie 计数 = 1（混合库的视频）', imageLibInfo && imageLibInfo.counts.movie === 1);
  check('图片库 total = 3', imageLibInfo && imageLibInfo.counts.total === 3);
  check('计数按库切分，不串库', movieLibInfo.counts.image === 0);

  await knex.destroy();
  fs.rmSync(tmpDir, { recursive: true, force: true });

  console.log(`\n结果：${pass} 通过 / ${fail} 失败\n`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch(err => {
  console.error('自检脚本异常：', err);
  try {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  } catch (_) {}
  process.exit(1);
});

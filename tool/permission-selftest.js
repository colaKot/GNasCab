'use strict';
/**
 * 子账号权限体系自检（纯 Node，不需要 Electron、不需要真实数据库）
 *
 *   node tool/permission-selftest.js
 *
 * 覆盖：
 *   Suite A —— user_permission 覆盖式写入 / 父子路径去重 / 两个历史 bug 的回归
 *   Suite B —— 应用白名单（appAccessGuard）的放行与拦截判定
 *
 * 说明：本机 flutter/dart CLI 起不了子进程（见 tool/env.sh 注释），
 *       但服务端是纯 Node，可以直接这样跑真实逻辑。
 */
const path = require('path');

const SERVER = path.join(__dirname, '..', 'electron_server');
const knexLib = require(path.join(SERVER, 'node_modules', 'knex'));
const UserService = require(path.join(SERVER, 'src', 'api', 'modules', 'user', 'userService'));

// 用假的 config 存储替换 tableConfig，避开真实数据库
const tableConfig = require(path.join(SERVER, 'src', 'db', 'table', 'tableConfig'));
let configStore = null; // null = 未配置（不限制）
tableConfig.getConfigByKey = async () => configStore;
tableConfig.setJsonConfigByKey = async (key, value) => {
  configStore = JSON.stringify(value);
  return true;
};
const guard = require(path.join(SERVER, 'src', 'utils', 'appAccessGuard'));

let pass = 0;
let fail = 0;
const failures = [];

function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    pass++;
    console.log('  PASS  ' + label);
  } else {
    fail++;
    failures.push(label);
    console.log('  FAIL  ' + label + '   期望 ' + JSON.stringify(expected) +
      '  实际 ' + JSON.stringify(actual));
  }
}

function newKnex() {
  return knexLib({
    client: 'better-sqlite3',
    connection: { filename: ':memory:' },
    useNullAsDefault: true,
  });
}

async function suiteA() {
  console.log('\n########## Suite A：目录授权写入 ##########');
  const knex = newKnex();
  await knex.schema.createTable('user_permission', (t) => {
    t.increments('id');
    t.integer('uid').notNullable();
    t.string('res_type').notNullable();
    t.string('res_path').notNullable();
    t.string('action').notNullable();
    t.timestamp('create_time');
  });
  const svc = new UserService(knex);
  const pathsOf = async (uid, action) => {
    const q = knex('user_permission').where({ uid });
    if (action) q.andWhere({ action });
    return (await q.orderBy('res_path')).map((r) => r.res_path);
  };
  const P = (p, a) => ({ res_type: 'file', res_path: p, action: a });

  console.log('\n--- 只读档（view + download）---');
  await svc.setUserPermissions(1, [P('E:\\Media\\Movie2', 'view'), P('E:\\Media\\Movie2', 'download')]);
  check('view 落库', await pathsOf(1, 'view'), ['E:\\Media\\Movie2']);
  check('download 落库', await pathsOf(1, 'download'), ['E:\\Media\\Movie2']);

  console.log('\n--- 同 action 父子并存 -> 保留父目录 ---');
  await svc.setUserPermissions(2, [P('E:\\Media', 'view'), P('E:\\Media\\Movie2', 'view')]);
  check('只留父路径', await pathsOf(2, 'view'), ['E:\\Media']);

  console.log('\n--- 回归①：MediaBackup 不能被 Media 吞掉 ---');
  await svc.setUserPermissions(3, [P('E:\\Media', 'view'), P('E:\\MediaBackup', 'view')]);
  check('两条都保留', await pathsOf(3, 'view'), ['E:\\Media', 'E:\\MediaBackup']);

  console.log('\n--- 回归②：覆盖式写入不被旧数据挡（父 -> 子收窄）---');
  await svc.setUserPermissions(4, [P('E:\\Media', 'view')]);
  let threw = null;
  try {
    await svc.setUserPermissions(4, [P('E:\\Media\\Movie2', 'view')]);
  } catch (e) { threw = e.message; }
  check('不再抛 PATH_PARENT_EXISTS', threw, null);
  check('已收窄为子路径', await pathsOf(4, 'view'), ['E:\\Media\\Movie2']);

  console.log('\n--- 混合档位：父只读 + 子可写 ---');
  await svc.setUserPermissions(5, [
    P('E:\\Media', 'view'), P('E:\\Media', 'download'),
    P('E:\\Media\\Movie2', 'view'), P('E:\\Media\\Movie2', 'download'),
    P('E:\\Media\\Movie2', 'upload'), P('E:\\Media\\Movie2', 'delete'),
  ]);
  check('view 去重到父', await pathsOf(5, 'view'), ['E:\\Media']);
  check('download 去重到父', await pathsOf(5, 'download'), ['E:\\Media']);
  check('upload 保留子', await pathsOf(5, 'upload'), ['E:\\Media\\Movie2']);
  check('delete 保留子', await pathsOf(5, 'delete'), ['E:\\Media\\Movie2']);

  console.log('\n--- 覆盖式清空 ---');
  await svc.setUserPermissions(6, [P('E:\\A', 'view')]);
  await svc.setUserPermissions(6, []);
  check('已清空', (await knex('user_permission').where({ uid: 6 })).length, 0);

  console.log('\n--- 路径分隔符混用（/ 与 \\）---');
  await svc.setUserPermissions(7, [P('E:/Media', 'view'), P('E:\\Media\\Movie2', 'view')]);
  check('归一化后判为父子', (await pathsOf(7, 'view')).length, 1);

  await knex.destroy();
}

async function suiteB() {
  console.log('\n########## Suite B：应用白名单 ##########');
  const knex = newKnex();
  const user = (id, type) => ({ id, userId: id, type });
  const allow = async (u, p) => (await guard.checkAppAccess(knex, u, p)).allowed;

  console.log('\n--- 未配置 -> 不限制（向后兼容）---');
  configStore = null;
  guard.invalidateCache();
  check('影视放行', await allow(user(1, 'user'), '/api/video/list'), true);
  check('Docker 放行', await allow(user(1, 'user'), '/api/docker/list'), true);

  console.log('\n--- 场景：只给 文件+影视+相册+音乐+同步 ---');
  configStore = null;
  guard.invalidateCache();
  await guard.setAllowedApps(10, ['folder', 'movie', 'photo', 'music', 'sync']);
  check('文件 /api/file/list 放行', await allow(user(10, 'user'), '/api/file/list'), true);
  check('影视 /api/video/list 放行', await allow(user(10, 'user'), '/api/video/list'), true);
  check('影视 HLS 分片 放行', await allow(user(10, 'user'), '/api/videoPlayer/hls/a/b.ts'), true);
  check('相册 /api/photo/timeline 放行', await allow(user(10, 'user'), '/api/photo/timeline'), true);
  check('音乐 /api/music/list 放行', await allow(user(10, 'user'), '/api/music/list'), true);
  check('同步 /api/sync/plan 放行', await allow(user(10, 'user'), '/api/sync/plan'), true);
  check('图书 拦截', await allow(user(10, 'user'), '/api/book/list'), false);
  check('笔记 拦截', await allow(user(10, 'user'), '/api/notes/list'), false);
  check('Docker 拦截', await allow(user(10, 'user'), '/api/docker/list'), false);
  check('加密空间 拦截', await allow(user(10, 'user'), '/api/encryptedSpace/x'), false);

  console.log('\n--- 公共接口永远放行 ---');
  check('/api/auth/login', await allow(user(10, 'user'), '/api/auth/login'), true);
  check('/api/apps/getApps', await allow(user(10, 'user'), '/api/apps/getApps'), true);
  check('/api/home/x', await allow(user(10, 'user'), '/api/home/x'), true);

  console.log('\n--- 管理员豁免 ---');
  await guard.setAllowedApps(20, ['folder']);
  check('admin 豁免', await allow(user(20, 'admin'), '/api/docker/list'), true);
  check('super_admin 豁免', await allow(user(20, 'super_admin'), '/api/docker/list'), true);

  console.log('\n--- 解除限制 ---');
  await tableConfig.setJsonConfigByKey(guard.CONFIG_KEY_ALLOWED_APPS, '');
  guard.invalidateCache(10);
  check('解除后图书放行', await allow(user(10, 'user'), '/api/book/list'), true);

  await knex.destroy();
}

(async () => {
  try {
    await suiteA();
    await suiteB();
  } catch (e) {
    console.error('\n测试脚本异常:', e && e.stack ? e.stack : e);
    process.exit(2);
  }
  console.log('\n========================================');
  console.log('  通过 ' + pass + ' / 失败 ' + fail);
  if (fail > 0) console.log('  失败项: ' + failures.join(' | '));
  console.log('========================================');
  process.exit(fail === 0 ? 0 : 1);
})();

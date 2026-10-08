/**
 * 原生模块 ABI 探测。
 * 用法（在 electron_server 目录下）：
 *   ELECTRON_RUN_AS_NODE=1 node_modules/electron/dist/electron.exe ../tool/_abi_probe.js
 *   node ../tool/_abi_probe.js      (纯 Node ABI 对照)
 */
const path = require('path');

// 脚本本身在 tool/ 下，require 会从 tool/ 往上找 node_modules —— 那是错的。
// 统一从 cwd（= electron_server）下的 node_modules 解析。
const NM = path.join(process.cwd(), 'node_modules');
const load = m => require(path.join(NM, m));

const MODS = ['better-sqlite3', 'sharp', 'onnxruntime-node', 'node-pty', 'nodejieba', 'bcrypt', 'dcraw', 'psd', 'sharp-bmp'];

console.log('runtime :', process.versions.electron ? 'electron' : 'node');
console.log('  node    :', process.versions.node);
console.log('  electron:', process.versions.electron || '-');
console.log('  modules :', process.versions.modules, '(NODE_MODULE_VERSION)');
console.log('  platform:', process.platform, process.arch);
console.log('');

let ok = 0;
let bad = 0;
for (const m of MODS) {
  try {
    load(m);
    console.log(`  ok    ${m}`);
    ok++;
  } catch (e) {
    const msg = String((e && e.message) || e).split('\n')[0];
    console.log(`  FAIL  ${m}  ->  ${msg}`);
    bad++;
  }
}
console.log(`\n可加载 ${ok} / 失败 ${bad}`);

/**
 * 相对路径 require 全量校验。
 *
 * 为什么需要它：`node --check` 只查语法，不查模块能否解析。
 * 一旦相对层级写错（少一级多一级 '../'），语法照样通过，
 * 直到运行时整条 require 链炸掉 —— 而且只在加载到那个路由时才暴露。
 *
 * 用法（在 electron_server 目录下）：
 *   node ../tool/check_requires.js            # 扫 src/
 *   node ../tool/check_requires.js src/api    # 只扫某个子目录
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Module = require('module');

const root = process.cwd();
const startDir = path.resolve(root, process.argv[2] || 'src');

const RE = /require\s*\(\s*['"](\.[^'"]+)['"]\s*\)/g;

const CANDIDATE_EXT = ['', '.js', '.json', '.node', '/index.js', '/index.json'];

function resolves(fromFile, spec) {
  const base = path.resolve(path.dirname(fromFile), spec);
  for (const ext of CANDIDATE_EXT) {
    const p = base + ext;
    try {
      const st = fs.statSync(p);
      if (st.isFile()) return p;
    } catch (_) {}
  }
  // 目录形式：package.json main
  try {
    if (fs.statSync(base).isDirectory()) {
      const pkg = path.join(base, 'package.json');
      if (fs.existsSync(pkg)) return base;
      const idx = path.join(base, 'index.js');
      if (fs.existsSync(idx)) return idx;
    }
  } catch (_) {}
  return null;
}

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
      walk(p, out);
    } else if (e.isFile() && (e.name.endsWith('.js') || e.name.endsWith('.cjs'))) {
      out.push(p);
    }
  }
}

const files = [];
walk(startDir, files);

let checked = 0;
const broken = [];
const builtinOrPkg = [];

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  let m;
  RE.lastIndex = 0;
  while ((m = RE.exec(src)) !== null) {
    const spec = m[1];
    // 跳过带通配/模板的（本仓库实际没有，防御一下）
    if (spec.includes('*') || spec.includes('${')) continue;
    checked++;
    const hit = resolves(f, spec);
    if (hit) {
      const rel = path.relative(root, hit).replace(/\\/g, '/');
      if (rel.startsWith('../')) {
        // 解析到了项目外
        broken.push({ file: f, spec, reason: '解析到项目外: ' + rel });
      }
    } else {
      broken.push({ file: f, spec, reason: '找不到文件' });
    }
  }
}

console.log(`扫描目录 : ${path.relative(root, startDir).replace(/\\/g, '/')}`);
console.log(`JS 文件  : ${files.length}`);
console.log(`相对引用 : ${checked}`);
console.log('');

if (broken.length === 0) {
  console.log('✓ 所有相对 require 均可解析');
  process.exit(0);
}

console.log(`✗ 发现 ${broken.length} 处断链：\n`);
for (const b of broken) {
  console.log(`  ${path.relative(root, b.file).replace(/\\/g, '/')}`);
  console.log(`      require('${b.spec}')  ->  ${b.reason}`);
}
process.exit(1);

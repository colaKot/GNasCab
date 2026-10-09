#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
把「被 Express 以裸引用注册、且方法体内用了 this.」的控制器方法改成箭头函数属性。

背景：`router.get('/detail', authenticateJWT, controller.getDetail)` 是**裸引用**，
派发时 `this` 为 undefined（类体是严格模式），方法体里的 `this._ensureIndexAccess(...)`
直接抛 `Cannot read properties of undefined`，被 catch 兜成 500。

仓库里正确的写法有两种：① 路由里包一层箭头 `(req, res) => controller.m(req, res)`
（apiSettingRouter 风格）；② 把方法本身声明成**箭头函数属性**（类字段，this 取词法作用域）。
这里统一用 ②，和同文件里已经改过的 `_ensureIndexAccess` / `_ensureOperatorTwofaVerified` 保持一致。

用法：python tool/_fix_controller_this_bind.py [--check-only]
"""
import re
import subprocess
import sys

TARGETS = {
    'electron_server/src/api/modules/video/detail/detailController.js': [
        'getDetail',
        'getEpisodes',
        'getTvPlayInfo',
        'getDiscContents',
        'getDiscContentThumb',
    ],
    'electron_server/src/api/modules/user/userController.js': [
        'createUser',
        'updateUser',
        'deleteUsers',
        'enableUser2fa',
        'resetUser2fa',
    ],
}


def find_method_end(src, start):
    """从 (签名行起始) 起，跳过字符串/注释，返回方法体结束 `}` 的下标。"""
    i = src.index('{', start)
    depth = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            i = src.index('\n', i)
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i = src.index('*/', i) + 2
            continue
        if c in ('\'', '"', '`'):
            quote = c
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == quote:
                    break
                i += 1
            i += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise RuntimeError('unbalanced braces')


def convert(path, names):
    src = open(path, encoding='utf-8').read()
    original = src
    changed = []
    for name in names:
        sig_re = re.compile(r'^  async %s\(req, res\) \{$' % re.escape(name), re.M)
        m = sig_re.search(src)
        if not m:
            raise RuntimeError('%s: signature not found: %s' % (path, name))
        if src.count(m.group(0)) != 1:
            raise RuntimeError('%s: signature not unique: %s' % (path, name))
        end = find_method_end(src, m.start())
        assert src[end] == '}', 'expected closing brace'
        new_sig = '  %s = async (req, res) => {' % name
        # 先把结尾的 `}` 换成 `};`，再换签名（改结尾不影响签名下标之前的内容）
        src = src[:end] + '};' + src[end + 1:]
        src = src[:m.start()] + new_sig + src[m.start() + len(m.group(0)):]
        changed.append(name)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(src)
    return changed, original != src


def main():
    for path, names in TARGETS.items():
        changed, diff = convert(path, names)
        print('%-72s  %s' % (path, ', '.join(changed)))
        assert diff, 'no change in %s' % path
    for path in TARGETS:
        r = subprocess.run(['node', '--check', path], capture_output=True, text=True)
        print('node --check %s -> rc=%d %s' % (path, r.returncode, (r.stderr or '').strip()))
        if r.returncode != 0:
            sys.exit(1)


if __name__ == '__main__':
    main()

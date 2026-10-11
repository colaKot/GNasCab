#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
把「登录前页面」写死的 `Theme(data: darkTheme)` 换成跟随当前配色的
`ThemeApplyService.instance.authTheme()`。

背景：`darkTheme` 是编译期常量 = buildDarkTheme(AppColorSchemes.defaultScheme)，
永远默认 shadBlue ⇒ 用户换任何配色，登录页/服务器列表页的颜色都不跟着变。
详见 docs/WaterNasOS-开发速查.md §1.3。

逐文件「读 → 改 → 校验」；改完必须没有残留的 `darkTheme` 标识符。
⚠️ 故意不动 `modules/home/views/pc_components/pc_app_window.dart`：
   那里是**终端 / 图片查看器窗口**，固定深色是刻意设计，不是漏改。
"""
import os
import re
import sys

ROOT = r'G:\work\nascab\flutter_client\lib'
FILES = [
    r'modules\auth\views\admin_create\admin_create_page.dart',
    r'modules\auth\views\admin_create\admin_create_view.dart',
    r'modules\auth\views\login\login_twofa_dialog.dart',
    r'modules\auth\views\login\login_view.dart',
    r'modules\auth\views\recover_password\recover_password_view.dart',
    r'modules\auth\views\server_add\server_add_view.dart',
    r'modules\auth\views\server_list\pair_code_scanner_io.dart',
    r'modules\auth\views\server_list\server_list_view.dart',
]

OLD_IMPORT = re.compile(r"import '([^']*core/theme/)dark_theme\.dart';")
NEW_USE = 'ThemeApplyService.instance.authTheme()'

total = 0
for rel in FILES:
    p = os.path.join(ROOT, rel)
    src = open(p, encoding='utf-8', newline='').read()
    before = src

    # 1) import: dark_theme.dart -> theme_apply_service.dart
    if 'theme_apply_service.dart' not in src:
        src, n = OLD_IMPORT.subn(
            lambda m: "import '%stheme_apply_service.dart';" % m.group(1), src
        )
        if n != 1:
            raise SystemExit('%s: dark_theme import not replaced (n=%d)' % (rel, n))
    else:
        # 已有 import，只需删掉 dark_theme 那行
        src = OLD_IMPORT.sub('', src)

    # 2) 用法：data: darkTheme -> data: authTheme()
    uses = src.count('darkTheme')
    if uses == 0:
        raise SystemExit('%s: no darkTheme usage found' % rel)
    src = src.replace('data: darkTheme', 'data: %s' % NEW_USE)

    left = src.count('darkTheme')
    if left:
        raise SystemExit('%s: %d leftover darkTheme identifier(s)' % (rel, left))
    if src == before:
        raise SystemExit('%s: nothing changed' % rel)

    with open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(src)
    total += uses
    print('%-64s %d 处' % (rel, uses))

print('共替换 %d 处' % total)

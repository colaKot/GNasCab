# GNasCab 主题「写死颜色」清理台账

> 背景：换肤的唯一入口是 `lib/core/theme/theme_apply_service.dart`；
> 项目硬要求「所有涉及主题的覆盖都以主题为主」。
> 排查方法论与根因分类见 `docs/GNasCab-开发速查.md` §1.3.2。
>
> 通用替换口诀：压在 `primary` 上 → `onPrimary`；压 `surface` → `onSurface`；
> 压 `primaryContainer` → `onPrimaryContainer`；压 `error` → `onError`；
> 分隔线/进度条轨道 → `outlineVariant` / `dividerColor`。

------------

## 一、已清理（2026-10-09）

### 第 1 批：确定性的「白/近白压浅底」

| 文件 | 处理 |
| --- | --- |
| `modules/home/views/pc_components/pc_dock_bar.dart` | 桌面左侧栏 Dock：图标/分隔线/指示点 `Colors.white`、`white24`、`white54` → `onSurface` / `outlineVariant` |
| `modules/base/components/custom_button.dart` | 禁用态 `Colors.white(38%)` + 灰 12% 底 → `onSurface(38%)` / `onSurface(12%)`（**全局所有按钮**） |
| `modules/photoBackup/view/app_photo_backup_view.dart` | AppBar 里 `iconColor: Colors.white` → 删除（回退 `onSurface`） |
| `modules/photo/ai_gps_add/view/ai_gps_add_view.dart` | 白字压 `primaryContainer` → `onPrimaryContainer` |
| `modules/files/views/pc_components/pc_internal_drag_item.dart` | `0xFFE8E8E8` 压 `primaryContainer` ×3 → `onPrimaryContainer` |
| `modules/base/components/side_menu_one_level.dart` | 选中项 → `onPrimary`（3 处） |
| `modules/base/components/side_menu_two_level.dart` | 选中项 → `onPrimary`（3 处） |

### 第 2 批：登录前页面不再写死 `Theme(data: darkTheme)`

> ⚠️ 本批**已被第 5 批取代**（下面保留了演进过程，别照着旧版本改回去）。

演进三步：
1. 原状：`Theme(data: darkTheme)`（编译期常量 = 默认 `shadBlue`）⇒ 换配色登录页永远是蓝。
2. 中间态：`authTheme()` = `darkFor(当前配色)` —— 亮度仍固定暗色，
   因为当时背景是写死的深蓝色照片 `assets/home/login_bg.jpg`。
3. **现状（正确）**：背景改成主题派生（见第 5 批），于是**亮度也必须跟随用户的亮/暗设置**
   ⇒ 登录前页面**不需要任何覆盖**，直接沿用 App 主题；
   各视图里的 `Theme(data: Theme.of(context), ...)` 是**显式 no-op**（顺便保住原 `Builder` 结构）。
   ⛔ **`ThemeApplyService.authTheme()` 已删除，别再往回加。**

### 第 3 批：写死白压在 `primary` 上（同源写法，统一口径）

| 文件 | 处数 | 处理 |
| --- | --- | --- |
| `modules/photo/photo_main/view/app_photo_main_view.dart` | 1 | 选中分段 chip → `onPrimary` |
| `modules/book/book_main/view/app_book_main_view.dart` | 1 | 同上 |
| `modules/video/video_main/view/app_video_main_view.dart` | 1 | 同上 |
| `modules/notes/view/parts/notes_note_list.dart` | 7 | 选中卡片前景/次要文字/预览/菜单图标/置顶图标 → `scheme.onPrimary*` |
| `modules/notes/view/parts/notes_sidebar.dart` | 3 | 选中项前景 + 首字母徽章 → `onPrimary`（302 处所在闭包无 `scheme`，就地 `Theme.of(context)`） |
| `modules/notes/view/parts/notes_mobile_view.dart` | 4 行删除 | FilledButton 显式白前景删除（默认即 `onPrimary`） |
| `modules/notes/view/parts/notes_notebook_chooser.dart` | 3 | `0xFF4F6AF2` → `primary`；FilledButton 白前景/白字删除 |
| `modules/docker/view/parts/docker_dialogs.dart` | 4 | 选中项 + 主色按钮 → `onPrimary` |
| `modules/home/views/pc_components/pc_wallpaper_picker_view.dart` | 4 | 删除按钮 → `onError`；应用按钮白字删除；选中勾 → `onPrimary` |
| `modules/home/views/app_components/app_wallpaper_picker_view.dart` | 2 | 选中勾 → `onPrimary` |
| `modules/home/views/components/user_info_dialog.dart` | 1 | 退出按钮 → `onPrimary` |
| `modules/service/account/view/service_contact_us_view.dart` | 1 | Snackbar 文字 → `Get.theme.colorScheme.onPrimary` |

### 第 4 批：语义色与其他硬编码

| 文件 | 处数 | 处理 |
| --- | --- | --- |
| `modules/docker/view/parts/docker_shared_widgets.dart` | 2 | `error` 底上的白图标/白字 → `onError` |
| `modules/message/views/message_center_view.dart` | 1 | 同上 → `onError` |
| `modules/video/detail/view/parts/video_detail_actions_section.dart` | 4 | 播放按钮 `Colors.blue.shade800`/白字 → `primary`/`onPrimary`；已看进度条轨道 `white(12%)`+`blue.shade400` → `primary(15%)`/`primary` |
| `modules/transmission/transmission_view.dart` | 2 组 | `0xFF2E7D32`/`0xFFE8F5E9` 的 `isLight` 分支 → 一律 `colorScheme.tertiary` 派生（`isLight` 仍被其他 6 处使用，保留） |
| `modules/transfer/views/file_log/file_log_item.dart` | 2 | 两处进度条轨道 `Colors.grey[200]` → `theme.dividerColor` |

**验收**：`flutter build web` 174.3s rc=0；`main.dart.js` 13009631 → **13009388**；
被删的 4 个常量在产物里出现次数**全部为 0**
（`0xFF4F6AF2` / `0xFF2E7D32` / `0xFFE8F5E9` / `0xFFE8E8E8`，用十进制搜，见 §1.3.2 验包手法）。

### 第 5 批：登录页背景主题化 + 窗口角标方向（2026-10-09 16:00）

**问题**：① 登录按钮跟随配色，但背景永远是那张深蓝色照片 ⇒ 永远不搭；
② PC 窗口左上角的「拉伸点阵」方向是反的。

| 内容 | 处理 |
| --- | --- |
| 登录背景 | 新增 `modules/base/components/auth_theme_background.dart`（`AuthThemeBackground`），背景 = `primaryContainer → surfaceContainerHighest` 的**主题派生渐变**（已 `export` 进 `components.dart`）。4 个页面替换：`login_view` / `admin_create_page` / `recover_password_view` / `server_list_view` |
| 登录主题 | 9 处 `data: ThemeApplyService.instance.authTheme()` → `data: Theme.of(context)`（显式 no-op，登录页跟随亮/暗）；`ThemeApplyService.authTheme()` 方法已删除 |
| 登录写死前景 | footer 链接白字 → `onSurface`；4 个按钮内转圈 `Colors.white` → `onPrimary`；服务器项图标 → `onPrimary`（顺带去掉 4 处 `const SizedBox(`，因为里面现在是非 const 表达式） |
| 失效导入 | 8 个文件的 `theme_apply_service.dart` / `background_controller.dart` 导入已删（`BackgroundController` 本身保留，只是没人用了） |
| 窗口角标 | `pc_app_window.dart` 左上角加 `Transform.flip(flipX: true)`：`window_right_corner.png` 的点阵贴在图片**右上角**，搬到左上角必须横向镜像；左下角用 `window_left_corner.png`（点阵本来就贴左下）**不翻** |

**验收**：`flutter build web` 151.9s、日志 `EXITCODE=0`；`main.dart.js` 13009388 → **13005788**。
（产物里 `login_bg.jpg` 还剩 1 次，来自 `BackgroundController` 的默认值字面量，登录页已不引用。）

------------

## 二、仍待人工确认（不确定底色，别盲改）

1. `modules/user/components/custom_user_card.dart:67`、`custom_user_info_card.dart:43`
   白字，底色是 `primary`（超管 OK）**或** `onSurface(0.5)`（普通用户，亮色下≈中灰，对比约 2.8:1 偏弱）。
2. `utils/toast_util.dart:10` `colorText: Colors.white` —— 依赖 GetX SnackBar 默认深底，
   当前看不出问题；若将来给 SnackBar 配浅色主题会立刻白压白。
3. `modules/home/views/app_components/app_apps_grid.dart:126` 白字 + 黑阴影，
   当前只压在手机桌面壁纸上（正确）；若被复用到浅色纯底会失效。
4. `modules/transfer/views/file_log/file_log_item.dart` 另有 ~8 处 `color: Colors.grey`
   纯中性灰文字（197/209/270/287/299/312/319）。`Colors.grey` 是中间调，明暗两种模式下都能看，
   **不属于"白压白"缺陷**；若要严格「以主题为主」应改 `onSurfaceVariant`——等你有空再定。

## 三、明确不要动（刻意深色 / 语义色）

`modules/terminal/**`（终端配色）、`modules/book/reader*/**`（阅读器）、
`modules/video_player/**` 浮层（固定深色）、
`pc_app_window.dart` 里 `terminal`/`image_view` 窗口的固定深色与 macOS 红黄绿交通灯、
图片/视频封面蒙层上的白字（`CustomAlbum` 黑渐变、各类 `*_card.dart`、`app_file_thumb` 播放角标）、
桌面图标文字（白字 + 黑阴影压壁纸）、二维码白底、PDF 搜索高亮、
`Colors.black.withValues(alpha: 0.0x)` 的投影/蒙层。

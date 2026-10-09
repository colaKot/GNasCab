# flutter_client 整套 UI 换皮方案（2026-10-08 评估）

结论先说：**能整套换，但不是"换个模板"那种换法。** 你这套的主题层已经搭好了，
改配色永远只动 2 个文件；真正的成本在 42 个自定义组件和 143 处硬编码颜色。

------------

## 一、现状盘点（实测数据，2026-10-08）

| 项 | 数字 |
---|---|
| dart 文件总数 | 893 |
| 业务页面文件（modules/ 下） | 801 |
| 主题层文件 | 3（light_theme / dark_theme / custom_colors） |
| custom_*.dart 组件 | 42 |
| `Theme.of(context)` / `context.theme` 调用 | 820 处 |
| 引用 CustomColors 的文件 | 116 |
| 直接用 Material 组件（未包 Custom） | 2453 处 |
| 硬编码 `Color(0x...)` | 143 处 / 27 文件 |
| 硬编码 `BorderRadius.circular(N)` | 471 处 |
| 硬编码 `EdgeInsets` | 908 处 |
| 硬编码 `width:/height: 数字` | 2629 处 |
| 布局自适应（isDesktop / LayoutBuilder / MediaQuery） | 226 文件 |

### 分层与换皮成本

| 层 | 范围 | 换整套时的成本 |
|---|---|---|
| L1 主题层 | light_theme / dark_theme / custom_colors | 改 2 个文件，全站生效 |
| L2 组件层 | 42 个 custom_*.dart | 要逐个改，工作量的大头 |
| L3 业务页面层 | 801 文件 | 多数自动跟随主题，少数要调 |
| L4 硬编码散点 | 27 文件 / 143 处 | 换皮时会"漏"，必须逐个清 |

### 硬编码颜色 Top 分布（换皮时重点盯）

| 文件 | 处数 | 备注 |
|---|---|---|
| core/theme/dark_theme.dart | 25 | 主题层本体，正常 |
| core/theme/light_theme.dart | 23 | 主题层本体，正常 |
| modules/terminal/controllers/terminal_controller.dart | 22 | 终端配色，独立体系 |
| modules/video_player/views/app_components/app_video_menus.dart | 9 | 播放器菜单 |
| modules/terminal/views/terminal_view.dart | 8 | |
| modules/home/views/pc_components/pc_app_window.dart | 7 | 自绘窗口 |
| modules/book/reader/view/book_txt_reader_page.dart | 7 | 阅读器（背景/文字对比度敏感） |
| modules/book/reader_comic/view/book_comic_reader_page.dart | 4 | |
| modules/photo/album/view/app_photo_album_home_page.dart | 3 | |

> 注意：终端（terminal）和阅读器（reader）是"故意硬编码"的 —— 前者要模拟终端配色，
> 后者要跟随书页背景保证对比度。这两处**不该跟着主题走**，换皮时要排除。

------------

## 二、四个候选方案

### 方案 A：自建主题层（推荐，零依赖）

**做法**：扩 `custom_colors.dart` 的 ThemeExtension 色槽，把 471 处硬编码圆角和
908 处硬编码间距抽成 token，改 `light_theme.dart` / `dark_theme.dart`。

**改动**：2–4 个文件
**依赖**：+0
**风险**：极低
**适合**：想保持 Windows 11 Fluent 气质、只想支持多套配色 / 圆角风格切换

**成本估算**：抽 5–8 个间距 token + 4 个圆角 token，改 2 个 theme 文件，
清 27 个文件的 143 处硬编码颜色（排除 terminal / reader）。约 1–2 天。

### 方案 B：flex_color_scheme（推荐的"引入外部"选项）

| 项 | 值 |
|---|---|
| pub.dev | `flex_color_scheme` |
| 最新版 | 9.0.0（2026-09-15） |
| **本工程能用的版本** | **8.4.0**（2025-11-29）✅ 首选 |
| 9.x | 9.0.0（2026-09-15），要求 sdk `^3.13.0` + flutter `>=3.47.0` —— **2026-10-08 升级后本机 3.47.5 也够了** |
| Flutter 约束 | 8.4.0 要求 `>=3.38.0`；9.x 要求 `>=3.47.0`。**本机 3.47.5 两条都能上** |
| 许可 | **BSD 3-Clause**（已核 LICENSE 原文），商用闭源无任何限制 |
| 间接依赖 | 8.4.0 仅 `flex_seed_scheme ^4.0.0` + `meta`；9.x 额外要 `material_ui` / `cupertino_ui` |
| 与现有 95 个依赖冲突 | 无 |

> ⚠️ **升级 Flutter 后的一处连带变化**：本仓 import 全是 `package:flutter/material.dart`。
> 3.47 把 Material/Cupertino 拆成独立 pub 包（`material_ui` / `cupertino_ui`），SDK 里仍保留、
> **迁移期不改 import 也能跑**，所以现在不用动。但将来若要跟进 9.x 的写法，得整体换 import。

**为什么仍推荐 8.4.0 而不是 9.0.0**：
- 8.4.0 只依赖 2 个间接包；9.x 要 `material_ui` + `cupertino_ui`，改动面更大
- 9.x 的 API 与 8.x 不同（`import 'package:material_ui/material_ui.dart'` 替代 `flutter/material.dart`）
- 8.4.0 的 BSD-3 许可与 9.x 一致，没有许可优势差异
- 项目铁律是「零下载、能不引就不引」⇒ 除非需要 9.x 独有能力，8.4.0 够用

**收益**：36 套内置配色（`FlexScheme.xxx`）、亮/暗自动配对、surface 混色、
**一个属性统一全站圆角**、Material You 动态取色。

**写法**（8.4.0 版，注意不是 9.x 的 `material_ui` 那套）：

```dart
// light_theme.dart
import 'package:flex_color_scheme/flex_color_scheme.dart';

final ThemeData lightTheme = FlexThemeData.light(
  scheme: FlexScheme.blueWhale,        // 或自定义 FlexSchemeColor.from
  useMaterial3: true,
  extensions: const <ThemeExtension<dynamic>>[
    CustomColors(
      nestedCardColor: Color(0xFFFFFFFF),
      emptyCardColor: Color(0xFFF9F9F9),
      leftTreeBgColor: Color(0xFFEDEDED),
      mainContentBgColor: Color(0xFFFFFFFF),
      oprationBarBgColor: Color(0xFFF3F3F3),
    ),
  ],
);
// dark_theme.dart 同理 FlexThemeData.dark(scheme: FlexScheme.blueWhale)
```

**风险点**：
- **必须锁 `8.4.0` 精确版本**（不是 `^8.4.0`）。`^8.4.0` 会被解析到 9.x 吗？不会 ——
  caret 会停在 8.x 大版本内，但保险起见写 `8.4.0` 不加 caret，防止将来升 SDK 时被动升级。
- flex_color_scheme 会**接管 `elevatedButtonTheme` / `inputDecorationTheme` 等**
  你现有的自定义值。要保留 Windows 风格，需显式传 `elevatedButtonTheme:` 等参数覆盖。
- 它的 `extensions` 参数在 8.x 存在，但建议**保留 CustomColors 不动**，
  这样 116 个引用它的文件零改动。

**适合**：想一次性拿到"36 套配色 + 全站圆角统一"，省掉自己造 token 的功夫。

### 方案 C：getwidget（组件库，不推荐引入）

| 项 | 值 |
|---|---|
| pub.dev 包名 | **`getwidget`**（不是 `get_widget`，后者不存在） |
| 最新版 | 7.0.2（2026-05-24） |
| SDK 约束 | `>=2.12.0 <4.0.0`，无 flutter 约束 —— 兼容性最宽松 |
| 许可 | **MIT**，商用闭源无限制 |
| 规模 | 1000+ 组件 |

**为什么不推荐**：
1. 它的定位是"消费级 App 的花哨组件"（GFCarousel / GFRating / GFAccordion），
   你的产品是 NAS 工具客户端，引入后风格会**变年轻化**，跟 Windows 11 Fluent 气质冲突。
2. 你的 42 个 custom 组件已经覆盖了实际需求（引用面 Top：custom_no_data 65 次、
   custom_extended_image 65 次、custom_bordered_icon_button 51 次、custom_glass_card 37 次）。
   再叠一层第三方 = 两套组件并存，**改主题时要两边都改**。
3. 组件粒度和你的 custom_* 不重合，替换等于重写 42 个文件。

**如果只想借它的某个组件**（比如图表、日期选择器），单独装单个包是可以的，
别整包引。

### 方案 D：换 admin dashboard 模板（不可行）

搜索到的 Flutter 模板（Flutter Responsive Admin Panel 7k★、FlareLine、htsuruo M3 模板、
flutter_admin）都是**后台管理壳**：Provider/BLoC 状态管理、侧栏 + 表格 + 图表、
面向 ERP/CRM 场景。

跟你的差异：
- 状态管理不同（你用 GetX 全功能，模板用 Provider/BLoC）
- 场景不同（你是媒体库客户端，模板是数据看板）
- 你有 801 个业务页面 + 45 个自定义路由 + 桌面/移动/Web 三套布局分支

**套模板 = 推倒重来**。唯一的参考价值是**抄它的配色方案和间距节奏**，
不抄代码。

------------

## 三、我的建议

**组合拳：A 为主 + B 为可选。**

1. **先做 A 的 token 抽取**（不引任何包）——
   把圆角、间距抽成 token，清掉 143 处硬编码颜色（排除 terminal / reader）。
   这一步做完，"换配色"就是纯改 2 个文件的事，以后无论引不引 B 都是稳的。

2. **如果要 36 套配色，再引 B**（`flex_color_scheme: 8.4.0` 精确锁版本）——
   它俩不冲突：A 的 token 放在 CustomColors 里，B 管 ColorScheme 和组件主题。

3. **C 和 D 都不动。**

**动手顺序建议**（每步都能编译验证）：
```
① 抽间距/圆角 token        → dart_analyze 静态检查
② 清 143 处硬编码颜色       → dart_analyze
③ 改 light/dark_theme     → flutter build bundle 闸门
④ (可选) 引 flex_color_scheme 8.4.0 → flutter build bundle
⑤ 视觉验收：PC / 移动 / Web 各看一遍
```

------------

## 四、闸门与坑（沿用速查文档 §9）

- **闸门是 `flutter build bundle`**，不是 analyze。不需 VS、不需安卓许可。
- 静态诊断：`python tool/dart_analyze.py flutter_client`
- **排除要写进就近的 `analysis_options.yaml`**，不要写根目录。
- 引入新包后必须跑 `flutter pub get`，注意本机 `PUB_HOSTED_URL` 未设置，默认走 pub.dev；
  拉不动就临时设 `PUB_HOSTED_URL=https://pub.flutter-io.cn`（实测 1.46s 可达，pub.dev 3.54s）。

------------

## 五、核查记录（2026-10-08）

| 核查项 | 结论 |
|---|---|
| flex_color_scheme 许可 | BSD 3-Clause，已读 LICENSE 原文，商用无限制 |
| flex_color_scheme 版本兼容 | 8.4.0 要求 flutter≥3.38.0 ✅；9.x 要求≥3.47.0 —— 本机 **已升级到 3.47.5，两者都满足**（首选 8.4.0） |
| getwidget 许可 | MIT，包名是 `getwidget` |
| 本机 pub 源连通 | pub.dev 200（3.54s）、pub.flutter-io.cn 200（1.46s） |
| 本地 pub cache 是否已有这些包 | ❌ 均无，需首次下载 |
| 现有依赖冲突面 | 95 个顶层依赖，flex_color_scheme 仅需 2 个间接依赖，无冲突 |
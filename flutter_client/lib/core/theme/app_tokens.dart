/// 设计 token —— 全局间距 / 圆角 / 控件尺寸的唯一来源
///
/// 为什么要这个文件（2026-10-08 引入）：
/// 升级前全工程散落着 471 处 `BorderRadius.circular(N)`、908 处 `EdgeInsets`、
/// 2629 处数字宽高，圆角档位从 2 到 40、间距档位从 0 到 92 全靠手敲，
/// 改一次风格要全仓库找。这里把高频档位收成命名常量。
///
/// ⭐ 档位是按**现有代码实测分布**定的，不是拍脑袋：
///   圆角高频（次）：12 / 8 / 10 / 999 / 16 / 14 / 6 / 4 / 18
///   间距高频（次）：12 / 16 / 8 / 6 / 10 / 4 / 20 / 2 / 14
///   ⚠️ `999` / `99` = 胶囊形徽章（书卡标签、播放徽章、Docker 状态点），
///      **不是随手写的数字**，故保留为 [pill]；大间距 72/80/92 是
///      Dock / 标题栏 / 底部操作条的固定偏移，也不进常规档位。
///
/// 用法：
/// ```dart
/// borderRadius: BorderRadius.circular(AppRadius.card)   // 12
/// padding: const EdgeInsets.all(AppSpace.md)            // 12
/// ```
class AppSpace {
  const AppSpace._();

  /// 2 —— 极紧微调（同图标内的字距、微小间隙）
  static const double xxs = 2;

  /// 4 —— 图标与文字之间、标签内边距
  static const double xs = 4;

  /// 6 —— 紧凑控件内边距（PC 侧栏项）
  static const double sm = 6;

  /// 8 —— 控件之间、卡片内容边距（最高频之一）
  static const double md = 8;

  /// 10 —— 中等留白
  static const double lg = 10;

  /// 12 —— 卡片内边距、列表项间距（**全工程最高频**）
  static const double xl = 12;

  /// 14 —— 表单字段垂直间距
  static const double xxl = 14;

  /// 16 —— 页面内容外边距
  static const double page = 16;

  /// 20 —— 区块之间的分隔
  static const double section = 20;
}

/// 圆角档位。命名对应语义而非数值，换主题时按语义批量替换即可。
class AppRadius {
  const AppRadius._();

  /// 2 —— 进度条、微小指示器
  static const double xs = 2;

  /// 4 —— Windows 风格控件（按钮/输入框），**与 Fluent 对齐，不要调大**
  static const double control = 4;

  /// 6 —— 小徽章、小图标底板
  static const double sm = 6;

  /// 8 —— 中等卡片、悬浮项
  static const double md = 8;

  /// 10 —— 侧栏项、菜单项（Windows 11 风格圆角）
  static const double item = 10;

  /// 12 —— **卡片默认圆角**（最高频），也是 Windows 11 卡片规格
  static const double card = 12;

  /// 14 —— 大卡片、对话框
  static const double lg = 14;

  /// 16 —— 模态/ 浮层
  static const double sheet = 16;

  /// 999 —— 胶囊形（徽章、标签、状态点）。保留原值不折算。
  static const double pill = 999;
}

/// 控件固定尺寸（替代散落的数字宽高）
class AppSize {
  const AppSize._();

  /// 常规按钮高度
  static const double buttonHeight = 40;

  /// 常规按钮最小宽度
  static const double buttonMinWidth = 80;

  /// 侧栏项高度
  static const double sideItemHeight = 40;

  /// 图标按钮方形边长
  static const double iconButton = 40;

  /// 顶部工具条高度
  static const double toolBarHeight = 56;

  /// 输入框高度
  static const double fieldHeight = 40;
}

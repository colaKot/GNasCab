import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:WaterNasOS/core/theme/app_skin.dart';
import 'package:WaterNasOS/core/theme/skin_presets.dart';
import '../pc_home_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../base/components/custom_inset_border_shell.dart';

/// 窗口内导航层级（2026-10-10）
///
/// 一级页（应用首页）：标题栏右侧显示 缩小 / 放大(还原) / 关闭 三个按钮；
/// 二级页：只显示一个「返回」按钮，返回动作由内容层提供（[onBack]）。
///
/// 带 `==` 实现是为了避免每帧重复通知 —— Dart 里**同一实例的同名方法 tear-off
/// 是相等的**，所以内容层可以直接把 `controller.navigateBack` 传进来。
@immutable
class PcWindowNavState {
  final bool secondary;
  final VoidCallback? onBack;

  const PcWindowNavState.home()
    : secondary = false,
      onBack = null;

  const PcWindowNavState.secondary(this.onBack) : secondary = true;

  @override
  bool operator ==(Object other) =>
      other is PcWindowNavState &&
      other.secondary == secondary &&
      other.onBack == onBack;

  @override
  int get hashCode => Object.hash(secondary, onBack);
}

/// 承载 [PcWindowNavState] 的可监听容器：由 `PcAppWindow` 持有并下发，
/// 内容层在 build 后（post-frame）调用 [update] 上报当前层级。
class PcWindowNav extends ValueNotifier<PcWindowNavState> {
  PcWindowNav() : super(const PcWindowNavState.home());

  void update(PcWindowNavState next) {
    if (next == value) return;
    value = next;
  }
}

class PcWindowScope extends InheritedWidget {
  final String windowId;

  /// ⭐⭐ 窗口按钮组在标题栏右侧占用的总宽度（2026-10-09）。
  ///
  /// 各 app 的顶栏若右侧有元素（搜索栏 / 图标按钮 / 下拉），必须用它做
  /// **水平让位**，否则会被窗口按钮压住：
  /// ```dart
  /// final cw = PcWindowScope.of(context)?.titleBarControlsWidth ?? 0;
  /// Padding(padding: EdgeInsets.only(right: cw))
  /// ```
  /// ⛔ 不要写死数字 —— 按钮尺寸改了这里要跟着变。
  final double titleBarControlsWidth;

  /// ⭐ 窗口内导航层级（2026-10-10）。内容层可用它上报「二级页」状态：
  /// ```dart
  /// PcWindowScope.of(context)?.nav.update(const PcWindowNavState.home());
  /// ```
  final PcWindowNav nav;

  /// ⭐⭐ 框架已为内容层预留的**顶部让位高度**（2026-10-10）。
  ///
  /// 非全屏窗口 = 当前皮肤的 [AppSkin.titleBarHeight]（内容整体下移，顶部只留
  /// 窗口按钮）；全屏窗口 = 0。子组件用 [PcAppWindow.titleBarHeightFor] 读它，
  /// 从而**不必、也不应**再自己叠一层让位。
  final double contentTopInset;

  const PcWindowScope({
    super.key,
    required this.windowId,
    this.titleBarControlsWidth = 0,
    this.contentTopInset = 0,
    required this.nav,
    required super.child,
  });

  static PcWindowScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PcWindowScope>();
  }

  @override
  bool updateShouldNotify(PcWindowScope oldWidget) =>
      windowId != oldWidget.windowId ||
      titleBarControlsWidth != oldWidget.titleBarControlsWidth ||
      contentTopInset != oldWidget.contentTopInset ||
      nav != oldWidget.nav;
}

class PcAppWindow extends StatefulWidget {
  final String windowId;
  final WidgetBuilder viewBuilder;
  final String? title;
  final bool showTitle;
  const PcAppWindow({
    super.key,
    required this.windowId,
    required this.viewBuilder,
    this.title,
    this.showTitle = true,
  });

  /// 标题栏高度兜底值，**必须与默认皮肤 `windows11` 的 `titleBarHeight` 一致**。
  /// 2026-10-10：按钮改 40×40 方块后，标题栏 40 → 48（上下各 4 让位）。
  static const double titleBarHeight = 48;
  static const double _topResizeStripHeight = 4;

  /// ⭐⭐ 窗口按钮组占用宽度（2026-10-09）。
  /// 顶部有元素、且该元素要靠右的 app 顶栏，必须用这个值做水平让位。
  /// ⚠️ 这是一个**兜底常量**（取默认皮肤）；app 视图内部优先用
  /// `PcWindowScope.of(context)?.titleBarControlsWidth`（能跟随实例/皮肤）。
  static double get titleBarControlsWidth =>
      SkinPresets.defaultSkin.titleBarControlsWidth;

  /// 全屏铺满的窗口：内容本身就是黑底满屏，**不做顶部让位**；
  /// 它们的顶部叠加层仍按 [PcWindowScope.titleBarControlsWidth] 自己躲开按钮。
  static const Set<String> fullBleedWindowIds = <String>{
    'video_player',
    'image_view',
    'terminal',
  };

  /// ⭐⭐ 标题栏高度（2026-10-09 换肤）：跟随当前皮肤。
  /// ⚠️ 静态常量 [titleBarHeight] 只是**默认皮肤兜底**；有 context 的地方一律走这里，
  /// 否则切换皮肤（如「紧凑」标题栏变矮）后垂直让位会对不上。
  ///
  /// ⚠️⚠️ **2026-10-10 起语义变更**：标题栏垂直让位已由 [PcAppWindow] **统一负责**
  /// （内容层整体下移 [PcWindowScope.contentTopInset]）。所以在普通窗口内，本方法
  /// **恒返回 0** —— 页面不要、也不该再自己让位，否则会双倍留白。
  /// 只有全屏窗口（见 [fullBleedWindowIds]）才返回真实高度。
  static double titleBarHeightFor(BuildContext context) {
    final scope = PcWindowScope.of(context);
    if (scope != null && scope.contentTopInset > 0) return 0;
    return Theme.of(context).extension<AppSkin>()?.titleBarHeight ??
        titleBarHeight;
  }

  @override
  State<PcAppWindow> createState() => _PcAppWindowState();
}

class _PcAppWindowState extends State<PcAppWindow> {
  /// 只创建一次，双击检测和内容可交互性探测复用
  final GlobalKey _contentKey = GlobalKey();

  /// 拖拽开始时清除内容层在命中测试缓存中的 entry
  final GlobalKey _passthroughKey = GlobalKey();

  /// ⭐ 框架给内容层预留的顶部让位高度（标题栏净空），用于命中测试坐标换算。
  double _contentTopInset = 0;

  /// ⭐ 窗口内导航层级（2026-10-10）：内容层上报，二级页标题栏只显示「返回」
  final PcWindowNav _nav = PcWindowNav();

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  void _onDragStateChanged(bool isDragging) {
    if (isDragging) {
      final ro =
          _passthroughKey.currentContext?.findRenderObject()
              as _RenderContentPassthrough?;
      // 将缓存的 HitTestResult 中内容 entry 替换为 no-op，
      // 后续 pointer move 复用缓存时不会再派发给内容层
      ro?.clearContentEntries();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal = widget.windowId == 'terminal';
    final isGallery = widget.windowId == 'image_view';
    final isMovie = widget.windowId == 'movie';
    if (isTerminal || isGallery) {
      return Theme(
        data: darkTheme,
        child: Builder(builder: (context) => _buildWindow(context)),
      );
    }
    return _buildWindow(context);
  }

  Widget _buildWindow(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final theme = Theme.of(context);
    // ⭐ 外观皮肤：窗口圆角 / 标题栏高度 / 右上角按钮造型都从这里取（2026-10-09）
    final skin = theme.extension<AppSkin>() ?? SkinPresets.defaultSkin;
    final isVideoPlayer = widget.windowId == 'video_player';
    final canResize = ctrl.windowCanResize(widget.windowId);
    final outerRadius = skin.windowRadius;
    final themeBackgroundColor = isVideoPlayer
        ? Colors.black
        : theme.scaffoldBackgroundColor;
    final isDark = theme.brightness == Brightness.dark;
    final frameColor = isDark
        ? const Color(0xFF3A3A3A).withValues(alpha: 0.4)
        : const Color(0xFFE0E0E0).withValues(alpha: 0.3);

    // ⭐⭐ 标题栏让位由框架统一负责（2026-10-10）：
    //   普通窗口 → 内容整体下移 titleBarHeight，右上角三按钮独占标题栏，
    //              子树不必再做垂直让位；
    //   全屏窗口 → 内容顶到窗口边缘，顶部叠加层仍按按钮组宽度自己让位。
    final fullBleed = PcAppWindow.fullBleedWindowIds.contains(widget.windowId);
    _contentTopInset = fullBleed ? 0 : skin.titleBarHeight;

    final appContent = PcWindowScope(
      windowId: widget.windowId,
      // ⭐ 让子树能读到按钮组宽度，右侧元素据此让位（跟随皮肤）
      // ⚠️ 框架已让位时传 0：顶栏已移到标题栏下方，再让位只会白留一截。
      titleBarControlsWidth: fullBleed ? skin.titleBarControlsWidth : 0,
      // ⭐ 框架已预留的顶部让位高度，子组件据此避免重复让位
      contentTopInset: _contentTopInset,
      // ⭐ 让子树能上报窗口导航层级（二级页 → 只显示返回按钮）
      nav: _nav,
      child: widget.viewBuilder(context),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius),
        clipBehavior: Clip.antiAlias,
        child: CustomInsetBorderShell(
          radius: outerRadius,
          borderWidth: skin.windowBorderWidth,
          borderColor: frameColor,
          backgroundColor: themeBackgroundColor,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => ctrl.focusWindow(widget.windowId),
            child: Stack(
              children: [
                // 底层：拖拽区 — pointer down 时探测内容有无纯 tap 组件，有则跳过拖拽
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: skin.titleBarHeight,
                  child: _DragArea(
                    windowId: widget.windowId,
                    checkInteractive: _hasInteractiveContentAt,
                    onDragStateChanged: _onDragStateChanged,
                  ),
                ),
                // 中层：内容（hitTest 永远返回 false，让 Stack 继续往下遍历）
                // ⭐ 顶部让出标题栏：非全屏窗口内容整体下移，标题栏只留窗口按钮。
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(top: _contentTopInset),
                    child: _ContentHitPassthrough(
                      key: _passthroughKey,
                      child: Builder(
                        key: _contentKey,
                        builder: (_) => appContent,
                      ),
                    ),
                  ),
                ),
                // 顶层：窗口控制按钮（右上角，Windows 习惯）
                // ⭐ 按导航层级切换（2026-10-10）：
                //   一级页（应用首页）→ 缩小 / 放大(还原) / 关闭；
                //   二级页 → 只有一个「返回」按钮（内容层通过 PcWindowScope 上报）。
                Positioned(
                  right: 12,
                  top: (skin.titleBarHeight - skin.titleBarButtonHeight) / 2,
                  child: ValueListenableBuilder<PcWindowNavState>(
                    valueListenable: _nav,
                    builder: (context, nav, _) {
                      // 二级页：右上角只剩一个「返回」（与三按钮同款）
                      if (nav.secondary) {
                        final onBack = nav.onBack;
                        return _TitleBarButton(
                          skin: skin,
                          icon: TablerIcons.arrowLeft,
                          tooltip: 'back'.tr,
                          onTap: onBack == null
                              ? null
                              : () {
                                  PcHomeController.instance.focusWindow(
                                    widget.windowId,
                                  );
                                  onBack();
                                },
                        );
                      }
                      return _WindowButtons(
                        windowId: widget.windowId,
                        skin: skin,
                        canMinimize: ctrl.windowCanMinimize(widget.windowId),
                        canMaximize: ctrl.windowCanMaximize(widget.windowId),
                      );
                    },
                  ),
                ),
                // 右上角已让给窗口控制按钮，角标换到左上角与左下角标呼应。
                // ⚠️ 必须 `flipX`：`window_right_corner.png` 的点阵贴在图片的**右上角**
                // （左边那个 `window_left_corner.png` 贴在左下角，所以左下角直接用是对的）。
                // 当初从左下搬到左上时漏了镜像，于是这条点阵方向看着是**反的**
                //（铁柱：「左上角有个拉伸的小图案，但是反了」）。
                if (canResize)
                  Positioned(
                    left: 1.6,
                    top: 1.6,
                    child: Tooltip(
                      message: '',
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Transform.flip(
                          flipX: true,
                          child: Image.asset(
                            'assets/icons/home/window_right_corner.png',
                            width: 16,
                            height: 16,
                            color:
                                (isVideoPlayer
                                        ? Colors.white
                                        : theme.colorScheme.onSurface)
                                    .withValues(alpha: 0.5),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (canResize)
                  Positioned(
                    left: 1.6,
                    bottom: 1.6,
                    child: Tooltip(
                      message: '',
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Image.asset(
                          'assets/icons/home/window_left_corner.png',
                          width: 16,
                          height: 16,
                          color:
                              (isVideoPlayer
                                      ? Colors.white
                                      : theme.colorScheme.onSurface)
                                  .withValues(alpha: 0.5),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                if (canResize)
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: PcAppWindow._topResizeStripHeight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 探测内容层 [localPosition] 是否有交互组件（按钮等）。
  ///
  /// 匹配两类 [RenderPointerListener]：
  /// 1. 明确设置了 onPointerUp 的 Listener（原始逻辑，保留兼容）
  /// 2. 仅设置了 onPointerDown（GestureDetector 按钮），但限定其 RenderBox
  ///    尺寸必须较小（<=250），以排除大面积容器如 Scrollable/RawGestureDetector、
  ///    悬停包裹组件等。容器级的 RenderPointerListener 覆盖整个内容区域，
  ///    不应阻止标题栏的拖拽和双击行为。
  bool _hasInteractiveContentAt(Offset localPosition) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;

    // ⭐ 内容层已整体下移 [_contentTopInset]（标题栏净空），而 [localPosition] 是
    //    相对标题栏拖拽区的坐标 ⇒ 先换算成内容层局部坐标。标题栏范围内的点会变成
    //    负值、必然落在内容层之外，hitTest 直接失败 —— 正是我们要的「标题栏可拖拽」。
    final local = localPosition - Offset(0, _contentTopInset);

    final result = BoxHitTestResult();
    if (!box.hitTest(result, position: local)) return false;

    return result.path.any((e) {
      if (e.target is! RenderPointerListener) return false;
      final l = e.target as RenderPointerListener;
      if (l.onPointerDown == null || l.onPointerMove != null) return false;

      // 明确设置了 onPointerUp → 肯定是有意处理 tap
      if (l.onPointerUp != null) return true;

      // 仅 onPointerDown（GestureDetector 常见模式）：检查尺寸，
      // 大面积容器（如 ScrollView 内部的 RawGestureDetector）跳过
      final rb = l as RenderBox;
      return rb.size.width <= 250 && rb.size.height <= 250;
    });
  }
}

/// 包裹内容层，hitTest 永远返回 false。
/// 这样 Stack 会继续遍历到底层的拖拽区，让内容可点击组件优先响应，
/// 未消费的事件自然落到拖拽区。
/// 同时记录内容 entry 在 HitTestResult 中的位置，
/// 拖拽开始时通过 [clearContentEntries] 从缓存结果中剔除，
/// 避免 pointer move 复用缓存时内容响应事件。
class _ContentHitPassthrough extends SingleChildRenderObjectWidget {
  const _ContentHitPassthrough({super.key, required super.child});

  @override
  _RenderContentPassthrough createRenderObject(BuildContext context) =>
      _RenderContentPassthrough();
}

class _RenderContentPassthrough extends RenderProxyBox {
  BoxHitTestResult? _lastResult;
  int _contentEntryStart = -1;
  int _contentEntryEnd = -1;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      _contentEntryStart = result.path.length;
      child!.hitTest(result, position: position);
      _contentEntryEnd = result.path.length;
      _lastResult = result;
    }
    return false;
  }

  /// 将缓存的 HitTestResult 中内容层 entry 原地替换为 no-op，
  /// 不改变列表结构，避免 ConcurrentModificationError。
  /// Flutter pointer move 复用 pointer down 的命中测试结果，
  /// 拖拽开始时调用此方法，后续 move 事件将不再派发给内容。
  void clearContentEntries() {
    if (_lastResult != null && _contentEntryStart >= 0) {
      final path = _lastResult!.path as List<HitTestEntry>;
      for (
        int i = _contentEntryStart;
        i < _contentEntryEnd && i < path.length;
        i++
      ) {
        // 替换为自身，RenderObject 默认 handleEvent 是 no-op
        path[i] = BoxHitTestEntry(this, Offset.zero);
      }
      _contentEntryStart = -1;
      _contentEntryEnd = -1;
      _lastResult = null;
    }
  }
}

/// 标题栏拖拽区。Pointer down 时先通过 [checkInteractive] 探测内容层
/// 是否有纯 tap 组件，有则跳过拖拽（按钮即时响应）；
/// 没有才启动手动拖拽追踪。同时内置双击最大化检测。
class _DragArea extends StatefulWidget {
  final String windowId;
  final bool Function(Offset localPosition) checkInteractive;
  final ValueChanged<bool> onDragStateChanged;

  const _DragArea({
    required this.windowId,
    required this.checkInteractive,
    required this.onDragStateChanged,
  });

  @override
  State<_DragArea> createState() => _DragAreaState();
}

class _DragAreaState extends State<_DragArea> {
  bool _isDragging = false;
  Offset? _dragOrigin;

  // 双击检测
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  static const _doubleTapWindow = Duration(milliseconds: 300);
  static const _doubleTapDistance = 20.0;

  void _handlePointerDown(PointerDownEvent event) {
    final ctrl = PcHomeController.instance;
    ctrl.focusWindow(widget.windowId);

    // 内容层该位置有纯 tap 按钮 → 不启动拖拽，让它优先响应
    if (widget.checkInteractive(event.localPosition)) return;

    // 双击检测
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < _doubleTapWindow &&
        (_lastTapPosition! - event.localPosition).distance <
            _doubleTapDistance) {
      _lastTapTime = null;
      if (ctrl.windowCanMaximize(widget.windowId)) {
        ctrl.maximizeApp(widget.windowId);
      }
      return;
    }
    _lastTapTime = now;
    _lastTapPosition = event.localPosition;

    _isDragging = true;
    _dragOrigin = event.position;
    widget.onDragStateChanged(true);
  }

  void _stopDragging() {
    _isDragging = false;
    _dragOrigin = null;
    widget.onDragStateChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: (event) {
        if (!_isDragging || _dragOrigin == null) return;
        if (ctrl.isMaximized(widget.windowId)) return;
        final delta = event.position - _dragOrigin!;
        final current =
            ctrl.windowPosition(widget.windowId) ??
            ctrl.getWindowPos(widget.windowId);
        ctrl.setLastPosition(widget.windowId, current + delta);
        _dragOrigin = event.position;
      },
      onPointerUp: (_) => _stopDragging(),
      onPointerCancel: (_) => _stopDragging(),
      child: const SizedBox.expand(),
    );
  }
}

/// 窗口右上角三个常规按钮：缩小 / 放大(还原) / 关闭（2026-10-10 改版）。
///
/// ⭐ 与二级页的「返回」按钮**完全同款**：方形圆角、透明中性底、图标常显；
/// 尺寸 / 间距 / 图标大小全部由皮肤驱动（默认皮肤 40×40）。
/// ⛔ 不再使用红/黄/绿语义色 —— 统一成无色透明方块，靠图标区分功能。
class _WindowButtons extends StatelessWidget {
  final String windowId;

  /// ⭐ 外观皮肤：按钮造型 / 尺寸由它决定
  final AppSkin skin;
  final bool canMinimize;
  final bool canMaximize;

  const _WindowButtons({
    required this.windowId,
    required this.skin,
    required this.canMinimize,
    required this.canMaximize,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final isMaximized = ctrl.isMaximized(windowId);
    // ⭐ 图标统一用 Tabler（MIT）：maximize = 四角外扩 / minimize = 四角内收（还原态）
    final maximizeIcon = (canMaximize && isMaximized)
        ? TablerIcons.minimize
        : TablerIcons.maximize;

    /// 点击前先把窗口置顶（与旧行为一致）
    VoidCallback wrap(VoidCallback action) => () {
      ctrl.focusWindow(windowId);
      action();
    };

    // Windows 习惯：左 → 右 依次为 最小化、最大化、关闭（关闭贴最右）
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleBarButton(
          skin: skin,
          icon: TablerIcons.minus,
          tooltip: 'home_window_min'.tr,
          onTap: canMinimize ? wrap(() => ctrl.minimizeApp(windowId)) : null,
        ),
        SizedBox(width: skin.titleBarButtonSpacing),
        _TitleBarButton(
          skin: skin,
          icon: maximizeIcon,
          tooltip: (canMaximize && isMaximized)
              ? 'home_window_restore'.tr
              : 'home_window_max'.tr,
          onTap: canMaximize ? wrap(() => ctrl.maximizeApp(windowId)) : null,
        ),
        SizedBox(width: skin.titleBarButtonSpacing),
        _TitleBarButton(
          skin: skin,
          icon: TablerIcons.x,
          tooltip: 'home_window_close'.tr,
          onTap: wrap(() => ctrl.closeApp(windowId)),
        ),
      ],
    );
  }
}

/// 标题栏按钮（2026-10-10 统一造型）—— 三个窗口按钮与二级页「返回」共用：
/// **方形圆角 + 透明中性底 + 图标常显**。
///
/// 底色取中性色、按亮/暗模式给不同透明度（暗色提亮 / 亮色压深），
/// 悬停时加深一档；禁用时图标降透明度且不可点。尺寸全部来自皮肤。
class _TitleBarButton extends StatefulWidget {
  final AppSkin skin;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _TitleBarButton({
    required this.skin,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovering = false;

  /// 方形圆角：Windows 取高度的 20%（40 高 → 8）；macOS 皮肤仍是正圆，极简更方
  double get _radius => switch (widget.skin.titleBarButtonStyle) {
    AppTitleBarButtonStyle.macos => widget.skin.titleBarButtonHeight / 2,
    AppTitleBarButtonStyle.minimal => 2,
    AppTitleBarButtonStyle.windows => widget.skin.titleBarButtonHeight * 0.2,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = widget.onTap != null;
    final hovered = _isHovering && enabled;
    // 透明中性底：暗色模式提亮、亮色模式压深，两种配色下都不糊
    final bg = isDark
        ? Colors.white.withValues(alpha: hovered ? 0.26 : 0.14)
        : theme.colorScheme.onSurface.withValues(
            alpha: hovered ? 0.18 : 0.08,
          );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.skin.titleBarButtonWidth,
            height: widget.skin.titleBarButtonHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              color: bg,
            ),
            child: Icon(
              widget.icon,
              size: widget.skin.titleBarButtonIconSize,
              color: enabled
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左栏（侧边栏）容器：自带底色，并把同一块底色**补画**到窗口标题栏左侧。
///
/// ⚠️ 为什么要它：2026-10-10 起 [PcAppWindow] 会把内容层整体下移
/// [PcWindowScope.contentTopInset]，左栏因此离开窗口上沿，顶部那截露出窗口底色。
/// 用它替掉左栏外层的 `Container(color: ...)`，就能把底色补回标题栏区域 ——
/// 只改绘制、不动布局（`Stack(clipBehavior: Clip.none)` + 负 top 探出），
/// 所以菜单位置 / 点击区域 / 折叠动画全都不受影响。
///
/// 标题栏右侧仍归三个窗口按钮独占，于是窗口自上而下就是干净的三段式：
/// 「左栏色 + 右上净空(窗口按钮)」/「左栏 + 顶栏」/「左栏 + 内容」。
///
/// 用法与 `Container` 一致：`Container(color: c, child: x)` 直接换成
/// `PcLeftRailTopExtend(color: c, child: x)`，缩进都不用动。
class PcLeftRailTopExtend extends StatelessWidget {
  /// 纯色底色（最常用的写法）。
  final Color? color;

  /// 需要边框 / 圆角时改用这个；给了它就忽略 [color]。
  final BoxDecoration? decoration;

  /// 固定宽度（如 transmission 左栏的 180）。
  final double? width;

  final Widget child;

  const PcLeftRailTopExtend({
    super.key,
    this.color,
    this.decoration,
    this.width,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final deco =
        decoration ?? (color == null ? null : BoxDecoration(color: color));
    final inset = PcWindowScope.of(context)?.contentTopInset ?? 0;
    if (deco == null || deco.color == null || inset <= 0) {
      return Container(width: width, decoration: deco, child: child);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 向上探出标题栏高度的一块同色背景；不参与命中测试，免得抢走拖拽。
        // 圆角清零：补画的这块贴在窗口上沿，圆角交给窗口自己的 ClipRRect 处理。
        Positioned(
          left: 0,
          right: 0,
          top: -inset,
          height: inset,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: deco.copyWith(borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        Container(width: width, decoration: deco, child: child),
      ],
    );
  }
}

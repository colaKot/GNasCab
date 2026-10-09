import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import '../pc_home_controller.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../base/components/custom_inset_border_shell.dart';

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

  const PcWindowScope({
    super.key,
    required this.windowId,
    this.titleBarControlsWidth = 0,
    required super.child,
  });

  static PcWindowScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PcWindowScope>();
  }

  @override
  bool updateShouldNotify(PcWindowScope oldWidget) =>
      windowId != oldWidget.windowId ||
      titleBarControlsWidth != oldWidget.titleBarControlsWidth;
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

  static const double titleBarHeight = 40;
  static const double _topResizeStripHeight = 4;

  /// ⭐⭐ 窗口按钮组占用宽度（2026-10-09）。
  /// 顶部有元素、且该元素要靠右的 app 顶栏，必须用这个值做水平让位。
  /// ⚠️ 这是一个**兜底常量**；app 视图内部优先用
  /// `PcWindowScope.of(context)?.titleBarControlsWidth`（能跟随实例）。
  static double get titleBarControlsWidth =>
      _TrafficLightButtonsState.totalWidth;

  @override
  State<PcAppWindow> createState() => _PcAppWindowState();
}

class _PcAppWindowState extends State<PcAppWindow> {
  /// 只创建一次，双击检测和内容可交互性探测复用
  final GlobalKey _contentKey = GlobalKey();

  /// 拖拽开始时清除内容层在命中测试缓存中的 entry
  final GlobalKey _passthroughKey = GlobalKey();

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
    final isVideoPlayer = widget.windowId == 'video_player';
    final canResize = ctrl.windowCanResize(widget.windowId);
    const outerRadius = 16.0;
    final themeBackgroundColor = isVideoPlayer
        ? Colors.black
        : theme.scaffoldBackgroundColor;
    final isDark = theme.brightness == Brightness.dark;
    final frameColor = isDark
        ? const Color(0xFF3A3A3A).withValues(alpha: 0.4)
        : const Color(0xFFE0E0E0).withValues(alpha: 0.3);

    final appContent = PcWindowScope(
      windowId: widget.windowId,
      // ⭐ 让子树能读到按钮组宽度，右侧元素据此让位
      titleBarControlsWidth: _TrafficLightButtonsState.totalWidth,
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
          borderWidth: 0.5,
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
                  height: PcAppWindow.titleBarHeight,
                  child: _DragArea(
                    windowId: widget.windowId,
                    checkInteractive: _hasInteractiveContentAt,
                    onDragStateChanged: _onDragStateChanged,
                  ),
                ),
                // 中层：内容（hitTest 永远返回 false，让 Stack 继续往下遍历）
                Positioned.fill(
                  child: _ContentHitPassthrough(
                    key: _passthroughKey,
                    child: Builder(
                      key: _contentKey,
                      builder: (_) => appContent,
                    ),
                  ),
                ),
                // 顶层：窗口控制按钮（右上角，Windows 习惯）
                Positioned(
                  right: 12,
                  top:
                      (PcAppWindow.titleBarHeight -
                          _TrafficLightButtonsState._btnHeight) /
                      2,
                  child: _TrafficLightButtons(
                    windowId: widget.windowId,
                    canMinimize: ctrl.windowCanMinimize(widget.windowId),
                    canMaximize: ctrl.windowCanMaximize(widget.windowId),
                  ),
                ),
                // 右上角已让给窗口控制按钮，角标换到左上角与左下角标呼应
                if (canResize)
                  Positioned(
                    left: 1.6,
                    top: 1.6,
                    child: Tooltip(
                      message: '',
                      child: SizedBox(
                        width: 20,
                        height: 20,
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

    final result = BoxHitTestResult();
    if (!box.hitTest(result, position: localPosition)) return false;

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

class _TrafficLightButtons extends StatefulWidget {
  final String windowId;
  final bool canMinimize;
  final bool canMaximize;

  const _TrafficLightButtons({
    required this.windowId,
    required this.canMinimize,
    required this.canMaximize,
  });

  @override
  State<_TrafficLightButtons> createState() => _TrafficLightButtonsState();
}

class _TrafficLightButtonsState extends State<_TrafficLightButtons> {
  bool _isHovering = false;

  /// ⭐ 扁平化按钮尺寸（2026-10-09）。
  /// 原先是 12×12 圆点 + 8 间距，在40px 标题栏里又小又圆，视觉上像三个小点。
  /// 现在改成 **24×16 圆角矩形**，宽扁造型更贴Windows 11 / macOS 现代窗口。
  static const double _btnWidth = 24.0;
  static const double _btnHeight = 16.0;
  static const double _spacing = 4.0;
  static const double _iconSize = 11.0;

  /// ⭐⭐ 按钮组在标题栏里占的总宽度（含间距 + 右侧留白）。
  /// 各 app 的顶栏要靠它做**水平让位**，否则右侧元素会被按钮压住。
  /// 用 `PcWindowScope.of(context)?.titleBarControlsWidth` 取，不要写死数字。
  static double get totalWidth => _btnWidth * 3 + _spacing * 2 + 12;

  bool get _isFocused =>
      PcHomeController.instance.topmostApp == widget.windowId;

  /// ⭐ 语义色仍保留 macOS 红/黄/绿的身份识别（这是功能约定，不是风格），
  /// 但**从主题派生明暗变体**：暗色模式下用更亮的色，亮色模式下用更沉的色，
  /// 保证在任何配色/亮暗下都有足够对比度。
  static const Color _closeBase = Color(0xFFFF5F57);
  static const Color _minimizeBase = Color(0xFFFFBD2E);
  static const Color _maximizeBase = Color(0xFF28CA41);

  /// 窗口未聚焦时统一压成中性灰（保留一点原色相，避免三个点糊成一团）
  Color _dotColor(Color activeColor, Brightness brightness) {
    final cs = Theme.of(context).colorScheme;
    if (!_isFocused) {
      return brightness == Brightness.dark
          ? cs.onSurface.withValues(alpha: 0.28)
          : cs.onSurface.withValues(alpha: 0.32);
    }
    // 暗色模式提亮、亮色模式压深，保证按钮在两种背景下都"跳"出来
    return brightness == Brightness.dark
        ? Color.lerp(activeColor, Colors.white, 0.22)!
        : Color.lerp(activeColor, Colors.black, 0.06)!;
  }

  /// ⭐ hover 时加深底色并显图标，替代原先"hover 变灰"的割裂感
  Color _hoverColor(Color activeColor, Brightness brightness) {
    return brightness == Brightness.dark
        ? Color.lerp(activeColor, Colors.white, 0.42)!
        : Color.lerp(activeColor, Colors.black, 0.14)!;
  }

  Widget _buildButton({
    required Color activeColor,
    required VoidCallback? onTap,
    required IconData icon,
    required String tooltip,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final showIcon = _isHovering && _isFocused;
    final color = _dotColor(activeColor, brightness);

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: _btnWidth,
      height: _btnHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // ⭐ 扁平化：圆角只留 4px，不再是圆形
        borderRadius: BorderRadius.circular(AppRadius.control),
        color: showIcon ? _hoverColor(activeColor, brightness) : color,
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: showIcon ? 1 : 0,
        child: Icon(
          icon,
          size: _iconSize,
          color: brightness == Brightness.dark
              ? const Color(0xFF1A1A1A)
              : const Color(0xFFFFFFFF),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  PcHomeController.instance.focusWindow(widget.windowId);
                  onTap();
                },
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final isMaximized = ctrl.isMaximized(widget.windowId);
    final maximizeIcon = widget.canMaximize && isMaximized
        ? Icons.close_fullscreen
        : Icons.open_in_full;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      // Windows 习惯：左 → 右 依次为 最小化、最大化、关闭（关闭贴最右）
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            activeColor: _minimizeBase,
            onTap: widget.canMinimize
                ? () => ctrl.minimizeApp(widget.windowId)
                : null,
            icon: Icons.remove,
            tooltip: 'home_window_min'.tr,
          ),
          SizedBox(width: _spacing),
          _buildButton(
            activeColor: _maximizeBase,
            onTap: widget.canMaximize
                ? () => ctrl.maximizeApp(widget.windowId)
                : null,
            icon: maximizeIcon,
            tooltip: (widget.canMaximize && isMaximized)
                ? 'home_window_restore'.tr
                : 'home_window_max'.tr,
          ),
          SizedBox(width: _spacing),
          _buildButton(
            activeColor: _closeBase,
            onTap: () => ctrl.closeApp(widget.windowId),
            icon: Icons.close,
            tooltip: 'home_window_close'.tr,
          ),
        ],
      ),
    );
  }
}

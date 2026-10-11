import 'package:WaterNasOS/core/theme/custom_colors.dart';
import 'package:WaterNasOS/modules/base/components/custom_no_data.dart';
import 'package:WaterNasOS/modules/base/components/custom_segmented_icon_toggle.dart';
import 'package:WaterNasOS/modules/video/list/controller/video_list_controller.dart';
import 'package:WaterNasOS/modules/video/list/view/parts/video_list_grid.dart';
import 'package:WaterNasOS/modules/video/media_browser/view/parts/media_folder_grid.dart';
import 'package:WaterNasOS/modules/video/media_browser/view/parts/media_masonry_sliver.dart';
import 'package:WaterNasOS/modules/video/media_browser/view/parts/video_media_grid.dart';
import 'package:WaterNasOS/modules/video/media_browser/view/video_media_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../home/views/pc_components/pc_app_window.dart';

/// 图片库 / 混合库的浏览页。
///
/// ## 两个**互相独立**的开关（都在顶栏）
/// * **文件夹 / 整库平铺**（[VideoListController.folderViewEnabled]）
///   文件夹视图按目录层级逐层下钻：每层 = 4:3 的文件夹卡片（在上）+
///   本级文件（在下）；最后一层没有子文件夹 ⇒ 整页就是文件。
/// * **瀑布流 / 普通网格**（[VideoListController.waterfallEnabled]）
///   瀑布流按每项自己的宽高比排（视频在混合库里有 ffprobe 尺寸，横屏就是横屏）；
///   普通网格统一 4:3、一行对齐。
///
/// 两者正交，四种组合都成立 —— 所以「整库平铺」也能用瀑布流。
///
/// ## 搜索
/// 搜索时口径换成「当前目录的整棵子树」并且不再展示文件夹卡片 ——
/// 结果是跨目录的，再列目录只会自相矛盾。库根搜索 == 整库搜索。
class VideoMediaBrowserPage extends StatefulWidget {
  final int libraryId;

  /// image 只列图片；mixed 图片与影视混排
  final String libType;
  final String title;

  const VideoMediaBrowserPage({
    super.key,
    required this.libraryId,
    required this.libType,
    required this.title,
  });

  @override
  State<VideoMediaBrowserPage> createState() => _VideoMediaBrowserPageState();
}

class _VideoMediaBrowserPageState extends State<VideoMediaBrowserPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late final String _controllerTag;

  bool get _isImageOnly => widget.libType == 'image';

  @override
  void initState() {
    super.initState();
    // ⚠️ tag 里**不能**带当前目录：目录状态存在 controller 内部
    //    （folderPath 是 Rx），tag 一变就会新建一个 controller，
    //    搜索框内容、排序、滚动位置全部丢失。
    _controllerTag = 'video_media_browser_${widget.libraryId}_${widget.libType}';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ctrl = Get.isRegistered<VideoListController>(tag: _controllerTag)
        ? Get.find<VideoListController>(tag: _controllerTag)
        : null;
    if (ctrl == null || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  Future<void> _openViewer(VideoListController ctrl, int index) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            VideoMediaViewerPage(controller: ctrl, initialIndex: index),
      ),
    );
  }

  void _enterFolder(VideoListController ctrl, String path) {
    // 换目录要回到顶部，否则会停在上一个目录的滚动位置上
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    ctrl.setFolder(path).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    return GetBuilder<VideoListController>(
      tag: _controllerTag,
      init: VideoListController(
        // 图片库只列图片；混合库不限定类型，图片与影视一起返回
        initialMediaType: _isImageOnly ? 'image' : '',
        libraryId: widget.libraryId,
        folderView: true,
      ),
      builder: (ctrl) {
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: Column(
            children: [
              _buildTopBar(theme, ctrl),
              Expanded(
                child: Obx(() {
                  // ⭐ 这些读取**必须在 Obx 闭包内**（build 阶段）完成：
                  //   下面的 MediaFolderGrid / MediaMasonrySliver 内部是
                  //   SliverLayoutBuilder，属于 **layout 阶段**，那时
                  //   RxInterface.proxy 早已还原 ⇒ 那里读 Rx 监听不到任何依赖
                  //   （表现：顶栏有数量、内容区一片空白）。
                  final items = ctrl.items.toList(growable: false);
                  final folders = ctrl.subFolders.toList(growable: false);
                  final waterfallOn = ctrl.waterfallEnabled.value;
                  final showFanart = ctrl.showFanart.value;
                  final showFolderSection =
                      ctrl.showFolderCards && folders.isNotEmpty;

                  if (ctrl.loading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.isEmpty && !showFolderSection) {
                    return CustomNoData(text: 'no_data'.tr);
                  }

                  return Scrollbar(
                    thumbVisibility: true,
                    controller: _scrollController,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        if (showFolderSection) ...[
                          _sectionHeader('dir'.tr, folders.length),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            sliver: MediaFolderGrid(
                              folders: folders,
                              onOpen: (folder) =>
                                  _enterFolder(ctrl, folder.path),
                            ),
                          ),
                        ],
                        if (items.isNotEmpty)
                          SliverPadding(
                            // 目录卡片和文件之间留一点呼吸；只有文件时保持原边距
                            padding: EdgeInsets.fromLTRB(
                              16,
                              showFolderSection ? 18 : 10,
                              16,
                              16,
                            ),
                            // ⭐ 布局只由「瀑布流 / 网格」这个开关决定，**与文件夹视图无关**：
                            //    以前是「文件夹视图 ⇒ 瀑布流、整库平铺 ⇒ 网格」绑死的，
                            //    于是想整库看瀑布流就没辙（需求 2026-10-10 要求拆开）。
                            sliver: waterfallOn
                                ? MediaMasonrySliver(
                                    items: items,
                                    showFanart: showFanart,
                                    onOpen: (index) => _openViewer(ctrl, index),
                                  )
                                : VideoMediaGrid(
                                    controller: ctrl,
                                    showFanart: showFanart,
                                    onOpen: (index) => _openViewer(ctrl, index),
                                  ),
                          ),
                        if (items.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: VideoListFooter(controller: ctrl),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String label, int count) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 8),
        child: Row(
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme, VideoListController ctrl) {
    // ⭐ 右侧给窗口按钮组让位（2026-10-09）：搜索框被推到最右
    final ctrlW = PcWindowScope.of(context)?.titleBarControlsWidth ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16 + ctrlW, 8),
      child: Row(
        children: [
          // 返回上一级（只在文件夹视图且确实有上一级时出现）
          Obx(() {
            if (!ctrl.canGoUp) return const SizedBox.shrink();
            return IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'back'.tr,
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: () => _enterFolder(ctrl, ctrl.parentFolderPath.value),
            );
          }),
          // 面包屑
          Expanded(child: Obx(() => _buildBreadcrumb(theme, ctrl))),
          const SizedBox(width: 10),
          // 数量：文件夹视图下显示「整棵子树」的量，否则显示整库量
          Obx(
            () => Text(
              '${ctrl.folderViewEnabled.value ? ctrl.subtreeTotal.value : ctrl.total.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildViewToggle(ctrl),
          const SizedBox(width: 6),
          // ⭐ 两个开关（2026-10-10）：
          //   [瀑布流 | 网格]   —— 布局，与「文件夹 / 整库平铺」正交
          //   [封面图 | 缩略图] —— 视频条目用竖版封面还是横版缩略图
          //                        （与影视列表同一个语义、同一套持久化 key 前缀）
          _buildLayoutToggle(ctrl),
          const SizedBox(width: 6),
          _buildImageModeToggle(ctrl),
          const SizedBox(width: 6),
          SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'search'.tr,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: Obx(
                  () => ctrl.searchText.value.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            ctrl.clearSearch();
                          },
                        ),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: ctrl.setSearchText,
              onSubmitted: ctrl.setSearchImmediate,
            ),
          ),
        ],
      ),
    );
  }

  /// 文件夹视图 ↔ 整库平铺
  Widget _buildViewToggle(VideoListController ctrl) {
    return Obx(() {
      final on = ctrl.folderViewEnabled.value;
      return IconButton(
        visualDensity: VisualDensity.compact,
        // 图标显示的是「当前形态」，tooltip 说的是「点它会切到哪」
        tooltip: on ? 'all'.tr : 'dir'.tr,
        icon: Icon(
          on ? Icons.grid_view_rounded : Icons.folder_rounded,
          size: 20,
        ),
        onPressed: () => ctrl.setFolderView(!on),
      );
    });
  }

  /// 瀑布流 ↔ 普通网格
  Widget _buildLayoutToggle(VideoListController ctrl) {
    return Obx(() {
      final waterfall = ctrl.waterfallEnabled.value;
      return CustomSegmentedIconToggle(
        // 左 = 瀑布流（view_quilt 就是「不等高格子」的象形），右 = 普通网格
        firstIcon: Icons.view_quilt_rounded,
        secondIcon: Icons.grid_view_rounded,
        firstTooltip: 'video_list_waterfall'.tr,
        secondTooltip: 'video_list_grid'.tr,
        // 组件语义：secondSelected = 选中后半（网格）
        secondSelected: !waterfall,
        onChanged: (second) => ctrl.setWaterfall(!second),
      );
    });
  }

  /// 封面图 ↔ 缩略图（只管视频条目，图片永远用自己）
  Widget _buildImageModeToggle(VideoListController ctrl) {
    return Obx(() {
      return CustomSegmentedIconToggle(
        firstIcon: Icons.crop_portrait,
        secondIcon: Icons.crop_16_9,
        firstTooltip: 'video_list_image_poster'.tr,
        secondTooltip: 'video_list_image_fanart'.tr,
        secondSelected: ctrl.showFanart.value,
        onChanged: ctrl.setShowFanart,
      );
    });
  }

  Widget _buildBreadcrumb(ThemeData theme, VideoListController ctrl) {
    final crumbs = ctrl.breadcrumbs;
    final dim = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final children = <Widget>[
      _crumbText(theme, widget.title, onTap: () => _enterFolder(ctrl, '')),
    ];
    for (var i = 0; i < crumbs.length; i++) {
      final seg = crumbs[i];
      final isLast = i == crumbs.length - 1;
      children.add(Icon(Icons.chevron_right, size: 16, color: dim));
      children.add(
        _crumbText(
          theme,
          seg.name,
          strong: isLast,
          // 最后一段就是当前目录，点了也没变化
          onTap: isLast ? null : () => _enterFolder(ctrl, seg.path),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // 路径很深时优先露出最后几段（当前目录才是重点）
      reverse: true,
      child: Row(children: children),
    );
  }

  Widget _crumbText(
    ThemeData theme,
    String text, {
    VoidCallback? onTap,
    bool strong = false,
  }) {
    final style =
        (strong ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              color: strong
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.65),
            );
    final label = Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: label,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: label,
      ),
    );
  }
}

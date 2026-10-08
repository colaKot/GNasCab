import 'package:GNasCab/core/theme/custom_colors.dart';
import 'package:GNasCab/modules/base/components/custom_no_data.dart';
import 'package:GNasCab/modules/video/list/controller/video_list_controller.dart';
import 'package:GNasCab/modules/video/list/view/parts/video_list_grid.dart';
import 'package:GNasCab/modules/video/media_browser/view/parts/video_media_grid.dart';
import 'package:GNasCab/modules/video/media_browser/view/video_media_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 图片库 / 混合库的浏览页：网格缩略图 + 竖向全屏浏览
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
      ),
      builder: (ctrl) {
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: Column(
            children: [
              _buildTopBar(theme, ctrl),
              Expanded(
                child: Obx(() {
                  if (ctrl.loading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ctrl.items.isEmpty) {
                    return CustomNoData(text: 'no_data'.tr);
                  }
                  return Scrollbar(
                    thumbVisibility: true,
                    controller: _scrollController,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                          sliver: VideoMediaGrid(
                            controller: ctrl,
                            onOpen: (index) => _openViewer(ctrl, index),
                          ),
                        ),
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

  Widget _buildTopBar(ThemeData theme, VideoListController ctrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(width: 10),
          Obx(
            () => Text(
              '${ctrl.total.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const Spacer(),
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
}

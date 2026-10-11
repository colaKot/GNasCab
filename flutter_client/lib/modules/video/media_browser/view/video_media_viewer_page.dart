import 'package:WaterNasOS/core/api/api_controller.dart';
import 'package:WaterNasOS/core/routes/app_routes.dart';
import 'package:WaterNasOS/modules/base/components/custom_extended_image.dart';
import 'package:WaterNasOS/modules/base/components/custom_icon_button.dart';
import 'package:WaterNasOS/modules/video/base/beans/video_item_bean.dart';
import 'package:WaterNasOS/modules/video/base/video_utils/video_utils.dart';
import 'package:WaterNasOS/modules/video/list/controller/video_list_controller.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 图片库 / 混合库的全屏浏览：竖向翻页，上滑进入下一个媒体。
/// 图片支持双击放大与手势缩放；视频点击后进入完整播放器（与普通影视一致，
/// 带进度条 / 画质切换 / 音轨字幕等全套控件）。
class VideoMediaViewerPage extends StatefulWidget {
  final VideoListController controller;
  final int initialIndex;

  const VideoMediaViewerPage({
    super.key,
    required this.controller,
    required this.initialIndex,
  });

  @override
  State<VideoMediaViewerPage> createState() => _VideoMediaViewerPageState();
}

class _VideoMediaViewerPageState extends State<VideoMediaViewerPage> {
  late final PageController _pageController;
  late int _index;

  /// 各图片的当前缩放比例（与画廊一致，默认 1.0）
  final Map<int, double> _scales = <int, double>{};
  static const double _scaleOrigin = 1.0;
  static const double _scaleZoomed = 3.0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (mounted) {
      setState(() {
        _index = index;
      });
    }
    // 快到底部时预取下一页，保证上滑能继续翻
    final ctrl = widget.controller;
    if (index >= ctrl.items.length - 3) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: PopScope(
        canPop: true,
        child: Obx(() {
          final items = widget.controller.items;
          if (items.isEmpty) {
            return Center(
              child: Text(
                'no_data'.tr,
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          final safeIndex = _index.clamp(0, items.length - 1);
          final current = items[safeIndex];

          return Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: _onPageChanged,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item.isImage) {
                      return _buildImagePage(item, index);
                    }
                    return _buildVideoPage(item);
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _buildTopBar(current, safeIndex, items.length),
              ),
              if (current.isImage)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'video_library_viewer_hint'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTopBar(VideoHomeItemBean item, int index, int total) {
    final name = item.nfoName.isNotEmpty ? item.nfoName : item.filename;
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            CustomIconButton(
              icon: Icons.close,
              onPressed: () => Navigator.of(context).maybePop(),
              iconColor: Colors.white,
              iconSize: 22,
              buttonSize: 40,
              tooltip: 'close'.tr,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            Text(
              '${index + 1} / $total',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePage(VideoHomeItemBean item, int index) {
    final path = item.fullPath.trim();
    if (path.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54),
      );
    }
    final url = ApiController.instance.getRawFileUrl(path);

    return Center(
      child: CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        borderRadius: 0,
        showLoading: true,
        initGestureConfigHandler: (state) => GestureConfig(
          minScale: 0.5,
          maxScale: 10.0,
          animationMinScale: 0.5,
          animationMaxScale: 10,
          initialScale: _scales[index] ?? _scaleOrigin,
          inPageView: true,
        ),
        onDoubleTap: (ExtendedImageGestureState state) {
          final pointerDownPosition = state.pointerDownPosition;
          final current = _scales[index] ?? _scaleOrigin;
          final end = current == _scaleOrigin ? _scaleZoomed : _scaleOrigin;
          state.handleDoubleTap(
            scale: end,
            doubleTapPosition: pointerDownPosition,
          );
          _scales[index] = end;
        },
      ),
    );
  }

  /// 点击视频：进入完整播放器（与普通影视同一套播放页，带进度条 / 画质 /
  /// 音轨字幕等全部控件），并把当前库里**所有视频**作为播放列表，
  /// 以便在播放器里直接切上一个/下一个。
  ///
  /// 视频项的播放地址取 `playFilePath`（分片/光盘文件夹场景），为空时退回
  /// `fullPath`；与旧的原地播放器口径保持一致。
  Future<void> _openVideoPlayer(VideoHomeItemBean tapped) async {
    final items = widget.controller.items;
    final playlist = <Map<String, dynamic>>[];
    var initialIndex = -1;
    for (final it in items) {
      if (it.isImage) continue;
      final playPath = (it.playFilePath.isNotEmpty ? it.playFilePath : it.fullPath)
          .trim();
      if (playPath.isEmpty) continue;
      if (identical(it, tapped) || it.id == tapped.id) {
        initialIndex = playlist.length;
      }
      playlist.add(<String, dynamic>{
        'path': playPath,
        'name': it.nfoName.isNotEmpty ? it.nfoName : it.filename,
      });
    }
    if (playlist.isEmpty) return;
    if (initialIndex < 0) initialIndex = 0;
    await AppRoutes.toVideoPlayer(playlist: playlist, initialIndex: initialIndex);
  }

  Widget _buildVideoPage(VideoHomeItemBean item) {
    final cover = VideoUtils.getPosterUrl(item, size: 800);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openVideoPlayer(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: cover.isEmpty
                ? const Icon(
                    Icons.movie_outlined,
                    color: Colors.white24,
                    size: 64,
                  )
                : AspectRatio(
                    aspectRatio: _aspectOf(item),
                    child: CustomExtendedImage(
                      imageUrl: cover,
                      fit: BoxFit.contain,
                      borderRadius: 0,
                    ),
                  ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 42,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _aspectOf(VideoHomeItemBean item) {
    final w = item.width;
    final h = item.height;
    if (w > 0 && h > 0) return w / h;
    return 16 / 9;
  }
}

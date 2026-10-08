import 'package:GNasCab/core/api/api_controller.dart';
import 'package:GNasCab/modules/base/components/custom_extended_image.dart';
import 'package:GNasCab/modules/base/components/custom_icon_button.dart';
import 'package:GNasCab/modules/gallery/views/live_photo_inline_player.dart';
import 'package:GNasCab/modules/video/base/beans/video_item_bean.dart';
import 'package:GNasCab/modules/video/base/video_utils/video_utils.dart';
import 'package:GNasCab/modules/video/list/controller/video_list_controller.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 图片库 / 混合库的全屏浏览：竖向翻页，上滑进入下一个媒体。
/// 图片支持双击放大与手势缩放；视频点击后原地全屏播放。
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

  /// 当前正在原地播放的视频下标；-1 表示没有播放中的视频
  int _playingIndex = -1;

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
        // 滑走即停播，避免后台继续播放
        _playingIndex = -1;
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
                    return _buildVideoPage(item, index);
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

  Widget _buildVideoPage(VideoHomeItemBean item, int index) {
    final playing = _playingIndex == index;
    if (playing) {
      final url = ApiController.instance.getRawFileUrl(
        item.playFilePath.isNotEmpty ? item.playFilePath : item.fullPath,
      );
      // LivePhotoInlinePlayer 内部是 Positioned.fill，必须放在 Stack 里
      return Stack(
        fit: StackFit.expand,
        children: [
          LivePhotoInlinePlayer(
            videoUrl: url,
            onClose: () {
              if (mounted) setState(() => _playingIndex = -1);
            },
          ),
        ],
      );
    }

    final cover = VideoUtils.getPosterUrl(item, size: 800);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (mounted) setState(() => _playingIndex = index);
      },
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

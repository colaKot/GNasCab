import 'package:GNasCab/core/api/api_controller.dart';
import 'package:GNasCab/modules/base/components/custom_extended_image.dart';
import 'package:GNasCab/modules/video/base/beans/video_item_bean.dart';
import 'package:GNasCab/modules/video/base/video_utils/video_utils.dart';
import 'package:GNasCab/modules/video/list/controller/video_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 图片库 / 混合库：网格缩略图列表
class VideoMediaGrid extends StatelessWidget {
  final VideoListController controller;
  final ValueChanged<int> onOpen;

  const VideoMediaGrid({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  /// 网格缩略图地址：图片走 tiny 缩略图，视频走海报/首帧
  static String thumbUrlOf(VideoHomeItemBean item, {int size = 400}) {
    if (item.isImage) {
      final p = item.fullPath.trim();
      if (p.isEmpty) return '';
      return ApiController.instance.getTinyUrl(p, size: size);
    }
    return VideoUtils.getPosterUrl(item, size: size);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.items;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          final baseWidth = maxWidth < 520 ? 120.0 : 160.0;
          final desiredWidth = baseWidth * controller.posterScale.value;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 12);
          final spacing = maxWidth < 520 ? 8.0 : 12.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = (maxWidth - totalSpacing) / crossAxisCount;

          return SliverGrid(
            delegate: SliverChildBuilderDelegate((context, idx) {
              final item = items[idx];
              return VideoMediaTile(
                item: item,
                size: itemWidth,
                onTap: () => onOpen(idx),
              );
            }, childCount: items.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 1,
            ),
          );
        },
      );
    });
  }
}

class VideoMediaTile extends StatelessWidget {
  final VideoHomeItemBean item;
  final double size;
  final VoidCallback onTap;

  const VideoMediaTile({
    super.key,
    required this.item,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = VideoMediaGrid.thumbUrlOf(item, size: (size * 2).round());

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                child: url.isEmpty
                    ? Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      )
                    : CustomExtendedImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        borderRadius: 0,
                        showLoading: false,
                      ),
              ),
              // 视频条目叠一个播放角标，与图片区分
              if (!item.isImage)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

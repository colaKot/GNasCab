import 'package:WaterNasOS/core/api/api_controller.dart';
import 'package:WaterNasOS/modules/base/components/custom_extended_image.dart';
import 'package:WaterNasOS/modules/video/base/beans/video_item_bean.dart';
import 'package:WaterNasOS/modules/video/base/video_utils/video_utils.dart';
import 'package:WaterNasOS/modules/video/list/controller/video_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 图片库 / 混合库：网格缩略图列表（统一格子比例，即「普通网格」）
class VideoMediaGrid extends StatelessWidget {
  final VideoListController controller;
  final ValueChanged<int> onOpen;

  /// 视频条目用横版缩略图还是竖版封面（对应顶栏「封面图 / 缩略图」开关）。
  /// 图片条目不受影响（永远用自己的 tiny 缩略图）。
  final bool showFanart;

  const VideoMediaGrid({
    super.key,
    required this.controller,
    required this.onOpen,
    this.showFanart = false,
  });

  /// 格子比例：**4:3**（需求明确「不要方形」）。
  /// 这里是「普通网格」，一行必须对齐 ⇒ 只能取一个统一比例。
  /// 想看每张原比例的用「瀑布流」（media_masonry_sliver.dart）。
  static const double tileAspect = 4 / 3;

  /// 网格缩略图地址：图片走 tiny 缩略图，视频走海报/首帧
  static String thumbUrlOf(
    VideoHomeItemBean item, {
    int size = 400,
    bool showFanart = false,
  }) {
    if (item.isImage) {
      final p = item.fullPath.trim();
      if (p.isEmpty) return '';
      return ApiController.instance.getTinyUrl(p, size: size);
    }
    return showFanart
        ? VideoUtils.getFanartThumbUrl(item, size: size)
        : VideoUtils.getPosterUrl(item, size: size);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // ⭐ 这些读取**必须在 Obx 闭包内**（也就是 build 阶段）完成。
      // SliverLayoutBuilder.builder 是 **layout 阶段**才跑的，那时 RxInterface.proxy
      // 早已还原 ⇒ GetX 监听到 0 个响应式依赖 ⇒ canUpdate==false ⇒
      // 抛 "the improper use of a GetX has been detected"，整棵Sliver 子树渲染失败
      // （表现：顶栏有数量、内容区一片空白）。
      final items = controller.items.toList(growable: false);
      final posterScale = controller.posterScale.value;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          // ⭐ 320 是「**卡片短边 =240**」倒推的（需求 2026-10-11）：
          //    普通网格统一 4:3 ⇒ 高 = 宽 × 3/4，要短边 240 就得宽 320。
          //    原来是 160（= 160×120，确实太小）。
          final baseWidth = maxWidth < 520 ? 120.0 : 320.0;
          final desiredWidth = baseWidth * posterScale;
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
                showFanart: showFanart,
                onTap: () => onOpen(idx),
              );
            }, childCount: items.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              // ⭐ 原来是 1（正方形）—— 图片被裁成方砖，一排下来既看不出构图、
              //    也看不出横竖，观感很差。改成 **4:3**：横向略宽、封面按 cover
              //    裁切，一行永远对齐。想要原比例的去看「瀑布流」
              //    （media_masonry_sliver.dart，按 width/height 还原真实比例）。
              childAspectRatio: tileAspect,
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
  final bool showFanart;
  final VoidCallback onTap;

  const VideoMediaTile({
    super.key,
    required this.item,
    required this.size,
    required this.onTap,
    this.showFanart = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = VideoMediaGrid.thumbUrlOf(
      item,
      size: (size * 2).round(),
      showFanart: showFanart,
    );

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

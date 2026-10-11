import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/views/video_item_poster.dart';
import '../../controller/video_list_controller.dart';

class VideoListGrid extends StatelessWidget {
  final VideoListController controller;
  const VideoListGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final posterScale = controller.posterScale.value;
      final showFanart = controller.showFanart.value;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          final spacing = maxWidth < 520 ? 12.0 : 15.0;
          // ⭐ posterScale 控制的是**图片高度**，两种模式共用同一个高度 ——
          //    所以切到横版缩略图时图片不会忽大忽小，只是按 16:9 等比变宽
          //    （≈ 竖版 2:3 的 2.67 倍），一行放得下的个数自然就少了。
          // ⭐ 横版用 3:2 —— 这是实际刮削出来的 backdrop 图的真实比例
          //    （实测 xxx-backdrop.jpg 全是 840×566 / 1000×674 / 800×538 ≈ 1.49）。
          //    ⚠️ 不要用 16:9：那是 xxx-landscape.jpg 的比例，拿 3:2 的 backdrop
          //    去 cover 16:9 的框会**上下各裁掉一条**。
          final imageAspect = showFanart ? 3 / 2 : 2 / 3;
          final imageHeight =
              (maxWidth < 520 ? 150.0 : 176.0) * 1.5 * posterScale;
          final desiredWidth = imageHeight * imageAspect;
          final crossAxisCount =
              ((maxWidth + spacing) / (desiredWidth + spacing)).floor().clamp(
                1,
                10,
              );
          final itemWidth =
              (maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
          // ⚠️ 图片高度必须按**格子实际宽度**反算，不能直接用上面的 imageHeight：
          //    网格会把每列宽度拉伸到均分整行（横版模式下往往比 desiredWidth 宽不少），
          //    卡片里的 AspectRatio 按真实宽度算出来的图会高出一大截、超出格子，
          //    表现就是「图片被上下裁掉一块」。
          final realImageHeight = itemWidth / imageAspect;
          final estimatedHeight = realImageHeight + 60;
          final aspectRatio = itemWidth / estimatedHeight;

          return SliverGrid(
            delegate: SliverChildBuilderDelegate((context, idx) {
              final item = controller.items[idx];
              return VideoItemPoster(
                contentPadding: EdgeInsets.zero,
                item: item,
                width: itemWidth,
                showFanart: showFanart,
                progress: null,
                currentAlbumId: controller.albumId,
                onRemovedFromCurrentAlbum: () =>
                    controller.removeFromCurrentAlbumState(item.id),
                onFavoriteChanged: (isFav) =>
                    controller.updateFavoriteState(item.id, isFav),
                onDeleted: (deleted) {
                  controller.items.removeWhere((e) => e.id == deleted.id);
                  controller.total.value = (controller.total.value - 1).clamp(
                    0,
                    1 << 30,
                  );
                },
              );
            }, childCount: controller.items.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
          );
        },
      );
    });
  }
}

class VideoListFooter extends StatelessWidget {
  final VideoListController controller;
  const VideoListFooter({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loadingMore.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Center(
          child: Text(
            'video_list_no_more'.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }

      if (!controller.autoLoadFailed.value) {
        return const SizedBox.shrink();
      }

      return Center(
        child: OutlinedButton(
          onPressed: () =>
              controller.loadMore(fromAuto: false).catchError((_) {}),
          child: Text('video_list_load_more'.tr),
        ),
      );
    });
  }
}

import 'package:WaterNasOS/core/theme/custom_colors.dart';
import 'package:WaterNasOS/modules/base/components/custom_extended_image.dart';
import 'package:WaterNasOS/modules/video/media_browser/bean/media_folder_item.dart';
import 'package:WaterNasOS/modules/video/media_browser/view/parts/video_media_grid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 文件夹卡片网格：**固定 4:3**（不是方形）。
///
/// ⭐ 为什么是 4:3，而不是「学 Jellyfin 跟着主图比例走」：
///    Jellyfin 的照片库卡片宽高比是由「主图是竖还是横」决定的 ——
///    同一个库的不同层级会混出 2:3 / 16:9 / 1:1 三种比例，社区里为此专门
///    写 CSS 强改比例（`aspect-ratio: 2/3`）。**一排卡片宽窄不一才是丑的根源**。
///    这里统一 4:3：横向略宽、封面按 cover 裁切、一行永远对齐；
///    图片本身的比例差异交给「本级文件的瀑布流」去体现。
class MediaFolderGrid extends StatelessWidget {
  final List<MediaFolderItem> folders;
  final ValueChanged<MediaFolderItem> onOpen;

  const MediaFolderGrid({
    super.key,
    required this.folders,
    required this.onOpen,
  });

  /// 4:3 —— 需求明确「不要方形」
  static const double folderAspect = 4 / 3;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.crossAxisExtent;
        final spacing = maxWidth < 520 ? 10.0 : 14.0;
        // 目标卡宽：小屏 150 / 大屏 220 —— 保证一行 2~8 个，卡片不会大到离谱
        final desired = maxWidth < 520 ? 150.0 : 220.0;
        final crossAxisCount = ((maxWidth + spacing) / (desired + spacing))
            .floor()
            .clamp(2, 8);
        final itemWidth =
            (maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;

        return SliverGrid(
          delegate: SliverChildBuilderDelegate((context, idx) {
            final folder = folders[idx];
            return MediaFolderTile(
              folder: folder,
              width: itemWidth,
              onTap: () => onOpen(folder),
            );
          }, childCount: folders.length),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: folderAspect,
          ),
        );
      },
    );
  }
}

/// 单个文件夹卡片：封面 + 文件夹角标 + 目录名 + 项目数
class MediaFolderTile extends StatefulWidget {
  final MediaFolderItem folder;
  final double width;
  final VoidCallback onTap;

  const MediaFolderTile({
    super.key,
    required this.folder,
    required this.width,
    required this.onTap,
  });

  @override
  State<MediaFolderTile> createState() => _MediaFolderTileState();
}

class _MediaFolderTileState extends State<MediaFolderTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final cover = widget.folder.cover;
    final url = cover == null
        ? ''
        : VideoMediaGrid.thumbUrlOf(cover, size: (widget.width * 2).round());
    final countText = 'folder_status_total'.trParams({
      'total': '${widget.folder.count}',
    });

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover
                  ? theme.colorScheme.primary
                  : (customColors?.hairlineBorderColor ?? theme.dividerColor),
              width: _hover ? 1.6 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color:
                    customColors?.emptyCardColor ??
                    theme.colorScheme.surfaceContainerHighest,
                child: url.isEmpty
                    ? Center(
                        child: Icon(
                          Icons.folder_outlined,
                          size: 40,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      )
                    : CustomExtendedImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        borderRadius: 0,
                        showLoading: false,
                      ),
              ),
              // 底部压暗，保证目录名在任何封面上都读得清
              // （压在照片上的文字用固定白色+黑渐变，和主题无关，
              //   与 VideoMediaTile 的播放角标同一口径）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        countText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 左上角文件夹角标
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.folder_rounded,
                    size: 15,
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

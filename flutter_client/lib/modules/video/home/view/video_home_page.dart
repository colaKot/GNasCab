import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../base/beans/video_item_bean.dart';
import '../../library_setting/models/video_library.dart';
import '../../video_main/controller/video_main_controller.dart';
import '../../list/view/video_list_page.dart';
import '../controller/video_home_page_controller.dart';
import '../service/video_home_api_service.dart';
import 'parts/video_recommend_section.dart';
import 'parts/video_recent_add_section.dart';
import 'parts/video_recent_play_section.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  final ScrollController _scrollController = ScrollController();

  void _openLibrary(String key, {String? fallbackMediaType}) {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().selectPage(key);
      return;
    }
    if (fallbackMediaType != null && fallbackMediaType.trim().isNotEmpty) {
      Get.to(() => VideoListPage(initialMediaType: fallbackMediaType));
    }
  }

  /// 库标题：服务端给的是 name_key（改名后为空），复用左侧栏的显示规则
  String _resolveLibTitle(VideoHomeLibraryGroup group) {
    if (Get.isRegistered<VideoMainController>()) {
      final lib = Get.find<VideoMainController>().libraryById(group.libraryId);
      if (lib != null) return lib.displayName;
    }
    final raw = group.libraryName.trim();
    if (raw.isEmpty) return libTypeLabelKey(group.libType).tr;
    final translated = raw.tr;
    return translated == raw ? raw : translated;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoHomePageController>(
      init: VideoHomePageController(alertWhenNoSourcePath: true),
      builder: (ctrl) {
        void handleDeleted(VideoHomeItemBean deleted) {
          ctrl.recommend.removeWhere((e) => e.id == deleted.id);
          ctrl.recentPlay.removeWhere((e) => e.id == deleted.id);
          // 分组是 immutable 的，要重建才能反映删除
          ctrl.recentAddByLib.assignAll(
            ctrl.recentAddByLib
                .map(
                  (g) => VideoHomeLibraryGroup(
                    libraryId: g.libraryId,
                    libraryName: g.libraryName,
                    libType: g.libType,
                    items: g.items.where((e) => e.id != deleted.id).toList(),
                  ),
                )
                .where((g) => g.items.isNotEmpty)
                .toList(),
          );
        }

        return Column(
          children: [
            // _TopBar(onRefresh: () => ctrl.refreshAll(showLoading: true)),
            Expanded(
              child: Obx(() {
                final noData =
                    ctrl.recommend.isEmpty &&
                    ctrl.recentPlay.isEmpty &&
                    ctrl.recentAddByLib.isEmpty;

                if (noData) {
                  if (ctrl.loading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CustomNoData(text: 'no_data'.tr);
                }

                return Scrollbar(
                  thumbVisibility: true,
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        VideoRecommendSection(
                          items: ctrl.recommend.toList(),
                          onDeleted: handleDeleted,
                        ),
                        VideoRecentPlaySection(
                          items: ctrl.recentPlay.toList(),
                          onTap: () => _openLibrary('library.history'),
                          onDeleted: handleDeleted,
                        ),
                        // 按影视库分类：只显示勾了「主页显示」的库，顺序与左侧栏一致
                        for (final g in ctrl.recentAddByLib)
                          VideoRecentAddSection(
                            key: ValueKey('home_lib_${g.libraryId}'),
                            items: g.items,
                            title: _resolveLibTitle(g),
                            onTap: () => _openLibrary(
                              VideoMainController.libraryKeyOf(g.libraryId),
                            ),
                            onDeleted: handleDeleted,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

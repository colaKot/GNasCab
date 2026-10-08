import 'package:get/get.dart';
import 'package:GNasCab/modules/video/library_setting/models/video_library.dart';
import 'package:GNasCab/modules/video/library_setting/service/video_library_api_service.dart';
import 'package:GNasCab/modules/video/list/service/video_list_api_service.dart';

enum VideoFilterOverlayKind { genre, region, actor, director }

class VideoFilterOverlayArgs {
  final VideoFilterOverlayKind kind;
  final String value;
  final String mediaType;

  const VideoFilterOverlayArgs({
    required this.kind,
    required this.value,
    required this.mediaType,
  });

  String get title {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (kind == VideoFilterOverlayKind.genre) return '风格：$v';
    if (kind == VideoFilterOverlayKind.region) return '地区：$v';
    if (kind == VideoFilterOverlayKind.actor) return '演员：$v';
    return '导演：$v';
  }
}

class VideoMainController extends GetxController {
  final RxString currentPageKey = 'library.home'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isLibraryExpanded = true.obs;
  final RxBool isAlbumExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;

  final RxInt movieCount = 0.obs;
  final RxInt tvCount = 0.obs;

  /// 影视库列表：每个库是左侧栏的一个栏目
  final RxList<VideoLibrary> libraries = <VideoLibrary>[].obs;
  final RxBool loadingLibraries = false.obs;

  final RxnInt activeDetailIndexId = RxnInt();
  final RxnInt activeSubDetailIndexId = RxnInt();
  final Rxn<VideoFilterOverlayArgs> activeFilterOverlay = Rxn();

  final VideoListApiService _api = VideoListApiService.instance;

  /// 自定义库栏目的 key 前缀：`library.lib.<id>`
  static const String libraryKeyPrefix = 'library.lib.';

  static String libraryKeyOf(int id) => '$libraryKeyPrefix$id';

  /// 从栏目 key 中解析影视库 id，非影视库栏目返回 0
  static int libraryIdFromKey(String key) {
    if (!key.startsWith(libraryKeyPrefix)) return 0;
    return int.tryParse(key.substring(libraryKeyPrefix.length)) ?? 0;
  }

  @override
  void onInit() {
    super.onInit();
    fetchIndexCounts();
    fetchLibraries();
  }

  VideoLibrary? libraryById(int id) {
    for (final lib in libraries) {
      if (lib.id == id) return lib;
    }
    return null;
  }

  Future<void> fetchLibraries() async {
    // 允许并发刷新（增删改后立即同步左侧栏），最后一次结果生效
    loadingLibraries.value = true;
    try {
      final list = await VideoLibraryApiService.instance.listLibraries();
      libraries.assignAll(list);
      // 当前停留的库已被删除时，回退到首页，避免停在空栏目
      final currentId = libraryIdFromKey(currentPageKey.value);
      if (currentId > 0 && !list.any((e) => e.id == currentId)) {
        currentPageKey.value = 'library.home';
      }
    } finally {
      loadingLibraries.value = false;
    }
  }

  Future<void> fetchIndexCounts() async {
    final res = await _api.getIndexCounts();
    final data = res.data;
    if (res.success && data != null) {
      movieCount.value = data.movie;
      tvCount.value = data.tv;
    }
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  void openDetail(int indexId) {
    if (indexId <= 0) return;
    activeDetailIndexId.value = indexId;
  }

  void closeDetail() {
    activeDetailIndexId.value = null;
    activeSubDetailIndexId.value = null;
  }

  void openSubDetail(int indexId) {
    print("打开季详情:$indexId");
    if (indexId <= 0) return;
    activeSubDetailIndexId.value = indexId;
  }

  void closeSubDetail() {
    activeSubDetailIndexId.value = null;
  }

  void openFilterOverlay({
    required VideoFilterOverlayKind kind,
    required String value,
    String? mediaType,
  }) {
    final v = value.trim();
    if (v.isEmpty) return;
    closeDetail();
    activeFilterOverlay.value = VideoFilterOverlayArgs(
      kind: kind,
      value: v,
      mediaType: (mediaType ?? '').trim(),
    );
  }

  void closeFilterOverlay() {
    activeFilterOverlay.value = null;
  }
}

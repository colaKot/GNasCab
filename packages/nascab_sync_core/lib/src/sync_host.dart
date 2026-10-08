import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;

import 'sync_models.dart';

/// 协议调用的统一返回。
///
/// 主客户端的 `ApiResponse<T>`、独立客户端的 `ApiResponse<T>` 都往这里收敛，
/// 使 [SyncEngine] 不必知道宿主用的是哪一套 HTTP 封装。
class SyncApiResult {
  final bool success;

  /// 服务端返回的 i18n key 或错误文案，由宿主决定是否已翻译。
  final String? message;
  final Map<String, dynamic>? data;

  const SyncApiResult({required this.success, this.message, this.data});

  factory SyncApiResult.failure(String message) =>
      SyncApiResult(success: false, message: message);
}

/// 下载流 + 收尾回调。
///
/// 宿主可能为某次下载临时创建 http client（例如自签证书客户端），
/// 需要在流读完后释放，因此顺带带一个 [dispose]。
class SyncDownloadStream {
  final http.StreamedResponse response;
  final void Function()? dispose;

  const SyncDownloadStream(this.response, [this.dispose]);
}

/// [SyncEngine] 需要宿主提供的全部能力。
///
/// 这是「共享同步代码」与「各客户端宿主」之间**唯一**的接缝：
/// 主客户端用 ApiController + UploadCore + BaseApiService 实现它，
/// 独立客户端用 SessionController + SyncUploader + SyncHttp 实现它。
///
/// 新增宿主能力时只改这里，两个客户端各自补一个实现即可。
abstract class SyncHost {
  /// 当前连接的 NAS 地址。
  String get baseUrl;

  /// 取一个可用的 access token；过期时由宿主自行刷新。
  /// 拿不到 token 时应抛异常，引擎会把它记为该轮同步的失败原因。
  Future<String> resolveAccessToken();

  /// 把服务端 i18n key 翻成当前语言文案。
  String message(String key);

  /// 上传一个文件到 NAS，保留修改时间。
  ///
  /// [filePath] 本地绝对路径；[relPath] POSIX 相对路径（同时作为远端子路径）；
  /// [remoteRoot] 远端根目录；[fileSize]/[fileMtimeMs] 由引擎扫描得到；
  /// [fileHash] 由引擎生成，服务端用它识别同一文件的上传会话。
  Future<void> uploadFile({
    required dio.Dio dioClient,
    required String filePath,
    required String relPath,
    required String remoteRoot,
    required int fileSize,
    required int fileMtimeMs,
    required String fileHash,
    required dio.CancelToken cancelToken,
    required void Function(int increment) onProgress,
  });

  /// 发起下载请求并返回流式响应。
  ///
  /// 宿主自行决定走直连还是 P2P 通道，并自行附加鉴权头。
  Future<SyncDownloadStream> sendDownload(
    http.Request request, {
    required Duration timeout,
    Future<void>? cancelFuture,
  });

  /// 提交本地清单，取回同步计划。
  Future<SyncApiResult> plan({
    required int id,
    required List<LocalFileEntry> localFiles,
    required List<LocalFileEntry> baselineFiles,
    int? maxListPerType,
  });

  /// 删除 NAS 侧文件（同步计划中的 deleteRemote）。
  Future<SyncApiResult> deleteRemote({
    required int id,
    required List<String> relPaths,
  });

  /// 回写一轮同步结果。
  Future<SyncApiResult> report({
    required int id,
    required int startTime,
    required int endTime,
    required String status,
    int uploadCount,
    int downloadCount,
    int deleteCount,
    int skipCount,
    int failCount,
    int bytesTransferred,
    List<String> errorList,
  });
}

/// 未装配宿主时的占位实现：调用即抛错，避免静默跑出错误结果。
class UnboundSyncHost implements SyncHost {
  const UnboundSyncHost();

  static Never _unbound() => throw StateError(
        'SyncHost 未装配：请在启动时设置 SyncHostHolder.instance = 你的实现。',
      );

  @override
  String get baseUrl => _unbound();

  @override
  Future<String> resolveAccessToken() async => _unbound();

  @override
  String message(String key) => key;

  @override
  Future<void> uploadFile({
    required dio.Dio dioClient,
    required String filePath,
    required String relPath,
    required String remoteRoot,
    required int fileSize,
    required int fileMtimeMs,
    required String fileHash,
    required dio.CancelToken cancelToken,
    required void Function(int increment) onProgress,
  }) async =>
      _unbound();

  @override
  Future<SyncDownloadStream> sendDownload(
    http.Request request, {
    required Duration timeout,
    Future<void>? cancelFuture,
  }) async =>
      _unbound();

  @override
  Future<SyncApiResult> plan({
    required int id,
    required List<LocalFileEntry> localFiles,
    required List<LocalFileEntry> baselineFiles,
    int? maxListPerType,
  }) async =>
      _unbound();

  @override
  Future<SyncApiResult> deleteRemote({
    required int id,
    required List<String> relPaths,
  }) async =>
      _unbound();

  @override
  Future<SyncApiResult> report({
    required int id,
    required int startTime,
    required int endTime,
    required String status,
    int uploadCount = 0,
    int downloadCount = 0,
    int deleteCount = 0,
    int skipCount = 0,
    int failCount = 0,
    int bytesTransferred = 0,
    List<String> errorList = const [],
  }) async =>
      _unbound();
}

/// [SyncHost] 的全局装配点。
///
/// 沿用项目既有的 `XxxController.instance` 风格。各客户端在 main() 里
/// 于 runApp 之前赋值一次即可；未赋值时引擎会以 [UnboundSyncHost] 运行并明确报错。
class SyncHostHolder {
  SyncHostHolder._();

  static SyncHost instance = const UnboundSyncHost();

  static bool get isBound => instance is! UnboundSyncHost;
}

import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class VideoTmdbSettingsApiService extends BaseApiService {
  static VideoTmdbSettingsApiService get instance =>
      Get.isRegistered<VideoTmdbSettingsApiService>()
      ? Get.find<VideoTmdbSettingsApiService>()
      : VideoTmdbSettingsApiService();

  Future<ApiResponse<Map<String, dynamic>>> getTmdbConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getTmdbConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTmdbConfig({
    required String accessToken,
    required bool proxyEnable,
    required String proxyUrl,
    required String language,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setTmdbConfig',
      body: {
        'accessToken': accessToken,
        'proxyEnable': proxyEnable ? 1 : 0,
        'proxyUrl': proxyUrl,
        'language': language,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTranscodeConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getTranscodeConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getSubtitleConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getSubtitleConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setSubtitleConfig({
    required bool preExtractEnable,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setSubtitleConfig',
      body: {
        'preExtractEnable': preExtractEnable ? 1 : 0,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTranscodeConfig({
    required String tempDir,
    required String preferredHwDecoder,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setTranscodeConfig',
      body: {
        'tempDir': tempDir,
        'preferredHwDecoder': preferredHwDecoder,
      },
      showLoading: showLoading,
    );
  }

  /// 读取服务端级「默认播放画质」。该接口对所有登录用户开放（含子账号），
  /// 否则管理员设置了默认码率，非管理员的播放端读不到。
  Future<ApiResponse<Map<String, dynamic>>> getPlayQuality({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getPlayQuality',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setPlayQuality({
    required String quality,
    required bool audioDownmix,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setPlayQuality',
      body: {
        'quality': quality,
        'audioDownmix': audioDownmix ? 1 : 0,
      },
      showLoading: showLoading,
    );
  }
}

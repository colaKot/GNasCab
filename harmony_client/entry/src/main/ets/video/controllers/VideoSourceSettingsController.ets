import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { VideoLibrary, VideoSource, cloneVideoSource, parseVideoSource } from '../models/VideoModels';
import { VideoLibraryApiService, VideoSourceApiService } from '../service/VideoApiServices';

/**
 * 影音来源设置控制器（对齐 Flutter VideoSourceSettingsController）：
 * 影视库列表 + 来源列表加载 + 单个/批量添加（按库） + 乐观更新（失败回滚） +
 * 删除/重定位/扫描/预生成缩略图。
 */
@ObservedV2
export class VideoSourceSettingsController {
  private api: VideoSourceApiService = new VideoSourceApiService();
  private libraryApi: VideoLibraryApiService = new VideoLibraryApiService();

  @Trace sources: VideoSource[] = [];
  /** 可选影视库（添加来源时选择归属；来源媒体类型由库派生） */
  @Trace libraries: VideoLibrary[] = [];
  @Trace loadingSources: boolean = false;
  @Trace loadingLibraries: boolean = false;
  @Trace scanning: boolean = false;

  init(): void {
    void this.fetchLibraries();
    void this.fetchSources();
  }

  dispose(): void {
  }

  /** 拉取影视库列表（对齐 Flutter fetchLibraries） */
  async fetchLibraries(): Promise<void> {
    this.loadingLibraries = true;
    try {
      this.libraries = await this.libraryApi.listLibraries();
    } catch (_e) {
      this.libraries = [];
    } finally {
      this.loadingLibraries = false;
    }
  }

  /** 定时扫描小时数（对齐 Flutter getIntervalHours：ms→小时，缺省 2） */
  getIntervalHours(source: VideoSource): number {
    const ms = source.scanIntervalMs;
    if (ms <= 0) {
      return 2;
    }
    const hours = Math.round(ms / (3600 * 1000));
    return Math.min(Math.max(hours, 1), 24);
  }

  /** 定时扫描是否启用（对齐 Flutter getIntervalEnabled） */
  getIntervalEnabled(source: VideoSource): boolean {
    return source.scanInterval === 1 || source.scanIntervalMs > 0;
  }

  /** 拉取来源列表（对齐 Flutter fetchSources） */
  async fetchSources(showLoading: boolean = false): Promise<void> {
    if (this.loadingSources) {
      return;
    }
    this.loadingSources = true;
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      this.sources = await this.api.listSources();
    } finally {
      this.loadingSources = false;
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 添加来源时的库校验提示：库为空提示去建库，未选中提示先选库 */
  private toastLibraryRequired(): void {
    ToastUtil.show(this.libraries.length === 0
      ? L10n.t('video_library_empty', '还没有创建影视库')
      : L10n.t('video_source_select_library', '选择影视库'));
  }

  /** 添加单个来源（对齐 Flutter addSource：libraryId + matchNfo 校验） */
  async addSource(path: string, libraryId: number, matchNfo: number): Promise<boolean> {
    const p = path.trim();
    if (p.length === 0) {
      return false;
    }
    if (libraryId <= 0 || !this.libraries.some((e: VideoLibrary): boolean => e.id === libraryId)) {
      this.toastLibraryRequired();
      return false;
    }
    if (matchNfo !== 0 && matchNfo !== 1) {
      return false;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.addSource(p, libraryId, matchNfo);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return false;
      }
      await this.fetchSources();
      await this.fetchLibraries();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 批量添加来源（对齐 Flutter addSourcesWithConfig：逐个添加，失败即停） */
  async addSourcesWithConfig(paths: string[], libraryId: number, matchNfo: number): Promise<boolean> {
    const uniq: string[] = [];
    for (const e of paths) {
      const t = e.trim();
      if (t.length > 0 && !uniq.includes(t)) {
        uniq.push(t);
      }
    }
    if (uniq.length === 0) {
      return false;
    }
    if (libraryId <= 0 || !this.libraries.some((e: VideoLibrary): boolean => e.id === libraryId)) {
      this.toastLibraryRequired();
      return false;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      for (const p of uniq) {
        const res = await this.api.addSource(p, libraryId, matchNfo);
        if (!res.success) {
          DialogUtil.dismissLoading();
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
          return false;
        }
      }
      await this.fetchSources();
      await this.fetchLibraries();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 乐观更新来源开关/间隔（对齐 Flutter updateSourceOptimistic：失败回滚） */
  async updateSourceOptimistic(source: VideoSource,
    scanWhenStart: number | undefined = undefined,
    scanWhenChange: number | undefined = undefined,
    scanInterval: number | undefined = undefined,
    scanIntervalMs: number | undefined = undefined): Promise<void> {
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const prev = this.sources[idx];
    const next = cloneVideoSource(prev);
    if (scanWhenStart !== undefined) {
      next.scanWhenStart = scanWhenStart;
    }
    if (scanWhenChange !== undefined) {
      next.scanWhenChange = scanWhenChange;
    }
    if (scanInterval !== undefined) {
      next.scanInterval = scanInterval;
    }
    if (scanIntervalMs !== undefined) {
      next.scanIntervalMs = scanIntervalMs;
    }
    this.sources[idx] = next;

    const payload: Record<string, Object> = {};
    if (scanWhenStart !== undefined) {
      payload['scan_when_start'] = scanWhenStart;
    }
    if (scanWhenChange !== undefined) {
      payload['scan_when_change'] = scanWhenChange;
    }
    if (scanInterval !== undefined) {
      payload['scan_interval'] = scanInterval;
    }
    if (scanIntervalMs !== undefined) {
      payload['scan_interval_ms'] = scanIntervalMs;
    }

    const res = await this.api.updateSource(source.id, payload);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (res.data !== undefined && res.data !== null) {
      this.sources[idx] = parseVideoSource(res.data as Object);
    }
  }

  // 注：原 updateMediaTypeOptimistic（切换来源媒体类型）已随影视库改造移除。
  // 来源归属的影视库创建后不可修改，媒体类型由库的 lib_type 派生。

  /** 乐观更新匹配 NFO（对齐 Flutter updateMatchNfoOptimistic） */
  async updateMatchNfoOptimistic(source: VideoSource, matchNfo: number): Promise<void> {
    if (matchNfo !== 0 && matchNfo !== 1) {
      return;
    }
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0 || this.sources[idx].matchNfo === matchNfo) {
      return;
    }
    const prev = this.sources[idx];
    const next = cloneVideoSource(prev);
    next.matchNfo = matchNfo;
    this.sources[idx] = next;

    const res = await this.api.updateMatchNfo(source.id, matchNfo);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (res.data !== undefined && res.data !== null) {
      this.sources[idx] = parseVideoSource(res.data as Object);
    }
  }

  /** 删除来源（乐观删除 + 失败恢复，对齐 Flutter deleteSourceOptimistic） */
  async deleteSourceOptimistic(source: VideoSource): Promise<void> {
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const removed = this.sources[idx];
    const next = this.sources.slice();
    next.splice(idx, 1);
    this.sources = next;

    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.deleteSource(source.id);
      if (!res.success) {
        const restored = this.sources.slice();
        restored.splice(idx, 0, removed);
        this.sources = restored;
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } catch (_e) {
      const restored = this.sources.slice();
      restored.splice(idx, 0, removed);
      this.sources = restored;
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 重定位来源（对齐 Flutter relocateSource） */
  async relocateSource(source: VideoSource, newPath: string): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.relocateSource(source.id, newPath);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      await this.fetchSources();
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } catch (_e) {
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 立即扫描（对齐 Flutter scanSource；path 传 'all' 扫描全部） */
  async scanSource(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0 || this.scanning) {
      return;
    }
    this.scanning = true;
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.scanSource(p);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchSources();
    } catch (_e) {
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } finally {
      this.scanning = false;
      DialogUtil.dismissLoading();
    }
  }

  /** 预生成缩略图（确认弹窗由页面触发，对齐 Flutter preGenerateThumbnails） */
  async preGenerateThumbnails(): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.preGenerateThumbnails();
      if (res.success) {
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
      } else {
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}

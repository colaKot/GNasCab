import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { VideoLibrary, parseVideoLibrary } from '../models/VideoModels';
import { VideoLibraryApiService } from '../service/VideoApiServices';

/**
 * 影视库管理控制器（对齐 Flutter VideoLibrarySettingsController）：
 * 列表加载 + 新建（含分类，创建后不可改）+ 重命名 + 删除（内置库/有来源的库由服务端拒绝）。
 */
@ObservedV2
export class VideoLibrarySettingsController {
  private api: VideoLibraryApiService = new VideoLibraryApiService();

  @Trace libraries: VideoLibrary[] = [];
  @Trace loading: boolean = false;
  @Trace saving: boolean = false;

  init(): void {
    void this.fetchLibraries();
  }

  dispose(): void {
  }

  async fetchLibraries(): Promise<void> {
    this.loading = true;
    try {
      this.libraries = await this.api.listLibraries();
    } catch (_e) {
      this.libraries = [];
    } finally {
      this.loading = false;
    }
  }

  /** 新建影视库（分类创建后不可修改） */
  async addLibrary(name: string, libType: string): Promise<boolean> {
    const n = name.trim();
    if (n.length === 0) {
      ToastUtil.show(L10n.t('video_library_name_required', '请输入名称'));
      return false;
    }
    this.saving = true;
    try {
      const res = await this.api.addLibrary(n, libType);
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return false;
      }
      await this.fetchLibraries();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return false;
    } finally {
      this.saving = false;
    }
  }

  /** 重命名影视库（仅改名，分类不动；改名后服务端会清空 name_key） */
  async renameLibrary(id: number, name: string): Promise<boolean> {
    const n = name.trim();
    if (n.length === 0) {
      ToastUtil.show(L10n.t('video_library_name_required', '请输入名称'));
      return false;
    }
    this.saving = true;
    try {
      const res = await this.api.renameLibrary(id, n);
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return false;
      }
      await this.fetchLibraries();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return false;
    } finally {
      this.saving = false;
    }
  }

  /** 删除影视库（乐观删除 + 失败恢复） */
  async deleteLibrary(lib: VideoLibrary): Promise<void> {
    const idx = this.libraries.findIndex((e: VideoLibrary): boolean => e.id === lib.id);
    if (idx < 0) {
      return;
    }
    const removed = this.libraries[idx];
    const next = this.libraries.slice();
    next.splice(idx, 1);
    this.libraries = next;

    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.deleteLibrary(lib.id);
      DialogUtil.dismissLoading();
      if (!res.success) {
        const restored = this.libraries.slice();
        restored.splice(idx, 0, removed);
        this.libraries = restored;
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchLibraries();
    } catch (_e) {
      const restored = this.libraries.slice();
      restored.splice(idx, 0, removed);
      this.libraries = restored;
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 服务端返回单条库数据时解析（当前实现走列表刷新，保留备用） */
  parseOne(data: Object): VideoLibrary {
    return parseVideoLibrary(data);
  }
}

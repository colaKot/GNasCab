import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase, DialogResult } from '../../common/DialogUtil';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../files/views/FolderPickerSheet';
import { VideoLibrary, VideoSource, libTypeLabelKey } from '../models/VideoModels';
import { VideoSourceSettingsController } from '../controllers/VideoSourceSettingsController';

/**
 * 影音来源设置视图（对齐 Flutter VideoSourceSettingsView 移动端版式）：
 * 标题 + 扫描全部/预生成缩略图 + 来源卡片列表 + 添加来源卡片 + 添加来源弹窗。
 * 来源的媒体类型由所属影视库派生，创建后不可修改 → 卡片只读展示「影视库」。
 */

@Builder
function VideoSourceSettingsEmpty() {
}

@ComponentV2
export struct VideoSourceSettingsView {
  ctrl: VideoSourceSettingsController = new VideoSourceSettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
  }

  private hoursOptions(): PickOption[] {
    const out: PickOption[] = [];
    for (let i = 1; i <= 24; i++) {
      out.push(new PickOption(`${i}`, `${i}`));
    }
    return out;
  }

  private showHoursPick(source: VideoSource): void {
    showOptionPickSheet(L10n.t('video_source_scan_interval_hours', '扫描间隔（小时）'),
      this.hoursOptions(), `${this.ctrl.getIntervalHours(source)}`, (key: string): void => {
        const hours = Number.parseInt(key, 10) || 2;
        void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1, hours * 3600 * 1000);
      });
  }

  private relocateSource(source: VideoSource): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_source_relocate_confirm', '确定要重新定位该来源路径吗？'),
      (): void => {
        pickTargetFolderViaSheet('', (paths: string[]): void => {
          if (paths.length === 0) {
            return;
          }
          void this.ctrl.relocateSource(source, paths[0].trim());
        });
      });
  }

  private deleteSource(source: VideoSource): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('video_source_delete_confirm', '确定删除该来源吗？(@path)', L10n.paramsOf('path', source.path)),
      (): void => {
        void this.ctrl.deleteSourceOptimistic(source);
      });
  }

  private scanAll(): void {
    void this.ctrl.scanSource('all');
  }

  private preGenerate(): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('photo_source_reset_thumbnails_confirm', '确定要重新生成缩略图吗？这可能需要较长时间'),
      (): void => {
        void this.ctrl.preGenerateThumbnails();
      });
  }

  private pickAndAdd(): void {
    if (this.ctrl.libraries.length === 0) {
      DialogUtil.showInfoDialog(L10n.tip, L10n.t('video_library_empty', '还没有创建影视库'));
      return;
    }
    showVideoAddSourceDialog(this.ctrl.libraries,
      (path: string, libraryId: number, matchNfo: boolean): void => {
        void this.ctrl.addSource(path, libraryId, matchNfo ? 1 : 0);
      });
  }

  /** 帮助图标（点击弹信息窗，对齐 Flutter IconButton + tooltip） */
  @Builder
  HelpButton(text: string) {
    SymbolGlyph($r('sys.symbol.questionmark_circle'))
      .fontSize(16)
      .fontColor([AppTheme.current().subText])
      .onClick(() => {
        DialogUtil.showInfoDialog(L10n.tip, text);
      })
  }

  /** 开关行（对齐 Flutter switchRow） */
  @Builder
  SwitchLine(title: string, helpText: string, value: boolean, onChanged: (v: boolean) => void) {
    Row() {
      Row({ space: 6 }) {
        Text(title)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.HelpButton(helpText)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(AppTheme.current().primary)
        .onChange((v: boolean) => {
          onChanged(v);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SourceCard(source: VideoSource) {
    Column() {
      Text(source.path)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Blank().height(8)
      Row({ space: 8 }) {
        if (!source.exists) {
          Text(L10n.t('photo_source_relocate', '重新定位'))
            .fontSize(13)
            .fontColor(AppTheme.current().primary)
            .padding({ top: 4, bottom: 4, right: 4 })
            .onClick(() => {
              this.relocateSource(source);
            })
        }
        Text(source.exists
          ? `[${L10n.t('video_source_available', '可用')}]`
          : `[${L10n.t('video_source_unavailable', '不可用')}]`)
          .fontSize(12)
          .fontColor(source.exists ? '#2E9E44' : '#D64545')
        Blank()
        if (source.exists) {
          Text(L10n.t('video_source_scan_now', '立即扫描'))
            .fontSize(13)
            .fontColor(AppTheme.current().primary)
            .padding({ top: 4, bottom: 4, left: 4 })
            .onClick(() => {
              void this.ctrl.scanSource(source.path);
            })
        }
        Text(L10n.t('delete', '删除'))
          .fontSize(13)
          .fontColor(AppTheme.current().error)
          .padding({ top: 4, bottom: 4, left: 4 })
          .onClick(() => {
            this.deleteSource(source);
          })
      }
      .width('100%')
      Blank().height(6)

      // 影视库行（只读：归属库创建后不可修改，媒体类型由它派生）
      Row() {
        Text(L10n.t('video_library_manage_title', '影视库'))
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(source.libraryDisplayName().length > 0
            ? source.libraryDisplayName()
            : L10n.t('video_library_manage_title', '影视库'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 130 })
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(13)
            .fontColor([AppTheme.current().subText])
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      this.SwitchLine(L10n.t('video_source_match_nfo', '匹配 NFO'),
        L10n.t('video_source_help_match_nfo', '开启后优先使用 NFO 文件中的元数据'),
        source.matchNfo === 1, (v: boolean): void => {
          void this.ctrl.updateMatchNfoOptimistic(source, v ? 1 : 0);
        })
      this.SwitchLine(L10n.t('video_source_scan_when_start', '启动时扫描'),
        L10n.t('video_source_help_scan_when_start', '启动应用时自动扫描该来源'),
        source.scanWhenStart === 1, (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(source, v ? 1 : 0);
        })
      this.SwitchLine(L10n.t('video_source_scan_when_change', '变化时扫描'),
        L10n.t('video_source_help_scan_when_change', '目录内容变化时自动扫描该来源'),
        source.scanWhenChange === 1, (v: boolean): void => {
          void this.ctrl.updateSourceOptimistic(source, undefined, v ? 1 : 0);
        })

      // 定时扫描开关
      Row() {
        Row({ space: 6 }) {
          Text(L10n.t('video_source_scan_interval', '定时扫描'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
          this.HelpButton(L10n.t('video_source_help_scan_interval', '按设定间隔定时扫描该来源'))
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.ctrl.getIntervalEnabled(source) })
          .selectedColor(AppTheme.current().primary)
          .onChange((v: boolean) => {
            if (v) {
              const ms = this.ctrl.getIntervalHours(source) * 3600 * 1000;
              void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 1, ms);
            } else {
              void this.ctrl.updateSourceOptimistic(source, undefined, undefined, 0, 0);
            }
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })

      // 小时下拉（启用时显示）
      if (this.ctrl.getIntervalEnabled(source)) {
        Row() {
          Text(L10n.t('video_source_scan_interval_hours', '扫描间隔（小时）'))
            .fontSize(13)
            .fontColor(AppTheme.current().onSurface)
          Blank()
          Row({ space: 4 }) {
            Text(`${this.ctrl.getIntervalHours(source)}`)
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([AppTheme.current().subText])
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.16)
          })
          .onClick(() => {
            this.showHoursPick(source);
          })
        }
        .width('100%')
        .padding({ top: 2 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(16)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
  }

  build() {
    Column() {
      List({ space: 12 }) {
        ListItem() {
          // 标题 + 扫描全部 + 预生成缩略图
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(L10n.t('settings_source', '来源设置'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .margin({ right: 10 })
            Text(L10n.t('video_source_scan_all', '扫描全部'))
              .fontSize(14)
              .fontColor(AppTheme.current().primary)
              .padding({ top: 4, bottom: 4, right: 10 })
              .onClick(() => {
                this.scanAll();
              })
            Text(L10n.t('photo_source_reset_thumbnails', '预生成缩略图'))
              .fontSize(14)
              .fontColor(AppTheme.current().primary)
              .padding({ top: 4, bottom: 4 })
              .onClick(() => {
                this.preGenerate();
              })
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
        }
        .padding({ left: 16, right: 16 })

        ForEach(this.ctrl.sources, (s: VideoSource) => {
          ListItem() {
            Column() {
              this.SourceCard(s)
            }
            .padding({ left: 16, right: 16 })
          }
        }, (s: VideoSource): string => `${s.id}_${s.path}_${s.mediaType}_${s.libraryId}_${s.libraryName}_${s.matchNfo}_${s.scanWhenStart}_${s.scanWhenChange}_${s.scanInterval}_${s.scanIntervalMs}_${s.exists}`)

        ListItem() {
          // 添加来源卡片
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(20)
              .fontColor([AppTheme.current().primary])
            Text(L10n.t('video_source_add_card', '添加来源'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.current().onSurface)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .borderRadius(16)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
          })
          .onClick(() => {
            this.pickAndAdd();
          })
        }
        .padding({ left: 16, right: 16 })

        ListItem() {
          Row().height(8)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }
}

// ===== 添加来源弹窗（对齐 Flutter _showAddSourceDialog） =====

class VideoAddSourceDialogParams extends DialogParamsBase {
  /** 可选影视库（来源的媒体类型由所属库 lib_type 派生，创建后不可改） */
  libraries: VideoLibrary[] = [];
  onConfirm: (path: string, libraryId: number, matchNfo: boolean) => void =
    (_p: string, _l: number, _n: boolean): void => {
    };
}

@ComponentV2
struct VideoAddSourceDialogInner {
  @Param p: VideoAddSourceDialogParams = new VideoAddSourceDialogParams();
  @Local selectedPath: string = '';
  @Local libraryId: number = 0;
  @Local matchNfo: boolean = false;

  aboutToAppear(): void {
    // 默认选中第一个影视库（对齐 Flutter：libraries.first.id）
    this.libraryId = this.p.libraries.length > 0 ? this.p.libraries[0].id : 0;
  }

  private pickPath(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.selectedPath = paths[0].trim();
    });
  }

  private libraryOptions(): PickOption[] {
    const out: PickOption[] = [];
    for (const lib of this.p.libraries) {
      out.push(new PickOption(`${lib.id}`,
        `${lib.displayName()}（${L10n.t(libTypeLabelKey(lib.libType), lib.libType)}）`));
    }
    return out;
  }

  private currentLibraryLabel(): string {
    for (const lib of this.p.libraries) {
      if (lib.id === this.libraryId) {
        return lib.displayName();
      }
    }
    return L10n.t('video_library_empty', '还没有创建影视库');
  }

  private pickLibrary(): void {
    if (this.p.libraries.length === 0) {
      return;
    }
    showOptionPickSheet(L10n.t('video_source_select_library', '选择影视库'),
      this.libraryOptions(), `${this.libraryId}`, (key: string): void => {
        this.libraryId = Number.parseInt(key, 10) || 0;
      });
  }

  private submit(): void {
    if (this.selectedPath.trim().length === 0) {
      DialogUtil.showInfoDialog(L10n.tip, L10n.t('video_source_add_path_required', '请先选择来源路径'));
      return;
    }
    if (this.libraryId <= 0) {
      DialogUtil.showInfoDialog(L10n.tip, L10n.t('video_source_select_library', '选择影视库'));
      return;
    }
    this.p.onConfirm(this.selectedPath.trim(), this.libraryId, this.matchNfo);
    this.p.onResult(undefined);
  }

  build() {
    Column() {
      Text(L10n.t('video_source_add_dialog_title', '添加来源'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Column() {
        // 路径行
        Row({ space: 12 }) {
          Text(this.selectedPath.length > 0 ? this.selectedPath
            : L10n.t('video_source_add_path_empty', '尚未选择路径'))
            .fontSize(14)
            .fontColor(this.selectedPath.length > 0
              ? AppTheme.current().onSurface
              : AppTheme.current().subText)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(L10n.t('video_source_add_pick_path', '选择路径'))
            .fontSize(14)
            .fontColor(AppTheme.current().primary)
            .onClick(() => {
              this.pickPath();
            })
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        // 影视库选择（替代原媒体类型单选）
        Text(L10n.t('video_source_select_library', '选择影视库'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .margin({ top: 16 })
        if (this.p.libraries.length === 0) {
          Text(L10n.t('video_library_empty', '还没有创建影视库'))
            .fontSize(13)
            .fontColor(AppTheme.current().error)
            .margin({ top: 8 })
        } else {
          Row() {
            Text(this.currentLibraryLabel())
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(13)
              .fontColor([AppTheme.current().subText])
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .margin({ top: 8 })
          .borderRadius(10)
          .border({
            width: 1,
            color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.16)
          })
          .onClick(() => {
            this.pickLibrary();
          })
          Text(L10n.t('video_library_type_immutable', '分类创建后不可修改'))
            .fontSize(12)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
            .margin({ top: 6 })
        }

        Row() {
          Text(L10n.t('video_source_add_match_nfo_title', '匹配 NFO 文件'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.matchNfo })
            .selectedColor(AppTheme.current().primary)
            .onChange((v: boolean) => {
              this.matchNfo = v;
            })
        }
        .margin({ top: 6 })
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 14 })
      .width('100%')

      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(L10n.t('video_source_add_submit', '添加'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .onClick(() => {
            this.submit();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoAddSourceDialogContent(p: VideoAddSourceDialogParams) {
  VideoAddSourceDialogInner({ p: p })
}

/** 打开添加来源弹窗（对齐 Flutter _pickAndAdd） */
function showVideoAddSourceDialog(libraries: VideoLibrary[],
  onConfirm: (path: string, libraryId: number, matchNfo: boolean) => void): void {
  const p = new VideoAddSourceDialogParams();
  p.libraries = libraries;
  p.onConfirm = onConfirm;
  DialogUtil.openCustom(p, wrapBuilder(VideoAddSourceDialogContent), false, (_r: DialogResult | undefined): void => {
  });
}

import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { DialogUtil, DialogParamsBase, DialogResult } from '../../common/DialogUtil';
import { EmptyState } from '../../common/components/EmptyState';
import { VideoLibrary, VIDEO_LIB_TYPES, libTypeLabelKey } from '../models/VideoModels';
import { VideoLibrarySettingsController } from '../controllers/VideoLibrarySettingsController';

/**
 * 影视库管理页（对齐 Flutter VideoLibrarySettingsView）：
 * 每个影视库会作为影音主页模式条上的一个栏目；分类创建后不可修改。
 * 内置库不可删除；库内仍有来源时服务端会拒绝删除。
 */
@ComponentV2
export struct VideoLibrarySettingsPage {
  @Param popPage: () => void = (): void => {
  };
  /**
   * 嵌入模式（影音设置页「影视库」标签内）：不包 PageScaffold
   * （NavDestination 不能嵌在 TabContent/Column 内），窗口样式与顶栏由宿主负责。
   */
  @Param embedded: boolean = false;
  ctrl: VideoLibrarySettingsController = new VideoLibrarySettingsController();

  aboutToAppear(): void {
    this.ctrl.init();
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
  }

  private showAddDialog(): void {
    showCreateLibraryDialog((name: string, libType: string): void => {
      void this.ctrl.addLibrary(name, libType);
    });
  }

  private rename(lib: VideoLibrary): void {
    DialogUtil.showInputDialog(L10n.t('video_library_rename_title', '重命名影视库'),
      L10n.t('video_library_name_hint', '请输入影视库名称'), lib.name,
      L10n.save, L10n.cancel,
      (value: string): string | undefined => {
        return value.trim().length === 0
          ? L10n.t('video_library_name_required', '请输入名称') : undefined;
      }).then((result: DialogResult | undefined): void => {
      if (typeof result !== 'string') {
        return;
      }
      void this.ctrl.renameLibrary(lib.id, result);
    });
  }

  private confirmDelete(lib: VideoLibrary): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('video_library_delete_confirm', '确定删除影视库「@name」吗？该操作不可撤销',
        L10n.paramsOf('name', lib.displayName())),
      (): void => {
        void this.ctrl.deleteLibrary(lib);
      });
  }

  /** 分类图标（按 lib_type 映射系统符号） */
  @Builder
  LibTypeIcon(libType: string) {
    if (libType === 'tv') {
      SymbolGlyph($r('sys.symbol.display'))
        .fontSize(22)
        .fontColor([AppTheme.current().primary])
    } else if (libType === 'image') {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(22)
        .fontColor([AppTheme.current().primary])
    } else if (libType === 'mixed') {
      SymbolGlyph($r('sys.symbol.rectangle_stack'))
        .fontSize(22)
        .fontColor([AppTheme.current().primary])
    } else {
      SymbolGlyph($r('sys.symbol.film'))
        .fontSize(22)
        .fontColor([AppTheme.current().primary])
    }
  }

  @Builder
  LibraryCard(lib: VideoLibrary) {
    Column() {
      Row({ space: 10 }) {
        this.LibTypeIcon(lib.libType)
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(lib.displayName())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.current().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (lib.isDefault) {
              Text(L10n.t('video_library_builtin', '内置'))
                .fontSize(10)
                .fontColor(AppTheme.current().primary)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .border({ width: 1, color: AppTheme.current().primary })
            }
          }
          Text(`${L10n.t(libTypeLabelKey(lib.libType), lib.libType)} · ` +
            `${L10n.t('video_library_source_count', '来源')} ${lib.sourceCount} · ` +
            `${lib.totalCount} ${L10n.t('video_library_item_count', '个条目')}`)
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 16 }) {
        Blank()
        Text(L10n.edit)
          .fontSize(13)
          .fontColor(AppTheme.current().primary)
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.rename(lib);
          })
        if (!lib.isDefault) {
          Text(L10n.delete)
            .fontSize(13)
            .fontColor(AppTheme.current().error)
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.confirmDelete(lib);
            })
        }
      }
      .width('100%')
      .margin({ top: 6 })
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
    if (this.embedded) {
      this.PageContent()
    } else {
      PageScaffold({
        title: L10n.t('video_library_manage_title', '影视库'),
        showBack: true,
        onBack: (): void => {
          this.popPage();
        },
        content: (): void => {
          this.PageContent()
        }
      })
    }
  }

  @Builder
  PageContent() {
    Column() {
      List({ space: 12 }) {
        ListItem() {
          Column({ space: 4 }) {
            Row() {
              Text(L10n.t('video_library_manage_title', '影视库'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.current().onSurface)
              Blank()
              Text(L10n.t('video_library_add', '新建影视库'))
                .fontSize(14)
                .fontColor(AppTheme.current().primary)
                .padding({ top: 4, bottom: 4, left: 8 })
                .onClick(() => {
                  this.showAddDialog();
                })
            }
            .width('100%')

            Text(L10n.t('video_library_manage_desc', '每个影视库会作为左侧栏的一个栏目出现'))
              .fontSize(12)
              .fontColor(AppTheme.current().subText)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .padding({ left: 16, right: 16 })

        if (this.ctrl.libraries.length === 0 && !this.ctrl.loading) {
          ListItem() {
            Column() {
              EmptyState({ message: L10n.t('video_library_empty', '还没有创建影视库') })
            }
            .width('100%')
            .padding({ top: 40 })
          }
          .padding({ left: 16, right: 16 })
        }

        ForEach(this.ctrl.libraries, (lib: VideoLibrary) => {
          ListItem() {
            Column() {
              this.LibraryCard(lib)
            }
            .padding({ left: 16, right: 16 })
          }
        }, (lib: VideoLibrary): string => `${lib.id}_${lib.name}_${lib.nameKey}_${lib.libType}_${lib.sourceCount}_${lib.totalCount}`)

        ListItem() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(20)
              .fontColor([AppTheme.current().primary])
            Text(L10n.t('video_library_add', '新建影视库'))
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
            this.showAddDialog();
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

// ===== 新建影视库弹窗（名称 + 分类单选） =====

class CreateLibraryDialogParams extends DialogParamsBase {
  onConfirm: (name: string, libType: string) => void =
    (_n: string, _t: string): void => {
    };
}

@ComponentV2
struct CreateLibraryDialogInner {
  @Param p: CreateLibraryDialogParams = new CreateLibraryDialogParams();
  @Local name: string = '';
  @Local libType: string = 'movie';
  @Local errorText: string = '';

  private typeLabel(libType: string): string {
    return L10n.t(libTypeLabelKey(libType), libType);
  }

  private typeHint(libType: string): string {
    if (libType === 'tv') {
      return L10n.t('video_library_type_tv', '影视剧');
    }
    if (libType === 'image') {
      return L10n.t('video_library_type_image', '图片');
    }
    if (libType === 'mixed') {
      return L10n.t('video_library_type_mixed', '图片和影视混合');
    }
    return L10n.t('video_library_type_movie', '电影');
  }

  private submit(): void {
    const n = this.name.trim();
    if (n.length === 0) {
      this.errorText = L10n.t('video_library_name_required', '请输入名称');
      return;
    }
    this.errorText = '';
    this.p.onConfirm(n, this.libType);
    this.p.onResult(undefined);
  }

  @Builder
  TypeRadio(libType: string) {
    Row({ space: 10 }) {
      Circle()
        .width(18)
        .height(18)
        .fill(this.libType === libType ? AppTheme.current().primary : Color.Transparent)
        .stroke(AppTheme.current().primary)
        .strokeWidth(this.libType === libType ? 5 : 1.5)
      Column({ space: 2 }) {
        Text(this.typeLabel(libType))
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
        Text(this.typeHint(libType))
          .fontSize(11)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.libType = libType;
    })
  }

  build() {
    Column() {
      Text(L10n.t('video_library_add_title', '新建影视库'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')

      Text(L10n.t('video_library_name_label', '名称'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 16 })
      TextInput({ text: this.name, placeholder: L10n.t('video_library_name_hint', '请输入影视库名称') })
        .type(InputType.Normal)
        .height(42)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .borderRadius(8)
        .margin({ top: 8 })
        .width('100%')
        .onChange((v: string) => {
          this.name = v;
          if (this.errorText.length > 0 && v.trim().length > 0) {
            this.errorText = '';
          }
        })
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(AppTheme.current().error)
          .margin({ top: 6 })
      }

      Text(L10n.t('video_library_type_label', '分类'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 16 })
      Column() {
        ForEach(VIDEO_LIB_TYPES, (t: string) => {
          this.TypeRadio(t)
        }, (t: string): string => t)
      }
      .margin({ top: 4 })
      .width('100%')

      Text(L10n.t('video_library_type_immutable', '分类创建后不可修改'))
        .fontSize(12)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .margin({ top: 4 })

      Row({ space: 8 }) {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(L10n.t('video_library_add', '新建影视库'))
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
function CreateLibraryDialogContent(p: CreateLibraryDialogParams) {
  CreateLibraryDialogInner({ p: p })
}

/** 打开新建影视库弹窗 */
function showCreateLibraryDialog(onConfirm: (name: string, libType: string) => void): void {
  const p = new CreateLibraryDialogParams();
  p.onConfirm = onConfirm;
  DialogUtil.openCustom(p, wrapBuilder(CreateLibraryDialogContent), false,
    (_r: DialogResult | undefined): void => {
    });
}

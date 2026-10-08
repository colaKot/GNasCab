import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { EmptyState } from '../../common/components/EmptyState';
import { AppImage } from '../../common/components/AppImage';
import { ApiUrls } from '../../core/network/ApiUrls';
import { LivePhotoInlinePlayer } from '../../gallery/components/LivePhotoInlinePlayer';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoListController } from '../controllers/VideoListController';
import { VideoUtils } from '../utils/VideoItemUtils';
import { VideoMediaBrowserPageParam } from '../router/VideoRoutes';

/**
 * 影视库媒体浏览页（对齐 Flutter VideoMediaBrowserPage）：
 * 图片库 / 图片与影视混合库专用 —— 网格缩略图列表，点开进入全屏；
 * 全屏用竖向 Swiper 实现「上滑进入下一个」，图片看原图、视频就地内联播放。
 */

/** 条目主路径（图片原图/缩略图都基于它） */
function mediaPrimaryPath(item: VideoHomeItemBean): string {
  const full = item.fullPath.trim();
  if (full.length > 0) {
    return full;
  }
  const first = item.firstFilePath.trim();
  if (first.length > 0) {
    return first;
  }
  return item.path.trim();
}

/** 条目展示名（优先 NFO 名，回落文件名） */
function mediaDisplayName(item: VideoHomeItemBean): string {
  const nfo = item.nfoName.trim();
  if (nfo.length > 0) {
    return nfo;
  }
  const name = item.filename.trim();
  return name.length > 0 ? name : mediaPrimaryPath(item);
}

// ===== 网格缩略图 =====

@ComponentV2
struct MediaGridTile {
  @Param item: VideoHomeItemBean = new VideoHomeItemBean();
  @Param onTap: () => void = (): void => {
  };
  @Local url: string = '';

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    if (this.item.isImage) {
      const p = mediaPrimaryPath(this.item);
      this.url = p.length > 0 ? await ApiUrls.getTinyUrl(p, 320) : '';
      return;
    }
    this.url = await VideoUtils.getPosterUrl(this.item, 400);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.url.length > 0) {
        AppImage({
          url: this.url,
          objectFit: ImageFit.Cover,
          showLoadingSpin: false
        })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      }
      // 视频条目左下角播放角标（图片不加）
      if (!this.item.isImage) {
        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(30)
          .fontColor(['#E6FFFFFF'])
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(6)
    .clip(true)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.06))
    .onClick(() => {
      this.onTap();
    })
  }
}

// ===== 全屏单页（竖向 Swiper 的一页） =====

@ComponentV2
struct MediaViewerSlide {
  @Param item: VideoHomeItemBean = new VideoHomeItemBean();
  @Local url: string = '';
  @Local playing: boolean = false;
  @Local videoUrl: string = '';

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    const p = mediaPrimaryPath(this.item);
    if (this.item.isImage) {
      this.url = p.length > 0 ? await ApiUrls.getRawFileUrl(p) : '';
      return;
    }
    // 视频：封面用海报/首帧，播放地址优先 play_file_path
    this.url = await VideoUtils.getPosterUrl(this.item, 1600);
    const play = this.item.playFilePath.trim();
    this.videoUrl = play.length > 0 ? play : p;
  }

  private async startPlay(): Promise<void> {
    if (this.videoUrl.trim().length === 0) {
      return;
    }
    // 播放器直接吃文件路径，由 LivePhotoInlinePlayer 内部解析为可播 URL
    const resolved = await ApiUrls.getRawFileUrl(this.videoUrl.trim());
    this.videoUrl = resolved;
    this.playing = true;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.playing && this.videoUrl.length > 0) {
        LivePhotoInlinePlayer({
          videoUrl: this.videoUrl,
          onClose: (): void => {
            this.playing = false;
          }
        })
      } else {
        if (this.url.length > 0) {
          AppImage({
            url: this.url,
            objectFit: ImageFit.Contain,
            showLoadingSpin: true
          })
        }
        if (!this.item.isImage) {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.play_circle'))
              .fontSize(64)
              .fontColor(['#E6FFFFFF'])
            Text(mediaDisplayName(this.item))
              .fontSize(13)
              .fontColor('#E6FFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            void this.startPlay();
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}

@ComponentV2
export struct VideoMediaBrowserPage {
  @Param param: VideoMediaBrowserPageParam = new VideoMediaBrowserPageParam();
  @Param popPage: () => void = (): void => {
  };
  /**
   * 嵌入模式（影音主页模式条内）：不包 PageScaffold（NavDestination 不能嵌在 Column 内），
   * 安全区与顶栏由宿主负责，这里只出网格与全屏浮层。
   */
  @Param embedded: boolean = false;
  ctrl: VideoListController = new VideoListController();
  @Local viewerIndex: number = 0;
  @Local viewerOpen: boolean = false;

  aboutToAppear(): void {
    // 图片库只取 image；混合库不限类型（由后端按库放行 image + 影视）
    this.ctrl.configure(this.param.libType === 'image' ? 'image' : '',
      '', 0, 0, 0, [], [], [], [], this.param.libraryId);
    this.ctrl.init();
  }

  aboutToDisappear(): void {
    this.ctrl.dispose();
  }

  private openViewer(index: number): void {
    this.viewerIndex = index;
    this.viewerOpen = true;
  }

  private title(): string {
    const t = this.param.title.trim();
    return t.length > 0 ? t : L10n.t('video_library_manage_title', '影视库');
  }

  build() {
    if (this.embedded) {
      // 嵌入模式：宿主负责窗口样式/安全区，这里自己叠一层全屏浮层
      Stack() {
        this.PageContent()
        if (this.viewerOpen) {
          this.ViewerOverlay()
        }
      }
      .width('100%')
      .height('100%')
    } else {
      // 常规路由页：PageScaffold 根节点即 NavDestination（不能被 Stack 包住），
      // 全屏浮层走它的 overlayContent（渲染在 NavDestination 内部顶层）
      PageScaffold({
        title: this.title(),
        showBack: true,
        onBack: (): void => {
          this.popPage();
        },
        actions: (): void => {
          this.HeaderActions()
        },
        content: (): void => {
          this.PageContent()
        },
        overlayContent: (): void => {
          if (this.viewerOpen) {
            this.ViewerOverlay()
          }
        }
      })
    }
  }

  @Builder
  HeaderActions() {
    Row({ space: 10 }) {
      Text(`${this.ctrl.total}`)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
    }
    .padding({ right: 12 })
  }

  @Builder
  PageContent() {
    Column() {
      if (this.ctrl.items.length === 0 && !this.ctrl.loading) {
        Column() {
          EmptyState({ message: L10n.t('no_data', '暂无数据') })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.ctrl.items, (item: VideoHomeItemBean) => {
            GridItem() {
              MediaGridTile({
                item: item,
                onTap: (): void => {
                  this.openViewer(this.indexOfItem(item.id));
                }
              })
            }
          }, (item: VideoHomeItemBean): string => `${item.id}_${item.mediaType}_${item.fullPath}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(4)
        .rowsGap(4)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ left: 8, right: 8, bottom: 8 })
        .onScrollIndex((_first: number, last: number): void => {
          if (last >= this.ctrl.items.length - 6) {
            void this.ctrl.loadMore(true);
          }
        })

        if (this.ctrl.loadingMore) {
          Row() {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 8 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }

  private indexOfItem(id: number): number {
    const idx = this.ctrl.items.findIndex((e: VideoHomeItemBean): boolean => e.id === id);
    return idx < 0 ? 0 : idx;
  }

  @Builder
  ViewerOverlay() {
    Stack() {
      Swiper() {
        ForEach(this.ctrl.items, (item: VideoHomeItemBean) => {
          MediaViewerSlide({ item: item })
        }, (item: VideoHomeItemBean): string => `viewer_${item.id}_${item.mediaType}`)
      }
      .vertical(true)
      .loop(false)
      .index(this.viewerIndex)
      .indicator(false)
      .width('100%')
      .height('100%')
      .onChange((index: number): void => {
        this.viewerIndex = index;
        // 接近末尾时预加载更多（与网格翻页一致）
        if (index >= this.ctrl.items.length - 3) {
          void this.ctrl.loadMore(true);
        }
      })

      // 顶栏：关闭 / 名称 / 序号
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(22)
          .fontColor(['#FFFFFF'])
          .onClick(() => {
            this.viewerOpen = false;
          })
        Column({ space: 2 }) {
          Text(this.ctrl.items.length > 0 && this.viewerIndex < this.ctrl.items.length
            ? mediaDisplayName(this.ctrl.items[this.viewerIndex])
            : '')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.ctrl.items.length > 0
            ? `${this.viewerIndex + 1} / ${this.ctrl.items.length}` : '')
            .fontSize(11)
            .fontColor('#B3FFFFFF')
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: 0 })

      // 底部提示
      Text(L10n.t('video_library_viewer_hint', '上滑查看下一个'))
        .fontSize(12)
        .fontColor('#B3FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ bottom: 16 })
        .position({ x: 0, y: '100%' })
        .markAnchor({ y: '100%' })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}

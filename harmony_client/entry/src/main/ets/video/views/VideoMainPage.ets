import { window } from '@kit.ArkUI';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { ThemeManager } from '../../core/theme/ThemeManager';
import { AppEventBus } from '../../common/AppEventBus';
import { SystemBars } from '../../common/SystemBars';
import { WindowStore } from '../../common/WindowStore';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../common/components/BottomTabBar';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { FolderViewBody } from '../../modules/folder_view/views/FolderViewBody';
import { FolderViewModuleType } from '../../modules/folder_view/models/FolderViewModuleType';
import { VideoListPageParam, VideoMediaBrowserPageParam } from '../router/VideoRoutes';
import { VideoListPage } from './VideoListPage';
import { VideoHomePage } from './VideoHomePage';
import { VideoAlbumsHomePage } from './VideoAlbumsHomePage';
import { VideoMediaBrowserPage } from './VideoMediaBrowserPage';
import { VideoLibrary } from '../models/VideoModels';
import { VideoLibraryApiService } from '../service/VideoApiServices';

/**
 * 影音管理主页（对齐 Flutter AppVideoMainView 移动端布局）：
 * 底部 4 标签（影库/历史/相册/文件）+ 影库内浮动模式条（首页 + 动态影视库栏目 + 收藏）+
 * 首页模式下左上主页按钮与右上设置按钮（管理员）。
 * 栏目由服务端下发的影视库列表驱动（创建/删除影视库后立即生效）。
 */
@ComponentV2
export struct VideoMainPage {
  @Param param: VideoMainPageParam = new VideoMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local activeTab: number = 0;
  /** 影库内当前栏目：'home' 首页 / 'lib:<id>' 影视库 / 'favorite' 收藏 */
  @Local activeKey: string = 'home';
  /** 影视库列表（驱动模式条栏目；每个库同时决定其中的媒体类型/展示方式） */
  @Local libraries: VideoLibrary[] = [];
  private libraryApi: VideoLibraryApiService = new VideoLibraryApiService();
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后非沉浸内容用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
  @Local navigationBarHeight: number = 0;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    SystemBars.update(this, { colors: SystemBars.immersiveColors(), fullscreen: true });
  };

  aboutToAppear(): void {
    SystemBars.activate(this, { colors: SystemBars.immersiveColors(), fullscreen: true });
    this.fetchSafeAreas();
    void this.fetchLibraries();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 出栈后自动恢复上一页窗口样式，无需手动重置
    SystemBars.deactivate(this);
  }

  /** 拉取影视库列表（创建/删除/改名后回到本页会重新刷新） */
  private async fetchLibraries(): Promise<void> {
    try {
      const list = await this.libraryApi.listLibraries();
      this.libraries = list;
      // 当前栏目对应的库已被删除 → 退回首页
      const id = this.libraryIdFromKey(this.activeKey);
      if (id > 0 && !list.some((e: VideoLibrary): boolean => e.id === id)) {
        this.activeKey = 'home';
      }
    } catch (_e) {
      // 拉取失败保持现有栏目，不打断首页
    }
  }

  /** 'lib:<id>' → id；非库栏目返回 0 */
  private libraryIdFromKey(key: string): number {
    if (!key.startsWith('lib:')) {
      return 0;
    }
    return Number.parseInt(key.substring(4), 10) || 0;
  }

  private libraryById(id: number): VideoLibrary | undefined {
    return this.libraries.find((e: VideoLibrary): boolean => e.id === id);
  }

  /** 按分类激活栏目（首页「最近添加」入口用：找第一个该分类的库） */
  private activateByLibType(libType: string): void {
    const lib = this.libraries.find((e: VideoLibrary): boolean => e.libType === libType);
    if (lib !== undefined) {
      this.activeKey = `lib:${lib.id}`;
    }
  }

  private fetchSafeAreas(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = px2vp(top.topRect.height);
    const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navigationBarHeight = px2vp(bottom.bottomRect.height);
  }

  private get isHomeMode(): boolean {
    return this.activeTab === 0 && this.activeKey === 'home';
  }

  build() {
    NavDestination() {
      Stack() {
        // 底部安全区背景层：与底部 tab 栏同底色（surfaceBg），延伸到底部导航条安全区
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.current().surfaceBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        Column() {
          // 内容区：tab 主体 + 浮动模式条
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              this.TabBody()
            }
            .width('100%')
            .height('100%')

            if (this.activeTab === 0) {
              this.FloatingModeBar()
            }

            // 首页模式下浮动主页/设置按钮（对齐 Flutter Positioned top+10）
            if (this.isHomeMode) {
              Row() {
                BorderedIconButton({
                  icon: $r('sys.symbol.house'),
                  btnSize: 42,
                  iconSize: 22,
                  corner: 21,
                  fillColor: AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.75),
                  onTap: (): void => {
                    this.popPage();
                  }
                })
                Blank()
                if (CurrentUserStore.getInstance().isAdmin) {
                  BorderedIconButton({
                    icon: $r('sys.symbol.gearshape'),
                    btnSize: 42,
                    iconSize: 22,
                    corner: 21,
                    fillColor: AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.75),
                    onTap: (): void => {
                      NavUtil.push(AppRouter.VIDEO_SETTINGS, new Object());
                    }
                  })
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: this.statusBarHeight + 10 })
              .position({ x: 0, y: 0 })
            }
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              this.activeTab = index;
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.current().pageBg)
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onShown((): void => {
      // 转场动画完成后再次激活本页样式（内部含 120ms 转场重试）
      SystemBars.activate(this, { colors: SystemBars.immersiveColors(), fullscreen: true });
      // 从设置页返回时刷新影视库列表（新建/删除/改名后栏目要跟着变）
      void this.fetchLibraries();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  /** 影库浮动模式条（对齐 _buildFloatingModeBar：首页 + 动态影视库栏目 + 收藏） */
  @Builder
  FloatingModeBar() {
    Scroll() {
      Row({ space: 6 }) {
        this.ModeChip(L10n.t('home', '首页'), 'home')
        ForEach(this.libraries, (lib: VideoLibrary) => {
          this.ModeChip(lib.displayName(), `lib:${lib.id}`)
        }, (lib: VideoLibrary): string => `mode_${lib.id}_${lib.name}_${lib.nameKey}_${lib.libType}`)
        this.ModeChip(L10n.t('favorites', '收藏'), 'favorite')
      }
      .padding({ left: 6, right: 6 })
      .height(45)
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(45)
    .borderRadius(22.5)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
    .margin({ left: 16, right: 16, bottom: 10 })
  }

  /** 选中态在 @Builder 内直接读取 this.activeKey（@Builder 按值传参不随状态刷新） */
  @Builder
  ModeChip(label: string, key: string) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.activeKey === key ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.activeKey === key ? '#FFFFFF' : AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 140 })
    }
    .height(32)
    .padding({ left: 14, right: 14 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.activeKey === key ? AppTheme.current().primary : Color.Transparent)
    .onClick(() => {
      this.activeKey = key;
    })
  }

  /** tab 主体（对齐 _buildTabBody）：全屏布局下非首页 tab 需避让状态栏 */
  @Builder
  TabBody() {
    if (this.activeTab === 0 && this.activeKey === 'home') {
      // 首页轮播顶格沉浸，不做状态栏避让
      this.TabBodyInner()
    } else {
      Column() {
        this.TabBodyInner()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
    }
  }

  @Builder
  TabBodyInner() {
    if (this.activeTab === 0) {
      if (this.activeKey === 'home') {
        VideoHomePage({
          onOpenMovie: (): void => {
            this.activateByLibType('movie');
          },
          onOpenTv: (): void => {
            this.activateByLibType('tv');
          },
          onOpenHistory: (): void => {
            this.activeTab = 1;
          },
          onOpenSettings: (): void => {
            NavUtil.push(AppRouter.VIDEO_SETTINGS, new Object());
          }
        })
      } else if (this.activeKey === 'favorite') {
        this.EmbeddedList('', 'favorite', 0)
      } else {
        this.LibraryBody()
      }
    } else if (this.activeTab === 1) {
      this.EmbeddedList('', 'history', 0)
    } else if (this.activeTab === 2) {
      VideoAlbumsHomePage()
    } else {
      // 文件视图（对齐 Flutter AppFolderViewPage，video 模块）
      FolderViewBody({ moduleType: FolderViewModuleType.Video })
    }
  }

  /** 影视库栏目主体：图片/混合库走网格+竖向全屏，电影/影视剧库走海报列表 */
  @Builder
  LibraryBody() {
    if (!this.hasActiveLibrary()) {
      // 列表尚未加载完（或该库刚被删除）→ 转圈占位，避免闪回首页
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.activeLibraryIsGrid()) {
      VideoMediaBrowserPage({
        param: this.makeMediaBrowserParam(this.libraryIdFromKey(this.activeKey)),
        embedded: true,
        popPage: (): void => {
          this.activeTab = 0;
          this.activeKey = 'home';
        }
      })
    } else {
      this.EmbeddedList(this.activeLibraryType(), '', this.libraryIdFromKey(this.activeKey))
    }
  }

  private hasActiveLibrary(): boolean {
    return this.libraryById(this.libraryIdFromKey(this.activeKey)) !== undefined;
  }

  private activeLibraryIsGrid(): boolean {
    const lib = this.libraryById(this.libraryIdFromKey(this.activeKey));
    return lib !== undefined && lib.isMediaGridLib;
  }

  private activeLibraryType(): string {
    const lib = this.libraryById(this.libraryIdFromKey(this.activeKey));
    return lib !== undefined ? lib.libType : '';
  }

  private makeMediaBrowserParam(libraryId: number): VideoMediaBrowserPageParam {
    const lib = this.libraryById(libraryId);
    const p = new VideoMediaBrowserPageParam();
    p.libraryId = libraryId;
    p.libType = lib !== undefined ? lib.libType : 'image';
    p.title = lib !== undefined ? lib.displayName() : '';
    return p;
  }

  @Builder
  EmbeddedList(initialMediaType: string, listType: string, libraryId: number) {
    VideoListPage({
      param: this.makeListParam(initialMediaType, listType, libraryId),
      embedded: true,
      onBackHome: (): void => {
        this.activeTab = 0;
        this.activeKey = 'home';
      },
      popPage: (): void => {
        this.activeTab = 0;
        this.activeKey = 'home';
      }
    })
  }

  private makeListParam(initialMediaType: string, listType: string,
    libraryId: number): VideoListPageParam {
    const p = new VideoListPageParam();
    p.initialMediaType = initialMediaType;
    p.listType = listType;
    p.libraryId = libraryId;
    return p;
  }

  /** 底部 4 标签（影库/历史/相册/文件） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.film'), L10n.t('video_menu_library', '影库')),
      new BottomTabItem($r('sys.symbol.clock'), L10n.t('video_menu_library_history', '历史')),
      new BottomTabItem($r('sys.symbol.rectangle_stack'), L10n.t('video_menu_albums', '相册')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file', '文件'))
    ];
  }
}

/** 影音主页路由参数（对齐 Flutter AppVideoMainRoutePage） */
export class VideoMainPageParam {
  title: string = '';
}

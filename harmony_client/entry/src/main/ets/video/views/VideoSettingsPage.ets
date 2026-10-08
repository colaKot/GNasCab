import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { PageScaffold } from '../../common/PageScaffold';
import { VideoLibrarySettingsPage } from './VideoLibrarySettingsPage';
import { VideoSourceSettingsView } from './VideoSourceSettingsView';
import { VideoOtherSettingsView } from './VideoOtherSettingsView';

/**
 * 影音设置页（对齐 Flutter AppVideoSettingsView）：
 * 顶部三个标签（影视库/来源设置/其他设置），内容区分别承载 VideoLibrarySettingsPage、
 * VideoSourceSettingsView 与 VideoOtherSettingsView。
 */
@ComponentV2
export struct VideoSettingsPage {
  @Param popPage: () => void = (): void => {
  };

  build() {
    PageScaffold({
      title: L10n.setting,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.SettingsContent()
      }
    })
  }

  @Builder
  SettingsContent() {
    Tabs({ barPosition: BarPosition.Start }) {
      TabContent() {
        // 影视库管理直接复用页面组件：嵌入模式下不接管窗口样式/返回
        VideoLibrarySettingsPage({ embedded: true })
      }
      .tabBar(this.TabLabel(L10n.t('video_library_manage_title', '影视库')))

      TabContent() {
        VideoSourceSettingsView()
      }
      .tabBar(this.TabLabel(L10n.t('settings_source', '来源设置')))

      TabContent() {
        VideoOtherSettingsView()
      }
      .tabBar(this.TabLabel(L10n.t('video_other_settings_title', '其他设置')))
    }
    .barMode(BarMode.Fixed)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
  }

  @Builder
  TabLabel(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
      .padding({ top: 10, bottom: 10 })
  }
}

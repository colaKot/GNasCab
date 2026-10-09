import 'package:flutter/material.dart';

/// 界面字体选项（2026-10-09 换肤系统）
///
/// ⭐ **零下载铁律**：这里只登记「已打包字体」和「操作系统自带字体族」。
/// 后者按族名引用即可，不需要下载任何字体文件（桌面端由系统字体管理器解析；
/// Web/移动端若系统无此字体，Flutter 会自动回退到默认字体，不会崩）。
class AppFontOption {
  /// 字体族名。null = 跟随系统默认（清除该项设置）
  final String? family;
  final String labelKey;

  const AppFontOption({required this.family, required this.labelKey});
}

class AppFonts {
  const AppFonts._();

  /// 全部可选字体。**顺序即设置页展示顺序**。
  static const List<AppFontOption> all = [
    AppFontOption(family: null, labelKey: 'theme_font_system'),
    AppFontOption(family: 'Microsoft YaHei', labelKey: 'theme_font_yahei'),
    AppFontOption(family: 'Segoe UI', labelKey: 'theme_font_segoe'),
    AppFontOption(family: 'RobotoMono', labelKey: 'theme_font_mono'),
  ];
}
import 'package:flutter/foundation.dart';

import 'novel_game_controller.dart';

/// 小说模块真正的显示模式。
///
/// 这不是“横屏 / 竖屏”的别名：手机也可以主动进入 desktop，
/// PC 也可以主动切回 mobile 预览。状态放在模块级共享对象里，
/// 因而剧情、人物、队伍、背包、经历、地图等页面都能读取同一个值。
enum NovelDisplayMode {
  mobile,
  desktop,
}

class NovelDisplayModeState extends ChangeNotifier {
  NovelDisplayMode? _mode;

  bool get initialized => _mode != null;

  NovelDisplayMode get mode => _mode ?? NovelDisplayMode.mobile;

  bool get desktopMode => mode == NovelDisplayMode.desktop;

  bool get mobileMode => mode == NovelDisplayMode.mobile;

  /// 只在第一次进入小说模块时根据运行环境给一个默认值。
  /// 一旦模式已经确定，后续窗口尺寸变化不会偷偷覆盖玩家的手动选择。
  void ensureInitialized({
    required double viewportWidth,
    required bool nativeMobile,
  }) {
    if (_mode != null) return;
    _mode = nativeMobile || viewportWidth < 820
        ? NovelDisplayMode.mobile
        : NovelDisplayMode.desktop;
  }

  void setMode(NovelDisplayMode next) {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  void setDesktopMode(bool desktop) {
    setMode(desktop ? NovelDisplayMode.desktop : NovelDisplayMode.mobile);
  }
}

/// 小说模块共享的显示模式状态。
///
/// 保持一个实例，确保切换主剧情后再打开人物 / 背包 / 地图时仍是同一模式。
final NovelDisplayModeState novelDisplayMode = NovelDisplayModeState();

/// 不修改 NovelGameController 原有业务字段，也能让所有已经持有 controller 的
/// 小说页面统一通过 controller.desktopMode 读取显示模式。
extension NovelGameControllerDisplayMode on NovelGameController {
  NovelDisplayMode get displayMode => novelDisplayMode.mode;

  bool get desktopMode => novelDisplayMode.desktopMode;

  bool get mobileMode => novelDisplayMode.mobileMode;

  void setDisplayMode(NovelDisplayMode mode) {
    novelDisplayMode.setMode(mode);
  }

  void setDesktopMode(bool desktop) {
    novelDisplayMode.setDesktopMode(desktop);
  }
}

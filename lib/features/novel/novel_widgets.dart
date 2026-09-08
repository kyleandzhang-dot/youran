import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'novel_asr_stream_service.dart';
import 'novel_game_controller.dart';
import 'novel_display_mode.dart';
import 'novel_socket_service.dart';
import 'novel_models.dart';

import '../../app_shared.dart';
import '../../services/depth_service.dart';

// Novel Widgets 总入口。
// 具体实现按功能域放在 widgets/ 子目录；外部继续只需 import 'novel_widgets.dart'。
// 使用 part/part of 保持原有私有 `_` 类型与方法的 library 可见性，不做业务重构。

part 'widgets/novel_widget_common.dart';
part 'widgets/novel_environment.dart';
part 'widgets/novel_hud.dart';
part 'widgets/novel_portrait.dart';
part 'widgets/novel_story_reader.dart';
part 'widgets/novel_story_controls.dart';
part 'widgets/novel_input.dart';
part 'widgets/novel_feedback_overlays.dart';
part 'widgets/novel_choice_panel.dart';
part 'widgets/novel_widget_previews.dart';


/// Shared responsive metrics for the whole novel UI.
///
/// The important distinction is between a genuinely spacious desktop window and
/// a very wide-but-short phone landscape viewport. A modern iPhone in landscape
/// can be wider than 800 logical pixels while still being under 430 pixels tall;
/// width-only breakpoints therefore misclassify it as desktop.
class NovelViewportMetrics {
  const NovelViewportMetrics._({
    required this.size,
    required this.desktopMode,
  });

  factory NovelViewportMetrics.of(
    BuildContext context, {
    bool desktopMode = false,
  }) {
    return NovelViewportMetrics.fromMediaQuery(
      MediaQuery.of(context),
      desktopMode: desktopMode,
    );
  }

  factory NovelViewportMetrics.fromMediaQuery(
    MediaQueryData media, {
    bool desktopMode = false,
  }) {
    return NovelViewportMetrics._(
      size: media.size,
      desktopMode: desktopMode,
    );
  }

  final Size size;
  final bool desktopMode;

  bool get isLandscape => size.width > size.height;
  bool get narrowWidth => size.width <= 600;
  bool get phoneWidth => size.width <= 430;
  bool get shortViewport => size.height < 520;
  bool get ultraShortViewport => size.height < 400;

  /// Phones in landscape (and similarly short browser windows) need a dedicated
  /// composition instead of the full desktop camera language.
  bool get shortWide => isLandscape && shortViewport;

  /// Compact chrome is used for HUD/nav/input controls. Content width can remain
  /// generous in landscape while the vertical chrome becomes denser.
  bool get compactChrome => phoneWidth || shortViewport;
  bool get compactContent => narrowWidth || shortViewport;

  /// Full desktop dialogue/portrait composition is only enabled when there is
  /// enough vertical room. This keeps PC behavior intact while preventing a
  /// landscape iPhone from inheriting desktop-sized portraits and text panels.
  bool get useDesktopDialogue =>
      desktopMode && !shortWide && size.width >= 700 && size.height >= 520;

  double get topHudHeight => shortWide ? 56.0 : (compactChrome ? 64.0 : 72.0);
  double get topContentReserve =>
      shortWide ? 58.0 : (compactChrome ? 74.0 : 86.0);
}

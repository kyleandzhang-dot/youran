import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'novel_asr_stream_service.dart';
import 'novel_game_controller.dart';
import 'novel_socket_service.dart';
import 'novel_models.dart';

import '../../app_shared.dart';

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

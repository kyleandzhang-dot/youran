import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import '../../app_shared.dart';
import '../../services/depth_parallax_preview.dart';
import 'novel_backend.dart';
import 'novel_game_controller.dart';
import 'novel_display_mode.dart';
import 'novel_models.dart';
import 'novel_widgets.dart';

// ============================================================================
// Novel Sheets 总入口
//
// 这里只负责：
//   1. 统一 import；
//   2. 声明各页面 part；
//   3. 不再堆放具体页面实现。
//
// 查页面时直接进入对应子文件；每个子文件顶部都标注了“页面入口 / 对外入口”。
// ============================================================================

part 'sheets/novel_sheet_common.dart';
part 'sheets/novel_choices.dart';
part 'sheets/novel_scene_map.dart';
part 'sheets/novel_inventory.dart';
part 'sheets/novel_store.dart';
part 'sheets/novel_character.dart';
part 'sheets/novel_characters.dart';
part 'sheets/novel_host_profile.dart';
part 'sheets/novel_journey.dart';
part 'sheets/novel_surroundings.dart';
part 'sheets/novel_settings.dart';
part 'sheets/novel_developer_tools.dart';
part 'sheets/novel_story_dialogs.dart';

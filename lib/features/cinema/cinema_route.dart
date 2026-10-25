import 'package:flutter/material.dart';

import 'cinema_editor_page.dart';
import 'cinema_player_page.dart';

/// 作品默认进入独立放映页，编辑使用单独的 /edit 路由。
Route<dynamic>? cinemaRoute(RouteSettings settings) {
  final uri = Uri.tryParse(settings.name ?? '');
  final segments = uri?.pathSegments ?? const <String>[];
  if (segments.length < 2 ||
      segments.length > 3 ||
      segments.first != 'cinema') {
    return null;
  }
  final workId = int.tryParse(segments[1]);
  if (workId == null || workId <= 0) return null;
  final action = segments.length == 3 ? segments[2] : 'play';
  if (action == 'edit') {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => CinemaEditorPage(workId: workId),
    );
  }
  if (action != 'play') return null;
  final chapterId = int.tryParse(uri?.queryParameters['chapter_id'] ?? '');
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => CinemaPlayerPage(
      workId: workId,
      chapterId: chapterId != null && chapterId > 0 ? chapterId : null,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youran_ai/features/cinema/cinema_editor_page.dart';
import 'package:youran_ai/features/cinema/cinema_player_page.dart';
import 'package:youran_ai/features/cinema/cinema_route.dart';

void main() {
  testWidgets('作品入口与旧放映链接都能在没有章节参数时进入放映页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));

    for (final name in ['/cinema/12', '/cinema/12/play']) {
      final settings = RouteSettings(name: name);
      final route = cinemaRoute(settings) as MaterialPageRoute<void>;
      final page = route.builder(context) as CinemaPlayerPage;
      expect(route.settings, same(settings));
      expect(page.workId, 12);
      expect(page.chapterId, isNull);
    }
  });

  testWidgets('放映链接保留指定章节，编辑链接进入独立编辑页', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final play =
        cinemaRoute(const RouteSettings(name: '/cinema/12/play?chapter_id=34'))
            as MaterialPageRoute<void>;
    expect((play.builder(context) as CinemaPlayerPage).chapterId, 34);

    final edit =
        cinemaRoute(const RouteSettings(name: '/cinema/12/edit'))
            as MaterialPageRoute<void>;
    expect((edit.builder(context) as CinemaEditorPage).workId, 12);
  });

  test('无效作品和其他模式的路由不进入电影页', () {
    for (final name in [
      '/novel/12',
      '/cinema',
      '/cinema/invalid',
      '/cinema/0',
      '/cinema/-1/play',
      '/cinema/12/unknown',
      '/cinema/12/play/extra',
    ]) {
      expect(cinemaRoute(RouteSettings(name: name)), isNull, reason: name);
    }
  });
}

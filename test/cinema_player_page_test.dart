import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youran_ai/features/cinema/cinema_api.dart';
import 'package:youran_ai/features/cinema/cinema_playback_controller.dart';
import 'package:youran_ai/features/cinema/cinema_player_page.dart';

class _Audio extends CinemaAudio {
  final completion = StreamController<void>.broadcast(sync: true);
  bool disposed = false;
  final urls = <String>[];
  @override
  Stream<void> get completed => completion.stream;
  @override
  Future<void> setUrl(String url) async {
    urls.add(url);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await completion.close();
  }
}

class _Api extends CinemaApi {
  _Api({
    this.withImage = false,
    this.pendingImages = false,
    this.savedProgress = const {},
  });
  final bool withImage;
  final bool pendingImages;
  final Map<String, dynamic> savedProgress;
  bool imagesReady = false;
  final prepared = <int>[];
  final saved = <Map<String, dynamic>>[];
  final requested = <int>[];
  @override
  Future<Map<String, dynamic>> getWork(int id) async => {
    'work': {'id': id, 'title': '测试电影'},
    'chapters': [
      {'id': 1, 'title': '第一章', 'sort_order': 1},
      {'id': 2, 'title': '第二章', 'sort_order': 2},
    ],
  };
  @override
  Future<Map<String, dynamic>> prepareAssets(
    int id, {
    Map<String, dynamic>? voice,
    Map<String, dynamic>? image,
    int? itemIndex,
  }) async {
    prepared.add(id);
    return {};
  }

  @override
  Future<Map<String, dynamic>> progress(int workId) async => savedProgress;
  @override
  Future<Map<String, dynamic>> saveProgress(
    int workId, {
    int? chapterId,
    int itemIndex = 0,
    double positionSeconds = 0,
  }) async {
    saved.add({'chapter_id': chapterId, 'item_index': itemIndex});
    return {};
  }

  @override
  Future<Map<String, dynamic>> playback(int id, {int? itemIndex}) async {
    requested.add(id);
    return {
      'items': List.generate(
        3,
        (index) => {
          'id': id * 10 + index,
          'item_index': index,
          'shot_id': index,
          'text': List.filled(10, '第$id章第${index + 1}句长台词。').join(),
          'speaker': '旁白',
          'assets': [
            {'asset_type': 'audio', 'url': '$id-$index.mp3', 'status': 'ready'},
            if (withImage || imagesReady)
              {
                'asset_type': 'image',
                'url': 'https://example.invalid/shot.png',
                'status': 'ready',
              },
            if (pendingImages && !imagesReady && !withImage)
              {'asset_type': 'image', 'status': 'processing'},
          ],
        },
      ),
    };
  }
}

void main() {
  testWidgets('画面生成后轮询更新显示，当前 TTS 不重新加载', (tester) async {
    final api = _Api(pendingImages: true);
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await tester.pumpWidget(
      MaterialApp(
        home: CinemaPlayerPage(workId: 12, api: api, playback: player),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在准备画面…'), findsOneWidget);
    expect(api.prepared, [1]);
    expect(player.isPlaying, isTrue);
    final urls = List<String>.of(audio.urls);
    api.imagesReady = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(player.imageUrl, 'https://example.invalid/shot.png');
    expect(player.index, 0);
    expect(player.isPlaying, isTrue);
    expect(audio.urls, urls);
    expect(
      api.saved.any((row) => row['chapter_id'] == 1 && row['item_index'] == 0),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('重新进入作品恢复上次章节和句子，不先播放首句', (tester) async {
    final api = _Api(savedProgress: {'chapter_id': 2, 'item_index': 1});
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await tester.pumpWidget(
      MaterialApp(
        home: CinemaPlayerPage(workId: 12, api: api, playback: player),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.index, 1);
    expect(audio.urls, ['2-1.mp3']);
    expect(api.prepared, [2]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('语音生成期间显示字幕和等待状态，暂停后生成完成不会抢播', (tester) async {
    final ready = Completer<String>();
    final player = CinemaPlaybackController(
      audio: _Audio(),
      resolveAudio: (_) => ready.future,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CinemaPlayerPage(workId: 12, api: _Api(), playback: player),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在准备语音…'), findsOneWidget);
    expect(find.byKey(const ValueKey('cinema-subtitles')), findsOneWidget);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
    ready.complete('ready.mp3');
    await tester.pumpAndSettle();
    expect(player.isPlaying, isFalse);
    expect(find.byTooltip('播放').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('播放器可暂停跳句，章节列表使用序号和绿色文字标识当前章', (tester) async {
    final api = _Api();
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CinemaPlayerPage(workId: 12, api: api, playback: player),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一章'), findsOneWidget);
    expect(find.byTooltip('退出放映'), findsNothing);
    expect(player.isPlaying, isTrue);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    expect(player.isPlaying, isFalse);
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();
    expect(player.isPlaying, isTrue);
    await tester.tap(find.byTooltip('下一句'));
    await tester.pumpAndSettle();
    expect(player.index, 1);
    await tester.tap(find.byTooltip('上一句'));
    await tester.pumpAndSettle();
    expect(player.index, 0);

    await tester.tap(find.byTooltip('选择章节'));
    await tester.pumpAndSettle();
    expect(player.isPlaying, isFalse);
    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('01')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('02')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(find.text('当前章节'), findsNothing);
    final currentTitle = tester.widget<Text>(
      find.descendant(of: sheet, matching: find.text('第一章')),
    );
    final otherTitle = tester.widget<Text>(
      find.descendant(of: sheet, matching: find.text('第二章')),
    );
    expect(currentTitle.style?.color, const Color(0xFF76B900));
    expect(otherTitle.style?.color, Colors.white70);
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();
    expect(api.requested.toSet(), {1, 2});
    expect(find.text('第二章'), findsOneWidget);
    expect(player.isPlaying, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(find.byType(CinemaPlayerPage), findsNothing);
    expect(audio.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏长台词和章末控制栏不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CinemaPlayerPage(workId: 12, api: _Api(), playback: player),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
    await player.select(2, autoPlay: true);
    audio.completion.add(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('本章结束'), findsOneWidget);
    expect(find.text('播放下一章').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('画面铺满屏幕，字幕叠加，播放控件自动收起并可点击唤回', (tester) async {
    final player = CinemaPlaybackController(audio: _Audio());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CinemaPlayerPage(
          workId: 12,
          api: _Api(withImage: true),
          playback: player,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stage = find.byKey(const ValueKey('cinema-stage'));
    final subtitles = find.byKey(const ValueKey('cinema-subtitles'));
    final stageRect = tester.getRect(stage);
    expect(stageRect, const Rect.fromLTWH(0, 0, 800, 600));
    expect(find.byType(AppBar), findsNothing);
    final background = tester.widget<Image>(
      find.descendant(of: stage, matching: find.byType(Image)),
    );
    expect(background.fit, BoxFit.cover);
    final visibleSubtitles = tester.getRect(subtitles);
    expect(stageRect.contains(visibleSubtitles.topLeft), isTrue);
    expect(stageRect.contains(visibleSubtitles.bottomRight), isTrue);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byTooltip('暂停').hitTestable(), findsNothing);
    expect(find.byTooltip('退出放映').hitTestable(), findsNothing);
    expect(subtitles, findsOneWidget);
    expect(tester.getRect(subtitles).top, greaterThan(visibleSubtitles.top));
    expect(tester.getRect(stage), stageRect);

    await tester.tapAt(const Offset(400, 150));
    await tester.pumpAndSettle();
    expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('播放').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('手机默认隐藏系统栏，支持切换全屏，离开页面后恢复', (tester) async {
    final calls = <MethodCall>[];
    final displayCalls = <MethodCall>[];
    const displayChannel = MethodChannel('youran/cinema_display');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      displayChannel,
      (call) async {
        displayCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        displayChannel,
        null,
      ),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final player = CinemaPlaybackController(audio: _Audio());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CinemaPlayerPage(workId: 12, api: _Api(), playback: player),
      ),
    );
    await tester.pumpAndSettle();
    expect(displayCalls.last.arguments, {'enabled': true});
    expect(
      calls.any(
        (call) =>
            call.method == 'SystemChrome.setEnabledSystemUIMode' &&
            call.arguments.toString().contains('immersiveSticky'),
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(displayCalls.last.arguments, {'enabled': false});
    expect(
      calls
          .lastWhere(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
          )
          .arguments
          .toString(),
      contains('edgeToEdge'),
    );
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(displayCalls.last.arguments, {'enabled': true});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(displayCalls.last.arguments, {'enabled': false});
    expect(
      calls
          .lastWhere(
            (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
          )
          .arguments
          .toString(),
      contains('edgeToEdge'),
    );
  });

  testWidgets('竖屏安全区只约束字幕和控件，背景仍铺满屏幕', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final player = CinemaPlaybackController(audio: _Audio());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: const EdgeInsets.only(top: 32, bottom: 24)),
          child: child!,
        ),
        home: CinemaPlayerPage(workId: 12, api: _Api(), playback: player),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('cinema-stage'))),
      const Rect.fromLTWH(0, 0, 360, 780),
    );
    expect(find.byTooltip('暂停').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('cinema-subtitles'))).bottom,
      lessThan(756),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

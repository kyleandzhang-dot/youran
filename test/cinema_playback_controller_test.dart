import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:youran_ai/features/cinema/cinema_playback_controller.dart';

class _Audio extends CinemaAudio {
  final completion = StreamController<void>.broadcast(sync: true);
  final urls = <String>[];
  int plays = 0;
  int pauses = 0;
  int stops = 0;
  bool fail = false;
  bool disposed = false;
  Completer<void>? loading;

  @override
  Stream<void> get completed => completion.stream;
  @override
  Future<void> setUrl(String url) async {
    urls.add(url);
    if (loading != null) await loading!.future;
    if (fail) throw StateError('audio unavailable');
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await completion.close();
  }
}

class _QueueAudio extends _Audio implements CinemaAudioPreloader {
  final started = StreamController<int>.broadcast(sync: true);
  final preloaded = <int>[];
  final preloadUrls = <String>[];
  Completer<void>? preloadGate;

  @override
  Stream<int> get currentItem => started.stream;
  @override
  Future<void> setItem(int itemIndex, String url) => setUrl(url);
  @override
  Future<void> preloadItem(int itemIndex, String url) async {
    if (preloaded.contains(itemIndex)) return;
    preloaded.add(itemIndex);
    preloadUrls.add(url);
    await preloadGate?.future;
  }

  @override
  Future<void> dispose() async {
    await started.close();
    await super.dispose();
  }
}

Map<String, dynamic> _line(
  String text, {
  String? audio,
  int shot = 0,
  String? image,
  int? id,
}) => {
  if (id != null) 'id': id,
  'text': text,
  'shot_id': shot,
  'assets': [
    if (audio != null) {'asset_type': 'audio', 'status': 'ready', 'url': audio},
    if (image != null) {'asset_type': 'image', 'status': 'ready', 'url': image},
  ],
};

void main() {
  test('同一镜头多句共享运镜设定和时长，换句不改变镜头标识', () async {
    final player = CinemaPlaybackController(audio: _Audio());
    await player.setItems([
      {
        ..._line('第一句', audio: 'a.mp3', id: 1),
        'metadata': {
          'camera_move': 'slow_zoom_out',
          'shot_duration_seconds': 12,
        },
      },
      _line('第二句', audio: 'b.mp3', id: 2),
      {
        ..._line('下个镜头', shot: 1, audio: 'c.mp3', id: 3),
        'metadata': {'camera_move': 'pan_left'},
      },
    ], autoPlay: false);
    final identity = player.shotIdentity;
    expect(player.cameraMove, 'slow_zoom_out');
    expect(player.shotMotionDuration, const Duration(seconds: 12));
    await player.select(1);
    expect(player.shotIdentity, identity);
    expect(player.cameraMove, 'slow_zoom_out');
    expect(player.shotMotionDuration, const Duration(seconds: 12));
    await player.select(2);
    expect(player.shotIdentity, isNot(identity));
    expect(player.cameraMove, 'pan_left');
    player.dispose();
  });

  test('换章初始化期间的暂停优先于自动播放', () async {
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    final loading = player.setItems([_line('甲', audio: 'a.mp3')]);
    final paused = player.pause();
    await loading;
    await paused;
    expect(player.isPlaying, isFalse);
    expect(audio.plays, 0);
    player.dispose();
  });

  test('暂停后继续使用同一条语音，不重新加载或切换台词', () async {
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', audio: 'a.mp3'),
      _line('乙', audio: 'b.mp3'),
    ]);
    expect(player.isPlaying, isTrue);
    expect(audio.plays, 1);
    await player.pause();
    expect(player.isPlaying, isFalse);
    expect(audio.pauses, 1);
    await player.resume();
    expect(player.isPlaying, isTrue);
    expect(player.index, 0);
    expect(audio.urls, ['a.mp3']);
    expect(audio.plays, 2);
    player.dispose();
  });

  testWidgets('没有语音时停在当前段，不按文字时长自动换段', (tester) async {
    final player = CinemaPlaybackController(audio: _Audio());
    await player.setItems([_line('甲'), _line('乙')]);
    await tester.pump(const Duration(seconds: 30));
    expect(player.index, 0);
    expect(player.isPlaying, isFalse);
    expect(player.notice, contains('语音准备失败'));
    await player.resume();
    await tester.pump(const Duration(seconds: 30));
    expect(player.index, 0);
    expect(player.hasEnded, isFalse);
    player.dispose();
  });

  testWidgets('语音结束自动换句，章末停止，播放按钮可重播', (tester) async {
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', audio: 'a.mp3'),
      _line('乙', audio: 'b.mp3'),
    ]);
    audio.completion.add(null);
    await tester.pump();
    expect(player.index, 1);
    expect(audio.urls, ['a.mp3', 'b.mp3']);
    audio.completion.add(null);
    await tester.pump();
    expect(player.isPlaying, isFalse);
    expect(player.hasEnded, isTrue);
    await player.toggle();
    expect(player.index, 0);
    expect(player.isPlaying, isTrue);
    player.dispose();
  });

  testWidgets('暂停时跳句保持暂停，换章替换当前段落', (tester) async {
    final player = CinemaPlaybackController(audio: _Audio());
    await player.setItems([_line('甲'), _line('乙'), _line('丙')]);
    await player.pause();
    await player.select(2);
    await tester.pump(const Duration(seconds: 5));
    expect(player.index, 2);
    expect(player.isPlaying, isFalse);
    await player.setItems([_line('新章节')], autoPlay: false);
    await tester.pump(const Duration(seconds: 5));
    expect(player.index, 0);
    expect(player.current['text'], '新章节');
    expect(player.hasEnded, isFalse);
    player.dispose();
  });

  testWidgets('语音失败停在当前段，播放按钮重试，不把其他资源当语音', (tester) async {
    final audio = _Audio()..fail = true;
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([_line('甲', audio: 'bad.mp3'), _line('乙')]);
    expect(player.hasAudio, isFalse);
    expect(player.notice, contains('语音准备失败'));
    await tester.pump(const Duration(seconds: 30));
    expect(player.index, 0);
    expect(player.isPlaying, isFalse);
    audio.fail = false;
    await player.resume();
    expect(player.index, 0);
    expect(player.isPlaying, isTrue);
    expect(
      CinemaPlaybackController.assetUrl({
        'assets': [
          {'asset_type': 'audio', 'url': 'ready.mp3', 'status': 'ready'},
          {'asset_type': 'audio', 'url': 'failed.mp3', 'status': 'failed'},
          {'asset_type': 'video', 'url': 'video.mp4'},
        ],
      }, 'audio'),
      'ready.mp3',
    );
    player.dispose();
  });

  test('同一镜头延续首句画面，下一镜头未就绪时暂时保留旧图', () async {
    final player = CinemaPlaybackController(audio: _Audio());
    await player.setItems([
      _line('甲', image: 'shot.png'),
      _line('乙'),
      _line('丙', shot: 1),
    ], autoPlay: false);
    await player.select(1);
    expect(player.imageUrl, 'shot.png');
    await player.select(2);
    expect(player.currentImageUrl, isEmpty);
    expect(player.imageUrl, 'shot.png');
    player.dispose();
  });

  test('图片状态刷新保持当前音频和字幕位置，更新后直接显示新图', () async {
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', id: 1, audio: 'a.mp3', image: 'old.png'),
      _line('乙', id: 2, shot: 1, audio: 'b.mp3'),
    ]);
    await player.select(1);
    final stops = audio.stops;
    final plays = audio.plays;
    final urls = List<String>.of(audio.urls);
    player.updateAssets([
      _line('服务端不同文字不会覆盖当前字幕', id: 2, shot: 1, image: 'new.png'),
      _line('其他章节', id: 999, image: 'foreign.png'),
    ]);
    expect(player.index, 1);
    expect(player.current['text'], '乙');
    expect(player.imageUrl, 'new.png');
    expect(player.isPlaying, isTrue);
    expect(audio.stops, stops);
    expect(audio.plays, plays);
    expect(audio.urls, urls);
    await player.pause();
    player.updateAssets([_line('乙', id: 2, shot: 1, image: 'updated.png')]);
    expect(player.isPlaying, isFalse);
    await player.setItems([
      _line('新章', id: 3, audio: 'c.mp3'),
    ], autoPlay: false);
    expect(player.imageUrl, isEmpty);
    player.dispose();
  });

  test('断点初始化直接加载指定句，图片预热按当前加后五个镜头计数', () async {
    final audio = _Audio();
    final player = CinemaPlaybackController(audio: audio);
    final items = <Map<String, dynamic>>[];
    for (var shot = 0; shot < 9; shot++) {
      items.add(
        _line(
          '镜头 $shot 第一句',
          shot: shot,
          audio: '$shot-a.mp3',
          image: '$shot.png',
        ),
      );
      items.add(_line('镜头 $shot 第二句', shot: shot, audio: '$shot-b.mp3'));
    }
    await player.setItems(items, initialIndex: 3, autoPlay: false);
    expect(player.index, 3);
    expect(audio.urls, ['1-b.mp3']);
    expect(player.imageUrlsAhead(), [
      '1.png',
      '2.png',
      '3.png',
      '4.png',
      '5.png',
      '6.png',
    ]);
    player.dispose();
  });

  testWidgets('加载语音期间暂停或退出不会在加载完成后自动播放', (tester) async {
    final audio = _Audio()..loading = Completer<void>();
    final player = CinemaPlaybackController(audio: audio);
    final loading = player.setItems([_line('甲', audio: 'a.mp3')]);
    await tester.pump();
    final paused = player.pause();
    audio.loading!.complete();
    await loading;
    await paused;
    expect(player.isPlaying, isFalse);
    expect(audio.plays, 0);
    final selection = player.select(0, autoPlay: true);
    final stopping = player.stop();
    await selection;
    await stopping;
    expect(player.isPlaying, isFalse);
    expect(audio.plays, 0);
    player.dispose();
    await tester.pump();
    expect(audio.disposed, isTrue);
  });

  testWidgets('播放时提前请求下一段，当前语音读完才切换字幕', (tester) async {
    final ready = Completer<String>();
    final audio = _Audio();
    final requested = <int>[];
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) {
        requested.add(item['id'] as int);
        return item['id'] == 1 ? ready.future : Future.value('second.mp3');
      },
    );
    final loading = player.setItems([_line('第一段', id: 1), _line('第二段', id: 2)]);
    await tester.pump();
    expect(player.isPreparing, isTrue);
    await tester.pump(const Duration(seconds: 30));
    expect(requested, [1]);
    expect(player.index, 0);
    ready.complete('first.mp3');
    await loading;
    await tester.pump();
    expect(requested, [1, 2]);
    await tester.pump(const Duration(seconds: 30));
    expect(player.index, 0);
    expect(audio.urls, ['first.mp3']);
    audio.completion.add(null);
    await tester.pump();
    expect(player.index, 1);
    expect(requested, [1, 2]);
    expect(audio.urls, ['first.mp3', 'second.mp3']);
    player.dispose();
  });

  testWidgets('等待后端时可立即暂停和跳段，过期结果不会抢播', (tester) async {
    final ready = Completer<String>();
    final audio = _Audio();
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) =>
          item['id'] == 1 ? ready.future : Future.value('second.mp3'),
    );
    final loading = player.setItems([_line('第一段', id: 1), _line('第二段', id: 2)]);
    await tester.pump();
    await player.pause();
    expect(player.isPlaying, isFalse);
    await player.select(1, autoPlay: true);
    ready.complete('old.mp3');
    await loading;
    expect(player.index, 1);
    expect(audio.urls, ['second.mp3']);
    expect(player.isPlaying, isTrue);
    player.dispose();
  });

  test('以后台返回的语音为准，暂停继续不重新请求合成', () async {
    final audio = _Audio();
    var requests = 0;
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) async {
        requests++;
        expect(item['id'], 1);
        return 'server-current-voice.mp3';
      },
    );
    await player.setItems([_line('第一段', id: 1, audio: 'old-voice.mp3')]);
    await player.pause();
    await player.resume();
    expect(audio.urls, ['server-current-voice.mp3']);
    expect(requests, 1);
    player.dispose();
  });

  testWidgets('只预加载下一句，队列实际接播时同步字幕且不重置播放器', (tester) async {
    final audio = _QueueAudio();
    final requested = <int>[];
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) async {
        requested.add(item['id'] as int);
        return '${item['id']}.mp3';
      },
    );
    await player.setItems([
      _line('第一句', id: 1),
      _line('第二句', id: 2),
      _line('第三句', id: 3),
    ]);
    await tester.pump();
    expect(player.index, 0);
    expect(requested, [1, 2]);
    expect(audio.preloaded, [1]);
    expect(audio.urls, ['1.mp3']);
    final stops = audio.stops;
    audio.started.add(1);
    await tester.pump();
    expect(player.current['text'], '第二句');
    expect(requested, [1, 2, 3]);
    expect(audio.preloaded, [1, 2]);
    expect(audio.stops, stops);
    expect(audio.urls, ['1.mp3']);
    expect(audio.plays, 1);
    audio.started.add(2);
    await tester.pump();
    audio.completion.add(null);
    await tester.pump();
    expect(player.hasEnded, isTrue);
    player.dispose();
  });

  testWidgets('等待下一句缓冲时仍可立即暂停和继续', (tester) async {
    final audio = _QueueAudio()..preloadGate = Completer<void>();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', audio: 'a.mp3'),
      _line('乙', audio: 'b.mp3'),
    ]);
    await tester.pump();
    expect(audio.preloaded, [1]);
    await player.pause();
    expect(audio.pauses, 1);
    expect(player.isPlaying, isFalse);
    await player.resume();
    expect(player.isPlaying, isTrue);
    expect(audio.plays, 2);
    audio.preloadGate!.complete();
    await tester.pump();
    player.dispose();
  });

  testWidgets('换章后旧的下一句请求不能加入新播放队列', (tester) async {
    final oldNext = Completer<String>();
    final audio = _QueueAudio();
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) =>
          item['id'] == 2 ? oldNext.future : Future.value('${item['id']}.mp3'),
    );
    await player.setItems([_line('旧第一句', id: 1), _line('旧第二句', id: 2)]);
    await tester.pump();
    await player.setItems([_line('新章节', id: 3)]);
    oldNext.complete('old-next.mp3');
    await tester.pump();
    expect(player.current['text'], '新章节');
    expect(audio.urls, ['1.mp3', '3.mp3']);
    expect(audio.preloadUrls, isEmpty);
    player.dispose();
  });

  testWidgets('下一句提前请求失败不影响当前句，真正读到时重试', (tester) async {
    final audio = _Audio();
    var secondRequests = 0;
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) async {
        if (item['id'] == 2 && ++secondRequests == 1) {
          throw StateError('temporary failure');
        }
        return '${item['id']}.mp3';
      },
    );
    await player.setItems([_line('甲', id: 1), _line('乙', id: 2)]);
    await tester.pump();
    expect(secondRequests, 1);
    expect(player.index, 0);
    expect(player.isPlaying, isTrue);
    expect(player.notice, isEmpty);
    audio.completion.add(null);
    await tester.pump();
    expect(secondRequests, 2);
    expect(player.index, 1);
    expect(audio.urls, ['1.mp3', '2.mp3']);
    player.dispose();
  });

  testWidgets('读完时下一句仍在请求中，复用同一个请求等待而不重复合成', (tester) async {
    final audio = _Audio();
    final next = Completer<String>();
    var secondRequests = 0;
    final player = CinemaPlaybackController(
      audio: audio,
      resolveAudio: (item) {
        if (item['id'] == 2) {
          secondRequests++;
          return next.future;
        }
        return Future.value('1.mp3');
      },
    );
    await player.setItems([_line('甲', id: 1), _line('乙', id: 2)]);
    await tester.pump();
    audio.completion.add(null);
    await tester.pump();
    expect(secondRequests, 1);
    expect(player.index, 1);
    expect(player.isPreparing, isTrue);
    next.complete('2.mp3');
    await tester.pump();
    expect(audio.urls, ['1.mp3', '2.mp3']);
    expect(secondRequests, 1);
    player.dispose();
  });

  testWidgets('队尾完成和预加载接播同时发生时不重复播放或跳过下一句', (tester) async {
    final audio = _QueueAudio()..preloadGate = Completer<void>();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', audio: 'a.mp3'),
      _line('乙', audio: 'b.mp3'),
    ]);
    await tester.pump();
    audio.completion.add(null);
    audio.started.add(1);
    audio.preloadGate!.complete();
    await tester.pump();
    expect(player.index, 1);
    expect(player.isPlaying, isTrue);
    expect(player.hasEnded, isFalse);
    expect(audio.urls, ['a.mp3']);
    expect(audio.plays, 1);
    audio.completion.add(null);
    await tester.pump();
    expect(player.hasEnded, isTrue);
    player.dispose();
  });

  testWidgets('退出可立即释放播放器，不等待下一句缓冲', (tester) async {
    final audio = _QueueAudio()..preloadGate = Completer<void>();
    final player = CinemaPlaybackController(audio: audio);
    await player.setItems([
      _line('甲', audio: 'a.mp3'),
      _line('乙', audio: 'b.mp3'),
    ]);
    await tester.pump();
    player.dispose();
    await tester.pump();
    expect(audio.disposed, isTrue);
    audio.preloadGate!.complete();
    await tester.pump();
  });
}

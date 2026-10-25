import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youran_ai/features/cinema/cinema_shot_stage.dart';

final _provider = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwaDjwHwAFBAKAPJ4DgAAAAABJRU5ErkJggg==',
  ),
);

Widget _stage({
  Object shot = 1,
  bool playing = true,
  bool currentImage = true,
  String url = 'one',
  String move = 'slow_zoom_in',
  bool reduce = false,
  ImageProvider? provider,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: SizedBox.expand(
        child: CinemaShotStage(
          shotId: shot,
          imageUrl: url,
          cameraMove: move,
          duration: const Duration(seconds: 10),
          playing: playing,
          hasCurrentImage: currentImage,
          imageProvider: provider ?? _provider,
        ),
      ),
    ),
  );
}

class _DeferredImage extends ImageProvider<_DeferredImage> {
  final ready = Completer<ImageInfo>();
  late final _completer = OneFrameImageStreamCompleter(ready.future);

  @override
  Future<_DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _DeferredImage key,
    ImageErrorListener handleError,
  ) {
    stream.setCompleter(
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => _completer,
        onError: handleError,
      )!,
    );
  }
}

double _scale(WidgetTester tester) => tester
    .widget<Transform>(
      find.byKey(const ValueKey('cinema-camera-transform')).last,
    )
    .transform
    .storage[0];

Future<void> _ready(WidgetTester tester) async {
  await tester.runAsync(
    () =>
        precacheImage(_provider, tester.element(find.byType(CinemaShotStage))),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('新图片下载期间保留旧画面，迟到图片不会覆盖跳转后的镜头', (tester) async {
    await tester.pumpWidget(_stage());
    await _ready(tester);
    await tester.pump(const Duration(seconds: 2));
    final previous = _scale(tester);
    final delayed = _DeferredImage();
    await tester.pumpWidget(_stage(shot: 2, url: 'two', provider: delayed));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey<(Object, String)>((1, 'one'))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<(Object, String)>((2, 'two'))),
      findsNothing,
    );
    expect(_scale(tester), closeTo(previous, .0001));
    await tester.pumpWidget(_stage(shot: 3, url: 'three'));
    await _ready(tester);
    await tester.pump(const Duration(milliseconds: 350));
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(_provider.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    delayed.ready.complete(ImageInfo(image: image!));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.byKey(const ValueKey<(Object, String)>((3, 'three'))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<(Object, String)>((2, 'two'))),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('推近、拉远和上下左右方向正确，画面变换不会露出边缘', () {
    const size = Size(1440, 720);
    expect(CinemaCameraMotion.sample('slow_zoom_in', 0, size).scale, 1);
    expect(
      CinemaCameraMotion.sample('slow_zoom_in', 1, size).scale,
      closeTo(1.10, .0001),
    );
    expect(
      CinemaCameraMotion.sample('slow_zoom_out', 0, size).scale,
      closeTo(1.12, .0001),
    );
    expect(
      CinemaCameraMotion.sample('slow_zoom_out', 1, size).scale,
      closeTo(1, .0001),
    );
    expect(
      CinemaCameraMotion.sample('pan_left', 1, size).offset.dx,
      greaterThan(0),
    );
    expect(
      CinemaCameraMotion.sample('pan_right', 1, size).offset.dx,
      lessThan(0),
    );
    expect(
      CinemaCameraMotion.sample('tilt_up', 1, size).offset.dy,
      greaterThan(0),
    );
    expect(
      CinemaCameraMotion.sample('tilt_down', 1, size).offset.dy,
      lessThan(0),
    );
    for (final viewport in [size, const Size(720, 1440)]) {
      for (final move in CinemaCameraMotion.labels.keys) {
        for (final p in [0.0, .02, .1, .25, .5, .75, 1.0]) {
          final pose = CinemaCameraMotion.sample(move, p, viewport);
          expect(pose.scale, greaterThanOrEqualTo(1));
          expect(
            pose.offset.dx.abs(),
            lessThanOrEqualTo((pose.scale - 1) * viewport.width / 2 + .0001),
          );
          expect(
            pose.offset.dy.abs(),
            lessThanOrEqualTo((pose.scale - 1) * viewport.height / 2 + .0001),
          );
        }
      }
    }
  });

  testWidgets('暂停冻结画面，恢复和同镜头刷新继续原来的运镜', (tester) async {
    await tester.pumpWidget(_stage());
    await _ready(tester);
    await tester.pump(const Duration(seconds: 3));
    final moving = _scale(tester);
    expect(moving, greaterThan(1));
    await tester.pumpWidget(_stage());
    expect(_scale(tester), closeTo(moving, .0001));
    await tester.pumpWidget(_stage(playing: false));
    await tester.pump(const Duration(seconds: 3));
    expect(_scale(tester), closeTo(moving, .0001));
    await tester.pumpWidget(_stage(playing: true));
    await tester.pump(const Duration(seconds: 2));
    expect(_scale(tester), greaterThan(moving));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新镜头图片等待时冻结旧画面，新图到达后开启新运镜', (tester) async {
    await tester.pumpWidget(_stage());
    await _ready(tester);
    await tester.pump(const Duration(seconds: 3));
    final previous = _scale(tester);
    await tester.pumpWidget(
      _stage(shot: 2, currentImage: false, move: 'slow_zoom_out'),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(_scale(tester), closeTo(previous, .0001));
    await tester.pumpWidget(_stage(shot: 2, url: 'two', move: 'slow_zoom_out'));
    await _ready(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(_scale(tester), greaterThan(1.10));
    final first = _scale(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_scale(tester), lessThan(first));
    expect(find.byType(ClipRect), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('减少动态效果设置使用静止画面', (tester) async {
    await tester.pumpWidget(_stage(reduce: true, move: 'shake'));
    await _ready(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_scale(tester), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

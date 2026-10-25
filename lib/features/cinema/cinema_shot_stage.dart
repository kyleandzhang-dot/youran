import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../novel/novel_image_provider.dart';

/// Camera motion is applied to a cached image on-device; it does not submit image jobs.
class CinemaCameraMotion {
  static const labels = <String, String>{
    'static': '静止',
    'slow_zoom_in': '缓慢推近 · 小到大',
    'slow_zoom_out': '缓慢拉远 · 大到小',
    'pan_left': '镜头向左',
    'pan_right': '镜头向右',
    'tilt_up': '镜头向上',
    'tilt_down': '镜头向下',
    'fast_zoom_in': '快速推近',
    'shake': '短促震动',
  };

  static String normalize(Object? value) {
    final key = value?.toString().trim().toLowerCase() ?? '';
    const aliases = {
      'zoom_in': 'slow_zoom_in',
      'push_in': 'slow_zoom_in',
      'slow_push_in': 'slow_zoom_in',
      'dolly_in': 'slow_zoom_in',
      'zoom_out': 'slow_zoom_out',
      'pull_out': 'slow_zoom_out',
      'slow_pull_out': 'slow_zoom_out',
      'dolly_out': 'slow_zoom_out',
      'fast_push_in': 'fast_zoom_in',
    };
    final canonical = aliases[key] ?? key;
    return labels.containsKey(canonical) ? canonical : 'static';
  }

  static CinemaCameraPose sample(
    String move,
    double progress,
    Size size, {
    double durationSeconds = 8,
  }) {
    final p = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final eased = Curves.easeInOutCubic.transform(p);
    var scale = 1.0;
    var offset = Offset.zero;
    switch (normalize(move)) {
      case 'slow_zoom_in':
        scale = 1 + .10 * eased;
      case 'slow_zoom_out':
        scale = 1.12 - .12 * eased;
      case 'fast_zoom_in':
        final punch = Curves.easeOutCubic.transform(
          (p * durationSeconds / .7).clamp(0.0, 1.0),
        );
        scale = 1 + .16 * punch;
      case 'pan_left' || 'pan_right':
        scale = 1.14;
        final direction = normalize(move) == 'pan_left' ? 1 : -1;
        // Camera left means the image moves right. Overscan keeps every edge covered.
        offset = Offset(direction * (eased * 2 - 1) * size.width * .06, 0);
      case 'tilt_up' || 'tilt_down':
        scale = 1.14;
        final direction = normalize(move) == 'tilt_up' ? 1 : -1;
        offset = Offset(0, direction * (eased * 2 - 1) * size.height * .06);
      case 'shake':
        scale = 1.04;
        final seconds = p * durationSeconds;
        final decay = math
            .pow((1 - seconds / .8).clamp(0.0, 1.0), 2)
            .toDouble();
        offset = Offset(
          math.sin(seconds * math.pi * 16) * size.width * .005 * decay,
          math.sin(seconds * math.pi * 22) * size.height * .005 * decay,
        );
    }
    return CinemaCameraPose(scale, offset);
  }
}

class CinemaCameraPose {
  const CinemaCameraPose(this.scale, this.offset);
  final double scale;
  final Offset offset;
}

class _Shot {
  const _Shot(this.id, this.url, this.move, this.duration, this.provider);
  final Object id;
  final String url;
  final String move;
  final Duration duration;
  final ImageProvider? provider;
}

/// One continuous motion per shot. Pending new images keep the last frame paused.
class CinemaShotStage extends StatefulWidget {
  const CinemaShotStage({
    super.key,
    required this.shotId,
    required this.imageUrl,
    required this.cameraMove,
    required this.duration,
    required this.playing,
    this.hasCurrentImage = true,
    this.imageProvider,
  });
  final Object shotId;
  final String imageUrl;
  final String cameraMove;
  final Duration duration;
  final bool playing;
  final bool hasCurrentImage;
  final ImageProvider? imageProvider;

  @override
  State<CinemaShotStage> createState() => _CinemaShotStageState();
}

class _CinemaShotStageState extends State<CinemaShotStage> {
  late _Shot _shown;
  (Object, String)? _pending;
  int _imageEpoch = 0;

  _Shot _snapshot() => _Shot(
    widget.shotId,
    widget.imageUrl,
    CinemaCameraMotion.normalize(widget.cameraMove),
    widget.duration,
    widget.imageProvider,
  );

  @override
  void initState() {
    super.initState();
    _shown = _snapshot();
  }

  @override
  void didUpdateWidget(CinemaShotStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hasCurrentImage) {
      _imageEpoch++;
      _pending = null;
      return;
    }
    final next = _snapshot();
    if (next.url == _shown.url) {
      _imageEpoch++;
      _pending = null;
      _shown = next;
      return;
    }
    if (_pending == (next.id, next.url)) return;
    _pending = (next.id, next.url);
    final epoch = ++_imageEpoch;
    unawaited(_prepareNext(next, epoch));
  }

  Future<void> _prepareNext(_Shot next, int epoch) async {
    var failed = false;
    await precacheImage(
      next.provider ?? NovelImageProvider.network(next.url),
      context,
      onError: (error, stack) => failed = true,
    );
    if (!mounted || epoch != _imageEpoch) return;
    _pending = null;
    if (!failed) setState(() => _shown = _snapshot());
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: _CameraFrame(
          key: ValueKey((_shown.id, _shown.url)),
          shot: _shown,
          playing:
              widget.playing &&
              widget.hasCurrentImage &&
              _shown.id == widget.shotId &&
              _shown.url == widget.imageUrl,
        ),
      ),
    );
  }
}

class _CameraFrame extends StatefulWidget {
  const _CameraFrame({super.key, required this.shot, required this.playing});
  final _Shot shot;
  final bool playing;

  @override
  State<_CameraFrame> createState() => _CameraFrameState();
}

class _CameraFrameState extends State<_CameraFrame>
    with SingleTickerProviderStateMixin {
  Duration get _duration => switch (widget.shot.move) {
    'fast_zoom_in' => const Duration(milliseconds: 700),
    'shake' => const Duration(milliseconds: 900),
    _ => widget.shot.duration,
  };
  late final _motion = AnimationController(vsync: this, duration: _duration);
  bool _imageReady = false;
  bool _reduceMotion = false;

  void _sync() {
    if (_imageReady &&
        widget.playing &&
        !_reduceMotion &&
        widget.shot.move != 'static') {
      if (!_motion.isAnimating && !_motion.isCompleted) _motion.forward();
    } else {
      _motion.stop(canceled: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(_CameraFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.duration = _duration;
    if (oldWidget.shot.move != widget.shot.move) _motion.value = 0;
    _sync();
  }

  void _markReady() {
    if (_imageReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _imageReady) return;
      _imageReady = true;
      _sync();
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return AnimatedBuilder(
        animation: _motion,
        child: Image(
          key: const ValueKey('cinema-background'),
          image:
              widget.shot.provider ??
              NovelImageProvider.network(widget.shot.url),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null || synchronous) {
              _markReady();
            } else {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              );
            }
            return child;
          },
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFF080B0E),
            child: Center(
              child: Text('画面暂时无法加载', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ),
        builder: (context, child) {
          final pose = CinemaCameraMotion.sample(
            _reduceMotion ? 'static' : widget.shot.move,
            _motion.value,
            constraints.biggest,
            durationSeconds: _duration.inMilliseconds / 1000,
          );
          return Transform(
            key: const ValueKey('cinema-camera-transform'),
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(pose.scale, pose.scale, 1)
              ..setTranslationRaw(pose.offset.dx, pose.offset.dy, 0),
            child: child,
          );
        },
      );
    },
  );
}

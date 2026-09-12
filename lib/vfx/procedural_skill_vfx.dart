import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// V19 Visual-Target procedural VFX runtime.
///
/// This intentionally keeps the same class/file contract used by V18 so the
/// existing novel_sheets.dart import does not need to change. Unlike V18 it is
/// a high-quality 2.5D compositor: layered gradients, additive/screen blending,
/// bezier constructs, fields, particles, silhouettes and precise timing.
class ProceduralSkillVfx extends StatefulWidget {
  const ProceduralSkillVfx({
    super.key,
    required this.vfxSpec,
    this.loop = false,
    this.tapToReplay = true,
    this.showDebugLabel = false,
    this.animation,
    this.transparentBackground = false,
    this.drawVignette = true,
  });

  final Map<String, dynamic> vfxSpec;
  final bool loop;
  final bool tapToReplay;
  final bool showDebugLabel;

  /// Optional external normalized timeline. Battle pages pass their own
  /// AnimationController here so hit-stop can freeze the VFX on the exact
  /// contact frame. Preview cards leave it null and use the internal timeline.
  final Animation<double>? animation;

  /// Battle overlays must preserve the scene/characters underneath.
  final bool transparentBackground;

  /// Vignette is useful for previews and cinematic battle beats, but callers
  /// can disable it when they only want geometry/light layers.
  final bool drawVignette;

  @override
  State<ProceduralSkillVfx> createState() => _ProceduralSkillVfxState();
}

class _ProceduralSkillVfxState extends State<ProceduralSkillVfx>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timeline;

  int _durationMs(Map<String, dynamic> spec) {
    final raw = spec['duration_ms'];
    final value = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 3600;
    return value.clamp(650, 9000).toInt();
  }

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationMs(widget.vfxSpec)),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            widget.animation == null &&
            widget.loop) {
          Future<void>.delayed(const Duration(milliseconds: 180), () {
            if (mounted) _timeline.forward(from: 0);
          });
        }
      });
    if (widget.animation == null) {
      _timeline.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant ProceduralSkillVfx oldWidget) {
    super.didUpdateWidget(oldWidget);
    final specChanged = !identical(oldWidget.vfxSpec, widget.vfxSpec);
    final switchedToInternal = oldWidget.animation != null && widget.animation == null;
    if (!specChanged && !switchedToInternal) return;
    _timeline.duration = Duration(milliseconds: _durationMs(widget.vfxSpec));
    if (widget.animation == null) {
      _timeline.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeAnimation = widget.animation ?? _timeline;
    final canReplay = widget.tapToReplay && widget.animation == null;
    final isOpenProgram = widget.vfxSpec['schema_version'] == 21 ||
        widget.vfxSpec['engine']?.toString().trim().toLowerCase() == 'open_visual_program' ||
        _asList(widget.vfxSpec['program']).isNotEmpty;
    final CustomPainter effectPainter = isOpenProgram
        ? _OpenVisualProgramPainter(
            spec: widget.vfxSpec,
            animation: activeAnimation,
            transparentBackground: widget.transparentBackground,
            drawVignette: widget.drawVignette,
          )
        : _VisualTargetPainter(
            spec: widget.vfxSpec,
            animation: activeAnimation,
            transparentBackground: widget.transparentBackground,
            drawVignette: widget.drawVignette,
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canReplay ? () => _timeline.forward(from: 0) : null,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(painter: effectPainter),
            if (canReplay)
              Positioned(
                right: 8,
                bottom: 6,
                child: Text(
                  '点击重播',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.24),
                    fontSize: 8,
                  ),
                ),
              ),
            if (widget.showDebugLabel)
              Positioned(
                left: 8,
                top: 6,
                child: Text(
                  isOpenProgram
                      ? 'V21 open-program · ${_asList(widget.vfxSpec['program']).length} nodes'
                      : 'V19 visual-target · ${_asList(widget.vfxSpec['layers']).length} layers',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.34),
                    fontSize: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<dynamic> _asList(dynamic value) => value is List ? value : const <dynamic>[];
dynamic _listAt(List<dynamic> list, int index) =>
    index >= 0 && index < list.length ? list[index] : null;
Map<String, dynamic> _asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class _OpenVisualProgramPainter extends CustomPainter {
  _OpenVisualProgramPainter({
    required this.spec,
    required this.animation,
    required this.transparentBackground,
    required this.drawVignette,
  }) : super(repaint: animation);

  final Map<String, dynamic> spec;
  final Animation<double> animation;
  final bool transparentBackground;
  final bool drawVignette;

  double get t => animation.value.clamp(0.0, 1.0);

  double _d(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  int _i(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  String _s(dynamic value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  bool _b(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    if (<String>{'1', 'true', 'yes', 'on'}.contains(text)) return true;
    if (<String>{'0', 'false', 'no', 'off'}.contains(text)) return false;
    return fallback;
  }

  double _clamp(double value, [double min = 0, double max = 1]) =>
      math.max(min, math.min(max, value));

  double _phase(double value, double start, double end) {
    if (end <= start) return value >= end ? 1 : 0;
    return _clamp((value - start) / (end - start));
  }

  double _easeOut(double value) =>
      1 - math.pow(1 - _clamp(value), 3).toDouble();

  double _easeIn(double value) => math.pow(_clamp(value), 3).toDouble();

  double _easeInOut(double value) {
    final x = _clamp(value);
    return x < .5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _curve(double value, String curve) {
    switch (curve.toLowerCase()) {
      case 'linear':
        return _clamp(value);
      case 'ease_in':
      case 'easein':
        return _easeIn(value);
      case 'ease_in_out':
      case 'easeinout':
        return _easeInOut(value);
      case 'pulse':
        return math.sin(math.pi * _clamp(value));
      default:
        return _easeOut(value);
    }
  }

  Color _color(dynamic value, Color fallback) {
    if (value is int) return Color(value);
    var text = _s(value);
    if (text.isEmpty) return fallback;
    text = text.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (text.length == 6) text = 'FF$text';
    final parsed = int.tryParse(text, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Color _alpha(Color color, double opacity) =>
      color.withOpacity(_clamp(opacity));

  Offset _screenPoint(dynamic value, Size size, [Offset? fallback]) {
    final list = _asList(value);
    if (list.length >= 2) {
      return Offset(
        _d(list[0], .5).clamp(-1.5, 2.5) * size.width,
        _d(list[1], .5).clamp(-1.5, 2.5) * size.height,
      );
    }
    return fallback ?? Offset(size.width * .5, size.height * .5);
  }

  Offset _localPoint(dynamic value, double unit, [Offset? fallback]) {
    final list = _asList(value);
    if (list.length >= 2) {
      return Offset(_d(list[0]) * unit, _d(list[1]) * unit);
    }
    return fallback ?? Offset.zero;
  }

  BlendMode _blend(dynamic value) {
    switch (_s(value, 'srcOver').toLowerCase()) {
      case 'screen':
        return BlendMode.screen;
      case 'plus':
      case 'add':
      case 'additive':
        return BlendMode.plus;
      case 'lighten':
        return BlendMode.lighten;
      case 'multiply':
        return BlendMode.multiply;
      default:
        return BlendMode.srcOver;
    }
  }

  double _seed01(int index, int salt, int seed) {
    final x = math.sin((index + seed * .071) * 12.9898 + salt * 78.233) *
        43758.5453;
    return x - x.floorToDouble();
  }

  double _animatedScalar(dynamic value, double q, double fallback) {
    if (value is num) return value.toDouble();
    final list = _asList(value);
    if (list.length >= 2) {
      final a = _d(list[0], fallback);
      final b = _d(list[1], a);
      return a + (b - a) * q;
    }
    return fallback;
  }

  Offset _animatedPair(dynamic value, double q, Offset fallback) {
    final list = _asList(value);
    if (list.length >= 2 && list[0] is List && list[1] is List) {
      final a = _asList(list[0]);
      final b = _asList(list[1]);
      if (a.length >= 2 && b.length >= 2) {
        return Offset(
          _d(a[0], fallback.dx) +
              (_d(b[0], fallback.dx) - _d(a[0], fallback.dx)) * q,
          _d(a[1], fallback.dy) +
              (_d(b[1], fallback.dy) - _d(a[1], fallback.dy)) * q,
        );
      }
    }
    if (list.length >= 2 && list[0] is num && list[1] is num) {
      return Offset(_d(list[0], fallback.dx), _d(list[1], fallback.dy));
    }
    return fallback;
  }

  double _nodeProgress(Map<String, dynamic> node) {
    final start = _d(node['start'], 0.0).clamp(0.0, 1.0);
    final end = _d(node['end'], 1.0).clamp(0.0, 1.0);
    return _curve(_phase(t, start, end), _s(node['curve'], 'ease_out'));
  }

  double _nodeAlpha(Map<String, dynamic> node) {
    final start = _d(node['start'], 0.0).clamp(0.0, 1.0);
    final end = _d(node['end'], 1.0).clamp(0.0, 1.0);
    if (t < start) return 0;
    final base = _d(_asMap(node['material'])['opacity'], 1.0)
        .clamp(0.0, 1.0);
    if (_b(node['persist'], false)) {
      final fadeEnd = _d(node['fade_end'], 1.02).clamp(end, 1.02);
      if (t >= fadeEnd) return 0;
      final fadeIn = _phase(t, start, math.min(end, start + math.max(.03, (end - start) * .35)));
      final fadeOut = fadeEnd > 1
          ? 1.0
          : 1.0 - _phase(t, math.max(end, fadeEnd - .10), fadeEnd);
      return base * _clamp(fadeIn) * _clamp(fadeOut);
    }
    if (t > end) return 0;
    final duration = math.max(.001, end - start);
    final fadeIn = _d(node['fade_in'], .10).clamp(.01, .48);
    final fadeOut = _d(node['fade_out'], .18).clamp(.01, .48);
    final aIn = _clamp((t - start) / (duration * fadeIn));
    final aOut = _clamp((end - t) / (duration * fadeOut));
    return base * math.min(aIn, aOut);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!transparentBackground) _drawBackground(canvas, size);

    var program = _asList(spec['program'])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (program.isEmpty) {
      program = _neutralFallbackProgram();
    }
    program.sort((a, b) {
        final z = _d(a['z']).compareTo(_d(b['z']));
        if (z != 0) return z;
        return _d(a['start']).compareTo(_d(b['start']));
      });

    final shake = _cameraShake(size);
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    for (final node in program) {
      final alpha = _nodeAlpha(node);
      if (alpha <= .001) continue;
      final q = _nodeProgress(node);
      _drawProgramNode(canvas, size, node, q, alpha);
    }
    canvas.restore();

    final camera = _asMap(spec['camera']);
    final vignette = drawVignette ? _d(camera['vignette'], .45) : 0.0;
    if (vignette > .001) _drawVignette(canvas, size, vignette);
  }

  List<Map<String, dynamic>> _neutralFallbackProgram() {
    final selfTarget = _s(spec['application_target']).toLowerCase() == 'self';
    final target = selfTarget ? <double>[.22, .55] : <double>[.82, .52];
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'runtime_origin_marker',
        'start': .04,
        'end': .34,
        'persist': true,
        'anchor': <double>[.22, .55],
        'shape': <String, dynamic>{'kind': 'ellipse', 'radius': <double>[.032, .032]},
        'transform': <String, dynamic>{'scale': <double>[.25, 1.0]},
        'material': <String, dynamic>{
          'fill': <String, dynamic>{
            'type': 'radial',
            'colors': <String>['#FFFFFFFF', '#8EC5FF66', '#8EC5FF00'],
            'stops': <double>[0, .35, 1],
          },
          'blend': 'plus',
          'glow': <Map<String, dynamic>>[
            <String, dynamic>{'color': '#9ED0FF', 'alpha': .35, 'blur': 10.0, 'width': 3.0, 'fill': true},
          ],
        },
      },
      <String, dynamic>{
        'id': 'runtime_contact_marker',
        'start': .56,
        'end': .78,
        'anchor': target,
        'shape': <String, dynamic>{'kind': 'ellipse', 'radius': <double>[.045, .028]},
        'transform': <String, dynamic>{'scale': <double>[.25, 2.4]},
        'material': <String, dynamic>{
          'stroke': <String, dynamic>{'color': '#F7FBFF', 'alpha': .75, 'width': 1.4},
          'blend': 'screen',
          'glow': <Map<String, dynamic>>[
            <String, dynamic>{'color': '#9ED0FF', 'alpha': .26, 'blur': 8.0, 'width': 4.0},
          ],
        },
      },
    ];
  }

  void _drawBackground(Canvas canvas, Size size) {
    final bg = _asMap(spec['background']);
    final top = _color(bg['top'], const Color(0xFF030713));
    final mid = _color(bg['mid'], const Color(0xFF080B15));
    final bottom = _color(bg['bottom'], const Color(0xFF130D0A));
    final darken = _d(bg['darken'], .12).clamp(0.0, .92);
    final gradient = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      <Color>[
        Color.lerp(top, Colors.black, darken)!,
        Color.lerp(mid, Colors.black, darken * .72)!,
        Color.lerp(bottom, Colors.black, darken * .48)!,
      ],
      const <double>[0, .62, 1],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = gradient);
  }

  Offset _cameraShake(Size size) {
    final camera = _asMap(spec['camera']);
    final raw = _asList(camera['shake']);
    double amplitude = 0;
    double frequency = 22;
    for (final entry in raw.whereType<Map>()) {
      final item = Map<String, dynamic>.from(entry);
      final start = _d(item['start'], .6);
      final end = _d(item['end'], .72);
      final q = math.sin(math.pi * _phase(t, start, end));
      if (q <= 0) continue;
      amplitude = math.max(amplitude, q * _d(item['amplitude'], .008));
      frequency = _d(item['frequency'], 22);
    }
    if (amplitude <= 0) return Offset.zero;
    final px = size.shortestSide * amplitude;
    return Offset(
      math.sin(t * math.pi * frequency * 2.1) * px,
      math.cos(t * math.pi * frequency * 1.73) * px * .62,
    );
  }

  void _drawVignette(Canvas canvas, Size size, double strength) {
    final center = Offset(size.width * .5, size.height * .48);
    final radius = math.max(size.width, size.height) * .78;
    final shader = ui.Gradient.radial(
      center,
      radius,
      <Color>[
        Colors.transparent,
        Colors.transparent,
        Colors.black.withOpacity(.76 * _clamp(strength)),
      ],
      const <double>[0, .56, 1],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _drawProgramNode(
    Canvas canvas,
    Size size,
    Map<String, dynamic> node,
    double q,
    double alpha,
  ) {
    final repeat = _asMap(node['repeat']);
    final count = _i(repeat['count'], 1).clamp(1, 128).toInt();
    final motion = _asMap(node['motion']);
    final trailCount = _i(motion['trail_count'], 0).clamp(0, 12).toInt();
    final trailSpan = _d(motion['trail_span'], .10).clamp(.01, .45);
    final trailDecay = _d(motion['trail_decay'], .72).clamp(.05, .98);

    for (var trail = trailCount; trail >= 0; trail--) {
      final trailQ = _clamp(q - trail * trailSpan / math.max(1, trailCount));
      final trailAlpha = alpha * math.pow(trailDecay, trail).toDouble();
      for (var i = 0; i < count; i++) {
        final phaseOffset = _d(repeat['phase_offset'], 0.0);
        final instanceQ = _clamp(trailQ - phaseOffset * i / math.max(1, count));
        _drawProgramInstance(
          canvas,
          size,
          node,
          repeat,
          motion,
          instanceQ,
          trailAlpha,
          i,
          count,
          trail > 0,
        );
      }
    }
  }

  void _drawProgramInstance(
    Canvas canvas,
    Size size,
    Map<String, dynamic> node,
    Map<String, dynamic> repeat,
    Map<String, dynamic> motion,
    double q,
    double alpha,
    int index,
    int count,
    bool trailGhost,
  ) {
    final seed = _i(repeat['seed'], _s(node['id']).hashCode & 0x7fffffff);
    var position = _motionPosition(node, motion, size, q, index, count, seed);
    var rotation = _animatedScalar(_asMap(node['transform'])['rotation'], q, 0.0);
    var scale = _animatedScalar(_asMap(node['transform'])['scale'], q, 1.0);
    var scaleXY = _animatedPair(
      _asMap(node['transform'])['scale_xy'],
      q,
      const Offset(1, 1),
    );
    final translate = _animatedPair(
      _asMap(node['transform'])['translate'],
      q,
      Offset.zero,
    );
    position += Offset(translate.dx * size.width, translate.dy * size.height);

    final repeatMode = _s(repeat['mode'], 'none').toLowerCase();
    var mirrorX = false;
    if (repeatMode == 'radial') {
      final angleStart = _d(repeat['angle_start'], 0.0);
      final angleSpan = _d(repeat['angle_span'], math.pi * 2);
      final angle = angleStart +
          (count <= 1 ? 0 : index / count) * angleSpan +
          _d(repeat['rotation_speed'], 0.0) * t;
      final radius = _d(repeat['radius'], 0.0) * size.shortestSide;
      position += Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (_b(repeat['rotate'], true)) rotation += angle;
    } else if (repeatMode == 'linear') {
      final axis = _asList(repeat['axis']);
      final ax = axis.length >= 2 ? _d(axis[0], 1) : 1.0;
      final ay = axis.length >= 2 ? _d(axis[1], 0) : 0.0;
      final length = math.max(.0001, math.sqrt(ax * ax + ay * ay));
      final spacing = _d(repeat['spacing'], .04) * size.shortestSide;
      final centered = index - (count - 1) / 2;
      position += Offset(ax / length * spacing * centered, ay / length * spacing * centered);
    } else if (repeatMode == 'scatter') {
      final jitterRaw = repeat['jitter'];
      final jitter = jitterRaw is List
          ? Offset(_d(_listAt(_asList(jitterRaw), 0), .12), _d(_listAt(_asList(jitterRaw), 1), .12))
          : Offset(_d(jitterRaw, .12), _d(jitterRaw, .12));
      position += Offset(
        (_seed01(index, 17, seed) - .5) * 2 * jitter.dx * size.width,
        (_seed01(index, 23, seed) - .5) * 2 * jitter.dy * size.height,
      );
      rotation += (_seed01(index, 29, seed) - .5) * _d(repeat['rotation_jitter'], math.pi * 2);
      final scaleJitter = _d(repeat['scale_jitter'], .25).clamp(0.0, .95);
      scale *= 1 + (_seed01(index, 31, seed) - .5) * 2 * scaleJitter;
    } else if (repeatMode == 'mirror') {
      mirrorX = index.isOdd;
    }

    if (_b(motion['orient_to_path'], false)) {
      rotation += _motionTangent(motion, size, q, node, index, count, seed);
    }

    final deform = _asMap(node['deform']);
    final pulse = _d(deform['pulse'], 0.0);
    if (pulse.abs() > .0001) {
      scale *= 1 + math.sin(q * math.pi) * pulse;
    }

    if (trailGhost) alpha *= .72;
    if (alpha <= .001 || scale.abs() <= .0001) return;

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    canvas.scale(scaleXY.dx * scale * (mirrorX ? -1 : 1), scaleXY.dy * scale);
    _drawShape(canvas, size, node, q, alpha, index, seed);
    canvas.restore();
  }

  Offset _motionPosition(
    Map<String, dynamic> node,
    Map<String, dynamic> motion,
    Size size,
    double q,
    int index,
    int count,
    int seed,
  ) {
    final anchor = _screenPoint(node['anchor'], size, Offset(size.width * .5, size.height * .5));
    final mode = _s(motion['mode'], 'stationary').toLowerCase();
    if (mode == 'path') {
      final points = _asList(motion['path']);
      if (points.length >= 2) return _sampleMotionPath(points, size, q);
      return anchor;
    }

    final directionRaw = _asList(motion['direction']);
    var dx = directionRaw.length >= 2 ? _d(directionRaw[0], 1) : 1.0;
    var dy = directionRaw.length >= 2 ? _d(directionRaw[1], 0) : 0.0;
    final length = math.max(.0001, math.sqrt(dx * dx + dy * dy));
    dx /= length;
    dy /= length;
    final spread = _d(motion['spread'], 0.0);
    if (spread.abs() > .0001 && count > 1) {
      final jitter = (_seed01(index, 43, seed) - .5) * spread * math.pi;
      final c = math.cos(jitter);
      final s = math.sin(jitter);
      final ndx = dx * c - dy * s;
      final ndy = dx * s + dy * c;
      dx = ndx;
      dy = ndy;
    }

    final speed = _d(motion['speed'], .28);
    if (mode == 'radial') {
      final distance = speed * size.shortestSide * q;
      final angle = count <= 1
          ? math.atan2(dy, dx)
          : math.atan2(dy, dx) + index * math.pi * 2 / count;
      return anchor + Offset(math.cos(angle) * distance, math.sin(angle) * distance);
    }
    if (mode == 'orbit') {
      final radius = _d(motion['radius'], .18) * size.shortestSide;
      final turns = _d(motion['turns'], 1.0);
      final angle = _d(motion['angle_start'], 0.0) +
          index * math.pi * 2 / math.max(1, count) +
          q * math.pi * 2 * turns;
      final aspect = _d(motion['aspect'], .72);
      return anchor + Offset(math.cos(angle) * radius, math.sin(angle) * radius * aspect);
    }
    if (mode == 'converge') {
      final radius = _d(motion['radius'], .26) * size.shortestSide;
      final angle = index * math.pi * 2 / math.max(1, count) +
          _seed01(index, 47, seed) * .7;
      final r = radius * (1 - _easeOut(q));
      return anchor + Offset(math.cos(angle) * r, math.sin(angle) * r * .72);
    }
    if (mode == 'ballistic') {
      final distance = speed * size.shortestSide * q;
      final gravity = _d(motion['gravity'], .35) * size.height;
      return anchor + Offset(dx * distance, dy * distance + gravity * q * q * .5);
    }
    if (mode == 'drift') {
      final driftRaw = _asList(motion['drift']);
      final drift = driftRaw.length >= 2
          ? Offset(_d(driftRaw[0]), _d(driftRaw[1]))
          : Offset(dx * speed, dy * speed);
      final wave = _d(motion['wave'], 0.0) * size.shortestSide;
      return anchor + Offset(
        drift.dx * size.width * q,
        drift.dy * size.height * q + math.sin((q * 2 + index * .17) * math.pi) * wave,
      );
    }
    return anchor;
  }

  Offset _sampleMotionPath(List<dynamic> raw, Size size, double q) {
    final points = raw.map((item) => _screenPoint(item, size)).toList(growable: false);
    if (points.length == 2) {
      return Offset.lerp(points[0], points[1], q)!;
    }
    if (points.length == 3) {
      final a = Offset.lerp(points[0], points[1], q)!;
      final b = Offset.lerp(points[1], points[2], q)!;
      return Offset.lerp(a, b, q)!;
    }
    if (points.length >= 4) {
      final segments = points.length - 1;
      final scaled = _clamp(q) * segments;
      final seg = math.min(segments - 1, scaled.floor());
      final u = scaled - seg;
      final p0 = points[math.max(0, seg - 1)];
      final p1 = points[seg];
      final p2 = points[math.min(points.length - 1, seg + 1)];
      final p3 = points[math.min(points.length - 1, seg + 2)];
      return _catmullRom(p0, p1, p2, p3, u);
    }
    return points.isEmpty ? Offset.zero : points.first;
  }

  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double u) {
    final u2 = u * u;
    final u3 = u2 * u;
    return Offset(
      .5 * ((2 * p1.dx) + (-p0.dx + p2.dx) * u +
          (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * u2 +
          (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * u3),
      .5 * ((2 * p1.dy) + (-p0.dy + p2.dy) * u +
          (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * u2 +
          (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * u3),
    );
  }

  double _motionTangent(
    Map<String, dynamic> motion,
    Size size,
    double q,
    Map<String, dynamic> node,
    int index,
    int count,
    int seed,
  ) {
    final q0 = _clamp(q - .012);
    final q1 = _clamp(q + .012);
    final p0 = _motionPosition(node, motion, size, q0, index, count, seed);
    final p1 = _motionPosition(node, motion, size, q1, index, count, seed);
    return math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
  }

  Offset _warpLocal(
    Offset p,
    Map<String, dynamic> deform,
    double q,
    int index,
    int seed,
    double unit,
  ) {
    if (deform.isEmpty) return p;
    var x = p.dx / unit;
    var y = p.dy / unit;
    final bend = _d(deform['bend'], 0.0);
    if (bend.abs() > .0001) y += bend * x * x * (x >= 0 ? 1 : -1);
    final wave = _d(deform['wave'], 0.0);
    if (wave.abs() > .0001) {
      final freq = _d(deform['wave_frequency'], 3.0);
      final phase = _d(deform['wave_phase'], 1.0) * q * math.pi * 2;
      y += math.sin(x * freq * math.pi * 2 + phase + _seed01(index, 61, seed)) * wave;
    }
    final taper = _d(deform['taper'], 0.0).clamp(-1.0, 1.0);
    if (taper.abs() > .0001) y *= 1 - taper * _clamp(x.abs(), 0, 1);
    final jitter = _d(deform['jitter'], 0.0);
    if (jitter > .0001) {
      x += (_seed01(index + (x * 1000).round(), 67, seed) - .5) * jitter;
      y += (_seed01(index + (y * 1000).round(), 71, seed) - .5) * jitter;
    }
    return Offset(x * unit, y * unit);
  }

  void _drawShape(
    Canvas canvas,
    Size size,
    Map<String, dynamic> node,
    double q,
    double alpha,
    int index,
    int seed,
  ) {
    final shape = _asMap(node['shape']);
    final kind = _s(shape['kind'], 'ellipse').toLowerCase();
    final unit = size.shortestSide;
    final deform = _asMap(node['deform']);
    Path path;
    var closed = false;

    if (kind == 'path') {
      path = _pathFromCommands(_asList(shape['commands']), deform, q, index, seed, unit);
      closed = _asList(shape['commands']).any((cmd) =>
          cmd is List && cmd.isNotEmpty && _s(cmd.first).toUpperCase() == 'Z');
    } else if (kind == 'polygon') {
      path = Path();
      final points = _asList(shape['points']);
      for (var i = 0; i < points.length; i++) {
        final p = _warpLocal(_localPoint(points[i], unit), deform, q, index, seed, unit);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (points.length >= 3) {
        path.close();
        closed = true;
      }
    } else if (kind == 'line') {
      final from = _warpLocal(_localPoint(shape['from'], unit), deform, q, index, seed, unit);
      final to = _warpLocal(_localPoint(shape['to'], unit), deform, q, index, seed, unit);
      path = Path()..moveTo(from.dx, from.dy)..lineTo(to.dx, to.dy);
    } else if (kind == 'arc') {
      final radius = _asList(shape['radius']);
      final rx = _d(_listAt(radius, 0), .10) * unit;
      final ry = _d(_listAt(radius, 1), _d(_listAt(radius, 0), .10)) * unit;
      final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
      path = Path()
        ..addArc(
          rect,
          _d(shape['start_angle'], 0.0),
          _d(shape['sweep_angle'], math.pi),
        );
    } else {
      final radius = _asList(shape['radius']);
      final rx = _d(_listAt(radius, 0), .06) * unit;
      final ry = _d(_listAt(radius, 1), _d(_listAt(radius, 0), .06)) * unit;
      path = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2));
      closed = true;
    }

    _paintPath(canvas, path, node, alpha, closed, unit);
  }

  Path _pathFromCommands(
    List<dynamic> commands,
    Map<String, dynamic> deform,
    double q,
    int index,
    int seed,
    double unit,
  ) {
    final path = Path();
    for (final raw in commands.take(128)) {
      final cmd = _asList(raw);
      if (cmd.isEmpty) continue;
      final op = _s(cmd[0]).toUpperCase();
      if (op == 'M' && cmd.length >= 3) {
        final p = _warpLocal(Offset(_d(cmd[1]) * unit, _d(cmd[2]) * unit), deform, q, index, seed, unit);
        path.moveTo(p.dx, p.dy);
      } else if (op == 'L' && cmd.length >= 3) {
        final p = _warpLocal(Offset(_d(cmd[1]) * unit, _d(cmd[2]) * unit), deform, q, index, seed, unit);
        path.lineTo(p.dx, p.dy);
      } else if (op == 'Q' && cmd.length >= 5) {
        final c = _warpLocal(Offset(_d(cmd[1]) * unit, _d(cmd[2]) * unit), deform, q, index, seed, unit);
        final p = _warpLocal(Offset(_d(cmd[3]) * unit, _d(cmd[4]) * unit), deform, q, index, seed, unit);
        path.quadraticBezierTo(c.dx, c.dy, p.dx, p.dy);
      } else if (op == 'C' && cmd.length >= 7) {
        final c1 = _warpLocal(Offset(_d(cmd[1]) * unit, _d(cmd[2]) * unit), deform, q, index, seed, unit);
        final c2 = _warpLocal(Offset(_d(cmd[3]) * unit, _d(cmd[4]) * unit), deform, q, index, seed, unit);
        final p = _warpLocal(Offset(_d(cmd[5]) * unit, _d(cmd[6]) * unit), deform, q, index, seed, unit);
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
      } else if (op == 'Z') {
        path.close();
      }
    }
    return path;
  }

  void _paintPath(
    Canvas canvas,
    Path path,
    Map<String, dynamic> node,
    double alpha,
    bool closed,
    double unit,
  ) {
    final material = _asMap(node['material']);
    final blend = _blend(material['blend']);
    final bounds = path.getBounds();
    final safeBounds = bounds.isEmpty
        ? Rect.fromCenter(center: Offset.zero, width: unit * .1, height: unit * .1)
        : bounds;

    final glows = _asList(material['glow']);
    for (final raw in glows.whereType<Map>()) {
      final glow = Map<String, dynamic>.from(raw);
      final color = _color(glow['color'], const Color(0xFFFFFFFF));
      final glowAlpha = _d(glow['alpha'], .25) * alpha;
      final width = _d(glow['width'], 3.0);
      final blur = _d(glow['blur'], 7.0).clamp(0.0, 48.0);
      final paint = Paint()
        ..color = _alpha(color, glowAlpha)
        ..blendMode = blend
        ..maskFilter = blur > .01 ? MaskFilter.blur(BlurStyle.normal, blur) : null;
      if (closed && _b(glow['fill'], false)) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.35, width)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      }
      canvas.drawPath(path, paint);
    }

    final fill = _asMap(material['fill']);
    if (closed && fill.isNotEmpty) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..blendMode = blend;
      final type = _s(fill['type'], 'solid').toLowerCase();
      if (type == 'linear' || type == 'radial') {
        final colorsRaw = _asList(fill['colors']);
        var colors = colorsRaw.isEmpty
            ? <Color>[_color(fill['color'], Colors.white)]
            : colorsRaw.map((c) => _color(c, Colors.white)).toList(growable: false);
        if (colors.length == 1) colors = <Color>[colors.first, colors.first];
        final stopsRaw = _asList(fill['stops']);
        List<double>? stops;
        if (stopsRaw.length == colors.length) {
          stops = stopsRaw.map((v) => _d(v).clamp(0.0, 1.0)).toList(growable: false);
        }
        if (type == 'radial') {
          final center = _localPoint(fill['center'], unit, safeBounds.center);
          final radius = _d(fill['radius'], .18) * unit;
          paint.shader = ui.Gradient.radial(
            center,
            math.max(1.0, radius),
            colors.map((c) => _alpha(c, alpha)).toList(growable: false),
            stops,
          );
        } else {
          final from = _localPoint(fill['from'], unit, safeBounds.centerLeft);
          final to = _localPoint(fill['to'], unit, safeBounds.centerRight);
          paint.shader = ui.Gradient.linear(
            from,
            to,
            colors.map((c) => _alpha(c, alpha)).toList(growable: false),
            stops,
          );
        }
      } else {
        paint.color = _alpha(_color(fill['color'], Colors.white), _d(fill['alpha'], 1.0) * alpha);
      }
      canvas.drawPath(path, paint);
    }

    final stroke = _asMap(material['stroke']);
    if (stroke.isNotEmpty || !closed) {
      final color = _color(stroke['color'], const Color(0xFFFFFFFF));
      final strokeAlpha = _d(stroke['alpha'], .85) * alpha;
      final width = _d(stroke['width'], closed ? 1.2 : 2.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.35, width)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = blend
        ..color = _alpha(color, strokeAlpha);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OpenVisualProgramPainter oldDelegate) =>
      !identical(oldDelegate.spec, spec) ||
      oldDelegate.animation != animation ||
      oldDelegate.transparentBackground != transparentBackground ||
      oldDelegate.drawVignette != drawVignette;
}


class _VisualTargetPainter extends CustomPainter {
  _VisualTargetPainter({
    required this.spec,
    required this.animation,
    required this.transparentBackground,
    required this.drawVignette,
  }) : super(repaint: animation);

  final Map<String, dynamic> spec;
  final Animation<double> animation;
  final bool transparentBackground;
  final bool drawVignette;

  double get t => animation.value.clamp(0.0, 1.0);

  double _d(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  int _i(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  String _s(dynamic value, [String fallback = '']) {
    final v = value?.toString().trim() ?? '';
    return v.isEmpty ? fallback : v;
  }

  bool _b(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    if (<String>{'1', 'true', 'yes', 'on'}.contains(text)) return true;
    if (<String>{'0', 'false', 'no', 'off'}.contains(text)) return false;
    return fallback;
  }

  Color _color(dynamic value, Color fallback) {
    if (value is int) return Color(value);
    var text = _s(value);
    if (text.isEmpty) return fallback;
    text = text.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    if (text.length == 6) text = 'FF$text';
    final parsed = int.tryParse(text, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  Color _withAlpha(Color color, double alpha) =>
      color.withOpacity(alpha.clamp(0.0, 1.0));

  Offset _point(dynamic value, Size size, [Offset? fallback]) {
    final list = _asList(value);
    if (list.length >= 2) {
      return Offset(
        _d(list[0], .5).clamp(-1.5, 2.5) * size.width,
        _d(list[1], .5).clamp(-1.5, 2.5) * size.height,
      );
    }
    return fallback ?? Offset(size.width * .5, size.height * .5);
  }

  double _clamp(double x, [double a = 0, double b = 1]) =>
      math.max(a, math.min(b, x));

  double _phase(double value, double start, double end) {
    if (end <= start) return value >= end ? 1 : 0;
    return _clamp((value - start) / (end - start));
  }

  double _ease(double x) => 1 - math.pow(1 - _clamp(x), 3).toDouble();
  double _easeIn(double x) => math.pow(_clamp(x), 3).toDouble();
  double _easeInOut(double x) {
    x = _clamp(x);
    return x < .5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }
  double _pulse(double x) => math.sin(math.pi * _clamp(x));

  double _curve(double x, String curve) {
    switch (curve.toLowerCase()) {
      case 'ease_in':
      case 'easein':
        return _easeIn(x);
      case 'ease_in_out':
      case 'easeinout':
        return _easeInOut(x);
      case 'pulse':
        return _pulse(x);
      case 'linear':
        return _clamp(x);
      default:
        return _ease(x);
    }
  }

  double _layerProgress(Map<String, dynamic> layer) {
    final start = _d(layer['start'], 0.0);
    final end = _d(layer['end'], 1.0);
    return _curve(_phase(t, start, end), _s(layer['curve'], 'ease_out'));
  }

  double _layerAlpha(Map<String, dynamic> layer, double progress) {
    final base = _d(layer['alpha'], 1.0).clamp(0.0, 1.0);
    final start = _d(layer['start'], 0.0);
    final end = _d(layer['end'], 1.0);
    if (t < start) return 0;
    if (_b(layer['persist'], false)) {
      final fadeEnd = _d(layer['fade_end'], 1.02);
      if (t > fadeEnd) return 0;
      final inA = _clamp(_phase(t, start, math.min(end, start + math.max(.02, (end - start) * .45))));
      final outA = fadeEnd > .99 ? 1.0 : 1.0 - _phase(t, fadeEnd - .08, fadeEnd);
      return base * inA * outA;
    }
    final fadeIn = _d(layer['fade_in'], .12).clamp(.01, .48);
    final fadeOut = _d(layer['fade_out'], .18).clamp(.01, .48);
    final duration = math.max(.001, end - start);
    final inA = _clamp((t - start) / (duration * fadeIn));
    final outA = _clamp((end - t) / (duration * fadeOut));
    return base * math.min(inA, outA);
  }

  BlendMode _blend(dynamic value) {
    switch (_s(value, 'srcOver').toLowerCase()) {
      case 'screen':
        return BlendMode.screen;
      case 'plus':
      case 'add':
      case 'additive':
        return BlendMode.plus;
      case 'lighten':
        return BlendMode.lighten;
      case 'multiply':
        return BlendMode.multiply;
      default:
        return BlendMode.srcOver;
    }
  }

  Map<String, Color> _palette() {
    final p = _asMap(spec['palette']);
    return <String, Color>{
      'primary': _color(p['primary'], const Color(0xFF78DFFF)),
      'secondary': _color(p['secondary'], const Color(0xFF496CFF)),
      'highlight': _color(p['highlight'], const Color(0xFFF1FEFF)),
      'shadow': _color(p['shadow'], const Color(0xFF07101E)),
      'accent': _color(p['accent'], const Color(0xFFFFC96B)),
      'ground': _color(p['ground'], const Color(0xFF2D2119)),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _palette();
    if (!transparentBackground) {
      _drawBackground(canvas, size, p);
    }

    var layers = _asList(spec['layers'])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (layers.isEmpty) {
      layers = _localFallbackLayers();
    }

    // Camera shake is applied to the composed VFX, not the UI chrome.
    final shake = _screenShake(layers, size);
    canvas.save();
    canvas.translate(shake.dx, shake.dy);

    for (final layer in layers) {
      final progress = _layerProgress(layer);
      final alpha = _layerAlpha(layer, progress);
      if (alpha <= .001 && !_b(layer['persist'], false)) continue;
      _drawLayer(canvas, size, p, layer, progress, alpha);
    }
    canvas.restore();

    if (drawVignette) {
      _drawVignette(canvas, size);
    }
  }

  void _drawBackground(Canvas canvas, Size size, Map<String, Color> p) {
    final bg = _asMap(spec['background']);
    final top = _color(bg['top'], const Color(0xFF030713));
    final mid = _color(bg['mid'], const Color(0xFF080B15));
    final bottom = _color(bg['bottom'], const Color(0xFF130D0A));
    final darken = _d(bg['darken'], 0.0).clamp(0.0, .92);
    final gradient = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      <Color>[
        Color.lerp(top, Colors.black, darken)!,
        Color.lerp(mid, Colors.black, darken * .72)!,
        Color.lerp(bottom, Colors.black, darken * .48)!,
      ],
      const <double>[0, .62, 1],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = gradient);
  }

  List<Map<String, dynamic>> _localFallbackLayers() {
    final caption = _s(spec['caption']).toLowerCase();
    final role = _s(spec['semantic_role']).toLowerCase();
    final isGuard = role == 'guard' || caption.contains('盾') || caption.contains('罩');
    final isIce = caption.contains('冰') || caption.contains('霜') || caption.contains('寒');
    final isLotus = caption.contains('莲');
    if (isGuard) {
      return <Map<String, dynamic>>[
        <String, dynamic>{'op': 'stars', 'start': 0.0, 'end': 1.0, 'persist': true, 'count': 42, 'alpha': .7},
        <String, dynamic>{'op': 'glow_field', 'start': .02, 'end': .24, 'persist': true, 'center': <double>[.5, .53], 'radius': .32, 'alpha': .9},
        if (isLotus)
          <String, dynamic>{
            'op': 'petal_field', 'start': .02, 'end': .28, 'persist': true, 'center': <double>[.5, .53],
            'rings': <Map<String, dynamic>>[
              <String, dynamic>{'count': 16, 'radius': .032, 'length': .17, 'width': .052, 'rotation_speed': -.09},
              <String, dynamic>{'count': 12, 'radius': .020, 'length': .135, 'width': .045, 'offset': .13, 'rotation_speed': .14},
              <String, dynamic>{'count': 8, 'radius': .008, 'length': .095, 'width': .038, 'offset': .25, 'rotation_speed': -.08},
            ],
            'alpha': .95,
          },
        <String, dynamic>{'op': 'energy_core', 'start': .04, 'end': .30, 'persist': true, 'center': <double>[.5, .53], 'radius': .032, 'alpha': 1.0},
        <String, dynamic>{'op': 'dome_field', 'start': .14, 'end': .34, 'persist': true, 'center': <double>[.5, .53], 'radius': .235, 'aspect': .82, 'layers': 4, 'alpha': .95},
        <String, dynamic>{'op': 'rune_ring', 'start': .18, 'end': .38, 'persist': true, 'center': <double>[.5, .55], 'radius': .28, 'aspect': .31, 'count': 16, 'rotation_speed': .55, 'alpha': .82},
        <String, dynamic>{'op': 'fracture_field', 'start': .50, 'end': .72, 'center': <double>[.5, .53], 'radius': .23, 'branches': 12, 'segments': 6, 'alpha': .82},
        <String, dynamic>{'op': 'shockwave', 'start': .50, 'end': .72, 'center': <double>[.5, .53], 'count': 4, 'base_radius': .20, 'growth': .30, 'aspect': .60, 'alpha': .82},
        if (isIce)
          <String, dynamic>{'op': 'shard_field', 'start': .18, 'end': .94, 'persist': true, 'center': <double>[.5, .53], 'target': <double>[.94, .53], 'count': 18, 'radius': .34, 'aspect': .52, 'rotation_speed': 1.7, 'launch_start': .66, 'launch_end': .92, 'alpha': .92},
      ];
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{'op': 'stars', 'start': 0.0, 'end': 1.0, 'persist': true, 'count': 42, 'alpha': .65},
      <String, dynamic>{'op': 'glow_field', 'start': .02, 'end': .22, 'persist': true, 'center': <double>[.20, .55], 'radius': .18, 'alpha': .9},
      <String, dynamic>{'op': 'energy_core', 'start': .03, 'end': .24, 'persist': true, 'center': <double>[.20, .55], 'radius': .025, 'alpha': .9},
      <String, dynamic>{'op': 'projectile_orb', 'start': .24, 'end': .68, 'from': <double>[.20, .55], 'to': <double>[.82, .52], 'radius': .032, 'alpha': 1.0},
      <String, dynamic>{'op': 'ribbon_field', 'start': .24, 'end': .70, 'from': <double>[.20, .55], 'to': <double>[.82, .52], 'count': 4, 'amplitude': .04, 'turns': 1.5, 'alpha': .65},
      <String, dynamic>{'op': 'impact_flash', 'start': .66, 'end': .82, 'curve': 'pulse', 'center': <double>[.82, .52], 'radius': .26, 'sparks': 45, 'alpha': .9},
      <String, dynamic>{'op': 'shockwave', 'start': .66, 'end': .88, 'center': <double>[.82, .52], 'count': 4, 'base_radius': .05, 'growth': .28, 'aspect': .72, 'alpha': .9},
    ];
  }

  Offset _screenShake(List<Map<String, dynamic>> layers, Size size) {
    double strength = 0;
    double frequency = 22;
    for (final layer in layers) {
      if (_s(layer['op']).toLowerCase() != 'camera_shake') continue;
      final q = _pulse(_phase(t, _d(layer['start'], .6), _d(layer['end'], .75)));
      strength = math.max(strength, q * _d(layer['strength'], .018));
      frequency = _d(layer['frequency'], 22);
    }
    if (strength <= 0) return Offset.zero;
    final px = math.min(size.width, size.height) * strength;
    return Offset(
      math.sin(t * math.pi * frequency * 2.1) * px,
      math.cos(t * math.pi * frequency * 1.7) * px * .58,
    );
  }

  void _drawLayer(
    Canvas canvas,
    Size size,
    Map<String, Color> p,
    Map<String, dynamic> layer,
    double q,
    double alpha,
  ) {
    final op = _s(layer['op']).toLowerCase();
    switch (op) {
      case 'stars':
        _drawStars(canvas, size, p, layer, alpha);
        break;
      case 'glow_field':
        _drawGlowField(canvas, size, p, layer, q, alpha);
        break;
      case 'floor_halo':
        _drawFloorHalo(canvas, size, p, layer, q, alpha);
        break;
      case 'petal_field':
        _drawPetalField(canvas, size, p, layer, q, alpha);
        break;
      case 'energy_core':
        _drawEnergyCore(canvas, size, p, layer, q, alpha);
        break;
      case 'dome_field':
      case 'refractive_dome':
        _drawDome(canvas, size, p, layer, q, alpha);
        break;
      case 'fracture_field':
        _drawFractureField(canvas, size, p, layer, q, alpha);
        break;
      case 'rune_ring':
        _drawRuneRing(canvas, size, p, layer, q, alpha);
        break;
      case 'shard_field':
        _drawShardField(canvas, size, p, layer, q, alpha);
        break;
      case 'streak_field':
        _drawStreakField(canvas, size, p, layer, q, alpha);
        break;
      case 'cloud_field':
        _drawCloudField(canvas, size, p, layer, q, alpha);
        break;
      case 'vortex_rings':
      case 'aperture_rings':
        _drawVortexRings(canvas, size, p, layer, q, alpha);
        break;
      case 'colossal_limb':
        _drawColossalLimb(canvas, size, p, layer, q, alpha);
        break;
      case 'pressure_rings':
        _drawPressureRings(canvas, size, p, layer, q, alpha);
        break;
      case 'ground_plane':
        _drawGround(canvas, size, p, layer, q, alpha);
        break;
      case 'crater_field':
        _drawCrater(canvas, size, p, layer, q, alpha);
        break;
      case 'debris_field':
        _drawDebris(canvas, size, p, layer, q, alpha);
        break;
      case 'impact_flash':
        _drawImpactFlash(canvas, size, p, layer, q, alpha);
        break;
      case 'shockwave':
        _drawShockwave(canvas, size, p, layer, q, alpha);
        break;
      case 'beam':
        _drawBeam(canvas, size, p, layer, q, alpha);
        break;
      case 'projectile_orb':
        _drawProjectileOrb(canvas, size, p, layer, q, alpha);
        break;
      case 'ribbon_field':
        _drawRibbonField(canvas, size, p, layer, q, alpha);
        break;
      case 'creature_construct':
        _drawCreature(canvas, size, p, layer, q, alpha);
        break;
      case 'bezier_shape':
        _drawBezierShape(canvas, size, p, layer, q, alpha);
        break;
      case 'camera_shake':
        break;
      default:
        // Unknown future operators degrade into a visible semantic glow instead
        // of disappearing/black-screening.
        _drawGlowField(canvas, size, p, layer, q, alpha * .45);
    }
  }

  void _drawStars(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double alpha) {
    final count = _i(layer['count'], 56).clamp(8, 160);
    final seed = _i(layer['seed'], _i(spec['seed'], 37));
    final rnd = math.Random(seed);
    final paint = Paint()..blendMode = BlendMode.screen;
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height * .82;
      final twinkle = .25 + .75 * math.pow(math.sin(t * 13 + i * 1.73), 2);
      final r = .45 + rnd.nextDouble() * 1.25;
      paint.color = _withAlpha(p['highlight']!, alpha * (.08 + .22 * twinkle));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _drawGlowField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final radius = _d(layer['radius'], .28) * unit * (1 + _d(layer['expand'], .08) * q);
    final aspect = _d(layer['aspect'], 1.0).clamp(.15, 4.0);
    final inner = _color(layer['inner_color'], p['primary']!);
    final outer = _color(layer['outer_color'], p['secondary']!);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, aspect);
    final shader = ui.Gradient.radial(
      Offset.zero,
      radius,
      <Color>[
        _withAlpha(inner, alpha * _d(layer['inner_alpha'], .32)),
        _withAlpha(outer, alpha * _d(layer['mid_alpha'], .09)),
        Colors.transparent,
      ],
      const <double>[0, .30, 1],
    );
    canvas.drawCircle(Offset.zero, radius, (Paint()..shader = shader..blendMode = _blend(layer['blend'])));
    canvas.restore();
  }

  void _drawFloorHalo(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .5, size.height * .68));
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 5).clamp(1, 12);
    final baseRx = _d(layer['radius_x'], .22) * unit;
    final baseRy = _d(layer['radius_y'], .045) * unit;
    final spacing = _d(layer['spacing'], .025) * unit;
    for (var i = 0; i < count; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..blendMode = _blend(layer['blend'] ?? 'screen')
        ..strokeWidth = .8 + i * .22
        ..color = _withAlpha(
          Color.lerp(p['primary'], p['highlight'], i / math.max(1, count - 1))!,
          alpha * math.max(.02, .16 - i * .018),
        );
      canvas.drawOval(
        Rect.fromCenter(
          center: c,
          width: (baseRx + spacing * i) * 2 * (1 + .04 * q),
          height: (baseRy + spacing * i * .22) * 2,
        ),
        paint,
      );
    }
  }

  void _drawPetalField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final ringsRaw = _asList(layer['rings']);
    final rings = ringsRaw.isEmpty ? <dynamic>[layer] : ringsRaw;
    final unit = math.min(size.width, size.height);
    final hit = _pulse(_phase(t, _d(layer['hit_start'], .50), _d(layer['hit_end'], .68)));
    final counter = _easeIn(_phase(t, _d(layer['counter_start'], .66), _d(layer['counter_end'], .92)));

    for (var ri = 0; ri < rings.length; ri++) {
      final ring = _asMap(rings[ri]);
      final count = _i(ring['count'], math.max(8, 16 - ri * 4)).clamp(3, 40);
      final radius = _d(ring['radius'], .025 + ri * .015) * unit;
      final length = _d(ring['length'], .17 - ri * .035) * unit;
      final width = _d(ring['width'], .052 - ri * .006) * unit;
      final offset = _d(ring['offset'], ri * .13);
      final speed = _d(ring['rotation_speed'], ri.isEven ? -.09 : .14);
      final open = _clamp(q * (1.25 - ri * .08));
      final recoil = 1 - hit * _d(ring['hit_recoil'], .22) + counter * _d(ring['counter_flare'], .16);
      for (var i = 0; i < count; i++) {
        final a = i * math.pi * 2 / count + offset + t * speed;
        final pos = Offset(
          c.dx + math.cos(a) * radius,
          c.dy + math.sin(a) * radius * _d(ring['orbit_aspect'], .45),
        );
        _drawPetal(
          canvas,
          pos,
          a,
          length * recoil,
          width,
          open,
          alpha * _d(ring['alpha'], .86),
          _color(ring['primary'], p['primary']!),
          _color(ring['secondary'], p['secondary']!),
          _color(ring['highlight'], p['highlight']!),
          _blend(ring['blend'] ?? layer['blend'] ?? 'screen'),
        );
      }
    }
  }

  void _drawPetal(
    Canvas canvas,
    Offset c,
    double angle,
    double length,
    double width,
    double open,
    double alpha,
    Color primary,
    Color secondary,
    Color highlight,
    BlendMode blend,
  ) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.scale(1, math.max(.05, open));
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(length * .32, -width * .92, length * .72, -width * .72, length, 0)
      ..cubicTo(length * .72, width * .72, length * .32, width * .92, 0, 0)
      ..close();
    final gradient = ui.Gradient.linear(
      Offset(0, -width),
      Offset(length, width),
      <Color>[
        _withAlpha(highlight, .26 * alpha),
        _withAlpha(primary, .27 * alpha),
        _withAlpha(secondary, .16 * alpha),
        _withAlpha(highlight, .36 * alpha),
      ],
      const <double>[0, .35, .72, 1],
    );
    final fill = Paint()
      ..shader = gradient
      ..blendMode = blend
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    final glow = Paint()
      ..color = _withAlpha(primary, .16 * alpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10)
      ..blendMode = BlendMode.plus
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawPath(path, glow);

    canvas.drawPath(
      path,
      Paint()
        ..color = _withAlpha(highlight, .72 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .85,
    );
    final vein = Path()
      ..moveTo(length * .12, 0)
      ..quadraticBezierTo(length * .55, -width * .08, length * .90, 0);
    canvas.drawPath(
      vein,
      Paint()
        ..color = _withAlpha(highlight, .25 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
    canvas.restore();
  }

  void _drawEnergyCore(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final hit = _pulse(_phase(t, _d(layer['hit_start'], .5), _d(layer['hit_end'], .68)));
    final counter = _easeIn(_phase(t, _d(layer['counter_start'], .66), _d(layer['counter_end'], .92)));
    final baseR = _d(layer['radius'], .032) * unit;
    final pulse = 1 + math.sin(t * math.pi * _d(layer['frequency'], 10)) * .12;
    final r = baseR * (pulse + hit * .8 + counter * .55) * math.max(.2, q);
    final glowR = r * _d(layer['glow_scale'], 4.0);
    final shader = ui.Gradient.radial(
      c,
      glowR,
      <Color>[
        _withAlpha(p['highlight']!, .62 * alpha),
        _withAlpha(p['primary']!, .12 * alpha),
        Colors.transparent,
      ],
      const <double>[0, .24, 1],
    );
    canvas.drawCircle(c, glowR, (Paint()..shader = shader..blendMode = BlendMode.screen));
    canvas.drawCircle(c, math.max(1.2, r * .36), Paint()..color = _withAlpha(p['highlight']!, .94 * alpha)..blendMode = BlendMode.plus);
  }

  void _drawDome(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final hit = _pulse(_phase(t, _d(layer['hit_start'], .50), _d(layer['hit_end'], .68)));
    final radius = _d(layer['radius'], .235) * unit * (1 + hit * .05);
    final aspect = _d(layer['aspect'], .82);
    final layers = _i(layer['layers'], 4).clamp(1, 8);
    final primary = _color(layer['primary'], p['primary']!);
    final highlight = _color(layer['highlight'], p['highlight']!);
    final secondary = _color(layer['secondary'], p['secondary']!);

    for (var i = 0; i < layers; i++) {
      final rr = radius + i * unit * .014;
      final rect = Rect.fromCenter(center: c, width: rr * 2, height: rr * 2 * aspect);
      final focal = Offset(c.dx - rr * .28, c.dy - rr * .36);
      final gradient = ui.Gradient.radial(
        focal,
        rr * 1.2,
        <Color>[
          _withAlpha(highlight, alpha * math.max(.01, .10 - i * .012)),
          _withAlpha(primary, alpha * math.max(.01, .065 - i * .008)),
          _withAlpha(secondary, alpha * .03),
          Colors.transparent,
        ],
        const <double>[0, .46, .80, 1],
      );
      canvas.drawOval(rect, (Paint()..shader = gradient..blendMode = BlendMode.screen));
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8 + i * .22
          ..color = _withAlpha(highlight, alpha * (.18 + hit * .42))
          ..blendMode = BlendMode.screen,
      );
    }
  }

  void _drawFractureField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final active = _pulse(_phase(t, _d(layer['active_start'], _d(layer['start'], .5)), _d(layer['active_end'], _d(layer['end'], .72))));
    if (active <= .001) return;
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final radius = _d(layer['radius'], .23) * unit * (0.55 + .45 * q);
    final branches = _i(layer['branches'], 12).clamp(3, 36);
    final segments = _i(layer['segments'], 6).clamp(2, 14);
    final seed = _d(layer['seed'], 3.1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _d(layer['width'], .8)
      ..color = _withAlpha(_color(layer['color'], p['highlight']!), alpha * active * .78)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2)
      ..blendMode = BlendMode.screen;
    for (var k = 0; k < branches; k++) {
      var a = k / branches * math.pi * 2 + math.sin(seed + k) * .18;
      var rr = unit * .015;
      final path = Path()..moveTo(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      for (var j = 1; j <= segments; j++) {
        rr = radius * (j / segments);
        a += math.sin(seed * 3 + k * 7 + j * 11) * .10;
        path.lineTo(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawRuneRing(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final r = _d(layer['radius'], .27) * unit * math.max(.25, q);
    final aspect = _d(layer['aspect'], .31);
    final count = _i(layer['count'], 16).clamp(4, 48);
    final speed = _d(layer['rotation_speed'], .55);
    final angle = t * math.pi * 2 * speed + _d(layer['offset'], 0);
    final color = _color(layer['color'], p['highlight']!);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _d(layer['width'], .8)
      ..color = _withAlpha(color, alpha * .48)
      ..blendMode = BlendMode.screen;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * aspect * 2), ringPaint);
    for (var i = 0; i < count; i++) {
      final a = i * math.pi * 2 / count;
      final x = math.cos(a) * r;
      final y = math.sin(a) * r * aspect;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(a + math.pi / 2);
      final s = unit * _d(layer['glyph_size'], .008);
      final path = Path()
        ..moveTo(-s, 0)
        ..lineTo(0, -s * 1.6)
        ..lineTo(s, 0)
        ..lineTo(0, s * 1.3)
        ..close();
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = .7..color = _withAlpha(color, alpha * .65)..blendMode = BlendMode.screen);
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawShardField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final target = _point(layer['target'], size, Offset(size.width * .94, c.dy));
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 18).clamp(3, 80);
    final radius = _d(layer['radius'], .34) * unit;
    final aspect = _d(layer['aspect'], .52);
    final speed = _d(layer['rotation_speed'], 1.7);
    final counter = _easeIn(_phase(t, _d(layer['launch_start'], .66), _d(layer['launch_end'], .92)));
    final seed = _i(layer['seed'], _i(spec['seed'], 31));
    for (var i = 0; i < count; i++) {
      final a = i * math.pi * 2 / count + t * (i.isEven ? speed : -speed);
      final wobble = math.sin(i * 2.1 + t * 8) * unit * .028;
      var pos = Offset(c.dx + math.cos(a) * (radius + wobble), c.dy + math.sin(a) * (radius + wobble) * aspect);
      if (counter > 0) {
        final lane = (i - (count - 1) / 2) * unit * .008;
        final tp = Offset(target.dx, target.dy + lane * .45);
        pos = Offset.lerp(pos, tp, counter)!;
      }
      _drawShard(canvas, pos, a, unit * (.010 + .010 * counter), alpha * .82, p);
    }
  }

  void _drawShard(Canvas canvas, Offset c, double angle, double scale,
      double alpha, Map<String, Color> p) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(scale * 2.2, 0)
      ..lineTo(-scale * .65, -scale * .48)
      ..lineTo(-scale * 1.5, 0)
      ..lineTo(-scale * .65, scale * .48)
      ..close();
    canvas.drawPath(path, Paint()..color = _withAlpha(p['primary']!, .34 * alpha)..blendMode = BlendMode.screen);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = .75..color = _withAlpha(p['highlight']!, .90 * alpha));
    canvas.restore();
  }

  void _drawStreakField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final active = _easeIn(_phase(t, _d(layer['active_start'], _d(layer['start'], .66)), _d(layer['active_end'], _d(layer['end'], .92))));
    if (active <= .001) return;
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 26).clamp(4, 90);
    final direction = _d(layer['direction'], 1.0).sign;
    final length = unit * (_d(layer['length'], .20) + active * _d(layer['growth'], .24));
    final spread = unit * _d(layer['spread'], .14);
    final headX = c.dx + direction * active * size.width * _d(layer['travel'], .43);
    final paint = Paint()..blendMode = BlendMode.screen..style = PaintingStyle.stroke;
    for (var i = 0; i < count; i++) {
      final lane = (i - (count - 1) / 2) / math.max(1, count - 1);
      final y = c.dy + lane * spread + math.sin(i * 3.7) * unit * .008;
      paint.color = _withAlpha(p['primary']!, alpha * (.07 + .23 * active));
      paint.strokeWidth = .5 + (i % 3) * .35;
      canvas.drawLine(Offset(headX - direction * length, y), Offset(headX, y), paint);
    }
  }

  void _drawCloudField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .5, size.height * .20));
    final count = _i(layer['count'], 20).clamp(4, 80);
    final rx = _d(layer['radius_x'], .30) * size.width;
    final ry = _d(layer['radius_y'], .11) * size.height;
    final speed = _d(layer['rotation_speed'], 2.1);
    final seed = _i(layer['seed'], 51);
    final color = _color(layer['color'], const Color(0xFF68717F));
    for (var i = 0; i < count; i++) {
      final a = t * speed + i * .87;
      final hash1 = ((i * 47 + seed) % 100) / 100;
      final hash2 = ((i * 23 + seed * 3) % 100) / 100;
      final rr = rx * (.3 + .7 * hash1);
      final pos = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a * 1.2) * ry * (.3 + .7 * hash2));
      final r = math.min(size.width, size.height) * (.075 + ((i * 29) % 45) / 1000);
      final shader = ui.Gradient.radial(pos, r, <Color>[
        _withAlpha(color, alpha * .065),
        _withAlpha(Colors.black, alpha * .07),
        Colors.transparent,
      ]);
      canvas.drawCircle(pos, r, (Paint()..shader = shader..blendMode = BlendMode.srcOver));
    }
  }

  void _drawVortexRings(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .5, size.height * .2));
    final count = _i(layer['count'], 10).clamp(1, 24);
    final unit = math.min(size.width, size.height);
    final baseRx = _d(layer['radius_x'], .13) * unit;
    final baseRy = _d(layer['radius_y'], .030) * unit;
    final spacing = _d(layer['spacing'], .045) * unit;
    final width = _d(layer['stroke_width'], 8.0);
    final rotation = t * _d(layer['rotation_speed'], .25);
    final color = _color(layer['color'], p['highlight']!);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    for (var i = 0; i < count; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.7, width + i * _d(layer['width_step'], 1.3))
        ..color = _withAlpha(color, alpha * (.03 + .055 * q))
        ..blendMode = _blend(layer['blend'] ?? 'screen');
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: (baseRx + i * spacing) * 2,
        height: (baseRy + i * spacing * .28) * 2,
      );
      final start = i * .45;
      canvas.drawArc(rect, start, math.pi * _d(layer['arc_turn'], 1.35), false, paint);
    }
    canvas.restore();
  }

  void _drawColossalLimb(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final kind = _s(layer['kind'], 'finger').toLowerCase();
    if (kind == 'hand') {
      _drawColossalHand(canvas, size, p, layer, q, alpha);
      return;
    }
    _drawColossalFinger(canvas, size, p, layer, q, alpha);
  }

  void _drawColossalFinger(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final unit = math.min(size.width, size.height);
    final c = _point(layer['center'], size, Offset(size.width * .63, size.height * .18));
    final fall = _easeIn(_phase(t, _d(layer['fall_start'], .42), _d(layer['fall_end'], .70)));
    final topY = c.dy + fall * size.height * _d(layer['fall_distance'], .31);
    final len = _d(layer['length'], .55) * size.height;
    final wid = _d(layer['width'], .13) * unit;
    final angle = _d(layer['angle'], -.10);
    final bodyA = _color(layer['body_dark'], const Color(0xFF2D221C));
    final bodyB = _color(layer['body_mid'], const Color(0xFF684E36));
    final rune = _color(layer['rune_color'], p['accent']!);

    canvas.save();
    canvas.translate(c.dx, topY);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(-wid * .48, 0)
      ..quadraticBezierTo(-wid * .76, len * .25, -wid * .61, len * .56)
      ..quadraticBezierTo(-wid * .55, len * .86, -wid * .32, len)
      ..quadraticBezierTo(0, len * 1.08, wid * .32, len)
      ..quadraticBezierTo(wid * .55, len * .86, wid * .61, len * .56)
      ..quadraticBezierTo(wid * .76, len * .25, wid * .48, 0)
      ..quadraticBezierTo(0, -wid * .40, -wid * .48, 0)
      ..close();
    final gradient = ui.Gradient.linear(
      Offset(-wid, 0),
      Offset(wid, len),
      <Color>[
        _withAlpha(bodyA, alpha),
        _withAlpha(bodyB, alpha),
        _withAlpha(Color.lerp(bodyA, bodyB, .35)!, alpha),
        _withAlpha(const Color(0xFF1B1716), alpha),
      ],
      const <double>[0, .32, .62, 1],
    );
    canvas.drawPath(path, Paint()..shader = gradient);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = _withAlpha(rune, .26 * alpha));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 10..color = _withAlpha(rune, .045 * alpha)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)..blendMode = BlendMode.screen);

    for (var k = 1; k <= 3; k++) {
      final y = len * (.20 + k * .19);
      final rw = wid * (.52 - k * .03);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, y), width: rw * 2, height: wid * .30),
        0,
        math.pi,
        false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 4.2..color = _withAlpha(const Color(0xFF100D0C), .55 * alpha),
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, y - 2), width: rw * 1.84, height: wid * .20),
        0,
        math.pi,
        false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = .8..color = _withAlpha(rune, .19 * alpha),
      );
    }
    for (var i = 0; i < _i(layer['crack_count'], 24).clamp(4, 50); i++) {
      final y = unit * .03 + (i * 83 % math.max(40, len.toInt() - 40));
      final x = (((i * 97) % 100) / 100 - .5) * wid * .72;
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + math.sin(i * 9) * unit * .02, y + unit * .025)
        ..lineTo(x + math.cos(i * 4) * unit * .032, y + unit * .045);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = .75..color = _withAlpha(rune, alpha * (.10 + .18 * math.pow(math.sin(t * 8 + i), 2)))..blendMode = BlendMode.screen);
    }
    canvas.restore();
  }

  void _drawColossalHand(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .62, size.height * .24));
    final unit = math.min(size.width, size.height);
    final fall = _easeIn(_phase(t, _d(layer['fall_start'], .38), _d(layer['fall_end'], .70)));
    final y = c.dy + fall * size.height * _d(layer['fall_distance'], .30);
    final palmW = unit * _d(layer['width'], .22);
    final palmH = unit * _d(layer['height'], .28);
    final body = _color(layer['body_mid'], const Color(0xFF654B35));
    final accent = _color(layer['rune_color'], p['accent']!);
    canvas.save();
    canvas.translate(c.dx, y);
    canvas.rotate(_d(layer['angle'], -.08));
    final palm = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: palmW, height: palmH),
      Radius.circular(palmW * .28),
    );
    canvas.drawRRect(palm, Paint()..color = _withAlpha(body, alpha));
    canvas.drawRRect(palm, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1..color = _withAlpha(accent, .26 * alpha));
    for (var i = 0; i < 5; i++) {
      final lane = (i - 2) * palmW * .19;
      final len = palmH * (.72 + (2 - (i - 2).abs()) * .08);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(lane - palmW * .07, -palmH * .52 - len, palmW * .14, len),
        Radius.circular(palmW * .07),
      );
      canvas.drawRRect(rect, Paint()..color = _withAlpha(Color.lerp(body, Colors.white, .07)!, alpha));
      canvas.drawRRect(rect, Paint()..style = PaintingStyle.stroke..strokeWidth = .7..color = _withAlpha(accent, .18 * alpha));
    }
    canvas.restore();
  }

  void _drawPressureRings(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .63, size.height * .76));
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 9).clamp(1, 20);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = _d(layer['width'], .8)..blendMode = BlendMode.screen;
    final color = _color(layer['color'], p['accent']!);
    for (var i = 0; i < count; i++) {
      final k = (i + 1) / count;
      final rx = unit * (_d(layer['base_rx'], .045) + k * _d(layer['grow_rx'], .36) * q);
      final ry = unit * (_d(layer['base_ry'], .010) + k * _d(layer['grow_ry'], .07) * q);
      paint.color = _withAlpha(color, alpha * (.035 + .08 * q));
      canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), paint);
    }
  }

  void _drawGround(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final y = _d(layer['y'], .76) * size.height;
    final top = _color(layer['top_color'], p['ground']!);
    final bottom = _color(layer['bottom_color'], const Color(0xFF080605));
    final shader = ui.Gradient.linear(Offset(0, y), Offset(0, size.height), <Color>[
      _withAlpha(top, .72 * alpha),
      _withAlpha(bottom, alpha),
    ]);
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, size.height - y), Paint()..shader = shader);
  }

  void _drawCrater(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .63, size.height * .76));
    final unit = math.min(size.width, size.height);
    final r = unit * (_d(layer['base_radius'], .08) + q * _d(layer['growth'], .30));
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2, height: r * _d(layer['aspect'], .48)),
      Paint()..color = _withAlpha(Colors.black, alpha * (.28 + .58 * q)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2, height: r * _d(layer['aspect'], .48)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 3.2..color = _withAlpha(_color(layer['rim_color'], const Color(0xFF845033)), .30 * alpha),
    );
    final cracks = _i(layer['cracks'], 30).clamp(4, 60);
    for (var k = 0; k < cracks; k++) {
      final a = k * math.pi * 2 / cracks + math.sin(k * 8) * .1;
      final len = r * (.8 + ((k * 31) % 40) / 100);
      final path = Path()
        ..moveTo(c.dx + math.cos(a) * r * .18, c.dy + math.sin(a) * r * .05)
        ..lineTo(c.dx + math.cos(a) * len, c.dy + math.sin(a) * len * .34);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = .8 + (k % 4) * .3..color = _withAlpha(_color(layer['crack_color'], const Color(0xFF78513A)), .27 * alpha));
    }
  }

  void _drawDebris(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size, Offset(size.width * .63, size.height * .76));
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 42).clamp(4, 120);
    final seed = _i(layer['seed'], 67);
    final rnd = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final a = -math.pi + rnd.nextDouble() * math.pi;
      final speed = unit * (.08 + rnd.nextDouble() * .25);
      final tt = q;
      final x = c.dx + math.cos(a) * speed * tt;
      final y = c.dy - unit * .015 - math.sin(a).abs() * speed * tt + tt * tt * unit * .14;
      final w = 2.0 + rnd.nextDouble() * 6;
      final h = 2.0 + rnd.nextDouble() * 4;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i + tt * 4);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w, height: h), Paint()..color = _withAlpha(_color(layer['color'], const Color(0xFF6C4A31)), .72 * alpha));
      canvas.restore();
    }
  }

  void _drawImpactFlash(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final r = unit * _d(layer['radius'], .36) * q;
    final color = _color(layer['color'], p['highlight']!);
    final shader = ui.Gradient.radial(c, math.max(1.0, r), <Color>[
      _withAlpha(color, .78 * alpha),
      _withAlpha(_color(layer['secondary'], p['accent']!), .10 * alpha),
      Colors.transparent,
    ]);
    canvas.drawCircle(c, math.max(1.0, r), (Paint()..shader = shader..blendMode = BlendMode.plus));
    final sparks = _i(layer['sparks'], 48).clamp(0, 100);
    for (var i = 0; i < sparks; i++) {
      final a = i * 2.399;
      final d = unit * (.06 + ((i * 47) % 240) / 1000) * q;
      final pos = Offset(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d * .35);
      canvas.drawCircle(pos, .8 + (i % 3) * .45, Paint()..color = _withAlpha(_color(layer['spark_color'], p['accent']!), .22 * alpha)..blendMode = BlendMode.plus);
    }
  }

  void _drawShockwave(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height);
    final count = _i(layer['count'], 4).clamp(1, 10);
    for (var i = 0; i < count; i++) {
      final local = _clamp(q * 1.25 - i * .10);
      final rx = unit * (_d(layer['base_radius'], .12) + _d(layer['growth'], .34) * local + i * .02);
      final ry = rx * _d(layer['aspect'], .62);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: rx * 2, height: ry * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.6, _d(layer['width'], 1.6) - i * .18)
          ..color = _withAlpha(_color(layer['color'], p['highlight']!), alpha * .28 * (1 - local))
          ..blendMode = BlendMode.screen,
      );
    }
  }

  void _drawBeam(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final from = _point(layer['from'], size, Offset(size.width * .18, size.height * .55));
    final to = _point(layer['to'], size, Offset(size.width * .84, size.height * .52));
    final head = Offset.lerp(from, to, q)!;
    final unit = math.min(size.width, size.height);
    final width = _d(layer['width'], .035) * unit;
    final dir = head - from;
    final len = dir.distance;
    if (len < 1) return;
    final angle = math.atan2(dir.dy, dir.dx);
    canvas.save();
    canvas.translate(from.dx, from.dy);
    canvas.rotate(angle);
    for (final entry in <(double, Color, double)>[
      (width * 3.2, p['primary']!, .10),
      (width * 1.8, p['secondary']!, .24),
      (width, p['primary']!, .62),
      (width * .30, p['highlight']!, .96),
    ]) {
      canvas.drawLine(
        Offset.zero,
        Offset(len, 0),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = entry.$1
          ..color = _withAlpha(entry.$2, entry.$3 * alpha)
          ..blendMode = BlendMode.plus
          ..maskFilter = entry.$1 > width ? const MaskFilter.blur(BlurStyle.normal, 5) : null,
      );
    }
    canvas.restore();
  }

  void _drawProjectileOrb(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final from = _point(layer['from'], size, Offset(size.width * .20, size.height * .55));
    final to = _point(layer['to'], size, Offset(size.width * .82, size.height * .52));
    final pos = Offset.lerp(from, to, q)!;
    final unit = math.min(size.width, size.height);
    final r = _d(layer['radius'], .035) * unit;
    _drawGlowDisc(canvas, pos, r * 4.2, p['primary']!, alpha * .38);
    _drawGlowDisc(canvas, pos, r * 2.1, p['secondary']!, alpha * .62);
    canvas.drawCircle(pos, r, Paint()..color = _withAlpha(p['highlight']!, .95 * alpha)..blendMode = BlendMode.plus);
    final tail = (pos - from);
    if (tail.distance > 3) {
      final n = tail / tail.distance;
      canvas.drawLine(pos - n * r * 5, pos, Paint()..strokeCap = StrokeCap.round..strokeWidth = r * .5..color = _withAlpha(p['primary']!, .45 * alpha)..blendMode = BlendMode.plus);
    }
  }

  void _drawRibbonField(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final from = _point(layer['from'], size, Offset(size.width * .20, size.height * .55));
    final to = _point(layer['to'], size, Offset(size.width * .82, size.height * .52));
    final count = _i(layer['count'], 5).clamp(1, 18);
    final unit = math.min(size.width, size.height);
    final amp = _d(layer['amplitude'], .06) * unit;
    final turns = _d(layer['turns'], 1.8);
    for (var j = 0; j < count; j++) {
      final path = Path();
      const steps = 28;
      for (var i = 0; i <= steps; i++) {
        final u = i / steps * q;
        final base = Offset.lerp(from, to, u)!;
        final phase = u * math.pi * 2 * turns + j * math.pi * 2 / count + t * 4;
        final y = math.sin(phase) * amp * (1 - .55 * u);
        final x = math.cos(phase * .7) * amp * .18;
        final pt = base + Offset(x, y);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = .7 + (j % 3) * .45..color = _withAlpha(Color.lerp(p['primary'], p['highlight'], j / math.max(1, count - 1))!, alpha * .34)..blendMode = BlendMode.screen);
    }
  }

  void _drawCreature(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final species = _s(layer['species'], 'phoenix').toLowerCase();
    if (species.contains('dragon') || species.contains('龙')) {
      _drawDragon(canvas, size, p, layer, q, alpha);
    } else {
      _drawPhoenix(canvas, size, p, layer, q, alpha);
    }
  }

  void _drawPhoenix(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final from = _point(layer['from'], size, Offset(size.width * .22, size.height * .56));
    final to = _point(layer['to'], size, Offset(size.width * .78, size.height * .48));
    final pos = Offset.lerp(from, to, q)!;
    final unit = math.min(size.width, size.height);
    final s = unit * _d(layer['scale'], .18) * (.65 + .35 * _ease(q));
    final dir = to - from;
    final angle = math.atan2(dir.dy, dir.dx);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);
    _drawGlowDisc(canvas, Offset.zero, s * 1.65, p['primary']!, alpha * .18);

    final body = Path()
      ..moveTo(-s * .45, 0)
      ..cubicTo(-s * .12, -s * .18, s * .24, -s * .16, s * .48, 0)
      ..cubicTo(s * .22, s * .16, -s * .12, s * .18, -s * .45, 0)
      ..close();
    final grad = ui.Gradient.linear(Offset(-s * .5, 0), Offset(s * .55, 0), <Color>[
      _withAlpha(p['accent']!, .45 * alpha),
      _withAlpha(p['primary']!, .82 * alpha),
      _withAlpha(p['highlight']!, .94 * alpha),
    ]);
    canvas.drawPath(body, (Paint()..shader = grad..blendMode = BlendMode.plus));

    final flap = math.sin(t * math.pi * 8) * .18;
    for (final side in <double>[-1, 1]) {
      for (var i = 0; i < 9; i++) {
        final a = side * (-.35 - i * .065 + flap * .12);
        final root = Offset(-s * .02, side * s * .04);
        _drawPetal(canvas, root, a, s * (.75 + i * .045), s * (.10 + i * .008), .88, alpha * (.72 - i * .035), p['accent']!, p['primary']!, p['highlight']!, BlendMode.plus);
      }
    }
    canvas.drawCircle(Offset(s * .42, -s * .04), s * .075, Paint()..color = _withAlpha(p['highlight']!, .9 * alpha)..blendMode = BlendMode.plus);
    final beak = Path()..moveTo(s * .48, -s * .06)..lineTo(s * .68, 0)..lineTo(s * .48, s * .04)..close();
    canvas.drawPath(beak, Paint()..color = _withAlpha(p['accent']!, .92 * alpha));
    for (var i = 0; i < 5; i++) {
      final path = Path()
        ..moveTo(-s * .38, 0)
        ..cubicTo(-s * .8, (i - 2) * s * .08, -s * 1.1, (i - 2) * s * .17, -s * 1.35, (i - 2) * s * .20);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 1.3 + (4 - i) * .35..color = _withAlpha(Color.lerp(p['accent'], p['primary'], i / 4)!, .48 * alpha)..blendMode = BlendMode.plus);
    }
    canvas.restore();
  }

  void _drawDragon(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final from = _point(layer['from'], size, Offset(size.width * .18, size.height * .58));
    final to = _point(layer['to'], size, Offset(size.width * .82, size.height * .50));
    final unit = math.min(size.width, size.height);
    final amp = _d(layer['amplitude'], .085) * unit;
    final turns = _d(layer['turns'], 1.65);
    final steps = _i(layer['segments'], 44).clamp(16, 80);
    final path = Path();
    Offset head = from;
    Offset prev = from;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps * q;
      final base = Offset.lerp(from, to, u)!;
      final wave = math.sin(u * math.pi * 2 * turns - t * 4.2) * amp * (1 - .4 * u);
      final pt = base + Offset(0, wave);
      if (i == 0) path.moveTo(pt.dx, pt.dy); else path.lineTo(pt.dx, pt.dy);
      prev = head;
      head = pt;
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = unit * .055..color = _withAlpha(p['primary']!, .10 * alpha)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)..blendMode = BlendMode.plus);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = unit * .026..color = _withAlpha(p['secondary']!, .58 * alpha)..blendMode = BlendMode.screen);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = unit * .010..color = _withAlpha(p['highlight']!, .74 * alpha)..blendMode = BlendMode.plus);
    final a = math.atan2(head.dy - prev.dy, head.dx - prev.dx);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(a);
    final hs = unit * .055;
    final headPath = Path()..moveTo(hs * .9, 0)..quadraticBezierTo(hs * .25, -hs * .55, -hs * .7, -hs * .32)..quadraticBezierTo(-hs * .45, 0, -hs * .7, hs * .32)..quadraticBezierTo(hs * .25, hs * .55, hs * .9, 0)..close();
    canvas.drawPath(headPath, Paint()..color = _withAlpha(p['primary']!, .72 * alpha)..blendMode = BlendMode.screen);
    canvas.drawPath(headPath, Paint()..style = PaintingStyle.stroke..strokeWidth = .9..color = _withAlpha(p['highlight']!, .82 * alpha));
    canvas.drawCircle(Offset(hs * .28, -hs * .13), hs * .055, Paint()..color = _withAlpha(p['accent']!, .92 * alpha)..blendMode = BlendMode.plus);
    for (final side in <double>[-1, 1]) {
      final horn = Path()..moveTo(-hs * .1, side * hs * .26)..quadraticBezierTo(-hs * .45, side * hs * .72, -hs * .92, side * hs * .65);
      canvas.drawPath(horn, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.1..color = _withAlpha(p['highlight']!, .70 * alpha));
    }
    canvas.restore();
  }

  void _drawBezierShape(Canvas canvas, Size size, Map<String, Color> p,
      Map<String, dynamic> layer, double q, double alpha) {
    final c = _point(layer['center'], size);
    final unit = math.min(size.width, size.height) * _d(layer['scale'], .25) * math.max(.05, q);
    final commands = _asList(layer['commands']);
    if (commands.isEmpty) return;
    final path = Path();
    for (final raw in commands) {
      final cmd = _asList(raw);
      if (cmd.isEmpty) continue;
      final op = _s(cmd[0]).toUpperCase();
      double x(int index) => c.dx + _d(cmd.length > index ? cmd[index] : 0) * unit;
      double y(int index) => c.dy + _d(cmd.length > index ? cmd[index] : 0) * unit;
      if (op == 'M' && cmd.length >= 3) path.moveTo(x(1), y(2));
      if (op == 'L' && cmd.length >= 3) path.lineTo(x(1), y(2));
      if (op == 'Q' && cmd.length >= 5) path.quadraticBezierTo(x(1), y(2), x(3), y(4));
      if (op == 'C' && cmd.length >= 7) path.cubicTo(x(1), y(2), x(3), y(4), x(5), y(6));
      if (op == 'Z') path.close();
    }
    final fill = _color(layer['fill'], p['primary']!);
    final stroke = _color(layer['stroke'], p['highlight']!);
    final blur = _d(layer['glow_blur'], 0);
    if (blur > 0) {
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = _d(layer['glow_width'], 8)..color = _withAlpha(fill, .18 * alpha)..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)..blendMode = BlendMode.plus);
    }
    if (_b(layer['filled'], true)) {
      canvas.drawPath(path, Paint()..color = _withAlpha(fill, _d(layer['fill_alpha'], .36) * alpha)..blendMode = _blend(layer['blend'] ?? 'screen'));
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = _d(layer['stroke_width'], 1.0)..color = _withAlpha(stroke, _d(layer['stroke_alpha'], .72) * alpha)..blendMode = _blend(layer['blend'] ?? 'screen'));
  }

  void _drawGlowDisc(Canvas canvas, Offset c, double r, Color color, double alpha) {
    final shader = ui.Gradient.radial(c, math.max(1.0, r), <Color>[
      _withAlpha(color, alpha),
      _withAlpha(color, alpha * .12),
      Colors.transparent,
    ]);
    canvas.drawCircle(c, math.max(1.0, r), (Paint()..shader = shader..blendMode = BlendMode.screen));
  }

  void _drawVignette(Canvas canvas, Size size) {
    final screen = _asMap(spec['screen_fx']);
    if (!_b(screen['vignette'], true)) return;
    final strength = _d(screen['vignette_strength'], .72).clamp(0.0, .95);
    final center = Offset(size.width * .5, size.height * .5);
    final radius = math.max(size.width, size.height) * .67;
    final shader = ui.Gradient.radial(
      center,
      radius,
      <Color>[
        Colors.transparent,
        Colors.transparent,
        Colors.black.withOpacity(strength),
      ],
      const <double>[0, .35, 1],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _VisualTargetPainter oldDelegate) =>
      !identical(oldDelegate.spec, spec) ||
      oldDelegate.animation != animation ||
      oldDelegate.transparentBackground != transparentBackground ||
      oldDelegate.drawVignette != drawVignette;
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'novel_game_controller.dart';
import 'novel_models.dart';

class NovelPalette {
  // 与 app_shared.dart / share_world_page.dart 对齐。
  static const Color background = Color(0xFF15131C);
  static const Color panel = Color.fromARGB(25, 253, 253, 253);
  static const Color panelStrong = Color.fromARGB(34, 253, 253, 253);
  static const Color text = Color(0xFFF5F1E6);
  static const Color muted = Color(0xFF8B8796);
  static const Color accent = Color.fromARGB(255, 129, 246, 112);
  static const Color accentDark = Color(0xFF10160F);
  static const Color warning = Color(0xFFE8C58B);
  static const Color danger = Color(0xFFE7685E);
}



/// 流式文本在网络 chunk 边界被错误解码时，偶尔会短暂出现 U+FFFD（�）。
/// 最终完整响应到达后通常又会恢复正常，所以显示层先过滤这些无效占位符，
/// 避免用户在流式过程中看到“方框/叉号”。
String _sanitizeNovelStreamingText(String value) {
  if (value.isEmpty) return value;
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0xFFFD || rune == 0x0000 || rune == 0xFEFF) {
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}


/// 后端已经把 dialogue.currentSentence 整理成最终展示格式：
///   （动作/神态/语气）真正对白
/// Flutter 不再理解小说语义，只负责把后端约定的全角括号区间做视觉降级。
/// 逐字动画尚未出现右括号时，从左括号到当前末尾也保持淡色，避免闪烁。
List<InlineSpan> _buildNovelDialogueDisplaySpans(
  String value,
  TextStyle baseStyle,
) {
  if (value.isEmpty) {
    return <InlineSpan>[TextSpan(text: value, style: baseStyle)];
  }

  final stageStyle = baseStyle.copyWith(
    color: (baseStyle.color ?? const Color(0xFFF7F7F7)).withOpacity(.58),
    fontWeight: FontWeight.w400,
    shadows: const <Shadow>[
      Shadow(color: Color(0xB0000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
  );

  final spans = <InlineSpan>[];
  var cursor = 0;

  while (cursor < value.length) {
    final open = value.indexOf('（', cursor);
    if (open < 0) {
      spans.add(TextSpan(text: value.substring(cursor), style: baseStyle));
      break;
    }

    if (open > cursor) {
      spans.add(TextSpan(text: value.substring(cursor, open), style: baseStyle));
    }

    final close = value.indexOf('）', open + 1);
    if (close < 0) {
      spans.add(TextSpan(text: value.substring(open), style: stageStyle));
      break;
    }

    spans.add(
      TextSpan(
        text: value.substring(open, close + 1),
        style: stageStyle,
      ),
    );
    cursor = close + 1;
  }

  return spans;
}

bool _useLowPowerNovelEffects(BuildContext context) {
  final media = MediaQuery.of(context);
  // 手机（含横屏）优先稳定帧率；平板/桌面继续保留完整毛玻璃与背景缓动。
  return media.size.shortestSide < 600 || media.disableAnimations;
}

class _AdaptiveBackdropBlur extends StatelessWidget {
  const _AdaptiveBackdropBlur({
    required this.sigma,
    required this.child,
  });

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (_useLowPowerNovelEffects(context) || sigma <= 0) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

/// 按 Unicode code point 截取，而不是用 String.substring 的 UTF-16 code unit。
/// 这样不会把 emoji / 扩展字符截成半个代理对，避免逐字动画产生临时乱码。
String _novelPrefixByRunes(String value, int count) {
  if (value.isEmpty || count <= 0) return '';
  final runes = value.runes.toList(growable: false);
  final safeCount = count.clamp(0, runes.length);
  return String.fromCharCodes(runes.take(safeCount));
}

class NovelArtwork extends StatelessWidget {
  const NovelArtwork({
    super.key,
    this.url = '',
    this.assetCandidates = const <String>[],
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackIcon = Icons.image_outlined,
    this.fallbackText = '',
    this.filterQuality = FilterQuality.medium,
  });

  final String url;
  final List<String> assetCandidates;
  final BoxFit fit;
  final Alignment alignment;
  final IconData fallbackIcon;
  final String fallbackText;
  final FilterQuality filterQuality;

  Widget _fallback() {
    return ColoredBox(
      color: Colors.white.withOpacity(.025),
      child: Center(
        child: fallbackText.trim().isNotEmpty
            ? Text(
                String.fromCharCode(fallbackText.trim().runes.first),
                style: TextStyle(
                  color: NovelPalette.text.withOpacity(.48),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(
                fallbackIcon,
                size: 20,
                color: NovelPalette.muted.withOpacity(.58),
              ),
      ),
    );
  }

  Widget _assetAt(int index) {
    if (index >= assetCandidates.length) return _fallback();
    final asset = assetCandidates[index].trim();
    if (asset.isEmpty) return _assetAt(index + 1);
    return Image.asset(
      asset,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _assetAt(index + 1),
    );
  }

  Widget _remoteOrAsset() {
    final value = url.trim();
    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _assetAt(0),
        );
      } catch (_) {
        return _assetAt(0);
      }
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _assetAt(0),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _assetAt(0),
      );
    }
    return _assetAt(0);
  }

  @override
  Widget build(BuildContext context) => _remoteOrAsset();
}

class _StagePortraitArtwork extends StatelessWidget {
  const _StagePortraitArtwork({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.filterQuality = FilterQuality.medium,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final value = url.trim();
    if (value.isEmpty) return const SizedBox.shrink();

    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return Image.asset(
      value,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

enum NovelWeatherEffect { none, rain, snow, thunderstorm }

extension NovelWeatherEffectLabel on NovelWeatherEffect {
  String get label {
    return switch (this) {
      NovelWeatherEffect.none => '无',
      NovelWeatherEffect.rain => '雨',
      NovelWeatherEffect.snow => '雪',
      NovelWeatherEffect.thunderstorm => '雷雨',
    };
  }

  IconData get icon {
    return switch (this) {
      NovelWeatherEffect.none => Icons.wb_sunny_outlined,
      NovelWeatherEffect.rain => Icons.water_drop_outlined,
      NovelWeatherEffect.snow => Icons.ac_unit_rounded,
      NovelWeatherEffect.thunderstorm => Icons.thunderstorm_outlined,
    };
  }
}

class NovelWeatherOverlay extends StatefulWidget {
  const NovelWeatherOverlay({
    super.key,
    required this.effect,
  });

  final NovelWeatherEffect effect;

  @override
  State<NovelWeatherOverlay> createState() => _NovelWeatherOverlayState();
}

class _NovelWeatherOverlayState extends State<NovelWeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = MediaQuery.of(context).disableAnimations;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant NovelWeatherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect != widget.effect) {
      _syncAnimation(reset: true);
    }
  }

  void _syncAnimation({bool reset = false}) {
    if (_animationsDisabled || widget.effect == NovelWeatherEffect.none) {
      _controller.stop();
      if (reset) _controller.value = 0;
      return;
    }
    if (reset) _controller.value = 0;
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.effect == NovelWeatherEffect.none) {
      return const SizedBox.shrink();
    }

    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _NovelWeatherPainter(
                effect: widget.effect,
                phase: _animationsDisabled ? .18 : _controller.value,
                compact: compact,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _NovelWeatherPainter extends CustomPainter {
  const _NovelWeatherPainter({
    required this.effect,
    required this.phase,
    required this.compact,
  });

  final NovelWeatherEffect effect;
  final double phase;
  final bool compact;

  static double _hash(int index, int salt) {
    final value = math.sin(index * 127.1 + salt * 311.7) * 43758.5453123;
    return value - value.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    switch (effect) {
      case NovelWeatherEffect.none:
        return;
      case NovelWeatherEffect.rain:
        _paintRain(canvas, size);
        return;
      case NovelWeatherEffect.snow:
        _paintSnow(canvas, size);
        return;
      case NovelWeatherEffect.thunderstorm:
        _paintThunderstorm(canvas, size);
        return;
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    // 雨丝尽量细、透明、分层。重点是“空气里有雨”，而不是满屏白色直线。
    final hazePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0x11283B49),
          const Color(0x061B2831),
          const Color(0x0D33444F),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, hazePaint);

    final count = compact ? 118 : 176;
    final backPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x35D6E8F4);
    final midPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x58E1EEF7);
    final frontPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x72EDF6FC);

    for (var i = 0; i < count; i++) {
      final depth = _hash(i, 1);
      final lane = _hash(i, 2);
      final seed = _hash(i, 3);
      final speedTurns = 1 + (_hash(i, 4) * 3).floor();
      final travel = (seed + phase * speedTurns) % 1.0;

      final length = 7.0 + depth * 21.0;
      final y = travel * (size.height + length + 24) - length - 12;
      final wind = 6.0 + depth * 14.0;
      final xBase = lane * (size.width + 48) - 24;
      final x = xBase + travel * wind;

      final paint = depth < .38
          ? backPaint
          : depth < .82
              ? midPaint
              : frontPaint;
      // 绝大多数雨丝都控制在 1px 以下，避免“粉笔线”质感。
      paint.strokeWidth = .28 + depth * .56;

      canvas.drawLine(
        Offset(x, y),
        Offset(x + 2.2 + depth * 4.5, y + length),
        paint,
      );
    }

    // 只留极少数镜头前雨丝，避免近景粗线让画面显假。
    final softPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x30FFFFFF)
      ..strokeWidth = 1.15
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.35);
    for (var i = 0; i < (compact ? 3 : 5); i++) {
      final seed = _hash(i, 21);
      final travel = (seed + phase * (1 + (i % 2))) % 1.0;
      final x = _hash(i, 22) * size.width + travel * 12;
      final y = travel * (size.height + 88) - 54;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 7, y + 48),
        softPaint,
      );
    }
  }

  void _paintThunderstorm(Canvas canvas, Size size) {
    // 雷雨以细雨为基础，不把雨丝突然做粗；主要靠密度、暗部和闪电体现强度。
    _paintRain(canvas, size);

    final extraPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x45DDEBF4);
    final extraCount = compact ? 54 : 82;
    for (var i = 0; i < extraCount; i++) {
      final depth = _hash(i, 71);
      final seed = _hash(i, 72);
      final travel = (seed + phase * (2 + (i % 3))) % 1.0;
      final length = 10.0 + depth * 25.0;
      final x = _hash(i, 73) * (size.width + 40) - 20 + travel * 18;
      final y = travel * (size.height + 56) - 34;
      extraPaint.strokeWidth = .34 + depth * .52;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 3 + depth * 5, y + length),
        extraPaint,
      );
    }

    // 12 秒循环里安排几组不等距闪光；双闪比固定“亮一下”自然得多。
    final seconds = phase * 12.0;
    double pulse(double center, double width) {
      final d = (seconds - center).abs();
      if (d >= width) return 0;
      final x = 1 - d / width;
      return Curves.easeOut.transform(x);
    }

    final flash = math.max(
      math.max(pulse(1.15, .11), pulse(1.34, .07) * .58),
      math.max(pulse(6.05, .09), pulse(9.72, .13) * .78),
    );
    if (flash <= 0) return;

    final flashPaint = Paint()
      ..color = const Color(0xFFD9E8FF).withOpacity((flash * .28).clamp(0.0, .28).toDouble());
    canvas.drawRect(Offset.zero & size, flashPaint);

    // 只有最强的一组闪光出现可见闪电枝杈，避免每次都像贴图特效。
    if (pulse(6.05, .09) > .35) {
      final bolt = Path()
        ..moveTo(size.width * .72, -8)
        ..lineTo(size.width * .67, size.height * .16)
        ..lineTo(size.width * .70, size.height * .25)
        ..lineTo(size.width * .63, size.height * .43)
        ..lineTo(size.width * .66, size.height * .50);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5.5
        ..color = const Color(0x667EAEFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.15
        ..color = const Color(0xE8EFF6FF);
      canvas.drawPath(bolt, glow);
      canvas.drawPath(bolt, core);
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final veilPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0x0AFFFFFF),
          Colors.transparent,
          const Color(0x102A3540),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, veilPaint);

    final count = compact ? 72 : 108;
    final crispPaint = Paint()..style = PaintingStyle.fill;
    final softPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);

    for (var i = 0; i < count; i++) {
      final depth = _hash(i, 31);
      final seed = _hash(i, 32);
      final speedTurns = depth > .72 ? 2 : 1;
      final travel = (seed + phase * speedTurns) % 1.0;

      final radius = .85 + depth * 2.65;
      final fallY = travel * (size.height + 42) - 22;
      final amplitude = 7 + depth * 24;
      final frequency = 1.0 + _hash(i, 33) * 1.8;
      final sway = math.sin(
            phase * math.pi * 2 * frequency + _hash(i, 34) * math.pi * 2,
          ) *
          amplitude;
      final x = _hash(i, 35) * size.width + sway;

      final opacity = .30 + depth * .58;
      final paint = depth > .82 ? softPaint : crispPaint;
      paint.color = Colors.white.withOpacity(opacity.clamp(0.0, .88).toDouble());

      canvas.drawCircle(Offset(x, fallY), radius, paint);

      // 少量近景雪片不是完美圆点，略带椭圆拖尾，更像镜头前的真实飘雪。
      if (depth > .90) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x + radius * .8, fallY + radius * 1.4),
            width: radius * 1.15,
            height: radius * 2.5,
          ),
          paint,
        );
      }
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    // 基础空气雾，不做纯白蒙版，保留背景层次。
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0x163B4650),
          const Color(0x244E5961),
          const Color(0x18364048),
        ],
        stops: const <double>[0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, basePaint);

    final angle = phase * math.pi * 2;
    for (var i = 0; i < 7; i++) {
      final depth = i / 6.0;
      final direction = i.isEven ? 1.0 : -1.0;
      final drift = math.sin(angle + i * .83) * size.width * (.08 + depth * .05);
      final lift = math.cos(angle * .72 + i * 1.17) * size.height * .035;
      final center = Offset(
        size.width * (.14 + _hash(i, 52) * .72) + drift * direction,
        size.height * (.18 + _hash(i, 53) * .68) + lift,
      );
      final width = size.width * (.58 + depth * .48);
      final height = size.height * (.16 + depth * .12);
      final opacity = .035 + depth * .045;

      final fogPaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withOpacity(opacity),
            const Color(0x124D5961),
            Colors.transparent,
          ],
          stops: const <double>[0, .46, 1],
        ).createShader(
          Rect.fromCenter(
            center: center,
            width: width,
            height: height,
          ),
        );

      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: width,
          height: height,
        ),
        fogPaint,
      );
    }

    // 地面附近再加一层慢雾，让场景有纵深，而不是整屏发白。
    final groundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.transparent,
          const Color(0x0FFFFFFF),
          const Color(0x2BFFFFFF),
        ],
        stops: const <double>[0, .55, 1],
      ).createShader(
        Rect.fromLTWH(0, size.height * .48, size.width, size.height * .52),
      );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * .48, size.width, size.height * .52),
      groundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NovelWeatherPainter oldDelegate) {
    return oldDelegate.effect != effect ||
        oldDelegate.phase != phase ||
        oldDelegate.compact != compact;
  }
}

class NovelWorldBackground extends StatefulWidget {
  const NovelWorldBackground({
    super.key,
    required this.url,
    this.fallbackAsset = 'assets/images/home_background.jpg',
    this.characterPresent = false,
    this.isGenerating = false,
    this.weatherEffect = NovelWeatherEffect.none,
  });

  final String url;
  final String fallbackAsset;
  final bool characterPresent;
  final bool isGenerating;
  final NovelWeatherEffect weatherEffect;

  @override
  State<NovelWorldBackground> createState() => _NovelWorldBackgroundState();
}

class _NovelWorldBackgroundState extends State<NovelWorldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  bool _lowPowerEffects = false;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final nextLowPower = media.size.shortestSide < 600;
    final nextAnimationsDisabled = media.disableAnimations;

    _lowPowerEffects = nextLowPower;
    _animationsDisabled = nextAnimationsDisabled;

    // 手机端也保留背景运动。手机只关闭昂贵的持续模糊，
    // 使用更小幅度的 translate + scale 来保持流畅与“活起来”的感觉。
    if (_animationsDisabled) {
      _motionController
        ..stop()
        ..value = .5;
    } else if (!_motionController.isAnimating) {
      _motionController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  Widget _fallback() {
    return Image.asset(
      widget.fallbackAsset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF343027),
                Color(0xFF171A17),
                Color(0xFF080908),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _image() {
    final value = widget.url.trim();
    if (value.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(value.split(',').last);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      } catch (_) {}
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  @override
  Widget build(BuildContext context) {
    final dim = widget.characterPresent ? .12 : .08;
    final blur = widget.characterPresent ? 2.2 : 0.0;

    final imageLayer = AnimatedSwitcher(
      duration: Duration(milliseconds: _lowPowerEffects ? 650 : 1200),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: SizedBox.expand(
        key: ValueKey<String>(widget.url),
        child: _image(),
      ),
    );

    final backgroundLayer = AnimatedBuilder(
      animation: _motionController,
      child: imageLayer,
      builder: (context, child) {
        final raw = _animationsDisabled ? .5 : _motionController.value;
        final t = Curves.easeInOut.transform(raw);
        final breathe = math.sin(t * math.pi);

        final scale = _lowPowerEffects
            ? 1.035 + breathe * .012
            : 1.052 + breathe * .016;
        final dx = _lowPowerEffects ? 9 - 18 * t : 14 - 28 * t;
        final dy = _lowPowerEffects ? 5 - 10 * t : 8 - 16 * t;

        Widget movingChild = child ?? const SizedBox.shrink();
        if (!_lowPowerEffects && blur > 0) {
          movingChild = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: movingChild,
          );
        }

        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: movingChild,
          ),
        );
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipRect(
          child: RepaintBoundary(child: backgroundLayer),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 760),
          curve: Curves.easeOutCubic,
          color: Colors.black.withOpacity(dim),
        ),
        if (widget.weatherEffect != NovelWeatherEffect.none)
          NovelWeatherOverlay(effect: widget.weatherEffect),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const <double>[0, .16, .56, .80, 1],
              colors: <Color>[
                Colors.black54,
                Colors.transparent,
                Colors.transparent,
                Color(0x42000000),
                Color(0xD6000000),
              ],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.12),
              radius: 1.03,
              stops: <double>[.46, .82, 1],
              colors: <Color>[
                Colors.transparent,
                Color(0x26000000),
                Color(0xA0000000),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: widget.isGenerating ? .18 : .07,
            duration: const Duration(milliseconds: 600),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0x16FFFFFF),
                    Colors.transparent,
                    Color(0x12000000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NovelTopHud extends StatelessWidget {
  const NovelTopHud({
    super.key,
    required this.controller,
    required this.onMenu,
    required this.onOpenProfile,
    required this.onOpenSettings,
  });

  final NovelGameController controller;
  final VoidCallback onMenu;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final generating = controller.isGenerating;
    return AnimatedOpacity(
      opacity: generating ? .42 : 1,
      duration: const Duration(milliseconds: 420),
      child: SizedBox(
        height: 48,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _TopIconButton(
                    tooltip: '菜单',
                    icon: Icons.menu_rounded,
                    onTap: onMenu,
                    size: 21,
              ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onOpenProfile,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _ConditionAvatar(
                            url: controller.protagonist?.avatarUrl ??
                                controller.scenario?.hostAvatarUrl ??
                                '',
                            hp: controller.protagonistHp,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 78),
                                child: Text(
                                  controller.protagonistName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: NovelPalette.text,
                                    fontSize: 12.5,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              _HealthBar(progress: controller.protagonistHp / 100),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _TopIconButton(
                tooltip: '设置',
                icon: Icons.more_horiz_rounded,
                onTap: onOpenSettings,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NovelLocationHud extends StatelessWidget {
  const NovelLocationHud({
    super.key,
    required this.title,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    if (title.trim().isEmpty && subtitle.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final compact = MediaQuery.sizeOf(context).width < 430;
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 235 : 330),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 2,
              height: subtitle.trim().isEmpty ? 22 : 34,
              margin: const EdgeInsets.only(top: 1, right: 8),
              decoration: BoxDecoration(
                color: NovelPalette.accent.withOpacity(.72),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (subtitle.trim().isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.46),
                        fontSize: 8.5,
                        height: 1.05,
                        letterSpacing: 1.0,
                        shadows: const <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 8),
                        ],
                      ),
                    ),
                  if (subtitle.trim().isNotEmpty) const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: NovelPalette.text,
                      fontSize: 13.2,
                      height: 1.08,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .45,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black87, blurRadius: 9),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.size = 20,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: Icon(
                icon,
                size: size,
                color: Colors.white.withOpacity(.88),
                shadows: const <Shadow>[
                  Shadow(color: Color(0xAA000000), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConditionAvatar extends StatelessWidget {
  const _ConditionAvatar({required this.url, required this.hp});
  final String url;
  final int hp;

  Color get color {
    if (hp <= 15) return const Color(0xFFC15CFF);
    if (hp <= 40) return const Color(0xFFEF5D5D);
    if (hp <= 75) return const Color(0xFFF2B648);
    return NovelPalette.accent;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      // ✨ 1. 外层 padding 控制彩色光圈的真实厚度（1.8 粗细适中）
      padding: const EdgeInsets.all(1.8), 
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: <Color>[
            color.withOpacity(.85),
            color.withOpacity(.30),
            color.withOpacity(.85),
          ],
        ),
        boxShadow: <BoxShadow>[BoxShadow(color: color.withOpacity(.22), blurRadius: 8)],
      ),
      child: Container(
        // ✨ 2. 内层 padding 负责把头像往里挤，让头像变小，并和光圈产生呼吸感间距
        padding: const EdgeInsets.all(1.5), 
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // ✨ 3. 垫一层较深的半透明黑底。这一层非常关键，它挡住了底下的渐变色，保证光圈不会视觉上发胖，同时依然能承托透明底的立绘
          color: Colors.black.withOpacity(0.65), 
        ),
        child: ClipOval(
          child: url.trim().isEmpty
              ? ColoredBox(
                  color: Colors.white.withOpacity(.08),
                  child: Icon(Icons.person_rounded, color: Colors.white.withOpacity(.4), size: 18),
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: Colors.white.withOpacity(.08),
                    child: Icon(Icons.person_rounded, color: Colors.white.withOpacity(.4), size: 18),
                  ),
                ),
        ),
      ),
    );
  }
}

class NovelSceneArrivalTitle extends StatelessWidget {
  const NovelSceneArrivalTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('$title|$subtitle'),
      duration: const Duration(milliseconds: 2800),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        final opacity = value < .18
            ? value / .18
            : value > .72
                ? (1 - value) / .28
                : 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(-12.0 * (1.0 - value.clamp(0.0, .3).toDouble() / .3), 8.0 * (1.0 - value.clamp(0.0, .3).toDouble() / .3)),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF7F3EA),
              fontSize: 46,
              // 中文场景标题不要把行高压得低于 1，避免上下笔画被裁掉。
              height: 1.12,
              fontWeight: FontWeight.w500,
              letterSpacing: 4,
              // 不再给场景大标题铺大面积黑色阴影，文字直接显示在场景背景上。
              shadows: <Shadow>[
                Shadow(color: Color(0x52000000), blurRadius: 5, offset: Offset(0, 1)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 36, height: 1, color: Colors.white.withOpacity(.68)),
              const SizedBox(width: 12),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(.74),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NovelPortraitStage extends StatelessWidget {
  const NovelPortraitStage({
    super.key,
    required this.url,
    required this.visible,
    required this.isSpeaking,
    this.alignRight = false,
    this.gender = '',
  });

  final String url;
  final bool visible;
  final bool isSpeaking;
  final bool alignRight;
  final String gender;

  String get _defaultPortraitAsset {
    final normalized = gender.trim().toLowerCase();
    if (normalized == '男' || normalized == 'male' || normalized == 'm') {
      return 'assets/images/portrait_male.png';
    }
    return 'assets/images/portrait_female.png';
  }

  Widget _defaultPortrait() {
    return Image.asset(
      _defaultPortraitAsset,
      // 500×800 的角色图统一按“半身窗口”裁剪，而不是完整缩小。
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _portraitImage() {
    final value = url.trim();
    if (value.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(value.split(',').last),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _defaultPortrait(),
        );
      } catch (_) {
        return _defaultPortrait();
      }
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _defaultPortrait(),
      );
    }
    if (value.isNotEmpty) {
      return Image.asset(
        value,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _defaultPortrait(),
      );
    }
    return _defaultPortrait();
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 520;

    // NPC 靠左，玩家/主角靠右。
    final alignment = alignRight ? Alignment.bottomRight : Alignment.bottomLeft;
    final beginOffset =
        alignRight ? const Offset(.055, .018) : const Offset(-.055, .018);

    // 这里是以后最常调的两个参数：
    // widthFactor 越大，人物越大；aspectRatio 越大，纵向裁剪越狠。
    // 500×800 立绘用接近 1:1 的裁剪窗口，大约保留上方 60%～65%，
    // 会得到头部到腰/大腿附近的视觉小说半身构图。
    final widthFactor = compact ? .86 : .62;
    final cropAspectRatio = compact ? .98 : 1.02;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: EdgeInsets.only(
            left: alignRight ? 0 : (compact ? 4 : 24),
            right: alignRight ? (compact ? 4 : 24) : 0,
          ),
          child: Align(
            alignment: alignment,
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              alignment: alignment,
              child: AspectRatio(
                aspectRatio: cropAspectRatio,
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 430),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: beginOffset,
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
                      );
                    },
                    child: AnimatedScale(
                      key: ValueKey<String>('${url.trim()}|${gender.trim()}'),
                      // 说话时只给非常轻微的呼吸感，不再额外把人物放大一圈。
                      scale: isSpeaking ? 1.006 : 1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: SizedBox.expand(
                        child: _portraitImage(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NovelDialogPanel extends StatefulWidget {
  const NovelDialogPanel({
    super.key,
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onContinue,
    required this.onForceContinue,
    required this.onOpenChoices,
    required this.onOpenInventory,
    required this.onOpenCharacters,
    required this.onOpenJourney,
    required this.onRevert,
    this.onOpenPortrait,
  });

  final NovelGameController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onContinue;
  final VoidCallback onForceContinue;
  final VoidCallback onOpenChoices;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCharacters;
  final VoidCallback onOpenJourney;
  final VoidCallback onRevert;
  final VoidCallback? onOpenPortrait;

  @override
  State<NovelDialogPanel> createState() => _NovelDialogPanelState();
}

enum _NovelLineMode { narration, npc, protagonist }

class _NovelDialogPanelState extends State<NovelDialogPanel>
    with SingleTickerProviderStateMixin {
  Timer? _revealTimer;
  int _visibleLength = 0;
  String _lastIdentity = '';
  String _lastFullText = '';
  late final ValueNotifier<String> _displayTextNotifier;
  bool _revealing = false;
  bool _showSwipeHint = true;
  Timer? _swipeHintTimer;
  double _horizontalDragDistance = 0;
  double _swipeVisualOffset = 0;
  bool _swipeTransitioning = false;
  late final AnimationController _swipeController;

  NovelGameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _displayTextNotifier = ValueNotifier<String>('');
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _syncReveal(force: true);
    _swipeHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showSwipeHint) {
        setState(() => _showSwipeHint = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant NovelDialogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncReveal();
  }

  // _syncReveal 会在句子变化时更新缓存。逐字动画期间直接读缓存，
  // 避免每 30ms 重跑 sanitize/正则与 Unicode 遍历。
  String get _fullText => _lastFullText;

  int get _fullRuneLength => _fullText.runes.length;

  void _publishVisibleText() {
    final next = _visibleLength >= _fullRuneLength
        ? _fullText
        : _novelPrefixByRunes(_fullText, _visibleLength);
    if (_displayTextNotifier.value != next) {
      _displayTextNotifier.value = next;
    }
  }

  void _syncReveal({bool force = false}) {
    final sentence = controller.currentSentence;
    // 后端已输出最终可展示的 currentSentence；前端不再做角色名/动作/引号解析。
    final full = _sanitizeNovelStreamingText(sentence?.text.trim() ?? '');
    final identity =
        '${controller.currentSentenceIndex}|${sentence?.speakerName ?? ''}|${sentence?.type ?? ''}';

    if (force || identity != _lastIdentity) {
      _lastIdentity = identity;
      _lastFullText = full;
      _revealTimer?.cancel();
      _revealTimer = null;
      _visibleLength = 0;
      _displayTextNotifier.value = '';
      _revealing = full.isNotEmpty;
      _scheduleReveal();
      return;
    }

    // SSE 继续补长同一句时保留已经打出的部分，不闪回。
    // 原代码拿 full.length 和实时 _fullText.length 比较，两者其实是同一个值，
    // 导致流式补长后 timer 已结束时无法重新启动。
    if (full != _lastFullText) {
      final previousLength = _lastFullText.runes.length;
      final nextLength = full.runes.length;
      _lastFullText = full;

      if (_visibleLength > nextLength) {
        _visibleLength = nextLength;
        _publishVisibleText();
      }

      if (nextLength > previousLength &&
          _visibleLength < nextLength &&
          _revealTimer == null) {
        _revealing = true;
        _scheduleReveal();
      }
    }
  }

  void _scheduleReveal() {
    _revealTimer?.cancel();

    final runes = _fullText.runes.toList(growable: false);
    if (!mounted || _visibleLength >= runes.length) {
      _revealTimer = null;
      if (_revealing && mounted) {
        setState(() => _revealing = false);
      }
      return;
    }

    const punctuation = '，。！？；：、…,.!?;:';
    _revealTimer = Timer(const Duration(milliseconds: 30), () {
      if (!mounted) return;

      final latestRunes = _fullText.runes.toList(growable: false);
      if (latestRunes.isEmpty || _visibleLength >= latestRunes.length) {
        _finishReveal();
        return;
      }

      final current =
          String.fromCharCode(latestRunes[_visibleLength.clamp(0, latestRunes.length - 1)]);
      final step = punctuation.contains(current) ? 1 : 2;

      _visibleLength =
          (_visibleLength + step).clamp(0, latestRunes.length);
      _publishVisibleText();

      if (_visibleLength >= latestRunes.length) {
        _finishReveal();
      } else {
        _scheduleReveal();
      }
    });
  }

  void _finishReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (mounted) setState(() => _revealing = false);
  }

  void _handleStoryTap() {
    if (_revealing) {
      _visibleLength = _fullRuneLength;
      _publishVisibleText();
      _finishReveal();
      return;
    }
    if (controller.hasNext || controller.pendingFateRevert) {
      controller.goNext();
    }
  }

  double _swipeLimit(double width) =>
      (width * .22).clamp(72.0, 126.0).toDouble();

  Widget _withSwipeMotion(Widget child, double width) {
    final progress =
        (_swipeVisualOffset.abs() / _swipeLimit(width)).clamp(0.0, 1.0);
    final opacity = (1.0 - progress * .20).clamp(.80, 1.0).toDouble();

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(_swipeVisualOffset, 0),
        child: child,
      ),
    );
  }

  Future<void> _animateSwipeTo(
    double target, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (!mounted) return;

    _swipeController.stop();
    _swipeController.duration = duration;
    final begin = _swipeVisualOffset;
    final animation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _swipeController, curve: curve),
    );

    void tick() {
      if (!mounted) return;
      setState(() => _swipeVisualOffset = animation.value);
    }

    _swipeController.addListener(tick);
    try {
      await _swipeController.forward(from: 0);
    } finally {
      _swipeController.removeListener(tick);
    }
  }

  Future<void> _springSwipeBack() async {
    if (_swipeTransitioning) return;
    _swipeTransitioning = true;
    try {
      await _animateSwipeTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _horizontalDragDistance = 0;
      _swipeTransitioning = false;
    }
  }

  Future<void> _commitSwipe(int direction) async {
    if (_swipeTransitioning || !mounted) return;

    final canMove = direction < 0 ? controller.hasNext : controller.hasPrevious;
    if (!canMove) {
      await _springSwipeBack();
      return;
    }

    _swipeTransitioning = true;
    _swipeHintTimer?.cancel();
    if (_showSwipeHint && mounted) {
      setState(() => _showSwipeHint = false);
    }

    // 横滑是明确的翻页动作，不再被逐字动画吞掉。
    // 离场时保持当前已显示文字，不突然补全整句，视觉更稳定。
    if (_revealing) {
      _finishReveal();
    }

    final width = MediaQuery.sizeOf(context).width;
    final exit = _swipeLimit(width) * (direction < 0 ? -1 : 1);

    try {
      // 旧内容顺着手势方向短距离离场 + 轻微淡出。
      await _animateSwipeTo(
        exit,
        duration: const Duration(milliseconds: 125),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;

      if (direction < 0) {
        controller.goNext();
      } else {
        controller.goPrevious();
      }

      if (!mounted) return;

      // 新内容从相反方向轻轻进入。幅度刻意控制得很小，
      // 保留“剧情阅读器”的高级感，而不是整页卡片飞来飞去。
      setState(() {
        _horizontalDragDistance = 0;
        _swipeVisualOffset = direction < 0 ? 30.0 : -30.0;
      });

      await _animateSwipeTo(
        0,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _horizontalDragDistance = 0;
      _swipeVisualOffset = 0;
      _swipeTransitioning = false;
      if (mounted) setState(() {});
    }
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (widget.focusNode.hasFocus ||
        controller.isGenerating ||
        _swipeTransitioning) {
      return;
    }
    _swipeController.stop();
    _horizontalDragDistance = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.focusNode.hasFocus ||
        controller.isGenerating ||
        _swipeTransitioning) {
      return;
    }

    _horizontalDragDistance += details.primaryDelta ?? 0;
    final width = MediaQuery.sizeOf(context).width;
    final limit = _swipeLimit(width);
    final wantsNext = _horizontalDragDistance < 0;
    final canMove = wantsNext ? controller.hasNext : controller.hasPrevious;

    // 可翻页时正常跟手；已经到头时增加阻尼，只让内容轻轻被“拉动”。
    final rawVisual = canMove
        ? _horizontalDragDistance
        : _horizontalDragDistance * .18;
    final visual = rawVisual.clamp(-limit, limit).toDouble();

    setState(() => _swipeVisualOffset = visual);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (widget.focusNode.hasFocus ||
        controller.isGenerating ||
        _swipeTransitioning) {
      _horizontalDragDistance = 0;
      if (_swipeVisualOffset != 0) {
        unawaited(_springSwipeBack());
      }
      return;
    }

    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;

    // 慢滑看位移，快速轻扫看速度。两个条件满足任意一个即可。
    final hasEnoughDistance = distance.abs() >= 46;
    final hasEnoughVelocity = velocity.abs() >= 320;
    if (!hasEnoughDistance && !hasEnoughVelocity) {
      unawaited(_springSwipeBack());
      return;
    }

    final directionSource = hasEnoughDistance ? distance : velocity;
    final direction = directionSource < 0 ? -1 : 1;
    final canMove = direction < 0 ? controller.hasNext : controller.hasPrevious;

    if (!canMove) {
      unawaited(_springSwipeBack());
      return;
    }

    unawaited(_commitSwipe(direction));
  }

  void _handleHorizontalDragCancel() {
    if (_swipeVisualOffset != 0 && !_swipeTransitioning) {
      unawaited(_springSwipeBack());
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _swipeHintTimer?.cancel();
    _swipeController.dispose();
    _displayTextNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentence = controller.currentSentence;
    final controllerSpeaker = controller.currentSpeakerName.trim();
    final sentenceSpeaker = sentence?.speakerName.trim() ?? '';
    final speaker = controllerSpeaker.isNotEmpty ? controllerSpeaker : sentenceSpeaker;
    final character = controller.currentSpeakerCharacter;
    final sentenceType = sentence?.type.toLowerCase().trim() ?? '';
    final isHost = sentence?.isProtagonist == true || character?.isMain == true;
    final hasSpeaker = speaker.isNotEmpty || character != null;
    final isNarration = sentence == null || (!hasSpeaker && (sentence.isNarration || sentenceType == 'narration' || sentenceType == 'action'));
    final mode = isNarration ? _NovelLineMode.narration : isHost ? _NovelLineMode.protagonist : _NovelLineMode.npc;

    final affection = mode == _NovelLineMode.npc ? character?.affection : null;

    // 剧情页人物层只显示真正的立绘，不再把头像/首字母当成立绘顶上去。
    final portraitUrl = <String>[
      controller.currentPortraitUrl,
      character?.portraitUrl ?? '',
      sentence?.portraitUrl ?? '',
    ].map((value) => value.trim()).firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    final canShowChoices = controller.choices.isNotEmpty && !controller.hasNext && !controller.isGenerating && !_revealing;
    final inputEnabled = !controller.isGenerating && !_revealing && !controller.isCinematic && !controller.pendingFateRevert;

    final emptyTextFallback =
        controller.isGenerating ? '' : '等待故事继续…';

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final compact = screen.width <= 600;
        final availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : screen.height - MediaQuery.paddingOf(context).vertical;
        final browsingStory = controller.hasNext;

        // 回看剧情时底部不再放“角色 / 经历 / 物品”，
        // 让画面底部只保留自然呼吸区。
        final footerHeight = browsingStory ? 0.0 : (compact ? 52.0 : 54.0);
        final footerBottom = compact ? 4.0 : 8.0;

        // 按真实视觉高度预留，不再给选择区留过多空白。
        final choiceCount = controller.choices.length;
        final choiceHeaderExtent = compact ? 42.0 : 44.0;
        final choiceItemHeight = 48.0;
        final choiceItemGap = compact ? 5.0 : 6.0;
        final choiceDockHeight = canShowChoices
            ? choiceHeaderExtent +
                choiceCount * choiceItemHeight +
                (choiceCount > 1 ? (choiceCount - 1) * choiceItemGap : 0)
            : 0.0;

        // 最后一条选择与自由输入框之间只保留轻微呼吸距离。
        final choiceBottomGap = compact ? 4.0 : 5.0;

        // 正文与选择区之间只留一条很小的安全距离。
        final contentChoiceGap = compact ? 5.0 : 6.0;

        // 角色对白整体上提一些。
        // 只调整普通角色/主角对白的位置，不改变旁白、选项区、输入框和右侧入口。
        // 底部多留出呼吸空间，避免对白贴着屏幕下沿。
        final dialogGap = compact ? 88.0 : 102.0;
        final panelBottom = footerBottom + footerHeight + dialogGap;

        // 最后一句出现选项时，不再把正文整体按选项数量不断往上推。
        // 选择区上方只保留一个固定高度的“正文阅读窗口”：
        // 短正文自然居中/靠下显示；长正文直接在窗口内滚动。
        final choiceContentBottom = footerBottom +
            footerHeight +
            choiceBottomGap +
            choiceDockHeight +
            contentChoiceGap;
        // 最后一句正文不再使用固定比例/固定高度。
        // 上边界只避开顶部 HUD，其余整块屏幕空间都交给正文使用。
        // 正文从选择框上方向上自然生长；只有真正占满剩余屏幕后才滚动。
        final choiceContentTop =
            MediaQuery.paddingOf(context).top + (compact ? 74.0 : 86.0);
        final choiceAvailableContentHeight =
            (availableHeight - choiceContentTop - choiceContentBottom)
                .clamp(0.0, availableHeight)
                .toDouble();

        return GestureDetector(
          // 整个对话舞台都能接收横滑，而不是只有命中内部文字/按钮时才生效。
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onHorizontalDragCancel: _handleHorizontalDragCancel,
          child: SizedBox(
            width: double.infinity,
            height: availableHeight,
            child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 当前角色半身立绘。
              // 500×800 原图只显示顶部约 64%，避免把完整全身硬塞进画面。
              // NPC 靠左；主角/玩家靠右。
              if (mode != _NovelLineMode.narration && portraitUrl.isNotEmpty)
                Builder(
                  builder: (context) {
                    final stageSize = MediaQuery.sizeOf(context);

                    // 真正的自适应：不再用 <1000 这种一刀切断点，
                    // 而是在“窄屏基准 360”与“宽屏基准 1400”之间按实际宽度连续插值，
                    // 数值会随屏幕宽度平滑变化，不会在临界宽度处突然跳一下。
                    const double minStage = 360.0;
                    const double maxStage = 1400.0;
                    final double t = ((stageSize.width - minStage) /
                            (maxStage - minStage))
                        .clamp(0.0, 1.0);

                    // ✨ 1. 人物大小：窄屏占比更高（0.9），宽屏占比更低（0.75），
                    // 随宽度平滑过渡，同时用 clamp 的上下限防止极端尺寸下跑飞。
                    final widthRatio = lerpDouble(1.10, 0.96, t)!;
                    final minPortraitWidth = lerpDouble(540.0, 760.0, t)!;
                    final maxPortraitWidth = lerpDouble(1160.0, 1320.0, t)!;
                    final portraitWidth = (stageSize.width * widthRatio)
                        .clamp(minPortraitWidth, maxPortraitWidth)
                        .toDouble();

                    final fullPortraitHeight = portraitWidth * 1.16;
                    final showOnRight = mode == _NovelLineMode.protagonist;

                    // ✨ 2. 让人物往上提：数字越小，人物越高。
                    final sinkOffset = -(fullPortraitHeight * 0.15);

                    // ✨ 3. NPC 靠左 / 主角靠右的横向偏移，同样连续插值，
                    // 不再是 narrowStage ? A : B 的二选一。
                    // 注意：手机宽度大多落在 360~430 之间，插值区间起点太靠近
                    // 会导致改基准值时手机端几乎看不出变化，所以这里把窄屏端的
                    // 基准值调得更负一些，确保在常见手机宽度下也能明显左移。
                    final npcLeftOffset = lerpDouble(-138.0, -42.0, t)!;
                    final protagonistRightOffset =
                        lerpDouble(-54.0, -6.0, t)!;

                    return Positioned(
                      bottom: sinkOffset, // 使用上面计算好的高低偏移
                      left: showOnRight ? null : npcLeftOffset,
                      right: showOnRight ? protagonistRightOffset : null,
                      child: _withSwipeMotion(
                        IgnorePointer(
                          child: SizedBox(
                            width: portraitWidth,
                          height: fullPortraitHeight,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                            child: _StagePortraitArtwork(
                              key: ValueKey<String>(portraitUrl),
                              url: portraitUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            ),
                            ),
                          ),
                        ),
                        stageSize.width,
                      ),
                    );
                  },
                ),

              if (mode == _NovelLineMode.narration)
                if (canShowChoices)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: choiceContentTop,
                    bottom: choiceContentBottom,
                    child: _withSwipeMotion(
                      Padding(
                        // 右侧单独加宽：避开右上角“角色 / 经历 / 背包”竖排入口
                      // 所在的区域，防止长正文的行尾伸到按钮底下去。
                      padding: EdgeInsets.only(
                        left: compact ? 16 : 30,
                        right: compact ? 22 : 38,
                      ),
                      child: Align(
                        // 短正文始终贴着选择框上方；
                        // 内容增加时只向上扩展，不会跑到屏幕中间悬空。
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: controller.hasNext,
                            choices: controller.choices,
                            playerHint: controller.playerHint,
                            onSelected: controller.selectChoice,
                            onCustomInput: () => widget.focusNode.requestFocus(),
                            onForceContinue: widget.onForceContinue,
                            onTap: _handleStoryTap,
                            ),
                          ),
                        ),
                      ),
                      screen.width,
                    ),
                  )
                else
                  Positioned.fill(
                    bottom: footerHeight + footerBottom + 8,
                    child: _withSwipeMotion(
                      Align(
                        alignment: const Alignment(0, -.02),
                      child: Padding(
                        // 同上：右侧加宽避开角色/经历/背包入口。
                        padding: EdgeInsets.only(
                          left: compact ? 16 : 30,
                          right: compact ? 22 : 38,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 650,
                            maxHeight: availableHeight * .60,
                          ),
                          child: _NovelNarrationSurface(
                            key: ValueKey<String>('narration-${controller.currentSentenceIndex}'),
                            displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                            isGenerating: controller.isGenerating,
                            isRevealing: _revealing,
                            fontFamily: controller.settings.fontFamily,
                            fontSize: controller.settings.fontSize,
                            hasNext: controller.hasNext,
                            choices: const <NovelChoice>[],
                            playerHint: controller.playerHint,
                            onSelected: controller.selectChoice,
                            onCustomInput: () => widget.focusNode.requestFocus(),
                            onForceContinue: widget.onForceContinue,
                            onTap: _handleStoryTap,
                            ),
                          ),
                        ),
                      ),
                      screen.width,
                    ),
                  )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  top: canShowChoices ? choiceContentTop : null,
                  bottom: canShowChoices ? choiceContentBottom : panelBottom,
                  child: _withSwipeMotion(
                    _NovelCharacterDialogueSurface(
                      key: ValueKey<String>('${mode.name}-${controller.currentSentenceIndex}-$speaker'),
                    mode: mode,
                    speakerName: speaker.isEmpty ? (mode == _NovelLineMode.protagonist ? controller.protagonistName : '角色') : speaker,
                    affection: affection,
                    displayTextListenable: _displayTextNotifier,
                            emptyTextFallback: emptyTextFallback,
                    isGenerating: controller.isGenerating,
                    isRevealing: _revealing,
                    fontFamily: controller.settings.fontFamily,
                    fontSize: controller.settings.fontSize,
                    hasNext: controller.hasNext,
                    choices: canShowChoices ? controller.choices : const <NovelChoice>[],
                    playerHint: controller.playerHint,
                    showPlayerHint: !_revealing && !controller.hasNext && !controller.isGenerating,
                    maxPanelHeight: canShowChoices
                        ? choiceAvailableContentHeight
                        : availableHeight * (compact ? .30 : .27),
                    onSelected: controller.selectChoice,
                    onCustomInput: () => widget.focusNode.requestFocus(),
                    onForceContinue: widget.onForceContinue,
                      onTap: _handleStoryTap,
                      onOpenPortrait: widget.onOpenPortrait,
                    ),
                    screen.width,
                  ),
                ),
              if (canShowChoices && !controller.isGenerating && !_revealing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: footerBottom + footerHeight + choiceBottomGap,
                  child: _withSwipeMotion(
                    _NovelChoiceDock(
                      choices: controller.choices,
                      onSelected: controller.selectChoice,
                    ),
                    screen.width,
                  ),
                ),
              if (!controller.isGenerating && !_revealing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: footerBottom,
                  child: _NovelDialogFooter(
                    controller: controller,
                    choicesAvailable: canShowChoices,
                    inputEnabled: inputEnabled,
                    textController: widget.textController,
                    focusNode: widget.focusNode,
                    onSend: widget.onSend,
                    onOpenInventory: widget.onOpenInventory,
                    onOpenCharacters: widget.onOpenCharacters,
                    onOpenJourney: widget.onOpenJourney,
                    onContinue: widget.onContinue,
                  ),
                ),
              if (_showSwipeHint &&
                  !canShowChoices &&
                  !controller.isGenerating &&
                  !_revealing &&
                  (controller.hasPrevious || controller.hasNext))
                Positioned(
                  // 左右各留出安全边距，跟进度条对齐，避免文字碰到右侧
                  // 角色/背包等入口按钮。
                  left: compact ? 18 : 34,
                  right: compact ? 18 : 34,
                  // 回溯历史时进度条会出现在最底部，滑动提示居中放在它正上方。
                  bottom: footerBottom + footerHeight + (browsingStory ? 26 : 7),
                  child: const Center(
                    child: _LuxurySwipeHint(),
                  ),
                ),
              // ✨ 沉浸式历史刻度：仅在回溯历史时于面板最底部浮现。
              // 此时 footerHeight 已收起（见上方 browsingStory 判断），
              // 底部是空的，不会跟“角色 / 经历 / 物品”footer 打架。
              Positioned(
                left: compact ? 18 : 34,
                right: compact ? 18 : 34,
                bottom: footerBottom + (compact ? 6 : 8),
                child: _StoryProgressLocator(
                  currentIndex: controller.currentSentenceIndex,
                  totalCount: controller.sentences.length,
                  isBrowsingHistory: browsingStory,
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}

class _NovelNarrationSurface extends StatelessWidget {
  const _NovelNarrationSurface({
    super.key,
    required this.displayTextListenable,
    required this.emptyTextFallback,
    required this.isGenerating,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    required this.hasNext,
    required this.choices,
    required this.playerHint,
    required this.onSelected,
    required this.onCustomInput,
    required this.onForceContinue,
    required this.onTap,
  });

  final ValueListenable<String> displayTextListenable;
  final String emptyTextFallback;
  final bool isGenerating;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final bool hasNext;
  final List<NovelChoice> choices;
  final String playerHint;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onForceContinue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final style = TextStyle(
      color: const Color(0xFFF3F4F6),
      fontFamily: fontFamily,
      fontSize: fontSize + 2,
      height: 1.90,
      fontWeight: FontWeight.w500,
      letterSpacing: .55,
      shadows: const <Shadow>[
        Shadow(color: Color(0xE6000000), blurRadius: 4, offset: Offset(0, 2)),
        Shadow(color: Color(0xB3000000), blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

    // Vue 的 is-narrative-mode：完全没有面板背景、边框、模糊和标题，
    // 文字直接浮在场景画面中央。
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ValueListenableBuilder<String>(
              valueListenable: displayTextListenable,
              builder: (context, value, _) => Text(
                value.isEmpty ? emptyTextFallback : value,
                style: style,
                textAlign: TextAlign.left,
              ),
            ),
            if (!hasNext &&
                !isGenerating &&
                !isRevealing &&
                playerHint.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _NarratorHint(text: playerHint),
            ],
          ],
        ),
      ),
    );
  }
}

class _NovelCharacterDialogueSurface extends StatelessWidget {
  const _NovelCharacterDialogueSurface({
    super.key,
    required this.mode,
    required this.speakerName,
    required this.affection,
    required this.displayTextListenable,
    required this.emptyTextFallback,
    required this.isGenerating,
    required this.isRevealing,
    required this.fontFamily,
    required this.fontSize,
    required this.hasNext,
    required this.choices,
    required this.playerHint,
    required this.showPlayerHint,
    required this.maxPanelHeight,
    required this.onSelected,
    required this.onCustomInput,
    required this.onForceContinue,
    required this.onTap,
    this.onOpenPortrait,
  });

  final _NovelLineMode mode;
  final String speakerName;
  final int? affection;
  final ValueListenable<String> displayTextListenable;
  final String emptyTextFallback;
  final bool isGenerating;
  final bool isRevealing;
  final String? fontFamily;
  final double fontSize;
  final bool hasNext;
  final List<NovelChoice> choices;
  final String playerHint;
  final bool showPlayerHint;
  final double maxPanelHeight;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onForceContinue;
  final VoidCallback onTap;
  final VoidCallback? onOpenPortrait;

  bool get isHost => mode == _NovelLineMode.protagonist;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final style = TextStyle(
      color: const Color(0xFFF7F7F7),
      fontFamily: fontFamily,
      fontSize: fontSize + (compact ? 0 : .4),
      height: 1.82,
      fontWeight: FontWeight.w500,
      letterSpacing: .15,
      shadows: const <Shadow>[
        Shadow(color: Color(0xF0000000), blurRadius: 4, offset: Offset(0, 2)),
        Shadow(color: Color(0xA6000000), blurRadius: 12, offset: Offset(0, 4)),
      ],
    );

    // 角色对白不再使用整块黑色/毛玻璃面板。
    // 让立绘和场景成为主视觉，仅用“居中名字 + 细线 + 正文”建立对白层级。
    final dialogueContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 26),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxPanelHeight.clamp(0.0, 520.0).toDouble(),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        _CenteredSpeakerIdentity(
                          name: speakerName,
                          affection: affection,
                          isHost: isHost,
                        ),
                        if (onOpenPortrait != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: _PortraitSwitchButton(onTap: onOpenPortrait!),
                          ),
                      ],
                    ),
                    SizedBox(height: compact ? 9 : 11),
                    Center(
                      child: Container(
                        width: compact ? 138 : 176,
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.white.withOpacity(0),
                              Colors.white.withOpacity(.44),
                              Colors.white.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 18),
                    ValueListenableBuilder<String>(
                      valueListenable: displayTextListenable,
                      builder: (context, value, _) {
                        final display = value.isEmpty ? emptyTextFallback : value;
                        return Text.rich(
                          TextSpan(
                            children: _buildNovelDialogueDisplaySpans(
                              display,
                              style,
                            ),
                          ),
                        );
                      },
                    ),
                    if (showPlayerHint && playerHint.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _NarratorHint(text: playerHint),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: choices.isNotEmpty
          ? Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: dialogueContent,
            )
          : Center(child: dialogueContent),
    );
  }
}

class _CenteredSpeakerIdentity extends StatefulWidget {
  const _CenteredSpeakerIdentity({
    required this.name,
    required this.affection,
    required this.isHost,
  });

  final String name;
  final int? affection;
  final bool isHost;

  @override
  State<_CenteredSpeakerIdentity> createState() =>
      _CenteredSpeakerIdentityState();
}

class _CenteredSpeakerIdentityState extends State<_CenteredSpeakerIdentity> {
  Timer? _affectionPulseTimer;
  int _pulseSerial = 0;
  int _pulseDirection = 0;

  @override
  void didUpdateWidget(covariant _CenteredSpeakerIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.name != widget.name) {
      _affectionPulseTimer?.cancel();
      _pulseDirection = 0;
      return;
    }

    final previous = oldWidget.affection;
    final current = widget.affection;
    if (previous == null || current == null || previous == current) return;

    _pulseDirection = current > previous ? 1 : -1;
    _pulseSerial += 1;
    _affectionPulseTimer?.cancel();
    _affectionPulseTimer = Timer(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      setState(() => _pulseDirection = 0);
    });
  }

  @override
  void dispose() {
    _affectionPulseTimer?.cancel();
    super.dispose();
  }

  Widget _buildAffectionHeart(int affection) {
    final restingColor = Colors.white.withOpacity(.78);
    final restingIcon = affection >= 60
        ? Icons.favorite_rounded
        : Icons.favorite_border_rounded;

    if (_pulseDirection == 0) {
      return Icon(
        restingIcon,
        size: 12.5,
        color: restingColor,
      );
    }

    final pulseColor = _pulseDirection > 0
        ? const Color(0xFFFF7DA5)
        : NovelPalette.danger;

    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_pulseSerial),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.elasticOut,
      builder: (context, value, _) {
        final safeValue = value.clamp(0.0, 1.0).toDouble();
        final icon = safeValue < .88
            ? Icons.favorite_rounded
            : restingIcon;
        return Transform.scale(
          scale: .72 + (.28 * value),
          child: Icon(
            icon,
            size: 13.5,
            color: Color.lerp(pulseColor, restingColor, safeValue),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final affection = widget.affection;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          widget.name,
          style: const TextStyle(
            color: Color(0xF2FFFFFF),
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.35,
            shadows: <Shadow>[
              Shadow(
                color: Color(0xE6000000),
                blurRadius: 7,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        if (affection != null) ...<Widget>[
          const SizedBox(width: 8),
          _buildAffectionHeart(affection),
          const SizedBox(width: 3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final direction = _pulseDirection >= 0 ? 1.0 : -1.0;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, .24 * direction),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              '$affection',
              key: ValueKey<int>(affection),
              style: TextStyle(
                color: Colors.white.withOpacity(.70),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                shadows: const <Shadow>[
                  Shadow(color: Color(0xD9000000), blurRadius: 5),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VueNamePlate extends StatelessWidget {
  const _VueNamePlate({
    required this.name,
    required this.affection,
    required this.isHost,
  });

  final String name;
  final int? affection;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Text(
        name,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: .65,
        ),
      ),
      if (affection != null) ...<Widget>[
        const SizedBox(width: 6),
        Text(
          affection! >= 60 ? '♥' : '♡',
          style: TextStyle(
            color: Colors.white.withOpacity(.76),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$affection',
          style: TextStyle(
            color: Colors.white.withOpacity(.72),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC141414),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(.15)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: isHost ? TextDirection.rtl : TextDirection.ltr,
        children: children,
      ),
    );
  }
}

class _DialogueAvatar extends StatelessWidget {
  const _DialogueAvatar({
    required this.url,
    required this.name,
    required this.isHost,
  });

  final String url;
  final String name;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(.04),
        border: Border.all(
          color: isHost ? NovelPalette.accent.withOpacity(.42) : Colors.white.withOpacity(.14),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x4D000000), blurRadius: 12, offset: Offset(0, 5)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: NovelArtwork(
        url: url,
        fit: BoxFit.cover,
        fallbackText: name,
        fallbackIcon: Icons.person_outline_rounded,
      ),
    );
  }
}

class _DialogueRoleTag extends StatelessWidget {
  const _DialogueRoleTag({required this.isHost});

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isHost ? NovelPalette.accent.withOpacity(.09) : Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHost ? NovelPalette.accent.withOpacity(.20) : Colors.white.withOpacity(.07),
        ),
      ),
      child: Text(
        isHost ? '主角对话' : '角色对话',
        style: TextStyle(
          color: isHost ? NovelPalette.accent.withOpacity(.88) : NovelPalette.text.withOpacity(.48),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .55,
        ),
      ),
    );
  }
}

class _AffectionInline extends StatelessWidget {
  const _AffectionInline({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value >= 60 ? '♥' : '♡',
          style: TextStyle(
            color: value >= 60 ? const Color(0xFFFF8FA3) : Colors.white.withOpacity(.42),
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
            color: Colors.white.withOpacity(.50),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NovelDecisionPanel extends StatelessWidget {
  const _NovelDecisionPanel({
    required this.choices,
    required this.playerHint,
    required this.onSelected,
    required this.onCustomInput,
    required this.onContinue,
    required this.onExpand,
  });

  final List<NovelChoice> choices;
  final String playerHint;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onContinue;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _AdaptiveBackdropBlur(
        sigma: 22,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xB8111313),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x50000000), blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: NovelPalette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '选择你的行动',
                    style: TextStyle(
                      color: NovelPalette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onExpand,
                    style: TextButton.styleFrom(
                      foregroundColor: NovelPalette.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '展开',
                      style: TextStyle(fontSize: 10.5),
                    ),
                  ),
                ],
              ),
              if (playerHint.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  playerHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NovelPalette.text.withOpacity(.38),
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _InlineNovelChoices(
                choices: choices,
                onSelected: onSelected,
                onCustomInput: onCustomInput,
                onContinue: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservedRevealText extends StatelessWidget {
  const _ReservedRevealText({
    required this.fullText,
    required this.visibleText,
    required this.style,
  });

  final String fullText;
  final String visibleText;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Opacity(
          opacity: 0,
          child: Text(
            fullText,
            style: style,
          ),
        ),
        Text(
          visibleText,
          style: style,
        ),
      ],
    );
  }
}

class _PortraitSwitchButton extends StatelessWidget {
  const _PortraitSwitchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '形象',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withOpacity(.08),
          highlightColor: Colors.white.withOpacity(.04),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(.22),
              border: Border.all(
                color: Colors.white.withOpacity(.18),
                width: .8,
              ),
            ),
            child: Icon(
              Icons.cached_rounded,
              size: 18,
              color: Colors.white.withOpacity(.92),
              shadows: const <Shadow>[
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 5,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryAdvanceCue extends StatefulWidget {
  const _StoryAdvanceCue();

  @override
  State<_StoryAdvanceCue> createState() => _StoryAdvanceCueState();
}

class _StoryAdvanceCueState extends State<_StoryAdvanceCue> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: .46, end: .96).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _slide = Tween<Offset>(begin: const Offset(0, -.06), end: const Offset(0, .11)).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: const _GameContinueGlyph(size: 34),
      ),
    );
  }
}

class _GameContinueGlyph extends StatelessWidget {
  const _GameContinueGlyph({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    // 可直接放入你自己的游戏 UI PNG：assets/images/novel_continue.png
    // 推荐透明底、白/香槟色细线菱形 + 向下箭头，尺寸 96x96 或 128x128。
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/novel_continue.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Transform.rotate(
              angle: .7853981633974483,
              child: Container(
                width: size * .56,
                height: size * .56,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.10),
                  border: Border.all(color: const Color(0xFFF3EBDD).withOpacity(.48), width: .85),
                  boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withOpacity(.26), blurRadius: 12, offset: const Offset(0, 4))],
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: size * .54, color: const Color(0xFFF6F1E7).withOpacity(.92), shadows: const <Shadow>[Shadow(color: Color(0xB3000000), blurRadius: 7)]),
          ],
        ),
      ),
    );
  }
}

class _NarratorHint extends StatefulWidget {
  const _NarratorHint({required this.text});
  final String text;

  @override
  State<_NarratorHint> createState() => _NarratorHintState();
}

class _NarratorHintState extends State<_NarratorHint> {
  bool revealed = false;

  @override
  Widget build(BuildContext context) {
    final hintText = widget.text.trim();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => setState(() => revealed = !revealed),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              revealed
                  ? '旁白提示：$hintText'
                  : '查看旁白提示',
              maxLines: revealed ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: Colors.white.withOpacity(revealed ? .86 : .78),
                fontSize: 11.2,
                height: 1.48,
                fontWeight: FontWeight.w600,
                letterSpacing: .12,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0x8A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NovelChoiceDock extends StatelessWidget {
  const _NovelChoiceDock({
    required this.choices,
    required this.onSelected,
  });

  final List<NovelChoice> choices;
  final ValueChanged<NovelChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;

    // 参考图：标题浮在场景上；卡片与底部自由输入框同宽。
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  '请做出你的选择',
                  style: TextStyle(
                    color: Color(0xFFF7F2EA),
                    fontSize: 16.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .45,
                    shadows: <Shadow>[
                      Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Transform.rotate(
                      angle: .7853981633974483,
                      child: Container(
                        width: 5,
                        height: 5,
                        color: _ChoiceColors.line.withOpacity(.86),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: compact ? 108 : 138,
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            _ChoiceColors.line.withOpacity(.48),
                            _ChoiceColors.line.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 7 : 8),
          _InlineNovelChoices(
            choices: choices,
            onSelected: onSelected,
            onCustomInput: () {},
            onContinue: () {},
          ),
        ],
      ),
    );
  }
}

/// 选择卡片：透明玻璃感，不使用暖棕色底。
class _ChoiceColors {
  static const Color line = Color(0xE6F3EEE9);
  static const Color cardTop = Color(0x20FFFFFF);
  static const Color cardMiddle = Color(0x15FFFFFF);
  static const Color cardBottom = Color(0x0FFFFFFF);

  // 整个选项框只用一圈较浅的白色描边。
  // 对比度明显低于自由输入框，避免抢正文。
  static const Color border = Color(0x4DFFFFFF);

  // 编号 / “行动”保持轻透明玻璃底，只强化白色描边，
  // 不再出现黑色方块。
  static const Color numberBg = Color(0x14FFFFFF);
  static const Color numberBorder = Color(0xA8FFFFFF);
  static const Color actionBg = Color(0x16FFFFFF);
  static const Color actionBorder = Color(0x92FFFFFF);
}

class _InlineNovelChoices extends StatelessWidget {
  const _InlineNovelChoices({
    required this.choices,
    required this.onSelected,
    required this.onCustomInput,
    required this.onContinue,
  });

  final List<NovelChoice> choices;
  final ValueChanged<NovelChoice> onSelected;
  final VoidCallback onCustomInput;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;

    return Column(
      children: <Widget>[
        ...choices.asMap().entries.map((entry) {
          final choice = entry.value;
          final isLast = entry.key == choices.length - 1;

          return Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : (compact ? 5 : 6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: _AdaptiveBackdropBlur(
                sigma: 18,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(choice),
                    borderRadius: BorderRadius.circular(3),
                    splashColor: Colors.white.withOpacity(.06),
                    highlightColor: Colors.white.withOpacity(.025),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: _ChoiceColors.border,
                          width: .8,
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            _ChoiceColors.cardTop,
                            _ChoiceColors.cardMiddle,
                            _ChoiceColors.cardBottom,
                          ],
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          // 左侧信息独立定位，不参与正文的居中计算。
                          // 顺序：1 / 2 / 3 在前，“行动”标签在编号后面。
                          Positioned(
                            left: compact ? 10 : 12,
                            top: 0,
                            bottom: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 23,
                                  height: 23,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _ChoiceColors.numberBg,
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(
                                      color: _ChoiceColors.numberBorder,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Text(
                                    '${entry.key + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.92),
                                      fontSize: 11.5,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (choice.isAction) ...<Widget>[
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _ChoiceColors.actionBg,
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(
                                        color: _ChoiceColors.actionBorder,
                                        width: .9,
                                      ),
                                    ),
                                    child: Text(
                                      '行动',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.94),
                                        fontSize: 9.5,
                                        height: 1.15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 左侧给编号 / “行动”标签留出必要空间；
                          // 右侧只保留正常安全边距，避免文字离右边过远。
                          Padding(
                            padding: EdgeInsets.only(
                              left: compact ? 78 : 88,
                              right: compact ? 18 : 22,
                            ),
                            child: Center(
                              child: Text(
                                choice.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.96),
                                  fontSize: compact ? 13.5 : 14,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: .08,
                                  shadows: const <Shadow>[
                                    Shadow(
                                      color: Color(0x99000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _NovelDialogFooter extends StatelessWidget {
  const _NovelDialogFooter({
    required this.controller,
    required this.choicesAvailable,
    required this.inputEnabled,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    required this.onOpenInventory,
    required this.onOpenCharacters,
    required this.onOpenJourney,
    required this.onContinue,
  });

  final NovelGameController controller;
  final bool choicesAvailable;
  final bool inputEnabled;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenCharacters;
  final VoidCallback onOpenJourney;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final browsingStory = controller.hasNext;

    // 回看历史剧情时底部完全留空。
    // 角色 / 经历 / 背包已经移到右上积分下方。
    if (browsingStory) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          if (!choicesAvailable) ...<Widget>[
            _GameContinueButton(onTap: onContinue),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: NovelInputBar(
              controller: textController,
              focusNode: focusNode,
              enabled: inputEnabled,
              luckyCardActive: controller.luckyCardActive,
              luckyCardCount: controller.luckyCardCount,
              onToggleLuckyCard: controller.toggleLuckyCard,
              onSend: onSend,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryImageAction extends StatelessWidget {
  const _StoryImageAction({
    required this.asset,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageSize = compact ? 28.0 : 31.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      splashColor: Colors.white.withOpacity(.05),
      highlightColor: Colors.white.withOpacity(.025),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
                width: imageSize,
                height: imageSize,
                child: NovelArtwork(
                  assetCandidates: <String>[asset],
                  fit: BoxFit.contain,
                  fallbackText: label,
                )),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                // 右侧入口必须始终可读：图标美术不动，只提高文字识别度。
                color: NovelPalette.text.withOpacity(.94),
                fontSize: 9.8,
                fontWeight: FontWeight.w700,
                letterSpacing: .20,
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameRevertButton extends StatelessWidget {
  const _GameRevertButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '轮次回溯',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.white.withOpacity(.05),
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 38,
            height: 44,
            child: Center(
                child: Opacity(
              opacity: onTap == null ? .24 : .68,
              child: Image.asset(
                'assets/images/novel_revert.png',
                width: 23,
                height: 23,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const Icon(Icons.undo_rounded, size: 23, color: Color(0xFFF3EBDD)),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

class _GameContinueButton extends StatelessWidget {
  const _GameContinueButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '继续剧情',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.white.withOpacity(.05),
          highlightColor: Colors.transparent,
          child: Opacity(
            opacity: onTap == null ? .25 : 1,
            child: const SizedBox(width: 42, height: 44, child: Center(child: _GameContinueGlyph(size: 32))),
          ),
        ),
      ),
    );
  }
}

class _StoryProgressLocator extends StatelessWidget {
  const _StoryProgressLocator({
    required this.currentIndex,
    required this.totalCount,
    required this.isBrowsingHistory,
  });

  final int currentIndex;
  final int totalCount;
  final bool isBrowsingHistory;

  @override
  Widget build(BuildContext context) {
    // 只有在回溯历史时才显示，保证最新剧情的极致干净。
    if (!isBrowsingHistory || totalCount <= 1) {
      return const SizedBox.shrink();
    }

    // 段与段之间的间距：格子越多，间距越窄，避免拥挤。
    final gap = totalCount > 24 ? 1.5 : totalCount > 12 ? 2.0 : 3.0;

    // 不加任何外层容器/背景/描边——就是一排简洁的细条，直接叠在画面上。
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: isBrowsingHistory ? 1.0 : 0.0,
        curve: Curves.easeOutCubic,
        child: Row(
          children: List<Widget>.generate(totalCount, (index) {
            final active = index == currentIndex;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: 2.5,
                margin: EdgeInsets.symmetric(horizontal: gap / 2),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white.withOpacity(.25),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: active
                      ? const <BoxShadow>[
                          BoxShadow(color: Color(0x99000000), blurRadius: 3),
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _LuxurySwipeHint extends StatefulWidget {
  const _LuxurySwipeHint();

  @override
  State<_LuxurySwipeHint> createState() => _LuxurySwipeHintState();
}

class _LuxurySwipeHintState extends State<_LuxurySwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shift;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    // 左右来回轻推 + 明暗呼吸，靠动画把注意力吸引过来，
    // 静态小字太容易被忽略了。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shift = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: .35, end: .95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.translate(
                offset: Offset(-_shift.value, 0),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(_glow.value),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '左右滑动回看剧情',
                style: TextStyle(
                  color: Colors.white.withOpacity(_glow.value),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0xCC000000), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Transform.translate(
                offset: Offset(_shift.value, 0),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(_glow.value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VueContinueButton extends StatelessWidget {
  const _VueContinueButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _AdaptiveBackdropBlur(
          sigma: 12,
          child: Material(
            color: Colors.white.withOpacity(.15),
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(.30)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.play_arrow_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 5),
                    Text('继续', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ));
  }
}

class NovelCinematicControls extends StatefulWidget {
  const NovelCinematicControls({
    super.key,
    required this.text,
    required this.speakerName,
    required this.isGenerating,
    required this.isFirst,
    required this.isLast,
    required this.fontFamily,
    required this.fontSize,
    required this.onRevert,
    required this.onPrevious,
    required this.onNext,
    required this.onContinue,
  });

  final String text;
  final String speakerName;
  final bool isGenerating;
  final bool isFirst;
  final bool isLast;
  final String? fontFamily;
  final double fontSize;
  final VoidCallback onRevert;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onContinue;

  @override
  State<NovelCinematicControls> createState() => _NovelCinematicControlsState();
}

class _NovelCinematicControlsState extends State<NovelCinematicControls> {
  Timer? _revealTimer;
  Timer? _typingTimer;
  int _visibleLength = 0;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) return;
      if (widget.text.isEmpty) {
        timer.cancel();
        return;
      }
      final safeText = _sanitizeNovelStreamingText(widget.text);
      final runeLength = safeText.runes.length;
      setState(() => _visibleLength = (_visibleLength + 1).clamp(0, runeLength));
      if (_visibleLength >= runeLength) timer.cancel();
    });
  }

  @override
  void didUpdateWidget(covariant NovelCinematicControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _typingTimer?.cancel();
      _visibleLength = 0;
      _typingTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (!mounted) return;
        if (widget.text.isEmpty) {
          timer.cancel();
          return;
        }
        setState(() => _visibleLength = (_visibleLength + 1).clamp(0, widget.text.length));
        if (_visibleLength >= widget.text.length) timer.cancel();
      });
    }
  }

  void _finishReveal() {
    _typingTimer?.cancel();
    if (mounted) {
      setState(
        () => _visibleLength =
            _sanitizeNovelStreamingText(widget.text).runes.length,
      );
    }
  }

  void _handleScreenTap() {
    if (!widget.isGenerating) widget.onContinue();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeText = _sanitizeNovelStreamingText(widget.text);
    final displayText = _novelPrefixByRunes(safeText, _visibleLength);
    final narration = widget.speakerName.trim().isEmpty;
    return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleScreenTap,
        onHorizontalDragEnd: (details) {
          if (widget.isGenerating) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 260) return;
          if (velocity < 0 && !widget.isLast) {
            widget.onNext();
          } else if (velocity > 0 && !widget.isFirst) {
            widget.onPrevious();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
                alignment: narration ? const Alignment(0, -.02) : const Alignment(0, .36),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width < 480 ? 30 : 64),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: narration ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: <Widget>[
                        if (!narration) ...<Widget>[
                          Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(.40), borderRadius: BorderRadius.circular(999), border: Border.all(color: NovelPalette.accent.withOpacity(.34))),
                              child: Text('「 ${widget.speakerName} 」', style: const TextStyle(color: NovelPalette.accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8))),
                          const SizedBox(height: 14),
                        ],
                        Text(displayText.isEmpty && !widget.isGenerating ? '等待故事继续…' : displayText,
                            textAlign: narration ? TextAlign.center : TextAlign.left,
                            style: TextStyle(color: NovelPalette.text, fontFamily: widget.fontFamily, fontSize: widget.fontSize + (narration ? 3 : 2), height: narration ? 1.95 : 1.8, fontWeight: narration ? FontWeight.w500 : FontWeight.w400, letterSpacing: narration ? .7 : .25, shadows: const <Shadow>[Shadow(color: Color(0xE0000000), blurRadius: 18, offset: Offset(0, 3))])),
                      ])),
                )),
            Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                    child: Container(
                  height: 210,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[Colors.transparent, Colors.black.withOpacity(.74), Colors.black.withOpacity(.92)])),
                ))),
            Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 38),
                          const Spacer(),
                          _GameContinueButton(onTap: widget.isGenerating ? null : widget.onContinue),
                          const Spacer(),
                          IgnorePointer(child: Opacity(opacity: (widget.isFirst && widget.isLast) ? 0 : 1, child: const _LuxurySwipeHint())),
                        ],
                      ),
                    ))),
          ],
        ));
  }
}

class NovelInputBar extends StatefulWidget {
  const NovelInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.luckyCardActive,
    required this.luckyCardCount,
    required this.onToggleLuckyCard,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool luckyCardActive;
  final int luckyCardCount;
  final VoidCallback onToggleLuckyCard;
  final ValueChanged<String> onSend;

  @override
  State<NovelInputBar> createState() => _NovelInputBarState();
}

class _NovelInputBarState extends State<NovelInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    widget.focusNode.addListener(_updateFocus);
    _update();
  }

  @override
  void didUpdateWidget(covariant NovelInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
      _update();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_updateFocus);
      widget.focusNode.addListener(_updateFocus);
    }
  }

  void _update() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText && mounted) setState(() => _hasText = next);
  }

  void _updateFocus() {
    if (mounted) setState(() {});
  }

  void _submit() {
    final text = widget.controller.text.trim();
    if (!widget.enabled || text.isEmpty) return;
    widget.onSend(text);
    widget.controller.clear();
    widget.focusNode.requestFocus();
  }

  void _insertNewline() {
    if (!widget.enabled) return;

    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : start;
    final nextText = value.text.replaceRange(start, end, '\n');

    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.enabled) {
      return KeyEventResult.ignored;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    // 中文 / 日文等输入法正在组合文字时，Enter 应继续用于确认候选词，
    // 不能被剧情输入框抢走。
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewline();
      return KeyEventResult.handled;
    }

    _submit();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    widget.focusNode.removeListener(_updateFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = widget.enabled && _hasText;
    final focused = widget.enabled && widget.focusNode.hasFocus;

    return AnimatedOpacity(
        opacity: widget.enabled ? 1 : .50,
        duration: const Duration(milliseconds: 160),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (widget.luckyCardCount > 0) ...<Widget>[
              ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _AdaptiveBackdropBlur(
                    sigma: 18,
                    child: Material(
                      color: widget.luckyCardActive ? NovelPalette.accent.withOpacity(.15) : Colors.white.withOpacity(.075),
                      child: InkWell(
                        onTap: widget.enabled ? widget.onToggleLuckyCard : null,
                        child: Container(
                          width: 46,
                          height: 48,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.luckyCardActive ? NovelPalette.accent.withOpacity(.45) : Colors.white.withOpacity(.08))),
                          child: Stack(fit: StackFit.expand, children: <Widget>[
                            const Padding(
                                padding: EdgeInsets.all(11),
                                child: NovelArtwork(
                                  assetCandidates: <String>['assets/images/lucky_card.webp'],
                                  fit: BoxFit.contain,
                                  fallbackIcon: Icons.auto_awesome_outlined,
                                )),
                            Positioned(
                                top: 3,
                                right: 3,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 15),
                                  height: 15,
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: NovelPalette.text, borderRadius: BorderRadius.circular(5)),
                                  child: Text('${widget.luckyCardCount}', style: const TextStyle(color: Color(0xFF111512), fontSize: 8.5, fontWeight: FontWeight.w900)),
                                )),
                          ]),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _AdaptiveBackdropBlur(
                        sigma: 22,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 170),
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.fromLTRB(15, 5, 6, 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(focused ? .12 : .085),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(focused ? .90 : .62),
                              width: focused ? 1.35 : 1.05,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x38000000),
                                blurRadius: 16,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Expanded(
                                child: Focus(
                                  onKeyEvent: _handleInputKey,
                                  child: TextField(
                                    controller: widget.controller,
                                    focusNode: widget.focusNode,
                                    enabled: widget.enabled,
                                    minLines: 1,
                                    maxLines: 3,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _submit(),
                                    cursorColor: NovelPalette.accent,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(color: Color(0xFFF4F3EE), fontSize: 14, height: 1.35, fontWeight: FontWeight.w400),
                                    decoration: InputDecoration(
                                      hintText: widget.luckyCardActive ? '运气已加持，输入你的行动…' : '输入你的行动…',
                                      hintStyle: TextStyle(color: Colors.white.withOpacity(.38), fontSize: 13.5, fontWeight: FontWeight.w400),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedOpacity(
                                  duration: const Duration(milliseconds: 150),
                                  opacity: canSend ? 1 : .34,
                                  child: Material(
                                      color: canSend ? NovelPalette.accent : Colors.white.withOpacity(.10),
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: canSend ? _submit : null,
                                          child: SizedBox(
                                            width: 36,
                                            height: 36,
                                            child: Icon(Icons.arrow_upward_rounded, size: 18, color: canSend ? const Color(0xFF0A110C) : Colors.white.withOpacity(.52)),
                                          )))),
                            ],
                          ),
                        )))),
          ],
        ));
  }
}

class NovelActionRail extends StatelessWidget {
  const NovelActionRail({
    super.key,
    required this.onStore,
    required this.onInventory,
    required this.onCharacters,
    required this.onJourney,
  });

  final VoidCallback onStore;
  final VoidCallback onInventory;
  final VoidCallback onCharacters;
  final VoidCallback onJourney;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
        radius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            _RailButton(icon: Icons.stars_rounded, label: '积分兑换', onTap: onStore, color: const Color(0xFFF4C542)),
            _RailButton(icon: Icons.backpack_outlined, label: '背包', onTap: onInventory),
            _RailButton(icon: Icons.people_outline_rounded, label: '人物', onTap: onCharacters),
            _RailButton(icon: Icons.menu_book_outlined, label: '旅程', onTap: onJourney),
          ]),
        ));
  }
}


class NovelArchiveRail extends StatelessWidget {
  const NovelArchiveRail({
    super.key,
    required this.onCharacters,
    required this.onJourney,
    required this.onInventory,
  });

  final VoidCallback onCharacters;
  final VoidCallback onJourney;
  final VoidCallback onInventory;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 390;

    // 完全复用原来底部的 _StoryImageAction 美术：
    // 原图片、原尺寸、原文字、原透明度、原点击效果都不改。
    // 唯一变化只是从“底部横排”移动到“右侧竖排”。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _StoryImageAction(
          asset: 'assets/images/relation.webp',
          label: '角色',
          compact: compact,
          onTap: onCharacters,
        ),
        SizedBox(height: compact ? 5 : 7),
        _StoryImageAction(
          asset: 'assets/images/journey.webp',
          label: '经历',
          compact: compact,
          onTap: onJourney,
        ),
        SizedBox(height: compact ? 5 : 7),
        _StoryImageAction(
          asset: 'assets/images/inventory.webp',
          label: '背包',
          compact: compact,
          onTap: onInventory,
        ),
      ],
    );
  }
}

class NovelScoreChip extends StatefulWidget {
  const NovelScoreChip({
    super.key,
    required this.score,
    required this.onTap,
  });

  final NovelScore score;
  final VoidCallback onTap;

  @override
  State<NovelScoreChip> createState() => _NovelScoreChipState();
}

class _NovelScoreChipState extends State<NovelScoreChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _deltaOpacity;
  late final Animation<double> _deltaLift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.16, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
    ]).animate(_controller);
    _deltaOpacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1),
        weight: 18,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 42,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0),
        weight: 40,
      ),
    ]).animate(_controller);
    _deltaLift = Tween<double>(begin: 4, end: -14).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    // 积分条在剧情生成期间会暂时隐藏；如果它重新挂载时已经带着 delta，
    // 也要播放一次反馈，而不是因为没有 didUpdateWidget 就静默跳数。
    if (widget.score.delta != 0) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant NovelScoreChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.score.total != oldWidget.score.total) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delta = widget.score.delta;
    final positive = delta >= 0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topRight,
          children: <Widget>[
            Transform.scale(
              scale: _controller.isAnimating ? _scale.value : 1,
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(10),
                  splashColor: Colors.white.withOpacity(.05),
                  highlightColor: Colors.white.withOpacity(.025),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.star_outline_rounded,
                          size: 15,
                          color: Colors.white.withOpacity(.96),
                        ),
                        const SizedBox(width: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, .22),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(
                            '${widget.score.total}',
                            key: ValueKey<int>(widget.score.total),
                            style: TextStyle(
                              color: Colors.white.withOpacity(.98),
                              fontSize: 11.4,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_controller.isAnimating && delta != 0)
              Positioned(
                right: 2,
                top: _deltaLift.value,
                child: Opacity(
                  opacity: _deltaOpacity.value,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        '${positive ? '+' : ''}$delta',
                        style: TextStyle(
                          color: positive
                              ? const Color(0xFFF2CE78)
                              : NovelPalette.danger,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          shadows: const <Shadow>[
                            Shadow(color: Color(0xCC000000), blurRadius: 7),
                          ],
                        ),
                      ),
                      if (widget.score.reason.trim().isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            widget.score.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.55),
                              fontSize: 8.8,
                              fontWeight: FontWeight.w500,
                              shadows: const <Shadow>[
                                Shadow(color: Color(0xD9000000), blurRadius: 5),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class NovelTaskBadge extends StatelessWidget {
  const NovelTaskBadge({
    super.key,
    required this.task,
    required this.completed,
  });

  final NovelTask? task;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final text = completed ? '任务完成' : task?.display ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(position: Tween<Offset>(begin: const Offset(-.08, 0), end: Offset.zero).animate(animation), child: child),
      ),
      child: Container(
        key: ValueKey<String>('$completed|$text'),
        constraints: const BoxConstraints(maxWidth: 250),
        padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.22),
          borderRadius: BorderRadius.circular(5),
          border: Border(left: BorderSide(color: completed ? Colors.white24 : const Color(0xFFF1C36A), width: 2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(completed ? '✓' : '✦', style: TextStyle(color: completed ? Colors.white30 : const Color(0xFFF1C36A), fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Flexible(
              child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: completed ? Colors.white38 : Colors.white.withOpacity(.84), fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w600, decoration: completed ? TextDecoration.lineThrough : TextDecoration.none),
          )),
        ]),
      ),
    );
  }
}

class NovelHudEventOverlay extends StatefulWidget {
  const NovelHudEventOverlay({
    super.key,
    required this.event,
  });

  final NovelHudEvent event;

  @override
  State<NovelHudEventOverlay> createState() => _NovelHudEventOverlayState();
}

class _NovelHudEventOverlayState extends State<NovelHudEventOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2050),
    )..forward();
    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 62,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 24,
      ),
    ]).animate(_controller);
    _slide = Tween<double>(begin: 10, end: -7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: .96, end: 1.02),
        weight: 24,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.02, end: 1),
        weight: 76,
      ),
    ]).animate(_controller);
  }

  Color get _accent {
    return switch (widget.event.tone) {
      'rose' => const Color(0xFFE6A1B6),
      'danger' => const Color(0xFFEF6B68),
      'critical' => const Color(0xFFC15CFF),
      'warning' => const Color(0xFFF2B648),
      'gold' => const Color(0xFFF0CB76),
      'violet' => const Color(0xFFB59BD9),
      'accent' => NovelPalette.accent,
      _ => Colors.white70,
    };
  }

  IconData get _icon {
    return switch (widget.event.kind) {
      'affection' => Icons.favorite_rounded,
      'relation_milestone' => Icons.favorite_border_rounded,
      'milestone' => Icons.auto_awesome_rounded,
      'route_shift' => Icons.alt_route_rounded,
      'injury' => Icons.monitor_heart_outlined,
      'inventory' => Icons.inventory_2_outlined,
      'score' => Icons.star_rounded,
      _ => Icons.circle_outlined,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, -.52),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: _opacity.value,
                child: Transform.translate(
                  offset: Offset(0, _slide.value),
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.fromLTRB(13, 9, 15, 9),
                      decoration: BoxDecoration(
                        color: const Color(0xC917181C),
                        borderRadius: BorderRadius.circular(6),
                        border: Border(
                          left: BorderSide(color: accent.withOpacity(.92), width: 2),
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x52000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(_icon, color: accent, size: 16),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: NovelPalette.text,
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .2,
                                  ),
                                ),
                                if (widget.event.detail.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.event.detail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.54),
                                      fontSize: 9.8,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class NovelBrewingOverlay extends StatefulWidget {
  const NovelBrewingOverlay({super.key});

  @override
  State<NovelBrewingOverlay> createState() => _NovelBrewingOverlayState();
}

class _NovelBrewingOverlayState extends State<NovelBrewingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 不使用“来回呼吸”的静态 Loading，而是让进度光持续向前流动。
    // 光段完整离开轨道后才重新进入，循环时不会有明显跳帧感。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: Colors.black.withOpacity(.27)),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  const trackWidth = 154.0;
                  const runnerWidth = 36.0;
                  final progress = Curves.easeInOutCubic.transform(
                    _controller.value,
                  );
                  final runnerLeft =
                      -runnerWidth + progress * (trackWidth + runnerWidth);
                  final dotCount = ((_controller.value * 4).floor() % 4);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: trackWidth,
                        height: 12,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            // 中性轨道只负责告诉用户“流程还在继续”，不抢主题色。
                            Center(
                              child: Container(
                                width: trackWidth,
                                height: 1,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.11),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            Positioned(
                              left: runnerLeft,
                              child: Container(
                                width: runnerWidth,
                                height: 2.4,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      NovelPalette.accent.withOpacity(0),
                                      NovelPalette.accent.withOpacity(.92),
                                      NovelPalette.accent.withOpacity(0),
                                    ],
                                    stops: const <double>[0, .50, 1],
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: NovelPalette.accent.withOpacity(.18),
                                      blurRadius: 9,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            '故事酝酿中',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.84),
                              fontSize: 11.6,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2.4,
                              shadows: const <Shadow>[
                                Shadow(
                                  color: Color(0xA8000000),
                                  blurRadius: 9,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          SizedBox(
                            width: 22,
                            child: Text(
                              List<String>.filled(dotCount, '.').join(),
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.68),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 主角伤势状态的屏幕级反馈。
///
/// 屏幕边缘长期跟随当前伤势等级：轻伤琥珀黄、重伤红、濒危紫红；
/// 状态越严重，呼吸越快、侵入视野越深。真实掉血时再额外叠加一次短促冲击。
class NovelDamageFeedbackOverlay extends StatefulWidget {
  const NovelDamageFeedbackOverlay({
    super.key,
    required this.hp,
  });

  final int hp;

  @override
  State<NovelDamageFeedbackOverlay> createState() =>
      _NovelDamageFeedbackOverlayState();
}

class _NovelDamageFeedbackOverlayState
    extends State<NovelDamageFeedbackOverlay> with TickerProviderStateMixin {
  late final AnimationController _hitController;
  late final AnimationController _breathController;
  late final Animation<double> _hitOpacity;
  late final Animation<double> _breathPhase;

  @override
  void initState() {
    super.initState();
    _hitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _hitOpacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 12,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 88,
      ),
    ]).animate(_hitController);

    _breathController = AnimationController(
      vsync: this,
      duration: _breathDuration,
    );
    _breathPhase = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant NovelDamageFeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 只有真实掉血才触发一次“受击冲击”；常驻边缘效果由当前伤势等级决定。
    if (widget.hp < oldWidget.hp) {
      _hitController.forward(from: 0);
    }

    if (widget.hp != oldWidget.hp) {
      _syncBreathing();
    }
  }

  Duration get _breathDuration {
    if (widget.hp <= 15) return const Duration(milliseconds: 1050); // 濒危：急促
    if (widget.hp <= 40) return const Duration(milliseconds: 1650); // 重伤：明显
    if (widget.hp <= 75) return const Duration(milliseconds: 2800); // 轻伤：缓慢
    return const Duration(milliseconds: 3000);
  }

  void _syncBreathing() {
    if (widget.hp <= 75) {
      // 伤势等级变化时立即切换呼吸节奏，而不是等上一轮动画结束。
      final currentValue = _breathController.value;
      _breathController
        ..stop()
        ..duration = _breathDuration
        ..value = currentValue
        ..repeat(reverse: true);
    } else {
      _breathController
        ..stop()
        ..value = 0;
    }
  }

  /// 与头像光圈 / HP 条完全使用同一套状态色：
  /// 健康=绿（不显示边缘），轻伤=琥珀黄，重伤=红，濒危=紫红。
  Color get _stateColor {
    if (widget.hp <= 15) return const Color(0xFFC15CFF);
    if (widget.hp <= 40) return const Color(0xFFEF5D5D);
    if (widget.hp <= 75) return const Color(0xFFF2B648);
    return NovelPalette.accent;
  }

  double get _baseEdgeOpacity {
    if (widget.hp <= 15) return .16;
    if (widget.hp <= 40) return .095;
    if (widget.hp <= 75) return .035;
    return 0;
  }

  double get _breathEdgeOpacity {
    if (widget.hp <= 15) return .18;
    if (widget.hp <= 40) return .13;
    if (widget.hp <= 75) return .065;
    return 0;
  }

  double get _hitStrength {
    if (widget.hp <= 15) return .30;
    if (widget.hp <= 40) return .27;
    if (widget.hp <= 75) return .22;
    return .18;
  }

  double get _darkVignetteStrength {
    if (widget.hp <= 15) return .16;
    if (widget.hp <= 40) return .075;
    return 0;
  }

  @override
  void dispose() {
    _hitController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _breathController,
          _hitController,
        ]),
        builder: (context, _) {
          if (widget.hp > 75 && !_hitController.isAnimating) {
            return const SizedBox.shrink();
          }

          final breath = widget.hp <= 75 ? _breathPhase.value : 0.0;
          final hit = _hitOpacity.value;
          final color = _stateColor;

          // 常驻状态 + 呼吸变化 + 刚掉血时的一次冲击。
          final edgeOpacity = (_baseEdgeOpacity +
                  breath * _breathEdgeOpacity +
                  hit * _hitStrength)
              .clamp(0.0, .58)
              .toDouble();
          final flashOpacity = (hit * (widget.hp <= 40 ? .075 : .045))
              .clamp(0.0, .085)
              .toDouble();
          final darkOpacity = (_darkVignetteStrength * (.55 + breath * .45))
              .clamp(0.0, .18)
              .toDouble();

          // 状态越严重，边缘侵入视野越深。
          final verticalDepth = widget.hp <= 15
              ? 150.0
              : widget.hp <= 40
                  ? 122.0
                  : 86.0;
          final horizontalDepth = widget.hp <= 15
              ? 76.0
              : widget.hp <= 40
                  ? 58.0
                  : 40.0;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 掉血瞬间轻闪一下当前伤势颜色，作为“命中反馈”。
              if (flashOpacity > 0)
                ColoredBox(color: color.withOpacity(flashOpacity)),

              // 重伤 / 濒危时增加暗角压迫，但不遮正文。
              if (darkOpacity > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: .86,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(darkOpacity),
                      ],
                      stops: const <double>[0, .64, 1],
                    ),
                  ),
                ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: verticalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity),
                        color.withOpacity(edgeOpacity * .34),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, .38, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: verticalDepth * 1.08,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity),
                        color.withOpacity(edgeOpacity * .36),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, .40, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: horizontalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity * .96),
                        color.withOpacity(edgeOpacity * .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: horizontalDepth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: <Color>[
                        color.withOpacity(edgeOpacity * .96),
                        color.withOpacity(edgeOpacity * .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NovelDiceOverlay extends StatelessWidget {
  const NovelDiceOverlay({super.key, required this.roll});

  final NovelDiceRoll roll;

  Color get _glowColor {
    return switch (roll.effect) {
      'critical' => const Color(0xFFF4C542),
      'fumble' => const Color(0xFFB38AE3),
      'fail' => const Color(0xFFE77A72),
      'partial' => const Color(0xFFE8C58B),
      _ => const Color(0xFF91D5A7),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
        child: _AdaptiveBackdropBlur(
            sigma: 7,
            child: ColoredBox(
                color: Colors.black.withOpacity(.34),
                child: Center(
                    child: Transform.translate(
                        offset: const Offset(0, -42),
                        child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 680),
                            tween: Tween<double>(begin: 0, end: 1),
                            curve: Curves.easeOutBack,
                            builder: (context, value, child) {
                              return Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: .78 + value * .22, child: child));
                            },
                            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                              Text('◇', style: TextStyle(color: Colors.white.withOpacity(.94), fontSize: 31, height: 1, fontWeight: FontWeight.w300, shadows: <Shadow>[Shadow(color: _glowColor.withOpacity(.85), blurRadius: 20)])),
                              const SizedBox(height: 14),
                              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                Container(width: 34, height: 1, color: _glowColor.withOpacity(.36)),
                                const SizedBox(width: 14),
                                Text('命运判定', style: TextStyle(color: Colors.white.withOpacity(.70), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 3.0)),
                                const SizedBox(width: 14),
                                Container(width: 34, height: 1, color: _glowColor.withOpacity(.36)),
                              ]),
                              const SizedBox(height: 18),
                              Text('${roll.roll}', style: TextStyle(color: Colors.white, fontSize: 72, height: .95, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: _glowColor.withOpacity(.90), blurRadius: 18), Shadow(color: _glowColor.withOpacity(.46), blurRadius: 42)])),
                              const SizedBox(height: 13),
                              Text(roll.label, style: const TextStyle(color: NovelPalette.text, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: .8)),
                              if (roll.skill.isNotEmpty || roll.dc > 0) ...<Widget>[
                                const SizedBox(height: 8),
                                Text('${roll.skill}${roll.dc > 0 ? '  ·  DC ${roll.dc}' : ''}', style: TextStyle(color: Colors.white.withOpacity(.48), fontSize: 11, letterSpacing: .4)),
                              ]
                            ])))))));
  }
}

class NovelTimeSkipOverlay extends StatelessWidget {
  const NovelTimeSkipOverlay({
    super.key,
    required this.label,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onDismiss,
        child: ColoredBox(
          color: const Color(0xD9000000),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(width: 54, height: 1, color: Colors.white.withOpacity(.48)),
            const SizedBox(height: 22),
            Text(label, style: const TextStyle(color: NovelPalette.text, fontSize: 24, fontWeight: FontWeight.w500, letterSpacing: 5)),
            const SizedBox(height: 22),
            Container(width: 54, height: 1, color: Colors.white.withOpacity(.48)),
          ])),
        ));
  }
}

class NovelStatusBanner extends StatelessWidget {
  const NovelStatusBanner({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return SafeArea(
        child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
          padding: const EdgeInsets.only(top: 64, left: 24, right: 24),
          child: GestureDetector(
            onTap: onDismiss,
            child: _GlassSurface(
                radius: 13,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: isError ? NovelPalette.danger : NovelPalette.accent, size: 17),
                      const SizedBox(width: 9),
                      Flexible(child: Text(message, style: const TextStyle(color: NovelPalette.text, fontSize: 12))),
                    ]))),
          )),
    ));
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.progress});
  final double progress;

  Color get _healthColor {
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= .15) return const Color(0xFFC15CFF); // 濒危：紫红
    if (p <= .40) return const Color(0xFFEF5D5D); // 重伤：红
    if (p <= .75) return const Color(0xFFF2B648); // 受损：琥珀
    return NovelPalette.accent; // 健康：统一使用主题主色绿
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    final color = _healthColor;
    return SizedBox(
        // HP 条只作为角色状态提示，不需要占据姓名下方整块宽度。
        // 68 -> 48，缩短约 29%，在手机 HUD 上更轻巧。
        width: 48,
        height: 3,
        child: Stack(alignment: Alignment.centerLeft, children: <Widget>[
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(.36), borderRadius: BorderRadius.circular(20)))),
          FractionallySizedBox(
              widthFactor: p,
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20), boxShadow: <BoxShadow>[BoxShadow(color: color.withOpacity(.52), blurRadius: 7)]),
              )),
        ]));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(width: 35, height: 35, decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: <BoxShadow>[BoxShadow(color: Color(0x52000000), blurRadius: 10, offset: Offset(0, 3))]), child: ClipOval(child: _NetworkOrFallback(url: url, icon: Icons.person_outline_rounded)));
  }
}

class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 26, height: 26, child: ClipOval(child: _NetworkOrFallback(url: url, icon: Icons.person_outline_rounded)));
  }
}

class _NetworkOrFallback extends StatelessWidget {
  const _NetworkOrFallback({required this.url, required this.icon});
  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (url.isNotEmpty) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return ColoredBox(color: const Color(0xB3222521), child: Icon(icon, size: 16, color: Colors.white.withOpacity(.62)));
  }
}

class _HudIcon extends StatelessWidget {
  const _HudIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 19, color: Colors.white.withOpacity(.82))),
        ));
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        message: tooltip,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: onTap == null ? Colors.white.withOpacity(.18) : highlighted ? NovelPalette.accent : Colors.white.withOpacity(.54)),
        ));
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(width: 43, height: 42, child: Icon(icon, color: color ?? Colors.white.withOpacity(.58), size: 19)),
        ));
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.radius = 16,
    this.blur = 18,
    this.color = const Color(0x73191B19),
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: _AdaptiveBackdropBlur(
            sigma: blur,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(.08)), boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x45000000), blurRadius: 22, offset: Offset(0, 8))]),
              child: child,
            )));
  }
}
/// 选择面板 —— 去掉了闪电/体力消耗徽标，改为反光毛玻璃卡片，
/// 三个选项自然贴底部展示，标题“请做出你的选择”置于选项上方。
/// 用法：NovelChoicePanel(options: ['借势反咬…', '正大光明…', '偷看系统…'], onSelect: (text) {...})
class NovelChoicePanel extends StatelessWidget {
  const NovelChoicePanel({
    super.key,
    required this.options,
    required this.onSelect,
    this.enabled = true,
    this.title = '请做出你的选择',
  });

  final List<String> options;
  final ValueChanged<String> onSelect;
  final bool enabled;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: NovelPalette.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: NovelPalette.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < options.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 10),
          _NovelChoiceCard(
            label: options[i],
            enabled: enabled,
            onTap: () => onSelect(options[i]),
          ),
        ],
      ],
    );
  }
}

class _NovelChoiceCard extends StatelessWidget {
  const _NovelChoiceCard({
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: _AdaptiveBackdropBlur(
        sigma: 18,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                // 反光玻璃遮罩：顶部略亮、底部略暗的渐变，模拟光线打在磨砂玻璃上的高光
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white.withOpacity(.16),
                    Colors.white.withOpacity(.045),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(.18), width: .8),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x30000000), blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NovelPalette.text.withOpacity(enabled ? 1 : .5),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
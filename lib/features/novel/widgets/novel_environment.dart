part of '../novel_widgets.dart';

// Novel Widgets · 世界环境
// 对外入口：NovelWeatherEffect / NovelTimePeriod / NovelTimeOverlay / NovelWeatherOverlay / NovelWorldBackground
// 内部实现：天气 Painter、时间色调、背景预载与切换动画。

enum NovelWeatherEffect {
  none,
  cloudy,
  rain,
  heavyRain,
  thunderstorm,
  snow,
  blizzard,
}

NovelWeatherEffect novelWeatherEffectFromKey(String raw) {
  final key = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  if (key.isEmpty || key == 'clear' || key == 'sunny' || key.contains('晴')) {
    return NovelWeatherEffect.none;
  }
  if (key == 'cloudy' || key.contains('多云') || key.contains('阴')) {
    return NovelWeatherEffect.cloudy;
  }
  if (key == 'thunderstorm' || key.contains('雷暴') || key.contains('雷阵雨') || key.contains('雷雨')) {
    return NovelWeatherEffect.thunderstorm;
  }
  if (key == 'heavy_rain' || key.contains('暴雨') || key.contains('大雨')) {
    return NovelWeatherEffect.heavyRain;
  }
  if (key == 'blizzard' || key.contains('暴雪') || key.contains('风雪')) {
    return NovelWeatherEffect.blizzard;
  }
  if (key == 'snow' || key.contains('雪')) {
    return NovelWeatherEffect.snow;
  }
  if (key == 'rain' || key.contains('小雨') || key.contains('细雨') || key == '雨') {
    return NovelWeatherEffect.rain;
  }
  return NovelWeatherEffect.none;
}

extension NovelWeatherEffectLabel on NovelWeatherEffect {
  String get label {
    return switch (this) {
      NovelWeatherEffect.none => '晴',
      NovelWeatherEffect.cloudy => '阴',
      NovelWeatherEffect.rain => '小雨',
      NovelWeatherEffect.heavyRain => '大雨',
      NovelWeatherEffect.thunderstorm => '雷暴雨',
      NovelWeatherEffect.snow => '雪',
      NovelWeatherEffect.blizzard => '暴雪',
    };
  }

  IconData get icon {
    return switch (this) {
      NovelWeatherEffect.none => Icons.wb_sunny_outlined,
      NovelWeatherEffect.cloudy => Icons.cloud_outlined,
      NovelWeatherEffect.rain => Icons.water_drop_outlined,
      NovelWeatherEffect.heavyRain => Icons.water_rounded,
      NovelWeatherEffect.thunderstorm => Icons.thunderstorm_outlined,
      NovelWeatherEffect.snow => Icons.ac_unit_rounded,
      NovelWeatherEffect.blizzard => Icons.ac_unit_rounded,
    };
  }
}

enum NovelTimePeriod {
  morning,
  noon,
  afternoon,
  evening,
  night,
  midnight,
}

NovelTimePeriod novelTimePeriodFromKey(String raw) {
  final key = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  if (key == 'midnight' || key.contains('凌晨') || key.contains('深夜')) {
    return NovelTimePeriod.midnight;
  }
  if (key == 'night' || key.contains('夜晚') || key.contains('晚上')) {
    return NovelTimePeriod.night;
  }
  if (key == 'evening' || key.contains('傍晚') || key.contains('黄昏')) {
    return NovelTimePeriod.evening;
  }
  if (key == 'afternoon' || key.contains('下午') || key.contains('午后')) {
    return NovelTimePeriod.afternoon;
  }
  if (key == 'noon' || key.contains('中午') || key.contains('正午')) {
    return NovelTimePeriod.noon;
  }
  return NovelTimePeriod.morning;
}

extension NovelTimePeriodVisual on NovelTimePeriod {
  String get label {
    return switch (this) {
      NovelTimePeriod.morning => '早晨',
      NovelTimePeriod.noon => '中午',
      NovelTimePeriod.afternoon => '下午',
      NovelTimePeriod.evening => '傍晚',
      NovelTimePeriod.night => '夜晚',
      NovelTimePeriod.midnight => '深夜',
    };
  }

  IconData get icon {
    return switch (this) {
      NovelTimePeriod.morning => Icons.wb_twilight_outlined,
      NovelTimePeriod.noon => Icons.light_mode_outlined,
      NovelTimePeriod.afternoon => Icons.wb_sunny_outlined,
      NovelTimePeriod.evening => Icons.wb_twilight_rounded,
      NovelTimePeriod.night => Icons.nights_stay_outlined,
      NovelTimePeriod.midnight => Icons.dark_mode_outlined,
    };
  }
}

class NovelTimeOverlay extends StatelessWidget {
  const NovelTimeOverlay({
    super.key,
    required this.period,
    this.weatherEffect = NovelWeatherEffect.none,
  });

  final NovelTimePeriod period;
  final NovelWeatherEffect weatherEffect;

  bool get _isWetWeather => switch (weatherEffect) {
        NovelWeatherEffect.cloudy ||
        NovelWeatherEffect.rain ||
        NovelWeatherEffect.heavyRain ||
        NovelWeatherEffect.thunderstorm => true,
        _ => false,
      };

  bool get _isSnowWeather => switch (weatherEffect) {
        NovelWeatherEffect.snow || NovelWeatherEffect.blizzard => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    // 时间只负责“基础光照”。天气拥有更高视觉优先级：
    // 阴雨/雷暴会压掉早晨、下午、傍晚的暖色，雪天则改成冷白漫射光。
    // 这样不会出现“明媚雷暴雨”或“橙红暴雪”的违和组合。
    final Color tint;
    final List<Color> lightColors;

    if (weatherEffect == NovelWeatherEffect.thunderstorm) {
      tint = switch (period) {
        NovelTimePeriod.morning => const Color(0x24415267),
        NovelTimePeriod.noon => const Color(0x1E46576A),
        NovelTimePeriod.afternoon => const Color(0x263C4D61),
        NovelTimePeriod.evening => const Color(0x30313D52),
        NovelTimePeriod.night => const Color(0x56203350),
        NovelTimePeriod.midnight => const Color(0x7210192C),
      };
      lightColors = switch (period) {
        NovelTimePeriod.morning || NovelTimePeriod.noon => const <Color>[
            Color(0x1C8192A4), Color(0x123C4E62), Colors.transparent,
          ],
        NovelTimePeriod.afternoon => const <Color>[
            Color(0x174B5D70), Color(0x16334255), Colors.transparent,
          ],
        NovelTimePeriod.evening => const <Color>[
            Color(0x123A465A), Color(0x26303A4C), Color(0x30090E19),
          ],
        NovelTimePeriod.night => const <Color>[
            Color(0x102F4868), Color(0x35223653), Color(0x55080D18),
          ],
        NovelTimePeriod.midnight => const <Color>[
            Color(0x0D263B59), Color(0x4A14233A), Color(0x70050912),
          ],
      };
    } else if (weatherEffect == NovelWeatherEffect.heavyRain ||
        weatherEffect == NovelWeatherEffect.rain ||
        weatherEffect == NovelWeatherEffect.cloudy) {
      final strength = weatherEffect == NovelWeatherEffect.heavyRain
          ? 1.0
          : weatherEffect == NovelWeatherEffect.rain
              ? .72
              : .52;
      final neutralAlpha = (0x24 * strength).round().clamp(0, 255).toInt();
      tint = switch (period) {
        NovelTimePeriod.morning => Color.fromARGB(neutralAlpha, 75, 91, 108),
        NovelTimePeriod.noon => Color.fromARGB((neutralAlpha * .55).round(), 210, 219, 225),
        NovelTimePeriod.afternoon => Color.fromARGB(neutralAlpha, 76, 91, 106),
        NovelTimePeriod.evening => Color.fromARGB((neutralAlpha * 1.15).round().clamp(0, 255).toInt(), 61, 66, 82),
        NovelTimePeriod.night => const Color(0x4A203860),
        NovelTimePeriod.midnight => const Color(0x7310192C),
      };
      lightColors = switch (period) {
        NovelTimePeriod.morning => <Color>[
            Color.fromARGB((26 * strength).round(), 164, 177, 187),
            Color.fromARGB((12 * strength).round(), 104, 119, 132),
            Colors.transparent,
          ],
        NovelTimePeriod.noon => <Color>[
            Color.fromARGB((18 * strength).round(), 226, 232, 235),
            Colors.transparent,
            Colors.transparent,
          ],
        NovelTimePeriod.afternoon => <Color>[
            Color.fromARGB((22 * strength).round(), 138, 149, 159),
            Color.fromARGB((12 * strength).round(), 78, 91, 104),
            Colors.transparent,
          ],
        NovelTimePeriod.evening => <Color>[
            Color.fromARGB((18 * strength).round(), 92, 96, 108),
            Color.fromARGB((22 * strength).round(), 58, 63, 78),
            const Color(0x220B1020),
          ],
        NovelTimePeriod.night => const <Color>[
            Color(0x142D4B77), Color(0x2B213B61), Color(0x4D080D1A),
          ],
        NovelTimePeriod.midnight => const <Color>[
            Color(0x12243B64), Color(0x46101E38), Color(0x6D050A14),
          ],
      };
    } else if (_isSnowWeather) {
      final blizzard = weatherEffect == NovelWeatherEffect.blizzard;
      tint = switch (period) {
        NovelTimePeriod.morning => Color(blizzard ? 0x24D8E6F2 : 0x1CE8F4FC),
        NovelTimePeriod.noon => Color(blizzard ? 0x20E1EAF1 : 0x18F2F8FC),
        NovelTimePeriod.afternoon => Color(blizzard ? 0x24CCD9E6 : 0x1BDDEAF4),
        NovelTimePeriod.evening => Color(blizzard ? 0x2A8799B2 : 0x229BAEC7),
        NovelTimePeriod.night => const Color(0x4D294568),
        NovelTimePeriod.midnight => const Color(0x68203957),
      };
      lightColors = switch (period) {
        NovelTimePeriod.morning => <Color>[
            Color(blizzard ? 0x30EDF4F8 : 0x35F5FAFC),
            const Color(0x14C8D8E6),
            Colors.transparent,
          ],
        NovelTimePeriod.noon => <Color>[
            Color(blizzard ? 0x2AE9F0F4 : 0x30F8FBFD),
            const Color(0x10D8E4EC),
            Colors.transparent,
          ],
        NovelTimePeriod.afternoon => const <Color>[
            Color(0x28E1EAF2), Color(0x139FB4C8), Colors.transparent,
          ],
        NovelTimePeriod.evening => const <Color>[
            Color(0x2097A8BE), Color(0x1C687A95), Color(0x220B1320),
          ],
        NovelTimePeriod.night => const <Color>[
            Color(0x183A5C83), Color(0x302A4364), Color(0x4B09101C),
          ],
        NovelTimePeriod.midnight => const <Color>[
            Color(0x122C4B71), Color(0x44213B5C), Color(0x65060D18),
          ],
      };
    } else {
      tint = switch (period) {
        NovelTimePeriod.morning => const Color(0x18FFD49A),
        NovelTimePeriod.noon => const Color(0x06FFFBEA),
        NovelTimePeriod.afternoon => const Color(0x17F1B06E),
        NovelTimePeriod.evening => const Color(0x32B85D38),
        NovelTimePeriod.night => const Color(0x4A203860),
        NovelTimePeriod.midnight => const Color(0x7310192C),
      };

      lightColors = switch (period) {
        NovelTimePeriod.morning => const <Color>[
            Color(0x3AFFDCA8), Color(0x0AFFF0D0), Colors.transparent,
          ],
        NovelTimePeriod.noon => const <Color>[
            Color(0x16FFFCE9), Colors.transparent, Colors.transparent,
          ],
        NovelTimePeriod.afternoon => const <Color>[
            Color(0x28F4B66F), Color(0x09E59A52), Colors.transparent,
          ],
        NovelTimePeriod.evening => const <Color>[
            Color(0x38D77B50), Color(0x1CA14642), Color(0x260B1020),
          ],
        NovelTimePeriod.night => const <Color>[
            Color(0x142D4B77), Color(0x2B213B61), Color(0x4D080D1A),
          ],
        NovelTimePeriod.midnight => const <Color>[
            Color(0x12243B64), Color(0x46101E38), Color(0x6D050A14),
          ],
      };
    }

    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
        color: tint,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: period == NovelTimePeriod.morning && !_isWetWeather
                  ? Alignment.topLeft
                  : Alignment.topCenter,
              end: Alignment.bottomRight,
              stops: const <double>[0, .48, 1],
              colors: lightColors,
            ),
          ),
        ),
      ),
    );
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
    if (_animationsDisabled ||
        widget.effect == NovelWeatherEffect.none ||
        widget.effect == NovelWeatherEffect.cloudy) {
      // 阴天只是一层静态色调，不需要让 AnimationController 永久 repeat。
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
            final rawPhase = _animationsDisabled ? .18 : _controller.value;
            // 手机端把天气绘制节奏限制在约 20fps。AnimatedBuilder 仍可接收 ticker，
            // 但 phase 未变化的帧 shouldRepaint 会返回 false，显著减少 Canvas 重绘。
            final paintPhase = compact && !_animationsDisabled
                ? (rawPhase * 240).floorToDouble() / 240
                : rawPhase;
            return CustomPaint(
              painter: _NovelWeatherPainter(
                effect: widget.effect,
                phase: paintPhase,
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
      case NovelWeatherEffect.cloudy:
        _paintCloudy(canvas, size);
        return;
      case NovelWeatherEffect.rain:
        _paintRain(canvas, size);
        return;
      case NovelWeatherEffect.heavyRain:
        _paintHeavyRain(canvas, size);
        return;
      case NovelWeatherEffect.snow:
        _paintSnow(canvas, size);
        return;
      case NovelWeatherEffect.blizzard:
        _paintBlizzard(canvas, size);
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

    final count = compact ? 82 : 176;
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

  void _paintCloudy(Canvas canvas, Size size) {
    final shade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const <Color>[
          Color(0x342B3440), Color(0x162C3640), Color(0x0C202832),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, shade);

    final cloudPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.08, -.92),
        radius: 1.18,
        colors: const <Color>[
          Color(0x384D5864), Color(0x1D3C4650), Colors.transparent,
        ],
        stops: const <double>[0, .52, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, cloudPaint);
  }

  void _paintHeavyRain(Canvas canvas, Size size) {
    final dark = Paint()..color = const Color(0x24202B36);
    canvas.drawRect(Offset.zero & size, dark);
    _paintRain(canvas, size);

    final extraPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x55DFEEF7);
    final count = compact ? 58 : 136;
    for (var i = 0; i < count; i++) {
      final depth = _hash(i, 81);
      final travel = (_hash(i, 82) + phase * (2 + (i % 3))) % 1.0;
      final length = 9.0 + depth * 24.0;
      final x = _hash(i, 83) * (size.width + 44) - 22 + travel * 16;
      final y = travel * (size.height + 56) - 34;
      extraPaint.strokeWidth = .30 + depth * .52;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 3 + depth * 5.5, y + length),
        extraPaint,
      );
    }
  }

  void _paintBlizzard(Canvas canvas, Size size) {
    final veil = Paint()..color = const Color(0x283B4754);
    canvas.drawRect(Offset.zero & size, veil);
    _paintSnow(canvas, size);

    final streakPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x65F3F7FA);
    final count = compact ? 50 : 110;
    for (var i = 0; i < count; i++) {
      final depth = _hash(i, 91);
      final travel = (_hash(i, 92) + phase * (2 + (i % 2))) % 1.0;
      final x = travel * (size.width + 90) - 45;
      final y = _hash(i, 93) * size.height +
          math.sin(phase * math.pi * 2 + i) * 18;
      final len = 10 + depth * 24;
      streakPaint.strokeWidth = .45 + depth * .8;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + len, y + len * .28),
        streakPaint,
      );
    }
  }

  void _paintThunderstorm(Canvas canvas, Size size) {
    // 雷暴雨先持续压暗环境，再叠加细密暴雨和随机雷光。
    // 暗部保持稳定，闪电出现时才有足够反差和压迫感。
    final stormDarkPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0x92050B12),
          const Color(0x7208121C),
          const Color(0x62050A10),
        ],
        stops: const <double>[0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, stormDarkPaint);

    // 顶部再压一层乌云阴影，让天空比地面更沉，不做成均匀黑色蒙版。
    final cloudShadePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.18, -.92),
        radius: 1.15,
        colors: <Color>[
          const Color(0x78101825),
          const Color(0x3D111A24),
          Colors.transparent,
        ],
        stops: const <double>[0, .52, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, cloudShadePaint);

    // 雷暴雨仍使用细雨丝，不用粗白线；强度主要来自密度、速度和环境压暗。
    _paintRain(canvas, size);

    final extraPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x45DDEBF4);
    final extraCount = compact ? 38 : 82;
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
      ..color = const Color(0xFFE4EEFF).withOpacity((flash * .46).clamp(0.0, .46).toDouble());
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

    final count = compact ? 50 : 108;
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
    this.fallbackAsset = '',
    this.characterPresent = false,
    this.isGenerating = false,
    this.weatherEffect = NovelWeatherEffect.none,
    this.timePeriod = NovelTimePeriod.noon,
  });

  final String url;
  final String fallbackAsset;
  final bool characterPresent;
  final bool isGenerating;
  final NovelWeatherEffect weatherEffect;
  final NovelTimePeriod timePeriod;

  @override
  State<NovelWorldBackground> createState() => _NovelWorldBackgroundState();
}

class _NovelWorldBackgroundState extends State<NovelWorldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController;
  bool _lowPowerEffects = false;
  bool _animationsDisabled = false;

  // 【核心修复】真正显示在屏幕上的 url，只有在新图完整解码完成后才会更新。
  // widget.url 变化并不会立刻触发 AnimatedSwitcher 切换，
  // 避免“动画计时器跑完了，但图片还没解码完”导致的黑屏/白屏。
  late String _displayedUrl;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );
    _displayedUrl = widget.url.trim();
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
  void didUpdateWidget(covariant NovelWorldBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.url.trim();
    if (next != oldWidget.url.trim()) {
      _preloadThenSwap(next);
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    _loadToken++; // 让所有还在飞行中的 precache 回调失效
    super.dispose();
  }

  ImageProvider? _providerFor(String value) {
    if (value.isEmpty) return null;
    if (value.startsWith('data:image/')) {
      try {
        return MemoryImage(base64Decode(value.split(',').last));
      } catch (_) {
        return null;
      }
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return NetworkImage(CdnUtil.resize(value, width: 1080)); // 压缩全屏背景
    }
    return AssetImage(value);
  }

  /// 新图先在后台完整解码，解码成功（或明确失败）之后再 setState 触发
  /// AnimatedSwitcher 的切换动画。这样动画开始时新图必然已经能立刻画出来，
  /// 老图会一直原地不动，杜绝“动画时间到了但图还没到”的黑屏窗口。
  Future<void> _preloadThenSwap(String value) async {
    final token = ++_loadToken;

    if (value.isEmpty) {
      if (mounted && token == _loadToken) {
        setState(() => _displayedUrl = value);
      }
      return;
    }

    final provider = _providerFor(value);
    if (provider == null) {
      // 无法识别的 url（比如 data: 解析失败），直接切换让 errorBuilder 兜底。
      if (mounted && token == _loadToken) {
        setState(() => _displayedUrl = value);
      }
      return;
    }

    try {
      await precacheImage(provider, context);
    } catch (_) {
      // 加载失败也要切换过去：交给 _image() 里的 errorBuilder 兜底，
      // 不要让背景永远卡在旧图上一动不动。
    }

    // token 不一致说明这期间 url 又变了（用户快速连续切换场景），
    // 这次已经过期的加载结果直接丢弃，只认最新的那次。
    if (!mounted || token != _loadToken) return;
    setState(() => _displayedUrl = value);
  }

  Widget _fallback() {
    final asset = widget.fallbackAsset.trim();
    if (asset.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF25282B),
              Color(0xFF121416),
              Color(0xFF08090A),
            ],
          ),
        ),
      );
    }

    // 兜底图只负责避免“背景为空 = 黑屏”。
    // 旧版本这里保留了一层 sigma=0 的 BackdropFilter，实际没有任何模糊效果，
    // 反而增加额外合成层；直接绘制兜底图即可。
    return Transform.scale(
      scale: 1.06,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF25282B),
                Color(0xFF121416),
                Color(0xFF08090A),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image() {
    // 注意：这里读的是 _displayedUrl（已经确认解码完成的图），
    // 不是 widget.url（可能还在飞行中的新值）。
    final value = _displayedUrl;
    final provider = _providerFor(value);
    if (provider == null) return _fallback();
    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      // 正常情况下走到这里时图片已经被 precacheImage 解码过、在缓存里，
      // errorBuilder 只兜底“缓存被回收 / 解码失败”这种极端情况。
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. 移除了默认的强压暗，只在雷暴或暴雪等极端天气时保留极轻微的氛围光暗度
    final weatherDim = switch (widget.weatherEffect) {
      NovelWeatherEffect.thunderstorm => .25,
      NovelWeatherEffect.heavyRain => .12,
      NovelWeatherEffect.blizzard => .10,
      _ => .0,
    };
    
    // 不再因为“有角色在场”就强制变暗
    final dim = weatherDim;
    final blur = widget.characterPresent ? 2.2 : 0.0;

    final imageLayer = AnimatedSwitcher(
      // 保持较长的呼吸感，1500ms 适合剧情氛围
      duration: Duration(milliseconds: _lowPowerEffects ? 800 : 1500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey<String>(_displayedUrl);

        if (isIncoming) {
          // 【新图出场】：透明度 0 -> 1 渐显，同时尺寸 1.05 -> 1.0 微距拉近
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.05, end: 1.0).animate(animation),
              child: child,
            ),
          );
        } else {
          // 【老图退场】：直接 return child，不做任何透明度衰减！
          // AnimatedSwitcher 默认会将新图盖在老图上方。
          // 这样老图会在整个 1.5 秒内保持 100% 可见，直到新图完全覆盖并结束动画，
          // 完美吃掉网络图片加载的延迟白屏，实现真正的无缝溶解。
          return child; 
        }
      },
      child: SizedBox.expand(
        key: ValueKey<String>(_displayedUrl),
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
        NovelTimeOverlay(
          period: widget.timePeriod,
          weatherEffect: widget.weatherEffect,
        ),
        
        // 2. 天气导致的基础环境压暗（现已极其微弱）
        if (dim > 0)
          AnimatedContainer(
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutCubic,
            color: Colors.black.withOpacity(dim),
          ),
          
        if (widget.weatherEffect != NovelWeatherEffect.none)
          NovelWeatherOverlay(effect: widget.weatherEffect),
          
        // 3. 彻底删除了高达 72% 透明度的深蓝灰阅读遮罩！
        // 彻底删除了 70% 透明度的四周 RadialGradient 暗角晕影！

        // 仅在最底部保留一层极淡极淡的渐变，防止背景正好是纯白色时影响摇杆/导航栏视认性
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.7, 1.0],
              colors: <Color>[
                Colors.transparent,
                Color(0x1A000000), // 只有 10% 的极弱黑边，几乎不可见
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


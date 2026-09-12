import 'dart:async';
import 'dart:math' as math;
import 'dart:ui'; // PointerDeviceKind / 绘制支持

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youran_ai/vfx/procedural_skill_vfx.dart';

import 'novel_socket_service.dart';

/// 战斗页返回给剧情层的最小结果。
enum YoranBattleOutcome {
  victory,
  defeat,
  escaped,
}

/// 一名静态敌人的展示与基础生命数据。
/// 同一场战斗最多使用前 5 名敌人，并按列表顺序依次登场。
class YoranBattleEnemy {
  const YoranBattleEnemy({
    required this.name,
    this.portrait = '',
    this.maxHp = 100,
    this.currentHp,
    this.currentEnergy,
    this.condition = '',
    this.realm = '',
    this.difficultyLabel = '',
    this.openingEstimate = '',
    this.basicAttackPowerPercent = 65,
    this.hitBonus = 4,
    this.playerDamageMultiplier = 1,
    this.opponentDamageMultiplier = 1,
    this.playerHitBonusShift = 0,
    this.opponentHitBonusShift = 0,
    this.allowInstantDefeat = false,
    this.skills = const <YoranBattleSkill>[],
  });

  final String name;
  final String portrait;
  final int maxHp;
  final int? currentHp;
  final int? currentEnergy;
  final String condition;
  final String realm;
  final String difficultyLabel;
  final String openingEstimate;
  final int basicAttackPowerPercent;
  final int hitBonus;
  final double playerDamageMultiplier;
  final double opponentDamageMultiplier;
  final int playerHitBonusShift;
  final int opponentHitBonusShift;
  final bool allowInstantDefeat;
  final List<YoranBattleSkill> skills;
}

/// 后端技能库在战斗页中的运行时视图。
///
/// 新协议只执行百分比技能：伤害使用 power_percent，治疗/回能使用最大值百分比。
/// 旧 damage.min/max、amount、extra_damage 不再读取或换算。
class YoranBattleSkill {
  const YoranBattleSkill({
    this.id = '',
    required this.name,
    required this.detail,
    this.archetype = 'direct',
    this.quality = 0,
    this.powerPercent = 0,
    this.hitBonus = 4,
    this.energyCost = 0,
    this.energyMaxQiPercent = 0,
    this.cooldown = 0,
    this.burnTurns = 0,
    this.burnPowerPercent = 0,
    this.healMaxHpPercent = 0,
    this.lifestealPercent = 0,
    this.healthCost = 0,
    this.stunTurns = 0,
    this.guardReductionPercent = 0,
    this.enemyHitDifficultyBonus = 0,
    this.exposeHitBonus = 0,
    this.exposeExtraPowerPercent = 0,
    this.exposes = false,
    this.guarding = false,
    this.dodging = false,
    this.resting = false,
    this.piercesGuard = false,
    this.targetSelf = false,
    this.canSelfKill = false,
    this.counterPowerPercent = 0,
    this.vfxSpec = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String detail;
  final String archetype;
  final int quality;
  /// 100 = 100% 标准基础威力。实际点数只在本场战斗结算时计算。
  final int powerPercent;
  final int hitBonus;
  final int energyCost;
  final int energyMaxQiPercent;
  final int cooldown;
  final int burnTurns;
  final int burnPowerPercent;
  final int healMaxHpPercent;
  final int lifestealPercent;
  final int healthCost;
  final int stunTurns;
  final int guardReductionPercent;
  final int enemyHitDifficultyBonus;
  final int exposeHitBonus;
  final int exposeExtraPowerPercent;
  final bool exposes;
  final bool guarding;
  final bool dodging;
  final bool resting;
  final bool piercesGuard;
  final bool targetSelf;
  final bool canSelfKill;
  final int counterPowerPercent;
  /// 后端在技能首次学会/命名时生成并持久化的受限 VFX DSL。
  /// 战斗中只解释执行，不再调用 LLM。
  final Map<String, dynamic> vfxSpec;

  bool get isSelfAction => targetSelf || guarding || dodging || resting;
  bool get hasVfx => vfxSpec.isNotEmpty;

  String get iconType {
    final type = archetype.trim().toLowerCase();
    if (const <String>{
      'direct', 'dot', 'guard', 'evade', 'heal', 'energy',
      'lifesteal', 'expose', 'counter', 'stun',
    }.contains(type)) return type;
    if (burnTurns > 0) return 'dot';
    if (guarding) return 'guard';
    if (dodging) return 'evade';
    if (lifestealPercent > 0) return 'lifesteal';
    if (exposes) return 'expose';
    if (counterPowerPercent > 0) return 'counter';
    if (stunTurns > 0) return 'stun';
    if (healMaxHpPercent > 0 && powerPercent <= 0) return 'heal';
    if ((energyMaxQiPercent > 0 || resting) && powerPercent <= 0) return 'energy';
    return 'direct';
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static Map<String, dynamic> _stringMap(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static YoranBattleSkill? fromState(dynamic raw) {
    if (raw is! Map) return null;
    final skill = _stringMap(raw);
    final name = '${skill['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;

    final spec = _stringMap(skill['battle_spec']);
    if (spec.isEmpty) return null;
    final powerSystem = '${spec['power_system'] ?? ''}'.trim().toLowerCase();
    final schemaVersion = _asInt(spec['schema_version'] ?? spec['version']);
    if (powerSystem != 'percent_v1' && schemaVersion < 4) return null;

    var burnTurns = 0;
    var burnPowerPercent = 0;
    var healMaxHpPercent = 0;
    var energyMaxQiPercent = 0;
    var lifestealPercent = 0;
    var stunTurns = 0;
    var guardReductionPercent = 0;
    var enemyHitDifficultyBonus = 0;
    var exposeHitBonus = 0;
    var exposeExtraPowerPercent = 0;
    var guarding = false;
    var dodging = false;
    var exposes = false;
    var counterPowerPercent = 0;

    final effects = spec['effects'];
    if (effects is List) {
      for (final rawEffect in effects.take(2)) {
        final effect = _stringMap(rawEffect);
        switch ('${effect['type'] ?? ''}'.trim().toLowerCase()) {
          case 'damage_over_time':
            burnTurns = _asInt(effect['duration']).clamp(0, 3).toInt();
            burnPowerPercent =
                _asInt(effect['power_percent']).clamp(0, 120).toInt();
            break;
          case 'evade':
            dodging = true;
            enemyHitDifficultyBonus =
                _asInt(effect['enemy_hit_difficulty_bonus'], 5)
                    .clamp(1, 8)
                    .toInt();
            break;
          case 'guard':
            guarding = true;
            guardReductionPercent =
                _asInt(effect['reduction_percent'], 50).clamp(10, 75).toInt();
            break;
          case 'heal':
            healMaxHpPercent =
                _asInt(effect['max_hp_percent']).clamp(0, 60).toInt();
            break;
          case 'energy_restore':
            energyMaxQiPercent =
                _asInt(effect['max_energy_percent']).clamp(0, 60).toInt();
            break;
          case 'lifesteal':
            lifestealPercent = _asInt(effect['percent']).clamp(0, 100).toInt();
            break;
          case 'stun':
            stunTurns = _asInt(effect['duration'], 1).clamp(0, 1).toInt();
            break;
          case 'next_attack_bonus':
            exposes = true;
            exposeHitBonus = _asInt(effect['hit_bonus'], 2).clamp(0, 4).toInt();
            exposeExtraPowerPercent =
                _asInt(effect['extra_power_percent']).clamp(0, 140).toInt();
            break;
          case 'counter':
            counterPowerPercent =
                _asInt(effect['power_percent']).clamp(0, 420).toInt();
            break;
        }
      }
    }

    final powerPercent = _asInt(spec['power_percent']).clamp(0, 500).toInt();
    final energyCost = _asInt(spec['energy_cost']).clamp(0, 40).toInt();
    final cooldown = _asInt(spec['cooldown']).clamp(0, 3).toInt();
    final quality = _asInt(spec['quality'], 3).clamp(1, 10).toInt();
    final designNote = '${spec['design_note'] ?? skill['description'] ?? ''}'.trim();
    final effectLabels = <String>[
      if (powerPercent > 0) '威力 $powerPercent%',
      if (burnPowerPercent > 0 && burnTurns > 0)
        '持续$burnTurns回合 · 每回合威力$burnPowerPercent%',
      if (healMaxHpPercent > 0) '恢复最大生命$healMaxHpPercent%',
      if (energyMaxQiPercent > 0) '恢复最大精力$energyMaxQiPercent%',
      if (lifestealPercent > 0) '吸血$lifestealPercent%',
      if (guardReductionPercent > 0) '减伤$guardReductionPercent%',
      if (enemyHitDifficultyBonus > 0) '敌方命中难度+$enemyHitDifficultyBonus',
      if (stunTurns > 0) '压制1回合',
      if (exposes && exposeExtraPowerPercent > 0)
        '下一击命中+$exposeHitBonus · 额外威力$exposeExtraPowerPercent%',
      if (counterPowerPercent > 0) '受击反击 · 威力$counterPowerPercent%',
    ];
    final gameplayDetail = effectLabels.join(' · ');

    if (powerPercent <= 0 &&
        burnPowerPercent <= 0 &&
        healMaxHpPercent <= 0 &&
        energyMaxQiPercent <= 0 &&
        lifestealPercent <= 0 &&
        guardReductionPercent <= 0 &&
        enemyHitDifficultyBonus <= 0 &&
        stunTurns <= 0 &&
        exposeExtraPowerPercent <= 0 &&
        counterPowerPercent <= 0) {
      return null;
    }

    return YoranBattleSkill(
      id: '${skill['id'] ?? ''}'.trim(),
      name: name,
      detail: gameplayDetail.isNotEmpty
          ? gameplayDetail
          : (designNote.isEmpty ? '暂无技能描述' : designNote),
      archetype: '${spec['archetype'] ?? skill['category'] ?? 'direct'}'
          .trim()
          .toLowerCase(),
      quality: quality,
      powerPercent: powerPercent,
      hitBonus: _asInt(spec['hit_bonus'], 4).clamp(0, 10).toInt(),
      energyCost: energyCost,
      energyMaxQiPercent: energyMaxQiPercent,
      cooldown: cooldown,
      burnTurns: burnTurns,
      burnPowerPercent: burnPowerPercent,
      healMaxHpPercent: healMaxHpPercent,
      lifestealPercent: lifestealPercent,
      healthCost: _asInt(spec['health_cost']).clamp(0, 100).toInt(),
      stunTurns: stunTurns,
      guardReductionPercent: guardReductionPercent,
      enemyHitDifficultyBonus: enemyHitDifficultyBonus,
      exposeHitBonus: exposeHitBonus,
      exposeExtraPowerPercent: exposeExtraPowerPercent,
      exposes: exposes,
      guarding: guarding,
      dodging: dodging,
      piercesGuard: '${spec['archetype'] ?? ''}'.trim().toLowerCase() == 'control',
      targetSelf: '${spec['target'] ?? ''}'.trim().toLowerCase() == 'self',
      canSelfKill: _asBool(spec['can_self_kill']),
      counterPowerPercent: counterPowerPercent,
      vfxSpec: Map<String, dynamic>.unmodifiable(_stringMap(skill['vfx_spec'])),
    );
  }
}

double _battleVfxDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? fallback;
}

Color _battleVfxPalette(String palette) => switch (palette.trim().toLowerCase()) {
      'ice_blue' => const Color(0xFF83E7FF),
      'flame' => const Color(0xFFFF7A2C),
      'emerald' => const Color(0xFF6DE6B4),
      'gold' => const Color(0xFFFFD873),
      'crimson' => const Color(0xFFFF5C67),
      'shadow' => const Color(0xFF9670C9),
      'white' => const Color(0xFFF5F3FF),
      _ => const Color(0xFFB779FF),
    };

const Set<String> _battleVfxHumanTokens = <String>{
  'human', 'humanoid', 'person', 'body', 'face', 'head', 'arm', 'leg', 'hand', 'foot',
  'warrior', 'swordsman', 'samurai', 'ninja', 'knight', 'fighter', 'character',
  'figure', 'stick', 'stickman', 'silhouette', 'man', 'woman', 'girl', 'boy', 'hero', 'avatar',
};

bool _battleVfxLooksHuman(dynamic value) {
  final text = '${value ?? ''}'.trim().toLowerCase();
  if (text.isEmpty) return false;
  return _battleVfxHumanTokens.any(text.contains);
}

Map<String, dynamic> _sanitizeBattleVfxSpec(Map<String, dynamic> raw) {
  if (raw.isEmpty) return const <String, dynamic>{};
  final spec = Map<String, dynamic>.from(raw);
  final identity = '${spec['visual_identity'] ?? ''}'.trim().toLowerCase();
  if (_battleVfxLooksHuman(identity) || identity == 'transformation') {
    spec['visual_identity'] = 'elemental_construct';
  }
  final rawSequence = spec['sequence'];
  if (rawSequence is List) {
    final filtered = <Map<String, dynamic>>[];
    for (final rawItem in rawSequence.take(12)) {
      if (rawItem is! Map) continue;
      final item = rawItem.map((key, value) => MapEntry('$key', value));
      final blocked = _battleVfxLooksHuman(item['type']) ||
          _battleVfxLooksHuman(item['shape']) ||
          _battleVfxLooksHuman(item['motion']) ||
          _battleVfxLooksHuman(item['path']) ||
          _battleVfxLooksHuman(item['origin']) ||
          _battleVfxLooksHuman(item['role']) ||
          _battleVfxLooksHuman(item['subject']) ||
          _battleVfxLooksHuman(item['subject_type']);
      if (blocked) continue;
      filtered.add(item);
    }
    spec['sequence'] = filtered;
  }
  return Map<String, dynamic>.unmodifiable(spec);
}


class _BattleSkillVfxPainter extends CustomPainter {
  const _BattleSkillVfxPainter({
    required this.spec,
    required this.progress,
    required this.impactProgress,
    required this.targetSelf,
    required this.hit,
    required this.critical,
  });

  final Map<String, dynamic> spec;
  final double progress;
  final double impactProgress;
  final bool targetSelf;
  final bool hit;
  final bool critical;

  Color get accent => _battleVfxPalette('${spec['palette'] ?? ''}');

  @override
  void paint(Canvas canvas, Size size) {
    // 与 2.5D 构图一致：玩家在左下近景，敌人在右侧中远景。
    final caster = Offset(size.width * .23, size.height * .58);
    final target = targetSelf
        ? Offset(size.width * .25, size.height * .58)
        : Offset(size.width * .67, size.height * .43);
    _BattleVfxGraphRenderer(spec: spec, progress: progress, accent: accent)
        .paint(canvas, size, caster: caster, target: target);

    if (hit && impactProgress > 0) {
      final t = impactProgress.clamp(0.0, 1.0).toDouble();
      final fade = (1 - t).clamp(0.0, 1.0).toDouble();
      final power = critical ? 1.0 : .72;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withOpacity(.18 * fade * power),
      );
      final center = target;
      final radius = 18 + t * (critical ? 160 : 112);
      canvas.drawCircle(center, radius, Paint()
        ..color = accent.withOpacity(.54 * fade * power)
        ..style = PaintingStyle.stroke
        ..strokeWidth = critical ? 5.0 : 2.6);
      final rays = critical ? 22 : 14;
      for (var i = 0; i < rays; i++) {
        final a = i * math.pi * 2 / rays;
        final p1 = Offset(center.dx + math.cos(a) * 12, center.dy + math.sin(a) * 12);
        final p2 = Offset(center.dx + math.cos(a) * (38 + 45 * t), center.dy + math.sin(a) * (38 + 45 * t));
        canvas.drawLine(p1, p2, Paint()
          ..color = (i.isEven ? Colors.white : accent).withOpacity(.34 * fade)
          ..strokeWidth = i.isEven ? 1.3 : .7
          ..strokeCap = StrokeCap.round);
      }
    }

    final caption = '${spec['caption'] ?? ''}'.trim();
    if (caption.isNotEmpty) {
      final intensity = YoranBattleSkill._asInt(spec['intensity'], 4).clamp(1, 10).toInt();
      final appear = (progress / .12).clamp(0.0, 1.0).toDouble();
      final disappear = ((1 - progress) / .18).clamp(0.0, 1.0).toDouble();
      final opacity = math.min(appear, disappear) * .90;
      final painter = TextPainter(
        text: TextSpan(
          text: caption,
          style: TextStyle(
            color: Colors.white.withOpacity(opacity),
            fontSize: intensity >= 8 ? 19 : 14,
            fontWeight: FontWeight.w900,
            letterSpacing: intensity >= 8 ? 4.2 : 2.5,
            shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 10)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * .66);
      painter.paint(canvas, Offset((size.width - painter.width) / 2, size.height * .22));
    }
  }

  @override
  bool shouldRepaint(covariant _BattleSkillVfxPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.impactProgress != impactProgress ||
      oldDelegate.spec != spec ||
      oldDelegate.hit != hit ||
      oldDelegate.critical != critical ||
      oldDelegate.targetSelf != targetSelf;
}


class _BattleVfxGraphRenderer {
  const _BattleVfxGraphRenderer({
    required this.spec,
    required this.progress,
    required this.accent,
  });

  final Map<String, dynamic> spec;
  final double progress;
  final Color accent;

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, item) => MapEntry('$key', item));
  }

  double _d(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  int _i(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  String _s(dynamic value, [String fallback = '']) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  double _easeOut(double t) {
    final x = _clamp01(t);
    return 1 - math.pow(1 - x, 3).toDouble();
  }

  double _easeInOut(double t) {
    final x = _clamp01(t);
    return x < .5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _pulse(double t) => math.sin(_clamp01(t) * math.pi);

  double _seed01(int index, int salt, int seed) {
    final x = math.sin((index + seed * .071) * 12.9898 + salt * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  Paint _stroke(Color color, double opacity, double width, {double blur = 0}) {
    final paint = Paint()
      ..color = color.withOpacity(_clamp01(opacity))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.35, width)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (blur > .01) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    return paint;
  }

  Paint _fill(Color color, double opacity, {double blur = 0, bool additive = false}) {
    final paint = Paint()
      ..color = color.withOpacity(_clamp01(opacity))
      ..style = PaintingStyle.fill;
    if (blur > .01) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    if (additive) paint.blendMode = BlendMode.plus;
    return paint;
  }

  void _layeredPath(
    Canvas canvas,
    Path path,
    Color color,
    double opacity,
    double width, {
    double glow = 4,
    bool whiteCore = true,
  }) {
    if (glow > .01) {
      canvas.drawPath(path, _stroke(color, opacity * .17, width * 2.5, blur: glow));
    }
    canvas.drawPath(path, _stroke(color, opacity * .78, width));
    if (whiteCore) {
      canvas.drawPath(path, _stroke(Colors.white, opacity * .78, math.max(.6, width * .20)));
    }
  }

  Offset _originFor(Map<String, dynamic> item, Size size, Offset caster, Offset target) {
    switch (_s(item['origin'], 'target').toLowerCase()) {
      case 'caster':
        return caster;
      case 'center':
        return Offset(size.width * .5, size.height * .44);
      case 'sky':
        return Offset(target.dx, size.height * .08);
      case 'ground':
        return Offset(target.dx, size.height * .72);
      default:
        return target;
    }
  }

  double _directionAngle(String direction, double randomAngle) {
    switch (direction) {
      case 'left_to_right':
        return 0;
      case 'right_to_left':
        return math.pi;
      case 'up':
        return -math.pi / 2;
      case 'down':
        return math.pi / 2;
      default:
        return randomAngle;
    }
  }

  List<dynamic> _renderSequence() {
    final raw = spec['sequence'];
    final original = raw is List ? raw : const <dynamic>[];
    if (_i(spec['schema_version'], 1) >= 3) return original;

    // Legacy V1/V2 specs used only a few coarse primitives. Upgrade them locally so
    // already-owned skills immediately benefit from V3 without another LLM request.
    final caption = _s(spec['caption']).toLowerCase();
    final element = _s(spec['element'], 'arcane').toLowerCase();
    final style = _s(spec['style'], 'burst').toLowerCase();
    final intensity = _i(spec['intensity'], 4).clamp(1, 10).toInt();
    final seed = caption.runes.fold<int>(17, (value, rune) => ((value * 31) + rune) & 0x7fffffff) % 10000;
    final particles = math.min(120, 30 + intensity * 8);

    Map<String, dynamic> n(
      String type,
      double at,
      double duration, {
      double scale = 1,
      int amount = 4,
      String direction = 'center',
      String shape = 'spark',
      String motion = 'radial',
      String path = 'straight',
      String origin = 'target',
      int particleCount = 0,
      double speed = .7,
      double spread = .6,
      double gravity = 0,
      double trail = .3,
      double glow = .35,
      int variant = 0,
      int salt = 0,
    }) => <String, dynamic>{
      'type': type, 'at': at, 'duration': duration, 'scale': scale,
      'amount': amount, 'direction': direction, 'shape': shape, 'motion': motion,
      'path': path, 'origin': origin, 'particle_count': particleCount,
      'speed': speed, 'spread': spread, 'gravity': gravity, 'trail': trail,
      'glow': glow, 'variant': variant, 'seed': (seed + salt) % 10000,
    };

    if (caption.contains('龙')) {
      return <dynamic>[
        if (intensity >= 8) n('darken', 0, .30, amount: 1, salt: 1),
        n('sigil', .02, .28, origin: 'caster', amount: 5, variant: seed % 6, salt: 2),
        n('dragon_trail', .16, .54, scale: 1.18, amount: 7, direction: 'left_to_right', path: 'serpentine', shape: element == 'ice' ? 'snow' : 'spark', particleCount: particles, trail: .82, glow: .52, salt: 3),
        n('particle_burst', .60, .28, scale: 1.2, particleCount: math.min(120, particles + 24), shape: element == 'ice' ? 'shard' : 'streak', motion: 'radial', speed: 1.05, spread: .95, gravity: element == 'ice' ? .18 : 0, trail: .48, glow: .42, salt: 4),
        n('impact_lines', .61, .18, scale: 1.3, amount: 9, salt: 5),
      ];
    }
    if (caption.contains('莲')) {
      return <dynamic>[
        n('energy_orb', .02, .26, origin: 'center', particleCount: 24, shape: 'ember', motion: 'converge', glow: .58, salt: 6),
        n('lotus', .16, .47, origin: 'center', scale: 1.18, amount: 8, variant: seed % 6, salt: 7),
        n('rune_ring', .20, .40, origin: 'center', scale: 1.32, amount: 6, variant: (seed + 2) % 6, salt: 8),
        n('petal_burst', .46, .32, origin: 'center', particleCount: math.min(100, particles), shape: 'petal', motion: 'swirl', speed: .78, spread: .88, gravity: -.06, glow: .40, salt: 9),
        n('particle_burst', .62, .28, origin: 'center', particleCount: math.min(120, particles + 28), shape: 'ember', motion: 'radial', speed: 1.1, spread: 1, trail: .38, glow: .52, salt: 10),
        n('impact_lines', .63, .18, origin: 'center', scale: 1.3, amount: 9, salt: 11),
      ];
    }
    if (style == 'slash' || <String>['斩', '刀', '剑', '刃'].any((token) => caption.contains(token))) {
      return <dynamic>[
        if (intensity >= 8) n('darken', 0, .28, amount: 1, salt: 12),
        if (element == 'lightning' || intensity >= 8) n('sigil', .02, .28, origin: 'center', amount: 5, variant: seed % 6, salt: 13),
        n('blade_manifest', .14, .34, origin: 'caster', scale: 1.16, particleCount: 22 + intensity * 3, shape: 'blade', motion: 'converge', glow: .54, salt: 14),
        n('slash', .42, .18, scale: 1.35, amount: 6, direction: 'left_to_right', path: seed.isEven ? 'crescent' : 'arc', trail: .78, glow: .54, salt: 15),
        n('particle_burst', .48, .28, particleCount: math.min(120, particles + 24), shape: 'streak', motion: 'cone', speed: 1.1, spread: .84, trail: .72, glow: .44, salt: 16),
        n('impact_lines', .49, .17, scale: 1.35, amount: 10, salt: 17),
        if (intensity >= 8) n('space_crack', .54, .38, scale: 1.2, amount: 8, path: 'zigzag', glow: .48, salt: 18),
        if (element == 'lightning') n('lightning', .57, .32, scale: 1.22, amount: 8, motion: 'scatter', salt: 19),
      ];
    }
    if (element == 'lightning') {
      return <dynamic>[
        n('sigil', .03, .30, origin: 'caster', amount: 6, variant: seed % 6, salt: 20),
        n('trail', .16, .42, origin: 'caster', direction: 'left_to_right', path: 'zigzag', particleCount: math.min(100, particles), shape: 'streak', motion: 'stream', speed: .96, spread: .32, trail: .74, glow: .38, salt: 21),
        n('lightning', .38, .36, amount: 9, motion: 'scatter', glow: .48, salt: 22),
        n('particle_burst', .58, .26, particleCount: math.min(120, particles + 18), shape: 'streak', motion: 'radial', speed: 1.02, spread: .92, trail: .58, glow: .42, salt: 23),
        n('impact_lines', .59, .18, amount: 10, scale: 1.25, salt: 24),
      ];
    }
    if (element == 'ice') {
      return <dynamic>[
        n('rune_ring', .03, .30, origin: 'caster', amount: 5, variant: seed % 6, salt: 25),
        n('trail', .16, .44, origin: 'caster', direction: 'left_to_right', path: 'wave', particleCount: math.min(90, particles), shape: 'snow', motion: 'stream', speed: .82, spread: .42, trail: .52, glow: .30, salt: 26),
        n('particle_burst', .56, .30, particleCount: math.min(120, particles + 20), shape: 'shard', motion: 'radial', speed: .98, spread: .95, gravity: .20, trail: .38, glow: .34, salt: 27),
        n('ground_crack', .58, .30, amount: 8, scale: 1.1, salt: 28),
        n('shockwave', .59, .23, scale: 1.25, amount: 5, salt: 29),
      ];
    }
    if (element == 'fire') {
      return <dynamic>[
        n('energy_orb', .03, .28, origin: 'caster', particleCount: 26 + intensity * 3, shape: 'ember', motion: 'converge', glow: .58, salt: 30),
        n('beam', .24, .42, origin: 'caster', direction: 'left_to_right', path: seed % 3 == 0 ? 'wave' : 'straight', particleCount: math.min(90, particles), shape: 'streak', motion: 'stream', speed: .96, spread: .26, trail: .70, glow: .52, salt: 31),
        n('particle_burst', .59, .28, particleCount: math.min(120, particles + 24), shape: 'ember', motion: 'radial', speed: 1.08, spread: .98, trail: .42, glow: .50, salt: 32),
        n('impact_lines', .60, .18, amount: 9, scale: 1.25, salt: 33),
      ];
    }
    if (style == 'aura') {
      return <dynamic>[
        n('rune_ring', .04, .44, origin: 'caster', amount: 6, variant: seed % 6, salt: 34),
        n('energy_orb', .18, .44, origin: 'caster', particleCount: 22 + intensity * 3, shape: 'star', motion: 'converge', glow: .44, salt: 35),
        n('particle_emitter', .20, .62, origin: 'caster', particleCount: math.min(80, particles), shape: 'star', motion: 'rise', speed: .34, spread: .72, gravity: -.14, trail: .14, glow: .30, salt: 36),
      ];
    }

    // Generic legacy skill: keep its old primary idea but add a deterministic visual identity.
    return <dynamic>[
      n('sigil', .03, .30, origin: 'caster', amount: 5, variant: seed % 6, salt: 37),
      n('energy_orb', .18, .28, origin: 'caster', particleCount: 20 + intensity * 3, shape: 'spark', motion: 'converge', glow: .46, salt: 38),
      n('projectile', .36, .30, origin: 'caster', direction: 'left_to_right', shape: seed.isEven ? 'diamond' : 'orb', path: seed % 3 == 0 ? 'arc' : 'straight', glow: .34, salt: 39),
      n('particle_burst', .60, .26, particleCount: math.min(110, particles), shape: 'spark', motion: 'radial', speed: .92, spread: .86, trail: .30, glow: .38, salt: 40),
      n('impact_lines', .61, .18, amount: 8, scale: 1.16, salt: 41),
    ];
  }

  void paint(Canvas canvas, Size size, {required Offset caster, required Offset target}) {
    final identity = _s(spec['visual_identity']).toLowerCase();
    final intensity = _i(spec['intensity'], 4).clamp(1, 10).toInt();
    final sequence = _renderSequence();

    // Cinematic skills get a subtle vignette, not a full-screen colored fog.
    if (identity == 'domain' || identity == 'magic_sigil' || identity == 'summoned_creature') {
      final r = math.max(size.width, size.height) * .72;
      final shader = RadialGradient(
        colors: <Color>[accent.withOpacity(.025 + intensity * .002), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * .5, size.height * .44), radius: r));
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    }

    for (final raw in sequence.take(10)) {
      final item = _map(raw);
      if (item.isEmpty) continue;
      final at = _d(item['at']).clamp(0.0, .97).toDouble();
      final duration = math.max(.06, _d(item['duration'], .30));
      if (progress < at) continue;
      final local = ((progress - at) / duration).clamp(0.0, 1.0).toDouble();
      _drawNode(canvas, size, caster, target, item, local, intensity);
    }
  }

  void _drawNode(
    Canvas canvas,
    Size size,
    Offset caster,
    Offset target,
    Map<String, dynamic> item,
    double t,
    int intensity,
  ) {
    final type = _s(item['type']).toLowerCase();
    final scale = _d(item['scale'], 1).clamp(.35, 2.4).toDouble();
    final amount = _i(item['amount'], 3).clamp(1, 12).toInt();
    final direction = _s(item['direction'], 'center').toLowerCase();
    final pathKind = _s(item['path'], 'straight').toLowerCase();
    final seed = _i(item['seed'], 0).clamp(0, 9999).toInt();
    final origin = _originFor(item, size, caster, target);
    final pulse = _pulse(t);
    final fade = (1 - (t - .72).clamp(0.0, .28) / .28).clamp(0.0, 1.0).toDouble();
    final glow = _d(item['glow'], .35).clamp(0.0, 1.0).toDouble();

    if (type == 'darken') {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(.50 * pulse));
      return;
    }
    if (type == 'screen_flash') {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withOpacity(.62 * pulse));
      return;
    }
    if (type == 'starfield') {
      _drawStarfield(canvas, size, item, t, fade, seed);
      return;
    }
    if (type == 'particle_emitter' || type == 'particle_burst' || type == 'petal_burst') {
      _drawParticles(canvas, size, origin, item, t, intensity,
          burst: type != 'particle_emitter', forcedShape: type == 'petal_burst' ? 'petal' : null);
      return;
    }
    if (type == 'sigil' || type == 'rune_ring') {
      _drawSigil(canvas, origin, item, t, scale, intensity, fade, ringOnly: type == 'rune_ring');
      return;
    }
    if (type == 'energy_orb' || type == 'charge' || type == 'aura') {
      _drawEnergyOrb(canvas, size, origin, item, t, scale, intensity, fade,
          aura: type == 'aura');
      return;
    }
    if (type == 'blade_manifest') {
      _drawBlade(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'beam') {
      _drawBeam(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'crescent_wave') {
      _drawCrescent(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'projectile_swarm') {
      _drawProjectileSwarm(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'dragon_trail') {
      _drawDragon(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'lotus') {
      _drawLotus(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'vortex') {
      _drawVortex(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'meteor') {
      _drawMeteor(canvas, size, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'force_field') {
      _drawForceField(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'impact_lines') {
      _drawImpactLines(canvas, origin, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'ground_crack') {
      _drawGroundCrack(canvas, size, origin, item, t, scale, fade, seed);
      return;
    }
    if (type == 'trail') {
      _drawTrail(canvas, size, caster, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'smoke' || type == 'frost_mist') {
      final smokeItem = <String, dynamic>{...item, 'shape': type == 'frost_mist' ? 'snow' : 'dust', 'motion': 'rise'};
      _drawParticles(canvas, size, origin, smokeItem, t, intensity, burst: false);
      return;
    }
    if (type == 'slash') {
      _drawSlash(canvas, size, caster, target, item, t, scale, intensity, fade, pathKind);
      return;
    }
    if (type == 'projectile') {
      _drawProjectile(canvas, size, caster, target, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'lightning') {
      _drawLightning(canvas, size, origin, target, item, t, scale, intensity, fade, seed);
      return;
    }
    if (type == 'ice_shards' || type == 'fire_particles') {
      final particleItem = <String, dynamic>{
        ...item,
        'shape': type == 'ice_shards' ? 'shard' : 'ember',
        'motion': _s(item['motion'], 'radial'),
        'particle_count': _i(item['particle_count'], amount * 9),
      };
      _drawParticles(canvas, size, origin, particleItem, t, intensity, burst: true);
      return;
    }
    if (type == 'shockwave' || type == 'explosion') {
      _drawShockwave(canvas, origin, item, t, scale, intensity, fade, seed, explosion: type == 'explosion');
      return;
    }
    if (type == 'heal_ring') {
      _drawHealRing(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'shield') {
      _drawShield(canvas, origin, item, t, scale, intensity, fade);
      return;
    }
    if (type == 'afterimage') {
      _drawAfterimages(canvas, size, caster, target, item, t, scale, fade);
      return;
    }
    if (type == 'space_crack') {
      _drawSpaceCrack(canvas, size, origin, item, t, scale, intensity, fade, seed);
      return;
    }
  }

  void _drawParticles(
    Canvas canvas,
    Size size,
    Offset origin,
    Map<String, dynamic> item,
    double t,
    int intensity, {
    bool burst = false,
    String? forcedShape,
  }) {
    final seed = _i(item['seed'], 0);
    final shape = forcedShape ?? _s(item['shape'], 'spark').toLowerCase();
    final motion = _s(item['motion'], burst ? 'radial' : 'stream').toLowerCase();
    final direction = _s(item['direction'], 'radial').toLowerCase();
    var count = _i(item['particle_count'], 0);
    if (count <= 0) count = _i(item['amount'], 3) * (burst ? 9 : 7);
    count = count.clamp(2, 120).toInt();
    final speed = _d(item['speed'], .65).clamp(0.0, 1.5).toDouble();
    final spread = _d(item['spread'], .55).clamp(0.0, 1.0).toDouble();
    final gravity = _d(item['gravity'], 0).clamp(-1.0, 1.0).toDouble();
    final trail = _d(item['trail'], .25).clamp(0.0, 1.0).toDouble();
    final glow = _d(item['glow'], .35).clamp(0.0, 1.0).toDouble();
    final scale = _d(item['scale'], 1).clamp(.35, 2.4).toDouble();
    final baseDistance = size.shortestSide * (.20 + speed * .62) * scale;

    Offset particlePosition(int i, double age) {
      final a0 = _seed01(i, 11, seed) * math.pi * 2;
      final s1 = _seed01(i, 17, seed);
      final s2 = _seed01(i, 23, seed);
      final s3 = _seed01(i, 29, seed);
      final baseAngle = _directionAngle(direction, a0);
      final jitter = (s1 - .5) * math.pi * (direction == 'radial' ? 2 : .9) * spread;
      final angle = baseAngle + jitter;
      final distance = baseDistance * (.52 + s2 * .78) * age;
      final gravY = size.height * gravity * age * age * .16;

      switch (motion) {
        case 'rise':
          return Offset(
            origin.dx + (s1 - .5) * size.width * .24 * spread + math.sin(age * 7 + i) * 5,
            origin.dy - distance * .72 + gravY,
          );
        case 'fall':
          return Offset(
            origin.dx + (s1 - .5) * size.width * .30 * spread,
            origin.dy + distance * .78 + gravY,
          );
        case 'orbit':
          final r = size.shortestSide * (.08 + s2 * .18) * scale * (1 - age * .16);
          final a = a0 + age * (2.2 + s3 * 3.4) * (i.isEven ? 1 : -1);
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .62);
        case 'swirl':
        case 'spiral':
          final r = size.shortestSide * (.04 + age * (.10 + spread * .22)) * scale * (.65 + s2 * .6);
          final a = a0 + age * (4.0 + s3 * 5.0) * (i.isEven ? 1 : -1);
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .68 + gravY);
        case 'converge':
          final startR = size.shortestSide * (.18 + s2 * .30) * scale;
          final a = a0 + age * (i.isEven ? .8 : -.8);
          final r = startR * (1 - _easeOut(age));
          return Offset(origin.dx + math.cos(a) * r, origin.dy + math.sin(a) * r * .65);
        case 'wave':
          return Offset(
            origin.dx + math.cos(angle) * distance,
            origin.dy + math.sin(angle) * distance + math.sin(age * math.pi * 5 + i) * 12 * spread + gravY,
          );
        case 'stream':
          final side = (s1 - .5) * size.shortestSide * .18 * spread * (1 - age * .55);
          return Offset(
            origin.dx + math.cos(baseAngle) * distance + math.cos(baseAngle + math.pi / 2) * side,
            origin.dy + math.sin(baseAngle) * distance + math.sin(baseAngle + math.pi / 2) * side + gravY,
          );
        case 'cone':
        case 'scatter':
        case 'radial':
        default:
          return Offset(
            origin.dx + math.cos(angle) * distance,
            origin.dy + math.sin(angle) * distance * (.72 + s3 * .35) + gravY,
          );
      }
    }

    for (var i = 0; i < count; i++) {
      final spawn = burst
          ? _seed01(i, 31, seed) * .10
          : (i / count) * (.52 + _seed01(i, 37, seed) * .12);
      if (t <= spawn) continue;
      final age = ((t - spawn) / math.max(.001, 1 - spawn)).clamp(0.0, 1.0).toDouble();
      if (age >= 1) continue;
      final life = math.sin(age * math.pi).clamp(0.0, 1.0).toDouble();
      final p = particlePosition(i, age);
      final previous = particlePosition(i, math.max(0.0, age - (.035 + trail * .11)));
      final rnd = _seed01(i, 41, seed);
      final sizePx = (.8 + rnd * (2.0 + intensity * .10)) * scale;
      _drawParticleShape(canvas, shape, p, previous, sizePx, life, glow, i, seed);
    }
  }

  void _drawParticleShape(
    Canvas canvas,
    String shape,
    Offset p,
    Offset previous,
    double sizePx,
    double life,
    double glow,
    int index,
    int seed,
  ) {
    final angle = math.atan2(p.dy - previous.dy, p.dx - previous.dx);
    final additive = Paint()
      ..blendMode = BlendMode.plus
      ..color = accent.withOpacity((.16 + glow * .22) * life);
    if (glow > .12) {
      canvas.drawCircle(p, sizePx * (1.8 + glow * 2.4), additive);
    }

    if (shape == 'streak' || shape == 'line') {
      canvas.drawLine(previous, p, _stroke(accent, .72 * life, math.max(.65, sizePx * .62)));
      canvas.drawLine(previous, p, _stroke(Colors.white, .52 * life, math.max(.35, sizePx * .18)));
      return;
    }
    if (shape == 'orb' || shape == 'spark' || shape == 'ember' || shape == 'dust') {
      final c = shape == 'ember' && index.isEven ? Colors.white : accent;
      canvas.drawCircle(p, sizePx * (shape == 'dust' ? 1.5 : 1), _fill(c, (shape == 'dust' ? .18 : .72) * life));
      if (shape == 'ember') canvas.drawLine(previous, p, _stroke(accent, .30 * life, .7));
      return;
    }

    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle + (_seed01(index, 47, seed) - .5) * 1.4);
    if (shape == 'shard') {
      final shard = Path()
        ..moveTo(sizePx * 2.8, 0)
        ..lineTo(-sizePx * 1.2, -sizePx * .9)
        ..lineTo(-sizePx * .4, sizePx * 1.1)
        ..close();
      canvas.drawPath(shard, _fill(accent, .70 * life));
      canvas.drawPath(shard, _stroke(Colors.white, .45 * life, .45));
    } else if (shape == 'diamond' || shape == 'blade') {
      final long = shape == 'blade' ? 4.2 : 2.2;
      final path = Path()
        ..moveTo(sizePx * long, 0)
        ..lineTo(0, -sizePx * .75)
        ..lineTo(-sizePx * (shape == 'blade' ? 1.8 : 2.0), 0)
        ..lineTo(0, sizePx * .75)
        ..close();
      canvas.drawPath(path, _fill(accent, .58 * life));
      canvas.drawPath(path, _stroke(Colors.white, .62 * life, .5));
    } else if (shape == 'petal') {
      final len = sizePx * 4.0;
      final wid = sizePx * 1.45;
      final path = Path()
        ..moveTo(-len * .35, 0)
        ..quadraticBezierTo(0, -wid, len * .65, 0)
        ..quadraticBezierTo(0, wid, -len * .35, 0)
        ..close();
      canvas.drawPath(path, _fill(accent, .48 * life));
      canvas.drawPath(path, _stroke(Colors.white, .30 * life, .4));
    } else if (shape == 'snow') {
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        canvas.drawLine(
          Offset(math.cos(a) * -sizePx * 1.8, math.sin(a) * -sizePx * 1.8),
          Offset(math.cos(a) * sizePx * 1.8, math.sin(a) * sizePx * 1.8),
          _stroke(Colors.white, .50 * life, .45),
        );
      }
    } else if (shape == 'star') {
      for (var k = 0; k < 2; k++) {
        final a = k * math.pi / 2;
        canvas.drawLine(
          Offset(math.cos(a) * -sizePx * 2.0, math.sin(a) * -sizePx * 2.0),
          Offset(math.cos(a) * sizePx * 2.0, math.sin(a) * sizePx * 2.0),
          _stroke(Colors.white, .62 * life, .55),
        );
      }
    } else if (shape == 'rune') {
      canvas.drawCircle(Offset.zero, sizePx * 1.5, _stroke(accent, .52 * life, .5));
      canvas.drawLine(Offset(-sizePx, 0), Offset(sizePx, 0), _stroke(Colors.white, .34 * life, .4));
    } else {
      canvas.drawCircle(Offset.zero, sizePx, _fill(accent, .62 * life));
    }
    canvas.restore();
  }

  void _drawStarfield(Canvas canvas, Size size, Map<String, dynamic> item, double t, double fade, int seed) {
    final count = _i(item['particle_count'], 36).clamp(12, 90).toInt();
    for (var i = 0; i < count; i++) {
      final x = _seed01(i, 61, seed) * size.width;
      final y = _seed01(i, 67, seed) * size.height * .82;
      final twinkle = .35 + .65 * math.sin((t * 6 + i * .73)).abs();
      final r = .35 + _seed01(i, 71, seed) * 1.1;
      canvas.drawCircle(Offset(x, y), r, _fill(i % 4 == 0 ? accent : Colors.white, .10 * fade * twinkle));
    }
  }

  void _drawSigil(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, {bool ringOnly = false}) {
    final amount = _i(item['amount'], 5).clamp(2, 12).toInt();
    final variant = _i(item['variant'], 0).clamp(0, 6).toInt();
    final reveal = _easeOut(t);
    final r = (28 + intensity * 3.4) * scale * reveal;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t * (variant.isEven ? .65 : -.48));
    for (var ring = 0; ring < math.min(4, 1 + amount ~/ 3); ring++) {
      final rr = r * (1 - ring * .18);
      final rect = Rect.fromCircle(center: Offset.zero, radius: rr);
      for (var i = 0; i < 12; i++) {
        canvas.drawArc(rect, i * math.pi * 2 / 12 + ring * .19, math.pi * (.045 + (i % 3) * .012), false,
            _stroke(i.isEven ? accent : Colors.white, (.20 + ring * .035) * fade, .65 + ring * .18));
      }
    }
    if (!ringOnly) {
      if (variant % 3 == 0) {
        // Eye-shaped sigil.
        final eye = Path()
          ..moveTo(-r * .82, 0)
          ..quadraticBezierTo(0, -r * .40, r * .82, 0)
          ..quadraticBezierTo(0, r * .40, -r * .82, 0);
        _layeredPath(canvas, eye, accent, .62 * fade, 1.05 * scale, glow: 3.0);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * .15, height: r * .55), _fill(Colors.white, .72 * fade));
      } else {
        final sides = 3 + variant % 4;
        final poly = Path();
        for (var i = 0; i <= sides; i++) {
          final a = -math.pi / 2 + i * math.pi * 2 / sides;
          final p = Offset(math.cos(a) * r * .62, math.sin(a) * r * .62);
          if (i == 0) poly.moveTo(p.dx, p.dy); else poly.lineTo(p.dx, p.dy);
        }
        _layeredPath(canvas, poly, accent, .48 * fade, .9 * scale, glow: 2.5, whiteCore: false);
      }
      for (var i = 0; i < amount; i++) {
        final a = i * math.pi * 2 / amount - t * 1.1;
        final p = Offset(math.cos(a) * r * .82, math.sin(a) * r * .82);
        canvas.drawCircle(p, 1.1 * scale, _fill(Colors.white, .42 * fade));
      }
    }
    canvas.restore();
  }

  void _drawEnergyOrb(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, {bool aura = false}) {
    final pulse = _pulse(t);
    final amount = _i(item['amount'], 4).clamp(2, 10).toInt();
    final coreR = (4 + intensity * .45 + pulse * 6) * scale;
    canvas.drawCircle(c, coreR * 2.4, _fill(accent, .10 * pulse, blur: 5, additive: true));
    canvas.drawCircle(c, coreR, _fill(Colors.white, .82 * pulse));
    canvas.drawCircle(c, coreR + 3 * scale, _stroke(accent, .68 * pulse, 1.1));
    for (var i = 0; i < math.min(5, amount); i++) {
      final r = (20 + i * 11 + t * (aura ? 18 : 9)) * scale;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, i * .78 + t * (i.isEven ? 1.3 : -.9), math.pi * (aura ? .95 : .55), false,
          _stroke(i.isEven ? accent : Colors.white, (.22 - i * .025) * fade, .8 + i * .08));
    }
    if (_i(item['particle_count'], 0) > 0) {
      final particles = <String, dynamic>{...item, 'motion': _s(item['motion'], 'converge'), 'shape': _s(item['shape'], 'spark')};
      _drawParticles(canvas, size, c, particles, t, intensity, burst: false);
    }
  }

  void _drawBlade(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final start = Offset(caster.dx - size.width * .06, caster.dy + size.height * .08);
    final len = math.min(size.width * .34, 220.0) * q * scale;
    final angle = -.16;
    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);
    final blade = Path()
      ..moveTo(-len * .10, 3 * scale)
      ..lineTo(len, -2 * scale)
      ..lineTo(len * .92, 2 * scale)
      ..lineTo(-len * .10, 6 * scale)
      ..close();
    canvas.drawPath(blade, _fill(accent, .26 * fade));
    canvas.drawLine(Offset(-len * .08, 3 * scale), Offset(len, 0), _stroke(Colors.white, .88 * fade, 1.4 * scale));
    canvas.drawLine(Offset(-len * .18, 4 * scale), Offset(-len * .03, 4 * scale), _stroke(accent, .82 * fade, 5 * scale));
    canvas.drawLine(Offset(-len * .08, -8 * scale), Offset(-len * .08, 14 * scale), _stroke(Colors.white, .46 * fade, 1.2 * scale));
    canvas.restore();
    if (_i(item['particle_count'], 0) > 0) {
      final p = <String, dynamic>{...item, 'origin': 'caster', 'motion': 'converge', 'shape': 'streak'};
      _drawParticles(canvas, size, start, p, t, intensity, burst: false);
    }
  }

  Path _beamPath(Offset start, Offset end, String pathKind, double reveal, double scale) {
    final p = Path()..moveTo(start.dx, start.dy);
    final current = Offset(start.dx + (end.dx - start.dx) * reveal, start.dy + (end.dy - start.dy) * reveal);
    if (pathKind == 'wave') {
      final mid = Offset((start.dx + current.dx) * .5, (start.dy + current.dy) * .5 - 18 * scale * math.sin(reveal * math.pi));
      p.quadraticBezierTo(mid.dx, mid.dy, current.dx, current.dy);
    } else if (pathKind == 'arc' || pathKind == 'crescent') {
      final mid = Offset((start.dx + current.dx) * .5, math.min(start.dy, current.dy) - 42 * scale);
      p.quadraticBezierTo(mid.dx, mid.dy, current.dx, current.dy);
    } else {
      p.lineTo(current.dx, current.dy);
    }
    return p;
  }

  void _drawBeam(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final reveal = _easeOut(math.min(1.0, t * 1.35));
    final path = _beamPath(caster, target, _s(item['path'], 'straight'), reveal, scale);
    final width = (3.2 + intensity * .55) * scale;
    _layeredPath(canvas, path, accent, .88 * fade, width, glow: 7 + _d(item['glow'], .4) * 8);
    final side1 = path;
    canvas.drawPath(side1, _stroke(accent, .16 * fade, width * 2.2));
    if (_i(item['particle_count'], 0) > 0) {
      final mid = Offset(caster.dx + (target.dx - caster.dx) * reveal * .55, caster.dy + (target.dy - caster.dy) * reveal * .55);
      final p = <String, dynamic>{...item, 'origin': 'caster', 'motion': 'stream', 'direction': target.dx >= caster.dx ? 'left_to_right' : 'right_to_left', 'shape': _s(item['shape'], 'streak')};
      _drawParticles(canvas, size, mid, p, t, intensity, burst: false);
    }
  }

  void _drawCrescent(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final center = Offset(caster.dx + (target.dx - caster.dx) * q, caster.dy + (target.dy - caster.dy) * q);
    final r = (32 + intensity * 4.5) * scale;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(accent, .18 * fade, 9 * scale, blur: 4));
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(accent, .78 * fade, 3.2 * scale));
    canvas.drawArc(rect, -math.pi * .72, math.pi * 1.36, false, _stroke(Colors.white, .82 * fade, .9 * scale));
  }

  void _drawProjectileSwarm(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    var count = _i(item['particle_count'], 48) ~/ 4;
    count = count.clamp(8, 28).toInt();
    for (var i = 0; i < count; i++) {
      final delay = (i / count) * .38 + _seed01(i, 83, seed) * .05;
      if (t < delay) continue;
      final u = ((t - delay) / math.max(.01, 1 - delay)).clamp(0.0, 1.0).toDouble();
      final lane = (_seed01(i, 89, seed) - .5) * size.height * .42;
      final arc = math.sin(u * math.pi) * (18 + _seed01(i, 97, seed) * 42) * (i.isEven ? -1 : 1);
      final p = Offset(
        caster.dx + (target.dx - caster.dx) * _easeOut(u),
        caster.dy + lane * (1 - u) + (target.dy - caster.dy) * u + arc,
      );
      final prevU = math.max(0.0, u - .06);
      final prev = Offset(
        caster.dx + (target.dx - caster.dx) * _easeOut(prevU),
        caster.dy + lane * (1 - prevU) + (target.dy - caster.dy) * prevU + math.sin(prevU * math.pi) * (18 + _seed01(i, 97, seed) * 42) * (i.isEven ? -1 : 1),
      );
      _drawParticleShape(canvas, _s(item['shape'], 'blade'), p, prev, (1.2 + _seed01(i, 101, seed) * 1.1) * scale, fade, _d(item['glow'], .3), i, seed);
    }
  }

  void _drawDragon(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final reveal = _easeInOut(t);
    final startX = caster.dx - size.width * .08;
    final endX = target.dx + size.width * .08;
    Offset point(double u) {
      final x = startX + (endX - startX) * u * reveal;
      final wave = math.sin((u * 3.15 - reveal * .55 + (seed % 11) * .013) * math.pi) * 30 * scale;
      final lift = -math.sin(u * math.pi) * 22 * scale;
      return Offset(x, caster.dy + (target.dy - caster.dy) * u + wave * (1 - u * .18) + lift);
    }
    final body = Path();
    for (var i = 0; i <= 46; i++) {
      final p = point(i / 46);
      if (i == 0) body.moveTo(p.dx, p.dy); else body.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(body, _stroke(accent, .13 * fade, 22 * scale, blur: 8));
    canvas.drawPath(body, _stroke(accent, .30 * fade, 12 * scale, blur: 2));
    canvas.drawPath(body, _stroke(accent, .64 * fade, 6.5 * scale));
    canvas.drawPath(body, _stroke(Colors.white, .84 * fade, 1.35 * scale));

    for (var i = 5; i < 42; i += 4) {
      final u = i / 46;
      final p = point(u);
      final p2 = point(math.min(1.0, u + .018));
      final a = math.atan2(p2.dy - p.dy, p2.dx - p.dx) - math.pi / 2;
      final len = (4 + _seed01(i, 109, seed) * 7) * scale;
      canvas.drawLine(p, Offset(p.dx + math.cos(a) * len, p.dy + math.sin(a) * len), _stroke(Colors.white, .30 * fade, .7));
    }

    final head = point(1);
    final neck = point(.965);
    final angle = math.atan2(head.dy - neck.dy, head.dx - neck.dx);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(angle);
    final s = (13 + intensity * .60) * scale;
    final headPath = Path()
      ..moveTo(s * 1.20, 0)
      ..lineTo(s * .38, -s * .60)
      ..lineTo(-s * .55, -s * .48)
      ..lineTo(-s * .25, -s * .08)
      ..lineTo(-s * .72, s * .44)
      ..lineTo(s * .22, s * .54)
      ..close();
    canvas.drawPath(headPath, _fill(accent, .56 * fade));
    canvas.drawPath(headPath, _stroke(Colors.white, .78 * fade, 1.0));
    final horns = Path()
      ..moveTo(-s * .30, -s * .43)..lineTo(-s * .68, -s * 1.15)
      ..moveTo(s * .08, -s * .50)..lineTo(-s * .02, -s * 1.20);
    canvas.drawPath(horns, _stroke(accent, .88 * fade, 1.2));
    canvas.drawCircle(Offset(s * .48, -s * .16), 1.8 * scale, _fill(Colors.white, .96 * fade, blur: 1));
    canvas.restore();

    final pItem = <String, dynamic>{
      ...item,
      'origin': 'caster',
      'motion': 'stream',
      'direction': 'left_to_right',
      'shape': _s(item['shape'], 'snow'),
      'particle_count': _i(item['particle_count'], 48 + intensity * 4),
      'spread': math.min(.58, _d(item['spread'], .38)),
    };
    _drawParticles(canvas, size, point(.55), pItem, t, intensity, burst: false);
  }

  void _drawLotus(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final bloom = _easeOut(t);
    final amount = _i(item['amount'], 7).clamp(4, 12).toInt();
    final variant = _i(item['variant'], 0);
    final spin = t * (.22 + variant * .025);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    void petal(double angle, double len, double width, double alpha) {
      canvas.save();
      canvas.rotate(angle);
      final p = Path()
        ..moveTo(0, 0)
        ..cubicTo(len * .24, -width, len * .74, -width * .82, len, 0)
        ..cubicTo(len * .74, width * .82, len * .24, width, 0, 0)
        ..close();
      final paint = Paint()
        ..shader = LinearGradient(
          colors: <Color>[Colors.white.withOpacity(.80 * alpha), accent.withOpacity(.64 * alpha), accent.withOpacity(.04)],
          stops: const <double>[0, .34, 1],
        ).createShader(Rect.fromLTWH(0, -width, len, width * 2));
      paint.blendMode = BlendMode.plus;
      canvas.drawPath(p, paint);
      canvas.drawPath(p, _stroke(Colors.white, .26 * alpha, .55));
      canvas.restore();
    }
    final outer = math.max(10, amount * 2);
    final outerLen = (28 + 52 * bloom + intensity * 1.7) * scale;
    final outerW = (8 + 12 * bloom) * scale;
    for (var i = 0; i < outer; i++) {
      petal(i * math.pi * 2 / outer + spin, outerLen, outerW, fade);
    }
    final inner = math.max(7, amount + 2);
    for (var i = 0; i < inner; i++) {
      petal(i * math.pi * 2 / inner - spin * 1.5 + .22, outerLen * .62, outerW * .68, fade * .86);
    }
    final ringR = outerLen * .95;
    final ring = Rect.fromCircle(center: Offset.zero, radius: ringR);
    for (var i = 0; i < 18; i++) {
      canvas.drawArc(ring, i * math.pi * 2 / 18 - t * .5, math.pi * .038, false, _stroke(accent, .26 * fade, .8));
    }
    final core = (5 + 10 * _pulse(t)) * scale;
    canvas.drawCircle(Offset.zero, core * 2.2, _fill(accent, .12 * fade, blur: 5, additive: true));
    canvas.drawCircle(Offset.zero, core, _fill(Colors.white, .88 * fade));
    canvas.restore();
  }

  void _drawVortex(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final arms = _i(item['amount'], 6).clamp(3, 10).toInt();
    final radius = size.shortestSide * (.12 + intensity * .012) * scale * _easeOut(t);
    for (var arm = 0; arm < arms; arm++) {
      final path = Path();
      for (var i = 0; i <= 32; i++) {
        final u = i / 32;
        final a = arm * math.pi * 2 / arms + u * math.pi * (2.2 + (seed % 5) * .18) + t * 2.4;
        final r = radius * u;
        final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r * .62);
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }
      _layeredPath(canvas, path, accent, .38 * fade, 1.0 + arm % 2 * .4, glow: 2.5, whiteCore: arm % 3 == 0);
    }
    final particles = <String, dynamic>{...item, 'motion': 'spiral', 'shape': _s(item['shape'], 'streak')};
    _drawParticles(canvas, size, c, particles, t, intensity, burst: false);
  }

  void _drawMeteor(Canvas canvas, Size size, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeInOut(t);
    final start = Offset(target.dx - size.width * .28, -size.height * .08);
    final p = Offset(start.dx + (target.dx - start.dx) * q, start.dy + (target.dy - start.dy) * q);
    final prevQ = math.max(0.0, q - .12);
    final prev = Offset(start.dx + (target.dx - start.dx) * prevQ, start.dy + (target.dy - start.dy) * prevQ);
    final tail = Path()..moveTo(prev.dx, prev.dy)..lineTo(p.dx, p.dy);
    _layeredPath(canvas, tail, accent, .72 * fade, (6 + intensity * .5) * scale, glow: 8);
    final r = (8 + intensity * .65) * scale;
    canvas.drawCircle(p, r * 2.4, _fill(accent, .18 * fade, blur: 7, additive: true));
    canvas.drawCircle(p, r, _fill(Colors.white, .88 * fade));
    final particles = <String, dynamic>{...item, 'origin': 'sky', 'direction': 'down', 'motion': 'stream', 'shape': _s(item['shape'], 'ember'), 'particle_count': math.max(24, _i(item['particle_count'], 48))};
    _drawParticles(canvas, size, p, particles, t, intensity, burst: false);
  }

  void _drawForceField(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final amount = _i(item['amount'], 5).clamp(2, 10).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final rx = (26 + i * 9 + q * 30) * scale;
      final ry = rx * (.42 + (i % 2) * .08);
      final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
      canvas.drawArc(rect, i * .6 + t * (i.isEven ? 1.1 : -.7), math.pi * (1.15 - i * .035), false,
          _stroke(i.isEven ? accent : Colors.white, (.30 - i * .018) * fade, .8 + (i % 3) * .25));
    }
    canvas.drawCircle(c, (11 + intensity) * scale * _pulse(t), _stroke(Colors.white, .18 * fade, .7));
  }

  void _drawImpactLines(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final amount = (_i(item['amount'], 8) * 2).clamp(8, 28).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final a = i * math.pi * 2 / amount + (_seed01(i, 127, seed) - .5) * .22;
      final inner = (12 + _seed01(i, 131, seed) * 16) * scale * q;
      final outer = inner + (28 + _seed01(i, 137, seed) * (44 + intensity * 3)) * scale * q;
      final p1 = Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner);
      final p2 = Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer);
      canvas.drawLine(p1, p2, _stroke(i % 4 == 0 ? Colors.white : accent, (.52 - i % 3 * .08) * fade, .55 + _seed01(i, 139, seed) * 1.2));
    }
  }

  void _drawGroundCrack(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, double fade, int seed) {
    final branches = _i(item['amount'], 8).clamp(4, 12).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < branches; i++) {
      final base = math.pi * (.08 + .84 * i / math.max(1, branches - 1));
      final path = Path()..moveTo(c.dx, c.dy);
      var x = c.dx;
      var y = c.dy;
      for (var k = 0; k < 5; k++) {
        final step = (10 + _seed01(i * 11 + k, 149, seed) * 16) * scale * q;
        final a = base + (_seed01(i * 17 + k, 151, seed) - .5) * .65;
        x += math.cos(a) * step;
        y += math.sin(a) * step * .55;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, _stroke(Colors.black, .72 * fade, 2.4 * scale));
      canvas.drawPath(path, _stroke(accent, .42 * fade, .75 * scale));
    }
  }

  void _drawTrail(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeOut(t);
    final kind = _s(item['path'], 'wave');
    final path = Path();
    final steps = 34;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps * q;
      var x = caster.dx + (target.dx - caster.dx) * u;
      var y = caster.dy + (target.dy - caster.dy) * u;
      if (kind == 'wave' || kind == 'serpentine') y += math.sin((u * 3.0 + t * .8) * math.pi) * 18 * scale;
      if (kind == 'arc') y -= math.sin(u * math.pi) * 42 * scale;
      if (kind == 'spiral') {
        x += math.cos(u * math.pi * 6) * (1 - u) * 28 * scale;
        y += math.sin(u * math.pi * 6) * (1 - u) * 18 * scale;
      }
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    _layeredPath(canvas, path, accent, .58 * fade, 2.2 * scale, glow: 4.0);
    final p = <String, dynamic>{...item, 'origin': 'caster', 'direction': target.dx >= caster.dx ? 'left_to_right' : 'right_to_left', 'motion': 'stream'};
    _drawParticles(canvas, size, caster, p, t, intensity, burst: false);
  }

  void _drawSlash(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, String pathKind) {
    final reveal = _easeOut(t);
    final reverse = _s(item['direction']) == 'right_to_left';
    final start = reverse ? Offset(size.width * .88, target.dy + 34 * scale) : Offset(size.width * .10, target.dy + 34 * scale);
    final endFull = reverse ? Offset(size.width * .10, target.dy - 34 * scale) : Offset(size.width * .90, target.dy - 34 * scale);
    final end = Offset(start.dx + (endFull.dx - start.dx) * reveal, start.dy + (endFull.dy - start.dy) * reveal);
    final mid = Offset((start.dx + end.dx) * .5, (start.dy + end.dy) * .5 - (pathKind == 'crescent' ? 46 : 18) * scale);
    final slash = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(slash, _stroke(Colors.black, .88 * fade, (7.5 + intensity * .25) * scale));
    _layeredPath(canvas, slash, accent, .96 * fade, (2.5 + intensity * .12) * scale, glow: 5.5 + _d(item['glow'], .4) * 5);
    final amount = _i(item['amount'], 4).clamp(1, 10).toInt();
    for (var i = 0; i < amount; i++) {
      final off = (i - (amount - 1) / 2) * 4.2 * scale;
      final ghost = Path()..moveTo(start.dx, start.dy + off)..quadraticBezierTo(mid.dx, mid.dy + off * .35, end.dx, end.dy + off);
      canvas.drawPath(ghost, _stroke(accent, .11 * fade, .65));
    }
  }

  void _drawProjectile(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final arc = _s(item['path']) == 'arc' ? -math.sin(q * math.pi) * 42 * scale : -math.sin(q * math.pi) * 14 * scale;
    final p = Offset(caster.dx + (target.dx - caster.dx) * q, caster.dy + (target.dy - caster.dy) * q + arc);
    final prevQ = math.max(0.0, q - .12);
    final prev = Offset(caster.dx + (target.dx - caster.dx) * prevQ, caster.dy + (target.dy - caster.dy) * prevQ + (_s(item['path']) == 'arc' ? -math.sin(prevQ * math.pi) * 42 * scale : 0));
    _drawParticleShape(canvas, _s(item['shape'], 'diamond'), p, prev, (2.2 + intensity * .10) * scale, fade, _d(item['glow'], .35), 0, _i(item['seed'], 0));
    canvas.drawLine(prev, p, _stroke(accent, .36 * fade, 2.2 * scale, blur: 2));
  }

  void _drawLightning(Canvas canvas, Size size, Offset origin, Offset target, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final amount = _i(item['amount'], 5).clamp(2, 12).toInt();
    final q = _easeOut(t);
    for (var b = 0; b < amount; b++) {
      final randomA = _seed01(b, 157, seed) * math.pi * 2;
      final baseA = _directionAngle(_s(item['direction'], 'radial'), randomA);
      final length = (42 + intensity * 7 + _seed01(b, 163, seed) * 52) * scale * q;
      final path = Path()..moveTo(origin.dx, origin.dy);
      var x = origin.dx;
      var y = origin.dy;
      for (var k = 1; k <= 8; k++) {
        final u = k / 8;
        final perp = (_seed01(b * 19 + k, 167, seed) - .5) * 24 * scale * (1 - u * .35);
        x = origin.dx + math.cos(baseA) * length * u + math.cos(baseA + math.pi / 2) * perp;
        y = origin.dy + math.sin(baseA) * length * u + math.sin(baseA + math.pi / 2) * perp;
        path.lineTo(x, y);
      }
      _layeredPath(canvas, path, accent, .72 * fade, 1.25 * scale, glow: 3.2);
    }
  }

  void _drawShockwave(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed, {required bool explosion}) {
    final q = _easeOut(t);
    final r = (14 + q * (explosion ? 132 : 96)) * scale;
    canvas.drawCircle(c, r, _stroke(accent, .56 * fade, explosion ? 2.8 : 1.7));
    canvas.drawCircle(c, r * .72, _stroke(Colors.white, .30 * fade, .75));
    if (explosion) {
      final rays = (_i(item['amount'], 5) * 3).clamp(10, 30).toInt();
      for (var i = 0; i < rays; i++) {
        final a = i * math.pi * 2 / rays + (_seed01(i, 173, seed) - .5) * .12;
        final inner = r * (.12 + _seed01(i, 179, seed) * .08);
        final outer = r * (.55 + _seed01(i, 181, seed) * .40);
        canvas.drawLine(Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner), Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer), _stroke(i.isEven ? Colors.white : accent, .42 * fade, .65 + _seed01(i, 191, seed)));
      }
      final core = (5 + 11 * _pulse(t)) * scale;
      canvas.drawCircle(c, core * 2.5, _fill(accent, .12 * fade, blur: 4, additive: true));
      canvas.drawCircle(c, core, _fill(Colors.white, .80 * fade));
    }
  }

  void _drawHealRing(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final amount = _i(item['amount'], 4).clamp(2, 10).toInt();
    final q = _easeOut(t);
    for (var i = 0; i < amount; i++) {
      final r = (22 + i * 13 + q * 24) * scale;
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, -math.pi * .8 + i * .6 + t, math.pi * 1.18, false, _stroke(i.isEven ? accent : Colors.white, (.34 - i * .025) * fade, 1.0));
    }
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi * 2 / 6 - t * .6;
      final p = Offset(c.dx + math.cos(a) * 18 * scale, c.dy + math.sin(a) * 18 * scale);
      canvas.drawCircle(p, 1.3 * scale, _fill(Colors.white, .42 * fade));
    }
  }

  void _drawShield(Canvas canvas, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade) {
    final q = _easeOut(t);
    final r = (34 + intensity * 2.4 + 12 * _pulse(t)) * scale * q;
    final shield = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * .88, c.dy - r * .45, c.dx + r * .68, c.dy + r * .40)
      ..quadraticBezierTo(c.dx + r * .34, c.dy + r * .96, c.dx, c.dy + r * 1.12)
      ..quadraticBezierTo(c.dx - r * .34, c.dy + r * .96, c.dx - r * .68, c.dy + r * .40)
      ..quadraticBezierTo(c.dx - r * .88, c.dy - r * .45, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(shield, _fill(accent, .045 * fade));
    _layeredPath(canvas, shield, accent, .68 * fade, 1.7 * scale, glow: 3.2, whiteCore: false);
    _drawSigil(canvas, c, {...item, 'amount': 4, 'variant': 2}, t, scale * .62, intensity, fade, ringOnly: false);
  }

  void _drawAfterimages(Canvas canvas, Size size, Offset caster, Offset target, Map<String, dynamic> item, double t, double scale, double fade) {
    final count = _i(item['amount'], 5).clamp(2, 10).toInt();
    final dx = target.dx - caster.dx;
    final dy = target.dy - caster.dy;
    final distance = math.max(1.0, math.sqrt(dx * dx + dy * dy));
    final ux = dx / distance;
    final uy = dy / distance;
    final nx = -uy;
    final ny = ux;
    for (var i = count - 1; i >= 0; i--) {
      final u = (t - i * .055).clamp(0.0, 1.0).toDouble();
      final eased = _easeOut(u);
      final p = Offset(
        caster.dx + dx * eased,
        caster.dy + dy * u - math.sin(u * math.pi) * 10,
      );
      final opacity = (.07 + (count - i) * .026) * fade;
      final length = (18 + (count - i) * 5.0) * scale;
      final bend = math.sin((u + i * .17) * math.pi * 2) * 6 * scale;
      final start = Offset(p.dx - ux * length, p.dy - uy * length);
      final end = Offset(p.dx + ux * 7 * scale, p.dy + uy * 7 * scale);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          p.dx + nx * bend,
          p.dy + ny * bend,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, _stroke(accent, opacity * .72, 5.2 * scale, blur: 6));
      canvas.drawPath(path, _stroke(accent, opacity, 1.45 * scale));
      canvas.drawPath(path, _stroke(Colors.white, opacity * .42, .55 * scale));
    }
  }

  void _drawSpaceCrack(Canvas canvas, Size size, Offset c, Map<String, dynamic> item, double t, double scale, int intensity, double fade, int seed) {
    final q = _easeOut(math.min(1.0, t * 1.3));
    final start = Offset(size.width * .10, c.dy + 22 * scale);
    final end = Offset(size.width * .90, c.dy - 28 * scale);
    final main = Path()..moveTo(start.dx, start.dy);
    final segments = 18;
    for (var i = 1; i <= segments; i++) {
      final u = i / segments * q;
      final x = start.dx + (end.dx - start.dx) * u;
      final y = start.dy + (end.dy - start.dy) * u + (_seed01(i, 197, seed) - .5) * 9 * scale;
      main.lineTo(x, y);
    }
    canvas.drawPath(main, _stroke(Colors.black, .96 * fade, (7 + intensity * .2) * scale));
    canvas.drawPath(main, _stroke(accent, .78 * fade, 1.8 * scale, blur: 2.8));
    canvas.drawPath(main, _stroke(Colors.white, .56 * fade, .65 * scale));
    final branches = _i(item['amount'], 7).clamp(3, 12).toInt();
    for (var i = 0; i < branches; i++) {
      final u = .15 + i / math.max(1, branches - 1) * .70;
      if (u > q) continue;
      var x = start.dx + (end.dx - start.dx) * u;
      var y = start.dy + (end.dy - start.dy) * u;
      final branch = Path()..moveTo(x, y);
      final side = i.isEven ? -1.0 : 1.0;
      for (var k = 0; k < 4; k++) {
        x += side * (8 + _seed01(i * 13 + k, 199, seed) * 17) * scale;
        y += (_seed01(i * 17 + k, 211, seed) - .5) * 22 * scale;
        branch.lineTo(x, y);
      }
      canvas.drawPath(branch, _stroke(accent, .42 * fade, .75));
    }
  }
}


String _battleSkillTypeName(String type) => switch (type) {
      'direct' => '直击',
      'dot' => '持续伤害',
      'guard' => '守护',
      'evade' => '闪避',
      'heal' => '治疗',
      'energy' => '精力恢复',
      'lifesteal' => '吸血',
      'expose' => '破绽',
      'counter' => '反击',
      'stun' => '压制',
      _ => '直击',
    };

String _battleSkillTypeAsset(String type) =>
    'assets/images/companion_skill_icons/${switch (type) {
      'direct' => 'direct',
      'dot' => 'dot',
      'guard' => 'guard',
      'evade' => 'evade',
      'heal' => 'heal',
      'energy' => 'energy',
      'lifesteal' => 'lifesteal',
      'expose' => 'expose',
      'counter' => 'counter',
      'stun' => 'stun',
      _ => 'direct',
    }}.webp';

IconData _battleSkillFallbackIcon(String type) => switch (type) {
      'direct' => Icons.flash_on_rounded,
      'dot' => Icons.local_fire_department_rounded,
      'guard' => Icons.shield_rounded,
      'evade' => Icons.air_rounded,
      'heal' => Icons.favorite_rounded,
      'energy' => Icons.bolt_rounded,
      'lifesteal' => Icons.bloodtype_rounded,
      'expose' => Icons.gps_fixed_rounded,
      'counter' => Icons.reply_rounded,
      'stun' => Icons.auto_awesome_rounded,
      _ => Icons.flash_on_rounded,
    };

Color _battleSkillQualityColor(int quality) =>
    switch (quality.clamp(1, 10)) {
      10 => const Color(0xFFFF5C7C),
      9 => const Color(0xFFFFCA62),
      8 => const Color(0xFFFF9D5C),
      7 => const Color(0xFFD979FF),
      6 => const Color(0xFFA88BFF),
      5 => const Color(0xFF5BD9F5),
      4 => const Color(0xFF64AEFF),
      3 => const Color(0xFF62D6B3),
      2 => const Color(0xFF91A9C7),
      _ => const Color(0xFFB9C5D6),
    };

class _BattleSkillTypeIcon extends StatelessWidget {
  const _BattleSkillTypeIcon({
    required this.skill,
    required this.size,
    required this.color,
  });

  final YoranBattleSkill skill;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final type = skill.iconType;
    final typeName = _battleSkillTypeName(type);
    return Tooltip(
      message: typeName,
      child: Image.asset(
        _battleSkillTypeAsset(type),
        width: size,
        height: size,
        color: color,
        semanticLabel: typeName,
        errorBuilder: (_, __, ___) => Icon(
          _battleSkillFallbackIcon(type),
          size: size,
          color: color,
          semanticLabel: typeName,
        ),
      ),
    );
  }
}

class YoranBattleCompanion {
  const YoranBattleCompanion({
    required this.id,
    required this.name,
    required this.avatar,
    required this.portrait,
    required this.skills,
    this.star = 0,
  });

  final String id;
  final String name;
  final String avatar;
  final String portrait;
  final List<YoranBattleSkill> skills;
  final int star;

  // Star is supplied by the backend companion payload. Keep the actual rule in one
  // deterministic place so battle preview and execution always agree.
  double get skillEffectMultiplier => 1.0 + star.clamp(0, 10) * .03;
  int get skillEffectPercent => (skillEffectMultiplier * 100).round();

  static YoranBattleCompanion? fromState(dynamic raw) {
    final data = YoranBattleSkill._stringMap(raw);
    final id = '${data['character_instance_id'] ?? data['id'] ?? ''}'.trim();
    final name = '${data['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final skills = <YoranBattleSkill>[];
    final rawSkills = data['skills'];
    if (rawSkills is List) {
      for (final item in rawSkills.take(4)) {
        final skill = YoranBattleSkill.fromState(item);
        if (skill != null && skill.id.isNotEmpty) skills.add(skill);
      }
    }
    return YoranBattleCompanion(
      id: id,
      name: name,
      avatar: '${data['avatar_url'] ?? ''}'.trim(),
      portrait: '${data['portrait_url'] ?? ''}'.trim(),
      skills: skills,
      star: YoranBattleSkill._asInt(data['star']).clamp(0, 10).toInt(),
    );
  }
}

int _battleImageCacheWidth(
  BuildContext context,
  double logicalWidth,
  int maxCacheWidth,
) {
  final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
  return (logicalWidth * pixelRatio)
      .round()
      .clamp(1, maxCacheWidth)
      .toInt();
}

ImageProvider<Object>? _battleImageProviderForPrecache(
  String source,
  int cacheWidth,
) {
  final path = source.trim();
  if (path.isEmpty) return null;
  final ImageProvider<Object> baseProvider =
      path.startsWith('http://') || path.startsWith('https://')
          ? NetworkImage(path)
          : AssetImage(path);
  return ResizeImage.resizeIfNeeded(cacheWidth, null, baseProvider);
}

Future<void> _precacheBattleImage(
  BuildContext context,
  String source,
  int cacheWidth,
) async {
  final provider = _battleImageProviderForPrecache(source, cacheWidth);
  if (provider == null) return;
  try {
    await precacheImage(provider, context);
  } catch (_) {
    // 图片预热失败不能阻断战斗；正式显示时仍会走原有 fallback/errorBuilder。
  }
}

Future<void> _precacheCompanionBattleImages(
  BuildContext context,
  List<YoranBattleCompanion> companions,
) async {
  if (companions.isEmpty) return;
  final screenWidth = MediaQuery.sizeOf(context).width;
  // 与援助大立绘和底部小头像的 _BattleImage cacheWidth 保持一致，
  // 确保预热后的解码结果能直接命中 Flutter ImageCache。
  final assistCacheWidth =
      _battleImageCacheWidth(context, screenWidth * .5, 900);
  final avatarCacheWidth = _battleImageCacheWidth(context, 30, 120);
  final futures = <Future<void>>[];
  final seen = <String>{};

  void queue(String source, int cacheWidth) {
    final path = source.trim();
    if (path.isEmpty) return;
    final key = '$path@$cacheWidth';
    if (!seen.add(key)) return;
    futures.add(_precacheBattleImage(context, path, cacheWidth));
  }

  for (final companion in companions) {
    final assistSource = companion.portrait.trim().isNotEmpty
        ? companion.portrait
        : companion.avatar;
    final avatarSource = companion.avatar.trim().isNotEmpty
        ? companion.avatar
        : companion.portrait;
    queue(assistSource, assistCacheWidth);
    queue(avatarSource, avatarCacheWidth);
  }

  if (futures.isNotEmpty) await Future.wait(futures);
}

/// 后端背包消耗品在战斗页中的运行时视图。
/// 只接收已持有、可在战斗中使用且具有 HP/SP 恢复效果的物品。
class YoranBattleItem {
  const YoranBattleItem({
    required this.id,
    required this.name,
    required this.detail,
    required this.quality,
    required this.quantity,
    required this.effectType,
    this.consumeOnUse = true,
  });

  final String id;
  final String name;
  final String detail;
  final int quality;
  final int quantity;
  final String effectType;
  final bool consumeOnUse;

  bool get restoresHp => effectType == 'hp' || effectType == 'both';
  bool get restoresSp => effectType == 'sp' || effectType == 'both';
  int get restorePercent => (5 + quality * 5).clamp(10, 55).toInt();

  String get effectLabel => <String>[
        if (restoresHp) 'HP +$restorePercent%',
        if (restoresSp) 'SP +$restorePercent%',
      ].join(' · ');

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static bool _asBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    final text = '$value'.trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  static Map<String, dynamic> _stringMap(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static YoranBattleItem? fromState(dynamic raw) {
    if (raw is YoranBattleItem) return raw;
    final item = _stringMap(raw);
    final name = '${item['name'] ?? ''}'.trim();
    final type = '${item['type'] ?? item['item_type'] ?? item['itemType'] ?? ''}'
        .trim()
        .toLowerCase();
    final quantity = _asInt(item['quantity'] ?? item['count'])
        .clamp(0, 9999)
        .toInt();
    if (name.isEmpty || type != 'consumable' || quantity <= 0) return null;

    final quality = _asInt(item['quality'] ?? item['grade'], 1)
        .clamp(1, 10)
        .toInt();
    final spec = _stringMap(item['item_spec'] ?? item['itemSpec'] ?? item['spec']);
    if (spec.isNotEmpty && !_asBool(spec['usable_in_battle'], true)) return null;

    var restoresHp = false;
    var restoresSp = false;
    final directType = '${item['effect_type'] ?? spec['effect_type'] ?? ''}'
        .trim()
        .toLowerCase();
    if (<String>{'hp', 'heal', 'hp_restore', 'health_restore'}.contains(directType)) {
      restoresHp = true;
    } else if (<String>{'sp', 'energy', 'energy_restore', 'sp_restore', 'qi_restore'}
        .contains(directType)) {
      restoresSp = true;
    } else if (<String>{'both', 'hp_sp', 'hp+sp', 'hp/sp'}.contains(directType)) {
      restoresHp = true;
      restoresSp = true;
    }
    // 兼容旧存档：只迁移效果类型，不读取旧 amount。
    final effects = spec['effects'];
    if (effects is List) {
      for (final rawEffect in effects.take(2)) {
        final legacyType = '${_stringMap(rawEffect)['type'] ?? ''}'.trim().toLowerCase();
        if (legacyType == 'heal') restoresHp = true;
        if (legacyType == 'energy_restore') restoresSp = true;
      }
    }
    if (!restoresHp && !restoresSp) return null;

    final id = '${item['id'] ?? item['item_id'] ?? ''}'.trim();
    final detail = '${item['description'] ?? item['detail'] ?? ''}'.trim();
    return YoranBattleItem(
      id: id.isEmpty ? 'item_${name.replaceAll(RegExp(r'\s+'), '')}' : id,
      name: name,
      detail: detail,
      quality: quality,
      quantity: quantity,
      effectType: restoresHp && restoresSp ? 'both' : (restoresHp ? 'hp' : 'sp'),
      consumeOnUse: _asBool(spec['consume_on_use'], true),
    );
  }
}

typedef YoranBattleItemConsumeCallback = Future<bool> Function(
  YoranBattleItem item,
);

class YoranBattleItemConsumption {
  const YoranBattleItemConsumption({
    required this.itemId,
    required this.name,
    required this.quantity,
  });

  final String itemId;
  final String name;
  final int quantity;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'item_id': itemId,
        'name': name,
        'quantity': quantity,
      };
}

/// 返回 null 表示结算失败；成功时返回后端的完整结算结果，供结束页展示奖励。
typedef YoranBattleItemSettlementCallback = Future<Map<String, dynamic>?> Function(
  List<YoranBattleItemConsumption> consumptions,
  YoranBattleOutcome outcome,
);

/// 当前穿戴装备。槽位与品质提供固定加成，后端持久化的基础词条提供差异化加成。
class YoranBattleEquipment {
  const YoranBattleEquipment({
    required this.id,
    required this.name,
    required this.slot,
    required this.quality,
    this.enhancementLevel = 0,
    this.affixes = const <String, int>{},
  });

  final String id;
  final String name;
  final String slot;
  final int quality;
  final int enhancementLevel;
  final Map<String, int> affixes;

  static const Map<String, int> _affixCaps = <String, int>{
    'attack_percent': 5,
    'max_hp_percent': 5,
    'max_energy_percent': 5,
    'defense_percent': 3,
    'hit_percent': 3,
    'critical_percent': 3,
    'dodge_percent': 2,
  };

  static const Set<String> _validSlots = <String>{
    'handheld',
    'upper',
    'head',
    'lower',
    'feet',
    'back',
    'face',
    'accessory',
  };

  static bool _asBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    if (<String>{'true', '1', 'yes', 'y', 'on', 'equipped', 'worn'}
        .contains(text)) {
      return true;
    }
    if (<String>{'false', '0', 'no', 'n', 'off', 'unequipped'}
        .contains(text)) {
      return false;
    }
    return fallback;
  }

  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static Map<String, int> _normalizeAffixes(dynamic raw) {
    final result = <String, int>{};

    void add(String rawKey, dynamic rawValue) {
      final key = rawKey.trim().toLowerCase();
      final cap = _affixCaps[key];
      if (cap == null) return;
      final value = _asInt(rawValue).clamp(0, cap).toInt();
      if (value <= 0) return;
      // 服务端不会生成重复词条；旧数据若重复，仅保留最高值，不叠加伪造数值。
      result[key] = math.max(result[key] ?? 0, value);
    }

    if (raw is Map) {
      raw.forEach((key, value) => add('$key', value));
    } else if (raw is List) {
      for (final entry in raw.take(5)) {
        if (entry is! Map) continue;
        add('${entry['key'] ?? entry['type'] ?? ''}', entry['value']);
      }
    }
    return Map<String, int>.unmodifiable(result);
  }

  static String _normalizeSlot(Map<dynamic, dynamic> raw) {
    final explicit = '${raw['slot'] ?? raw['wear_slot'] ?? raw['wearSlot'] ?? ''}'
        .trim()
        .toLowerCase();
    final itemType = '${raw['item_type'] ?? raw['itemType'] ?? raw['type'] ?? ''}'
        .trim()
        .toLowerCase();
    final value = explicit.isNotEmpty ? explicit : itemType;
    if (value.isEmpty) return '';
    if (<String>{'handheld', 'hand', 'weapon', 'main_hand', 'off_hand', 'tool'}
            .contains(value) ||
        value.contains('武器') ||
        value.contains('手持')) {
      return 'handheld';
    }
    if (<String>{'upper', 'upper_body', 'body', 'chest', 'armor', 'wearable', 'clothes', 'clothing'}
            .contains(value) ||
        value.contains('上装') ||
        value.contains('上身') ||
        value.contains('衣') ||
        value.contains('护甲')) {
      return 'upper';
    }
    if (<String>{'head', 'helmet', 'hat', 'headwear'}.contains(value) ||
        value.contains('头') ||
        value.contains('帽')) {
      return 'head';
    }
    if (<String>{'lower', 'lower_body', 'legs', 'pants', 'trousers'}.contains(value) ||
        value.contains('下装') ||
        value.contains('下身') ||
        value.contains('裤') ||
        value.contains('腿')) {
      return 'lower';
    }
    if (<String>{'feet', 'foot', 'shoes', 'boots', 'footwear'}.contains(value) ||
        value.contains('脚') ||
        value.contains('足') ||
        value.contains('鞋') ||
        value.contains('靴')) {
      return 'feet';
    }
    if (<String>{'back', 'backpack', 'cape', 'cloak', 'wings'}.contains(value) ||
        value.contains('背') ||
        value.contains('披风') ||
        value.contains('翅膀')) {
      return 'back';
    }
    if (<String>{'face', 'mask', 'eyewear', 'glasses'}.contains(value) ||
        value.contains('面') ||
        value.contains('眼镜')) {
      return 'face';
    }
    if (<String>{'accessory', 'jewelry', 'jewellery', 'ring', 'necklace'}
            .contains(value) ||
        value.contains('饰') ||
        value.contains('首饰') ||
        value.contains('戒指') ||
        value.contains('项链')) {
      return 'accessory';
    }
    return _validSlots.contains(value) ? value : '';
  }

  static YoranBattleEquipment? fromState(dynamic raw) {
    if (raw is YoranBattleEquipment) return raw;
    if (raw is! Map) return null;
    final equipped = raw['equipped'] ??
        raw['is_equipped'] ??
        raw['isEquipped'] ??
        raw['worn'] ??
        raw['wearing'];
    if (!_asBool(equipped)) return null;
    final name = '${raw['name'] ?? ''}'.trim();
    final slot = _normalizeSlot(raw);
    if (name.isEmpty || !_validSlots.contains(slot)) return null;
    final rawQuality = raw['quality'] ?? raw['grade'];
    final quality = (rawQuality is num
            ? rawQuality.round()
            : int.tryParse('$rawQuality') ?? 1)
        .clamp(1, 10)
        .toInt();
    final id = '${raw['id'] ?? raw['item_id'] ?? ''}'.trim();
    final enhancementLevel = _asInt(
      raw['enhancement_level'] ??
          raw['enhancementLevel'] ??
          raw['enhance_level'] ??
          raw['upgrade_level'],
    ).clamp(0, 10).toInt();
    final affixes = _normalizeAffixes(
      raw['affixes'] ?? raw['affix_stats'] ?? raw['affixStats'],
    );
    return YoranBattleEquipment(
      id: id.isEmpty ? 'equipment_${slot}_$name' : id,
      name: name,
      slot: slot,
      quality: quality,
      enhancementLevel: enhancementLevel,
      affixes: affixes,
    );
  }
}

/// 后端“测试对手”接口返回的一场完整战斗快照。
/// 玩家与对手都从同一次响应构建，避免前端使用旧角色数据进行比较。
class YoranGeneratedBattleSetup {
  const YoranGeneratedBattleSetup({
    required this.playerName,
    required this.playerAvatar,
    required this.playerPortrait,
    required this.playerSkills,
    this.companions = const <YoranBattleCompanion>[],
    this.playerItems = const <YoranBattleItem>[],
    this.playerEquipment = const <YoranBattleEquipment>[],
    required this.enemy,
    required this.difficultyLabel,
    required this.openingEstimate,
  });

  final String playerName;
  final String playerAvatar;
  final String playerPortrait;
  final List<YoranBattleSkill> playerSkills;
  final List<YoranBattleCompanion> companions;
  final List<YoranBattleItem> playerItems;
  final List<YoranBattleEquipment> playerEquipment;
  final YoranBattleEnemy enemy;
  final String difficultyLabel;
  final String openingEstimate;

  static String _string(dynamic value) => '${value ?? ''}'.trim();

  static int _int(dynamic value, [int fallback = 0]) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? fallback;
  }

  static double _double(dynamic value, [double fallback = 1]) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  static List<YoranBattleSkill> _skills(dynamic raw) {
    if (raw is! List) return const <YoranBattleSkill>[];
    final result = <YoranBattleSkill>[];
    final seen = <String>{};
    for (final item in raw) {
      final skill = YoranBattleSkill.fromState(item);
      if (skill == null) continue;
      final key = skill.name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      if (key.isNotEmpty && seen.add(key)) result.add(skill);
    }
    return result;
  }

  static List<YoranBattleItem> _items(dynamic raw) {
    if (raw is! List) return const <YoranBattleItem>[];
    final result = <YoranBattleItem>[];
    final seen = <String>{};
    for (final rawItem in raw) {
      final item = YoranBattleItem.fromState(rawItem);
      if (item == null || !seen.add(item.id)) continue;
      result.add(item);
    }
    return result;
  }

  static List<YoranBattleEquipment> _equipment(dynamic raw) {
    if (raw is! List) return const <YoranBattleEquipment>[];
    final result = <YoranBattleEquipment>[];
    final seen = <String>{};
    for (final rawItem in raw) {
      final item = YoranBattleEquipment.fromState(rawItem);
      if (item == null || !seen.add(item.id)) continue;
      result.add(item);
    }
    return result;
  }

  static List<YoranBattleCompanion> _companions(dynamic raw) {
    if (raw is! List) return const <YoranBattleCompanion>[];
    return raw
        .map(YoranBattleCompanion.fromState)
        .whereType<YoranBattleCompanion>()
        .where((companion) => companion.skills.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  static List<dynamic> _playerAssets(
    Map<String, dynamic> player,
    Map<String, dynamic> json,
  ) {
    final result = <dynamic>[];

    void append(dynamic raw, {bool assumeEquipped = false}) {
      final values = <dynamic>[];
      if (raw is List) {
        values.addAll(raw);
      } else if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.value is Map) {
            final item = (entry.value as Map).map<String, dynamic>(
              (key, value) => MapEntry<String, dynamic>('$key', value),
            );
            item.putIfAbsent('slot', () => '${entry.key}');
            values.add(item);
          }
        }
      }
      for (final value in values) {
        if (!assumeEquipped || value is! Map) {
          result.add(value);
          continue;
        }
        final item = value.map<String, dynamic>(
          (key, item) => MapEntry<String, dynamic>('$key', item),
        );
        if (!item.containsKey('equipped') &&
            !item.containsKey('is_equipped') &&
            !item.containsKey('isEquipped') &&
            !item.containsKey('worn') &&
            !item.containsKey('wearing')) {
          item['equipped'] = true;
        }
        result.add(item);
      }
    }

    // 独立 equipment 数组中的条目默认就是已穿戴；背包条目仍要求显式穿戴标记。
    append(player['equipment'], assumeEquipped: true);
    append(json['equipment'], assumeEquipped: true);
    append(player['inventory']);
    append(player['items']);
    append(json['inventory']);
    append(json['items']);
    return result;
  }

  factory YoranGeneratedBattleSetup.fromJson(Map<String, dynamic> json) {
    final player = YoranBattleSkill._stringMap(json['player_snapshot']);
    final design = YoranBattleSkill._stringMap(json['battle_opponent']);
    final assessedPlayer = YoranBattleSkill._stringMap(design['player_assessment']);
    final opponent = YoranBattleSkill._stringMap(design['opponent']);
    final stats = YoranBattleSkill._stringMap(opponent['stats']);
    final runtime = YoranBattleSkill._stringMap(opponent['runtime_state']);
    final basicAttack = YoranBattleSkill._stringMap(stats['basic_attack']);
    final matchup = YoranBattleSkill._stringMap(design['matchup']);
    final playerAsset = YoranBattleSkill._stringMap(player['character_asset']);
    final enemyAsset = YoranBattleSkill._stringMap(opponent['character_asset']);

    final opponentName = _string(opponent['name']);
    if (opponentName.isEmpty) {
      throw const FormatException('后端没有返回有效的对手名称');
    }
    final basicPowerPercent =
        _int(basicAttack['power_percent'], 65).clamp(35, 220).toInt();
    final maxHp = _int(stats['max_health'], 100).clamp(1, 1000).toInt();
    final playerMultiplier =
        _double(matchup['player_damage_multiplier']).clamp(.05, 20).toDouble();
    final opponentMultiplier = _double(
      matchup['opponent_damage_multiplier'],
    ).clamp(.05, 20).toDouble();

    final learned = _skills(player['skills'])
        .where((skill) => skill.name.trim() != '普通攻击')
        .toList(growable: false);
    final playerSkills = learned.isEmpty
        ? yoranDefaultBattleSkills
        : <YoranBattleSkill>[
            yoranDefaultBattleSkills.first,
            ...learned,
          ];
    final enemySkills = _skills(opponent['skills']);
    final playerAssets = _playerAssets(player, json);

    return YoranGeneratedBattleSetup(
      playerName: _string(player['name']).isNotEmpty
          ? _string(player['name'])
          : (_string(assessedPlayer['name']).isNotEmpty
              ? _string(assessedPlayer['name'])
              : '玩家'),
      playerAvatar: _string(playerAsset['avatar_url']),
      playerPortrait: _string(playerAsset['portrait_url']),
      playerSkills: playerSkills,
      companions: _companions(player['companions']),
      playerItems: _items(playerAssets),
      playerEquipment: _equipment(playerAssets),
      difficultyLabel: _string(matchup['difficulty_label']),
      openingEstimate: _string(matchup['opening_estimate']),
      enemy: YoranBattleEnemy(
        name: opponentName,
        portrait: _string(enemyAsset['portrait_url']).isNotEmpty
            ? _string(enemyAsset['portrait_url'])
            : _string(enemyAsset['avatar_url']),
        maxHp: maxHp,
        currentHp: _int(runtime['current_health'], maxHp)
            .clamp(1, maxHp)
            .toInt(),
        currentEnergy: _int(runtime['current_energy'], 100)
            .clamp(0, 100)
            .toInt(),
        condition: _string(runtime['condition']),
        realm: _string(opponent['realm']),
        difficultyLabel: _string(matchup['difficulty_label']),
        openingEstimate: _string(matchup['opening_estimate']),
        basicAttackPowerPercent: basicPowerPercent,
        hitBonus: _int(stats['hit_bonus'], 4).clamp(0, 10).toInt(),
        playerDamageMultiplier: playerMultiplier,
        opponentDamageMultiplier: opponentMultiplier,
        playerHitBonusShift:
            _int(matchup['player_hit_bonus_shift']).clamp(-10, 10).toInt(),
        opponentHitBonusShift:
            _int(matchup['opponent_hit_bonus_shift']).clamp(-10, 10).toInt(),
        allowInstantDefeat: matchup['allow_instant_defeat'] == true,
        skills: enemySkills,
      ),
    );
  }
}

/// 每个角色始终可用的基础行动。它们不来自剧情技能库，
/// 而是回合制战斗的保底选择，避免精力耗尽后无法行动。
const List<YoranBattleSkill> yoranBaseBattleSkills = <YoranBattleSkill>[
  YoranBattleSkill(
    name: '普通攻击',
    detail: '基础攻击动作，无需消耗精力',
    powerPercent: 65,
    hitBonus: 6,
  ),
  YoranBattleSkill(
    name: '休整',
    detail: '放缓呼吸并调整状态，恢复大量精力',
    archetype: 'energy',
    energyMaxQiPercent: 20,
    resting: true,
    targetSelf: true,
  ),
  YoranBattleSkill(
    name: '防御',
    detail: '稳住重心，大幅降低下次受到的伤害',
    archetype: 'guard',
    energyCost: 5,
    guarding: true,
    guardReductionPercent: 50,
    targetSelf: true,
  ),
  YoranBattleSkill(
    name: '闪避',
    detail: '放轻脚步，提高敌方的命中难度',
    archetype: 'evade',
    energyCost: 10,
    dodging: true,
    // D20 命中难度 +5：通常等价于敌方命中率下降约 25 个百分点，
    // 并不是“闪避率 +5%”。例如敌方命中加值为 +4 时，约从 70% 降至 45%。
    enemyHitDifficultyBonus: 5,
    targetSelf: true,
  ),
];

const List<YoranBattleSkill> yoranDefaultBattleSkills = <YoranBattleSkill>[
  ...yoranBaseBattleSkills,
  // 通用强力攻击只作为“普通攻击”的进阶保底，不应压过角色真正学会的技能。
  YoranBattleSkill(
    name: '强力攻击',
    detail: '蓄力后发动更重的一击，可穿过部分防御',
    quality: 2,
    powerPercent: 110,
    hitBonus: 4,
    energyCost: 15,
    cooldown: 1,
    piercesGuard: true,
  ),
];

/// `socketService` 参数暂为兼容旧调用保留；当前战斗页不再包含语音输入入口。
/// `skills` 与 `items` 可直接传入后端战斗快照中的真实技能和背包消耗品。
/// 正式模式应提供 [onSettleItems]，在返回剧情时一次性扣除本场消耗品。
Future<YoranBattleOutcome?> showYoranBattlePage(
  BuildContext context, {
  String playerName = '玩家',
  String playerAvatar = '',
  String playerPortrait = '',
  String enemyName = '对手',
  String enemyPortrait = '',
  String sceneBackground = '',
  String sceneTitle = '',
  String sceneSubtitle = '',
  NovelSocketService? socketService,
  List<YoranBattleEnemy> enemies = const <YoranBattleEnemy>[],
  List<YoranBattleSkill> skills = yoranDefaultBattleSkills,
  List<YoranBattleCompanion> companions = const <YoranBattleCompanion>[],
  List<dynamic> items = const <dynamic>[],
  List<dynamic> equipment = const <dynamic>[],
  YoranBattleItemSettlementCallback? onSettleItems,
  @Deprecated('请改用战斗结束批量结算 onSettleItems')
  YoranBattleItemConsumeCallback? onConsumeItem,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<YoranBattleOutcome>(
    PageRouteBuilder<YoranBattleOutcome>(
      settings: const RouteSettings(name: 'yoran-battle'),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, secondaryAnimation) => YoranBattlePage(
        playerName: playerName,
        playerAvatar: playerAvatar,
        playerPortrait: playerPortrait,
        enemyName: enemyName,
        enemyPortrait: enemyPortrait,
        sceneBackground: sceneBackground,
        sceneTitle: sceneTitle,
        sceneSubtitle: sceneSubtitle,
        socketService: socketService,
        enemies: enemies,
        skills: skills,
        companions: companions,
        items: items,
        equipment: equipment,
        onSettleItems: onSettleItems,
        onConsumeItem: onConsumeItem,
      ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    ),
  );
}


typedef YoranGeneratedBattleSetupLoader = Future<YoranGeneratedBattleSetup> Function();

/// 对手需要较长时间由后端生成时使用：先进入战斗路由展示 VS 加载态，
/// 数据返回后再挂载现有 [YoranBattlePage]，让正式入场动画与战斗逻辑保持原样。
Future<YoranBattleOutcome?> showYoranGeneratedBattlePage(
  BuildContext context, {
  required YoranGeneratedBattleSetupLoader setupLoader,
  String playerName = '玩家',
  String playerAvatar = '',
  String playerPortrait = '',
  String enemyName = '对手',
  String sceneBackground = '',
  String sceneTitle = '',
  String sceneSubtitle = '',
  NovelSocketService? socketService,
  YoranBattleItemSettlementCallback? onSettleItems,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<YoranBattleOutcome>(
    PageRouteBuilder<YoranBattleOutcome>(
      settings: const RouteSettings(name: 'yoran-battle-loading'),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, secondaryAnimation) =>
          _YoranGeneratedBattleLoaderPage(
        setupLoader: setupLoader,
        playerName: playerName,
        playerAvatar: playerAvatar,
        playerPortrait: playerPortrait,
        enemyName: enemyName,
        sceneBackground: sceneBackground,
        sceneTitle: sceneTitle,
        sceneSubtitle: sceneSubtitle,
        socketService: socketService,
        onSettleItems: onSettleItems,
      ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}

class _YoranGeneratedBattleLoaderPage extends StatefulWidget {
  const _YoranGeneratedBattleLoaderPage({
    required this.setupLoader,
    required this.playerName,
    required this.playerAvatar,
    required this.playerPortrait,
    required this.enemyName,
    required this.sceneBackground,
    required this.sceneTitle,
    required this.sceneSubtitle,
    required this.socketService,
    required this.onSettleItems,
  });

  final YoranGeneratedBattleSetupLoader setupLoader;
  final String playerName;
  final String playerAvatar;
  final String playerPortrait;
  final String enemyName;
  final String sceneBackground;
  final String sceneTitle;
  final String sceneSubtitle;
  final NovelSocketService? socketService;
  final YoranBattleItemSettlementCallback? onSettleItems;

  @override
  State<_YoranGeneratedBattleLoaderPage> createState() =>
      _YoranGeneratedBattleLoaderPageState();
}

class _YoranGeneratedBattleLoaderPageState
    extends State<_YoranGeneratedBattleLoaderPage> {
  YoranGeneratedBattleSetup? _setup;
  Object? _loadError;
  bool _loading = false;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSetup());
  }

  Future<void> _loadSetup() async {
    if (_loading) return;
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final setup = await widget.setupLoader();
      if (!mounted || epoch != _loadEpoch) return;

      // 后端数据一到就先预热援助角色图片。加载页会继续显示，
      // 等大立绘/头像进入 Flutter ImageCache 后再真正挂载战斗页。
      await _precacheCompanionBattleImages(context, setup.companions);
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _setup = setup;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  String get _errorText {
    final error = _loadError;
    if (error == null) return '';
    var text = '$error'.trim();
    for (final prefix in const <String>[
      'Exception: ',
      'Bad state: ',
      'FormatException: ',
    ]) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    return text.isEmpty ? '对手数据生成失败，请重试。' : text;
  }

  String _finalSceneSubtitle(YoranGeneratedBattleSetup setup) {
    return <String>[
      if (widget.sceneSubtitle.trim().isNotEmpty)
        widget.sceneSubtitle.trim(),
      if (setup.difficultyLabel.trim().isNotEmpty)
        setup.difficultyLabel.trim(),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    if (setup != null) {
      return YoranBattlePage(
        playerName: setup.playerName.trim().isNotEmpty
            ? setup.playerName.trim()
            : widget.playerName,
        playerAvatar: setup.playerAvatar.trim().isNotEmpty
            ? setup.playerAvatar.trim()
            : widget.playerAvatar,
        playerPortrait: setup.playerPortrait.trim().isNotEmpty
            ? setup.playerPortrait.trim()
            : widget.playerPortrait,
        enemyName: setup.enemy.name,
        enemyPortrait: setup.enemy.portrait,
        enemies: <YoranBattleEnemy>[setup.enemy],
        skills: setup.playerSkills,
        companions: setup.companions,
        items: setup.playerItems,
        equipment: setup.playerEquipment,
        sceneBackground: widget.sceneBackground,
        sceneTitle: widget.sceneTitle,
        sceneSubtitle: _finalSceneSubtitle(setup),
        socketService: widget.socketService,
        onSettleItems: widget.onSettleItems,
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _BattleColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _BattleSceneBackground(image: widget.sceneBackground),
          // 战前加载只轻轻压暗场景，不做厚重黑幕；让等待页更像一层轻薄过场。
          const ColoredBox(color: Color(0x78080908)),
          _BattleSetupLoadingOverlay(
            playerName: widget.playerName,
            enemyName: widget.enemyName,
            playerPortrait: widget.playerPortrait.trim().isNotEmpty
                ? widget.playerPortrait
                : widget.playerAvatar,
            loading: _loading,
            errorText: _errorText,
            onRetry: _loading ? null : _loadSetup,
          ),
        ],
      ),
    );
  }
}

class _BattleSetupLoadingOverlay extends StatelessWidget {
  const _BattleSetupLoadingOverlay({
    required this.playerName,
    required this.enemyName,
    required this.playerPortrait,
    required this.loading,
    required this.errorText,
    required this.onRetry,
  });

  final String playerName;
  final String enemyName;
  final String playerPortrait;
  final bool loading;
  final String errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width <= 430;
    final leftName = playerName.trim().isEmpty ? '玩家' : playerName.trim();
    final rightName = enemyName.trim().isEmpty ? '对手' : enemyName.trim();

    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 44),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 330 : 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 加载页只保留双方名字、VS 与一条白色进度线。
                // 不再铺角色立绘、卡片、阵营色，避免等待十几秒时画面显得厚重。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        leftName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.88),
                          fontSize: compact ? 18 : 20,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                      child: Text(
                        'VS',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.48),
                          fontFamily: 'WenJinMinchoP0',
                          fontSize: compact ? 12.5 : 13.5,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.4,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        rightName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.82),
                          fontSize: compact ? 18 : 20,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 22 : 26),
                if (loading)
                  SizedBox(
                    width: compact ? 176 : 210,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 1.15,
                        backgroundColor: Colors.white.withOpacity(.07),
                        color: Colors.white.withOpacity(.78),
                      ),
                    ),
                  )
                else ...<Widget>[
                  SizedBox(
                    width: compact ? 176 : 210,
                    child: Container(
                      height: .8,
                      color: Colors.white.withOpacity(.12),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    '生成失败',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.84),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                  if (errorText.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        errorText.trim(),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.36),
                          fontSize: 9.8,
                          height: 1.45,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(.82),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                        side: BorderSide(
                          color: Colors.white.withOpacity(.16),
                          width: .7,
                        ),
                      ),
                    ),
                    child: const Text(
                      '重试',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class YoranBattlePage extends StatefulWidget {
  const YoranBattlePage({
    super.key,
    this.playerName = '玩家',
    this.playerAvatar = '',
    this.playerPortrait = '',
    this.enemyName = '对手',
    this.enemyPortrait = '',
    this.sceneBackground = '',
    this.sceneTitle = '',
    this.sceneSubtitle = '',
    this.socketService,
    this.enemies = const <YoranBattleEnemy>[],
    this.skills = yoranDefaultBattleSkills,
    this.companions = const <YoranBattleCompanion>[],
    this.items = const <dynamic>[],
    this.equipment = const <dynamic>[],
    this.onSettleItems,
    this.onConsumeItem,
  });

  final String playerName;
  final String playerAvatar;
  final String playerPortrait;
  final String enemyName;
  final String enemyPortrait;
  final String sceneBackground;
  final String sceneTitle;
  final String sceneSubtitle;
  final NovelSocketService? socketService;
  final List<YoranBattleEnemy> enemies;
  final List<YoranBattleSkill> skills;
  final List<YoranBattleCompanion> companions;
  final List<dynamic> items;
  final List<dynamic> equipment;
  final YoranBattleItemSettlementCallback? onSettleItems;
  @Deprecated('请改用战斗结束批量结算 onSettleItems')
  final YoranBattleItemConsumeCallback? onConsumeItem;

  @override
  State<YoranBattlePage> createState() => _YoranBattlePageState();
}

enum _BattleCommandCategory { skills, items, companions }

enum _EnemyIntentKind {
  claw,
  heavy,
  guard,
  recover,
  skill,
}

class _YoranBattlePageState extends State<YoranBattlePage>
    with TickerProviderStateMixin {
  static const int _baseMaxHp = 100;
  static const int _baseMaxQi = 100;
  static const double _baseSkillPower = 10.0;
  static const double _skillDamageVariance = .10;
  static const int _maxBattleLogEntries = 120;

  final math.Random _random = math.Random();
  final ScrollController _logController = ScrollController();

  late final AnimationController _entranceController;
  late final AnimationController _playerAttackController;
  late final AnimationController _enemyAttackController;
  late final AnimationController _playerDamageController;
  late final AnimationController _enemyDamageController;
  late final AnimationController _enemyDodgeController;
  late final AnimationController _playerDodgeController;
  late final AnimationController _playerHealController;
  late final AnimationController _playerRestController;
  late final AnimationController _playerGuardController;
  late final AnimationController _playerGuardImpactController;
  late final AnimationController _combatTextController;
  late final AnimationController _companionAssistController;
  late final AnimationController _skillVfxController;
  late final AnimationController _skillImpactController;
  late final AnimationController _playerBreathController;
  late final AnimationController _enemyBreathController;


  late int _playerHp;
  int _enemyHp = _baseMaxHp;
  late final List<YoranBattleEnemy> _battleEnemies;
  late final List<YoranBattleItem> _battleItems;
  late final List<YoranBattleEquipment> _playerEquipment;
  late final List<YoranBattleCompanion> _battleCompanions;
  late List<YoranBattleSkill> _availableSkillsCache;
  late final int _playerMaxHp;
  late final int _playerMaxQi;
  late final double _equipmentAttackMultiplier;
  late final double _equipmentDefenseMultiplier;
  late final int _equipmentHitPercent;
  late final int _equipmentDodgePercent;
  late final int _equipmentCriticalPercent;
  late final int _maxItemUsesPerBattle;
  final Map<String, int> _itemCounts = <String, int>{};
  final Map<String, int> _consumedItemCounts = <String, int>{};
  int _itemUsesThisBattle = 0;
  bool _settlingItems = false;
  bool _settlementAccepted = false;
  Map<String, dynamic> _battleSettlement = const <String, dynamic>{};
  String _settlementError = '';
  int _enemyIndex = 0;
  String? _selectedSkillName;
  // 拖拽技能卡时用于显示场景中央的“释放区”。
  String? _draggingSkillName;
  String? _selectedItemId;
  String? _selectedCompanionId;
  String? _selectedCompanionSkillId;
  YoranBattleCompanion? _activeAssistCompanion;
  YoranBattleSkill? _activeAssistSkill;
  final Set<String> _usedCompanionSkillIds = <String>{};
  bool _companionAssistUsedThisRound = false;
  bool _companionImagesPrecacheStarted = false;
  int _enemyStunnedByCompanion = 0;
  int _companionCounterMin = 0;
  int _companionCounterMax = 0;
  String _companionCounterName = '';
  late int _playerQi;
  int _enemyQi = 100;
  int _enemyBurnTurns = 0;
  int _enemyBurnDamage = 0;
  int _playerBurnTurns = 0;
  int _playerBurnDamage = 0;
  int _playerStunnedTurns = 0;
  int _enemyExposedTurns = 0;
  int _enemyExposedHitBonus = 0;
  int _enemyExposedExtraDamageMin = 0;
  int _enemyExposedExtraDamageMax = 0;
  int _round = 1;
  bool _playerGuarding = false;
  bool _playerDodging = false;
  int _playerGuardReductionPercent = 0;
  int _playerDodgeDifficultyBonus = 0;
  _EnemyIntentKind _enemyIntent = _EnemyIntentKind.claw;
  YoranBattleSkill? _enemyIntentSkill;
  final Map<String, int> _skillCooldowns = <String, int>{};
  final Map<String, int> _enemySkillCooldowns = <String, int>{};
  String _combatText = '';
  bool _combatTextOnEnemy = true;
  bool _combatTextCritical = false;
  Color _combatTextColor = _BattleColors.enemy;
  bool _playerDamageCritical = false;
  bool _enemyDamageCritical = false;
  YoranBattleSkill? _activeSkillVfx;
  bool _activeSkillVfxHit = true;
  bool _activeSkillVfxCritical = false;
  bool _busy = true;
  bool _entranceVisible = true;
  YoranBattleOutcome? _outcome;
  
  _BattleCommandCategory? _activeCategory = _BattleCommandCategory.skills;
  
  final List<_BattleLogEntry> _logs = <_BattleLogEntry>[];
  final ValueNotifier<int> _logRevision = ValueNotifier<int>(0);

  bool get _canAct => !_busy && _outcome == null && !_entranceVisible;
  YoranBattleEnemy get _currentEnemy => _battleEnemies[_enemyIndex];
  String get _enemyName => _currentEnemy.name.trim().isEmpty
      ? '对手${_enemyIndex + 1}'
      : _currentEnemy.name.trim();
  String get _enemyPortrait => _currentEnemy.portrait;
  int get _enemyMaxHp => math.max(1, _currentEnemy.maxHp);
  int get _enemyStartingHp =>
      (_currentEnemy.currentHp ?? _enemyMaxHp).clamp(1, _enemyMaxHp).toInt();
  int get _enemyStartingQi =>
      (_currentEnemy.currentEnergy ?? 100).clamp(0, 100).toInt();
  double get _playerDamageMultiplier =>
      _currentEnemy.playerDamageMultiplier.clamp(.05, 20).toDouble();
  double get _opponentDamageMultiplier =>
      _currentEnemy.opponentDamageMultiplier.clamp(.05, 20).toDouble();
  int get _playerHitBonusShift => _currentEnemy.playerHitBonusShift;
  int get _opponentHitBonusShift => _currentEnemy.opponentHitBonusShift;
  bool get _hasNextEnemy => _enemyIndex + 1 < _battleEnemies.length;

  int _qualityForSlot(String slot) {
    var quality = 0;
    for (final item in _playerEquipment) {
      if (item.slot == slot) quality = math.max(quality, item.quality);
    }
    return quality.clamp(0, 10).toInt();
  }

  int _accessoryQualityTotal() {
    final qualities = _playerEquipment
        .where((item) => item.slot == 'accessory')
        .map((item) => item.quality)
        .toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return qualities.take(3).fold<int>(0, (sum, quality) => sum + quality);
  }

  int _enhancementForSlot(String slot) {
    var level = 0;
    for (final item in _playerEquipment) {
      if (item.slot == slot) level = math.max(level, item.enhancementLevel);
    }
    return level.clamp(0, 10).toInt();
  }

  int _accessoryEnhancementTotal() {
    final levels = _playerEquipment
        .where((item) => item.slot == 'accessory')
        .map((item) => item.enhancementLevel)
        .toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return levels.take(3).fold<int>(0, (sum, level) => sum + level);
  }

  int _equipmentAffixTotal(String key, {required int cap}) {
    var total = 0;
    for (final item in _playerEquipment) {
      total += item.affixes[key] ?? 0;
    }
    return total.clamp(0, cap).toInt();
  }

  String get _equipmentEffectSummary {
    if (_playerEquipment.isEmpty) return '';
    final effects = <String>[
      if (_playerMaxHp != _baseMaxHp) '生命$_playerMaxHp',
      if (_playerMaxQi != _baseMaxQi) '精力$_playerMaxQi',
      if (_equipmentAttackMultiplier > 1)
        '威力×${_equipmentAttackMultiplier.toStringAsFixed(1)}',
      if (_equipmentDefenseMultiplier < 1)
        '承伤×${_equipmentDefenseMultiplier.toStringAsFixed(2)}',
      if (_equipmentHitPercent > 0) '精准$_equipmentHitPercent%',
      if (_equipmentDodgePercent > 0) '机动$_equipmentDodgePercent%',
      if (_equipmentCriticalPercent > 0) '爆发$_equipmentCriticalPercent%',
      if (_qualityForSlot('back') > 0) '本局道具$_maxItemUsesPerBattle次',
    ];
    return effects.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _battleEnemies = (widget.enemies.isEmpty
            ? <YoranBattleEnemy>[
                YoranBattleEnemy(
                  name: widget.enemyName,
                  portrait: widget.enemyPortrait,
                ),
              ]
            : widget.enemies)
        .take(5)
        .toList(growable: false);
    _battleItems = widget.items
        .map(YoranBattleItem.fromState)
        .whereType<YoranBattleItem>()
        .toList(growable: false);
    _playerEquipment = widget.equipment
        .map(YoranBattleEquipment.fromState)
        .whereType<YoranBattleEquipment>()
        .toList(growable: false);
    _battleCompanions = widget.companions.take(3).toList(growable: false);
    _selectedCompanionId =
        _battleCompanions.isEmpty ? null : _battleCompanions.first.id;
    _availableSkillsCache = _collectAvailableSkills();

    final upperQuality = _qualityForSlot('upper');
    final faceQuality = _qualityForSlot('face');
    final handheldQuality = _qualityForSlot('handheld');
    final lowerQuality = _qualityForSlot('lower');
    final backQuality = _qualityForSlot('back');
    final upperEnhancement = _enhancementForSlot('upper');
    final faceEnhancement = _enhancementForSlot('face');
    final handheldEnhancement = _enhancementForSlot('handheld');
    final lowerEnhancement = _enhancementForSlot('lower');
    final headEnhancement = _enhancementForSlot('head');
    final feetEnhancement = _enhancementForSlot('feet');
    final backEnhancement = _enhancementForSlot('back');
    final accessoryEnhancementTotal = _accessoryEnhancementTotal();
    final hpAffix = _equipmentAffixTotal('max_hp_percent', cap: 40);
    final energyAffix = _equipmentAffixTotal('max_energy_percent', cap: 40);
    final attackAffix = _equipmentAffixTotal('attack_percent', cap: 40);
    final defenseAffix = _equipmentAffixTotal('defense_percent', cap: 15);
    final hitAffix = _equipmentAffixTotal('hit_percent', cap: 24);
    final dodgeAffix = _equipmentAffixTotal('dodge_percent', cap: 16);
    final criticalAffix = _equipmentAffixTotal('critical_percent', cap: 24);

    // 强化最高+10；成功率由后端结算。攻击/生命/精力每级+3%；其余主属性采用较小增幅并继续受原硬上限约束。
    _playerMaxHp = (_baseMaxHp *
            (1 + upperQuality * .10 + upperEnhancement * .03 + hpAffix / 100))
        .round();
    _playerMaxQi = (_baseMaxQi *
            (1 + faceQuality * .10 + faceEnhancement * .03 + energyAffix / 100))
        .round();
    _equipmentAttackMultiplier = 1 +
        handheldQuality * .10 +
        handheldEnhancement * .03 +
        attackAffix / 100;
    // 下装强化每级额外1%减伤；总减伤仍封顶65%。
    final defenseReduction = (lowerQuality * .05 +
            lowerEnhancement * .01 +
            defenseAffix / 100)
        .clamp(0.0, .65)
        .toDouble();
    _equipmentDefenseMultiplier = 1 - defenseReduction;
    // 头部强化每级+1%装备命中，仍封顶45%。
    _equipmentHitPercent = (_qualityForSlot('head') * 3 +
            headEnhancement +
            hitAffix)
        .clamp(0, 45)
        .toInt();
    // 足部强化每2级+1%装备闪避，+10共+5%，仍封顶25%。
    _equipmentDodgePercent = (_qualityForSlot('feet') +
            (feetEnhancement ~/ 2) +
            dodgeAffix)
        .clamp(0, 25)
        .toInt();
    // 饰品强化总等级每约3.33级提供1%暴击；三件+10合计+9%，最终仍封顶50%。
    final accessoryEnhancementCritical =
        (accessoryEnhancementTotal * .30).round();
    _equipmentCriticalPercent = (_accessoryQualityTotal() +
            accessoryEnhancementCritical +
            criticalAffix)
        .clamp(0, 50)
        .toInt();
    // 背包+5/+10各额外增加1次道具使用；整场战斗共享次数。
    _maxItemUsesPerBattle = 2 + backQuality + (backEnhancement ~/ 5);
    _playerHp = _playerMaxHp;
    _playerQi = (_playerMaxQi * .40).round();
    for (final item in _battleItems) {
      _itemCounts[item.id] = item.quantity;
    }
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850), // 入场动画：短促的黑白斜切过场
    )..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        setState(() {
          _entranceVisible = false;
          _busy = false;
          _activeCategory = _BattleCommandCategory.skills; 
        });
      });
    _playerAttackController = _controller(520);
    _enemyAttackController = _controller(520);
    _playerDamageController = _controller(420);
    _enemyDamageController = _controller(420);
    _enemyDodgeController = _controller(440);
    _playerDodgeController = _controller(440);
    _playerHealController = _controller(720);
    _playerRestController = _controller(900);
    _playerGuardController = _controller(520);
    _playerGuardImpactController = _controller(460);
    _combatTextController = _controller(760);
    _companionAssistController = _controller(1080)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _activeAssistCompanion = null;
            _activeAssistSkill = null;
          });
        }
      });
    _skillVfxController = _controller(1200)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _activeSkillVfx = null);
        }
      });
    _skillImpactController = _controller(190);
    _playerBreathController = _controller(3900)
      ..value = .18
      ..repeat(reverse: true);
    _enemyBreathController = _controller(4400)
      ..value = .62
      ..repeat(reverse: true);
    _resetBattle(startEntrance: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_companionImagesPrecacheStarted) return;
    _companionImagesPrecacheStarted = true;
    // 兼容直接 showYoranBattlePage 的入口：没有战前 loader 时，
    // 也会在战斗页第一次拿到 MediaQuery 后立刻预热援助角色图片。
    unawaited(_precacheCompanionBattleImages(context, _battleCompanions));
  }

  AnimationController _controller(int milliseconds) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: milliseconds),
      );

  @override
  void didUpdateWidget(covariant YoranBattlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.skills, widget.skills)) {
      _availableSkillsCache = _collectAvailableSkills();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _playerAttackController.dispose();
    _enemyAttackController.dispose();
    _playerDamageController.dispose();
    _enemyDamageController.dispose();
    _enemyDodgeController.dispose();
    _playerDodgeController.dispose();
    _playerHealController.dispose();
    _playerRestController.dispose();
    _playerGuardController.dispose();
    _playerGuardImpactController.dispose();
    _combatTextController.dispose();
    _companionAssistController.dispose();
    _skillVfxController.dispose();
    _skillImpactController.dispose();
    _playerBreathController.dispose();
    _enemyBreathController.dispose();
    _logController.dispose();
    _logRevision.dispose();
    super.dispose();
  }

  void _toggleCategory(_BattleCommandCategory category) {
    if (!_canAct) return;
    if (_activeCategory == category) return;
    setState(() {
      _activeCategory = category;
    });
  }


  // 渲染技能卡片
  Widget _buildSkillCards({bool compact = false}) {
    return _BattleCardHand(
      compact: compact,
      skills: _availableSkills,
      cooldowns: _skillCooldowns,
      playerQi: _playerQi,
      playerHp: _playerHp,
      enabled: _canAct,
      selectedSkillName: _selectedSkillName,
      onSkillSelected: (name) {
        if (!_canAct) return;
        setState(() {
          if (_selectedSkillName == name) {
            _selectedSkillName = null;
          } else {
            _selectedSkillName = name;
            _selectedItemId = null;
          }
        });
        unawaited(HapticFeedback.selectionClick());
      },
      onSkillQuickCast: (name) {
        if (!_canUseSkill(name)) return;
        if (mounted) {
          setState(() {
            _draggingSkillName = null;
            _selectedSkillName = null;
            _selectedItemId = null;
          });
        }
        unawaited(HapticFeedback.mediumImpact());
        unawaited(_useSkill(name));
      },
      onDragStateChanged: (name) {
        if (!mounted) return;
        setState(() {
          // 拖拽和“选择技能”彻底解耦：任意可用卡都能直接上滑释放。
          _draggingSkillName = name;
          if (name != null) _selectedItemId = null;
        });
      },
    );
  }

  // 渲染道具卡片
  Widget _buildItemCards({bool compact = false}) {
    if (_battleItems.isEmpty) {
      return const Center(
        child: Text(
          '暂无可在战斗中使用的道具',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 24,
          compact ? 3 : 7,
          compact ? 10 : 24,
          compact ? 2 : 4,
        ),
        physics: const BouncingScrollPhysics(),
        itemCount: _battleItems.length,
        separatorBuilder: (context, index) => SizedBox(width: compact ? 7 : 10),
        itemBuilder: (context, index) {
          final item = _battleItems[index];
          final count = _itemCounts[item.id] ?? 0;
          final isSelected = _selectedItemId == item.id;
          final isEmpty = count <= 0;
          final accent = item.restoresHp && !item.restoresSp
              ? _BattleColors.player
              : item.restoresSp && !item.restoresHp
                  ? _BattleColors.energy
                  : _BattleColors.text;

          return AnimatedSlide(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            offset: isSelected ? const Offset(0, -0.055) : Offset.zero,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              scale: isSelected ? 1.035 : 1.0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (!isEmpty && _canAct)
                    ? () {
                        setState(() {
                          if (_selectedItemId == item.id) {
                            _selectedItemId = null;
                          } else {
                            _selectedItemId = item.id;
                            _selectedSkillName = null;
                          }
                        });
                        unawaited(HapticFeedback.selectionClick());
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  width: compact ? 76 : 92,
                  height: compact ? 100 : 122,
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? const Color(0x8A0A0B0D)
                        : (isSelected
                            ? const Color(0xD9181A1D)
                            : const Color(0x99121416)),
                    borderRadius: BorderRadius.circular(compact ? 8 : 10),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white.withOpacity(.82)
                          : Colors.white.withOpacity(isEmpty ? .035 : .10),
                      width: isSelected ? 1.1 : .8,
                    ),
                    boxShadow: isSelected
                        ? const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x52000000),
                              blurRadius: 14,
                              offset: Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: compact ? 7 : 9,
                        right: compact ? 7 : 9,
                        top: 0,
                        child: Container(
                          height: 2,
                          color: isEmpty
                              ? Colors.white10
                              : (isSelected ? Colors.white : accent.withOpacity(.62)),
                        ),
                      ),
                      Positioned(
                        top: compact ? 7 : 9,
                        left: compact ? 7 : 9,
                        child: Text(
                          'Q${item.quality}',
                          style: TextStyle(
                            color: isEmpty ? Colors.white24 : Colors.white54,
                            fontSize: compact ? 7.5 : 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                      Positioned(
                        top: compact ? 6 : 8,
                        right: compact ? 7 : 9,
                        child: Text(
                          '×$count',
                          style: TextStyle(
                            color: isEmpty ? Colors.white24 : Colors.white70,
                            fontSize: compact ? 8.8 : 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 6 : 8,
                            2,
                            compact ? 6 : 8,
                            compact ? 12 : 14,
                          ),
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isEmpty ? Colors.white30 : _BattleColors.text,
                              fontFamily: 'WenJinMinchoP0',
                              fontSize: compact ? 11.8 : 14,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: compact ? 5 : 7,
                        right: compact ? 5 : 7,
                        bottom: compact ? 6 : 8,
                        child: Text(
                          item.effectLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isEmpty ? Colors.white24 : accent.withOpacity(.78),
                            fontSize: compact ? 7.4 : 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .2,
                          ),
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
    );
  }

  void _showCompanionUnavailableMessage({required bool used}) {
    final String message;
    if (used) {
      message = '该援助技能本场已经使用过了';
    } else if (_companionAssistUsedThisRound) {
      message = '本回合援助已使用 · 下一回合可再次援助';
    } else if (!_canAct) {
      message = '当前行动正在结算，请稍候';
    } else {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEE111317),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      ),
    );
  }

  Widget _buildCompanionSkillCard(
    YoranBattleCompanion companion,
    YoranBattleSkill skill, {
    required bool compact,
  }) {
    final used = _usedCompanionSkillIds.contains(skill.id);
    final selected = _selectedCompanionSkillId == skill.id;
    final roundLocked = _companionAssistUsedThisRound && !used;
    final disabled = used || roundLocked || !_canAct;
    final accent = _battleSkillQualityColor(skill.quality);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (disabled) {
          _showCompanionUnavailableMessage(used: used);
          return;
        }
        setState(() {
          _selectedCompanionSkillId = selected ? null : skill.id;
          _selectedSkillName = null;
          _selectedItemId = null;
        });
        unawaited(HapticFeedback.selectionClick());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 10,
          compact ? 6 : 9,
          compact ? 8 : 10,
          compact ? 5 : 8,
        ),
        decoration: BoxDecoration(
          color: used
              ? const Color(0x8A0A0B0D)
              : (selected
                  ? const Color(0xD9181A1D)
                  : const Color(0x99121416)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(.84)
                : Colors.white.withOpacity(used ? .04 : .10),
            width: selected ? 1.1 : .8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _BattleSkillTypeIcon(
                  skill: skill,
                  size: compact ? 15 : 18,
                  color: disabled ? Colors.white24 : accent.withOpacity(.86),
                ),
                SizedBox(width: compact ? 5 : 7),
                Expanded(
                  child: Text(
                    skill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: used ? Colors.white30 : _BattleColors.text,
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${companion.star}★ · ${companion.skillEffectPercent}%',
                  maxLines: 1,
                  style: TextStyle(
                    color: used ? Colors.white24 : Colors.white38,
                    fontSize: compact ? 7.4 : 8.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .15,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 3 : 7),
            Expanded(
              child: Text(
                skill.detail,
                maxLines: compact ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: used ? Colors.white24 : Colors.white54,
                  fontSize: compact ? 8.5 : 9.5,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    used
                        ? '本场已使用'
                        : roundLocked
                            ? '本回合已援助 · 下回合恢复'
                            : !_canAct
                                ? '等待当前行动结束'
                                : '每回合可援助 1 次 · 0 SP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: used
                          ? Colors.white30
                          : roundLocked
                              ? Colors.white.withOpacity(.72)
                              : disabled
                                  ? Colors.white38
                                  : accent.withOpacity(.86),
                      fontSize: compact ? 8.2 : 9.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!compact)
                  Text(
                    _battleSkillTypeName(skill.iconType),
                    style: TextStyle(
                      color: used ? Colors.white24 : Colors.white38,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionCards({bool compact = false}) {
    YoranBattleCompanion? activeCompanion;
    for (final companion in _battleCompanions) {
      if (companion.id == _selectedCompanionId) {
        activeCompanion = companion;
        break;
      }
    }
    activeCompanion ??=
        _battleCompanions.isEmpty ? null : _battleCompanions.first;
    final entries = activeCompanion == null
        ? const <MapEntry<YoranBattleCompanion, YoranBattleSkill>>[]
        : activeCompanion.skills
            .map((skill) =>
                MapEntry<YoranBattleCompanion, YoranBattleSkill>(
                  activeCompanion!,
                  skill,
                ))
            .toList(growable: false);
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '暂无出战角色或援战技能',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compact
            ? entries.length.clamp(1, 4).toInt()
            : (constraints.maxWidth >= 520 ? 4 : 2);
        final rowCount = (entries.length / columns).ceil();
        final gap = compact ? 6.0 : 8.0;
        final denseCards = compact || rowCount > 1;
        final rows = <Widget>[];
        for (var row = 0; row < rowCount; row++) {
          final cells = <Widget>[];
          for (var column = 0; column < columns; column++) {
            final index = row * columns + column;
            cells.add(
              Expanded(
                child: index < entries.length
                    ? _buildCompanionSkillCard(
                        entries[index].key,
                        entries[index].value,
                        compact: denseCards,
                      )
                    : const SizedBox.shrink(),
              ),
            );
            if (column < columns - 1) cells.add(SizedBox(width: gap));
          }
          rows.add(Expanded(child: Row(children: cells)));
          if (row < rowCount - 1) rows.add(SizedBox(height: gap));
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 18,
            compact ? 2 : 4,
            compact ? 8 : 18,
            0,
          ),
          child: Column(children: rows),
        );
      },
    );
  }

  MapEntry<YoranBattleCompanion, YoranBattleSkill>? _selectedCompanionSkill() {
    final selectedId = _selectedCompanionSkillId;
    if (selectedId == null) return null;
    for (final companion in _battleCompanions) {
      for (final skill in companion.skills) {
        if (skill.id == selectedId) {
          return MapEntry<YoranBattleCompanion, YoranBattleSkill>(companion, skill);
        }
      }
    }
    return null;
  }

  Future<void> _useCompanionSkill(
    YoranBattleCompanion companion,
    YoranBattleSkill skill,
  ) async {
    if (!_canAct ||
        _companionAssistUsedThisRound ||
        _usedCompanionSkillIds.contains(skill.id)) return;
    setState(() {
      _busy = true;
      _usedCompanionSkillIds.add(skill.id);
      _companionAssistUsedThisRound = true;
      _selectedCompanionSkillId = null;
      _activeAssistCompanion = companion;
      _activeAssistSkill = skill;
    });
    unawaited(HapticFeedback.mediumImpact());
    // Companion assist and skill VFX play sequentially: finish assist first,
    // then start VFX so the assist overlay cannot cover the skill effect.
    try {
      await _companionAssistController.forward(from: 0).orCancel;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (!await _advanceCompanionSkillToImpact(skill)) return;

    final starMultiplier = companion.skillEffectMultiplier;
    final rolledDamage = _rollSkillDamage(
      skill,
      effectMultiplier: starMultiplier,
    );
    final actualDamage = math.min(_enemyHp, _scaleCompanionDamage(rolledDamage));
    final directHeal = _skillHealAmount(
      skill,
      _playerMaxHp,
      effectMultiplier: starMultiplier,
    );
    final recovered = math.min(
      directHeal + (actualDamage * skill.lifestealPercent / 100).round(),
      _playerMaxHp - _playerHp,
    );
    final energyGain = _skillEnergyGain(
      skill,
      _playerMaxQi,
      effectMultiplier: starMultiplier,
    );
    final beforeQi = _playerQi;
    if (actualDamage > 0) {
      if (!await _performSkillHitStop(
        skill,
        critical: false,
        stopPlayerAttack: false,
      )) return;
    } else if (skill.hasVfx) {
      unawaited(_skillImpactController.forward(from: 0));
    }
    setState(() {
      _enemyHp = _clampEnemyHp(_enemyHp - actualDamage);
      _playerHp = _clampPlayerHp(_playerHp + recovered);
      _playerQi = _clampPlayerQi(_playerQi + energyGain);
      final burnBase = _skillBurnBaseDamage(
        skill,
        effectMultiplier: starMultiplier,
      );
      if (skill.burnTurns > 0 && burnBase > 0) {
        _enemyBurnTurns = math.max(_enemyBurnTurns, skill.burnTurns);
        _enemyBurnDamage = math.max(
          _enemyBurnDamage,
          _scaleCompanionDamage(burnBase),
        );
      }
      if (skill.guarding) {
        _playerGuarding = true;
        _playerGuardReductionPercent = math.max(
          _playerGuardReductionPercent,
          skill.guardReductionPercent,
        );
      }
      if (skill.dodging) {
        _playerDodging = true;
        _playerDodgeDifficultyBonus = math.max(
          _playerDodgeDifficultyBonus,
          skill.enemyHitDifficultyBonus,
        );
      }
      if (skill.exposes) {
        _enemyExposedTurns = math.max(_enemyExposedTurns, 1);
        _enemyExposedHitBonus = math.max(_enemyExposedHitBonus, skill.exposeHitBonus);
        final extraPower =
            (skill.exposeExtraPowerPercent * starMultiplier).round();
        final extraMin = _powerDamageMin(extraPower);
        final extraMax = _powerDamageMax(extraPower);
        _enemyExposedExtraDamageMin = math.max(
          _enemyExposedExtraDamageMin,
          extraMin,
        );
        _enemyExposedExtraDamageMax = math.max(
          _enemyExposedExtraDamageMax,
          extraMax,
        );
      }
      if (skill.stunTurns > 0) {
        _enemyStunnedByCompanion = math.max(_enemyStunnedByCompanion, 1);
      }
      if (skill.counterPowerPercent > 0) {
        final counterPower =
            (skill.counterPowerPercent * starMultiplier).round();
        _companionCounterMin = _powerDamageMin(counterPower);
        _companionCounterMax = _powerDamageMax(counterPower);
        _companionCounterName = companion.name;
      }
    });
    if (actualDamage > 0) {
      unawaited(_enemyDamageController.forward(from: 0));
      _showCombatText('-$actualDamage', onEnemy: true, color: _BattleColors.player);
    }
    if (recovered > 0) unawaited(_playerHealController.forward(from: 0));
    _addLog(
      _BattleLogEntry(
        label: '${companion.name} · ${skill.name}',
        before: '${companion.name}发动援战技能。',
        meta: <String>[
          '${skill.quality}品',
          if (actualDamage > 0) '伤害$actualDamage',
          if (recovered > 0) '生命+$recovered',
          if (_playerQi > beforeQi) '精力+${_playerQi - beforeQi}',
          '本场剩余${_battleCompanions.fold<int>(0, (sum, item) => sum + item.skills.where((candidate) => !_usedCompanionSkillIds.contains(candidate.id)).length)}个援战技能',
        ].join(' · '),
        tone: _BattleLogTone.success,
      ),
    );
    if (!await _pause(520)) return;
    if (_enemyHp <= 0) {
      await _finishVictory();
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _activeCategory = _BattleCommandCategory.skills;
      });
    }
  }

  int _d20() => 1 + _random.nextInt(20);

  int _clampPlayerHp(int value) => value.clamp(0, _playerMaxHp).toInt();

  int _clampEnemyHp(int value) => value.clamp(0, _enemyMaxHp).toInt();

  int _clampPlayerQi(int value) => value.clamp(0, _playerMaxQi).toInt();

  int _clampEnemyQi(int value) => value.clamp(0, 100).toInt();

  int _scalePlayerDamage(int value) {
    if (value <= 0) return 0;
    return math.max(
      1,
      (value * _playerDamageMultiplier * _equipmentAttackMultiplier).round(),
    );
  }

  int _scaleOpponentDamage(int value) {
    if (value <= 0) return 0;
    return math.max(
      1,
      (value * _opponentDamageMultiplier * _equipmentDefenseMultiplier).round(),
    );
  }

  int _rollBetween(int min, int max) =>
      min + _random.nextInt(math.max(1, max - min + 1));

  int _rollPowerDamage(int powerPercent, {double effectMultiplier = 1.0}) {
    if (powerPercent <= 0) return 0;
    final variance = 1 - _skillDamageVariance +
        _random.nextDouble() * (_skillDamageVariance * 2);
    return math.max(
      1,
      (_baseSkillPower * (powerPercent / 100) * effectMultiplier * variance)
          .round(),
    );
  }

  int _powerDamageMin(int powerPercent, {double effectMultiplier = 1.0}) {
    if (powerPercent <= 0) return 0;
    return math.max(
      1,
      (_baseSkillPower * (powerPercent / 100) * effectMultiplier *
              (1 - _skillDamageVariance))
          .round(),
    );
  }

  int _powerDamageMax(int powerPercent, {double effectMultiplier = 1.0}) {
    if (powerPercent <= 0) return 0;
    return math.max(
      1,
      (_baseSkillPower * (powerPercent / 100) * effectMultiplier *
              (1 + _skillDamageVariance))
          .round(),
    );
  }

  int _rollSkillDamage(YoranBattleSkill skill, {double effectMultiplier = 1.0}) {
    return _rollPowerDamage(
      skill.powerPercent,
      effectMultiplier: effectMultiplier,
    );
  }

  int _percentAmount(int maximum, int percent, {double effectMultiplier = 1.0}) {
    if (maximum <= 0 || percent <= 0) return 0;
    return math.max(
      1,
      (maximum * (percent / 100) * effectMultiplier).round(),
    );
  }

  int _skillHealAmount(
    YoranBattleSkill skill,
    int maximum, {
    double effectMultiplier = 1.0,
  }) {
    return _percentAmount(
      maximum,
      skill.healMaxHpPercent,
      effectMultiplier: effectMultiplier,
    );
  }

  int _skillEnergyGain(
    YoranBattleSkill skill,
    int maximum, {
    double effectMultiplier = 1.0,
  }) {
    return _percentAmount(
      maximum,
      skill.energyMaxQiPercent,
      effectMultiplier: effectMultiplier,
    );
  }

  int _skillBurnBaseDamage(
    YoranBattleSkill skill, {
    double effectMultiplier = 1.0,
  }) {
    return _rollPowerDamage(
      skill.burnPowerPercent,
      effectMultiplier: effectMultiplier,
    );
  }

  int _scaleCompanionDamage(int value) {
    if (value <= 0) return 0;
    // 伙伴吃敌我强弱修正，但不继承主角武器威力；角色星级单独作用于援战效果。
    return math.max(1, (value * _playerDamageMultiplier).round());
  }

  String _modifierLabel(int value, String label) {
    if (value == 0) return '';
    return ' ${value > 0 ? '+' : ''}$value$label';
  }

  List<YoranBattleSkill> _collectAvailableSkills() {
    final skillsByName = <String, YoranBattleSkill>{};
    for (final skill in yoranBaseBattleSkills) {
      skillsByName[skill.name.trim()] = skill;
    }
    for (final skill in widget.skills) {
      final name = skill.name.trim();
      if (name.isNotEmpty && !skillsByName.containsKey(name)) {
        skillsByName[name] = skill;
      }
    }
    return skillsByName.values.toList(growable: false);
  }

  List<YoranBattleSkill> get _availableSkills => _availableSkillsCache;

  YoranBattleSkill _skillFor(String rawName) {
    final name = rawName.trim();
    for (final skill in _availableSkills) {
      if (skill.name.trim() == name) return skill;
    }
    for (final skill in yoranDefaultBattleSkills) {
      if (skill.name == name) return skill;
    }
    return YoranBattleSkill(
      name: name.isEmpty ? '技能攻击' : name,
      detail: '暂无技能描述',
      quality: 3,
      powerPercent: 120,
      hitBonus: 4,
      energyCost: 12,
      cooldown: 1,
    );
  }

  int _cooldownFor(String skillName) => _skillCooldowns[skillName] ?? 0;

  bool _canUseSkill(String skillName) {
    final skill = _skillFor(skillName);
    return _canAct &&
        (!skill.resting || _playerQi < _playerMaxQi) &&
        _playerQi >= skill.energyCost &&
        (skill.canSelfKill || _playerHp > skill.healthCost) &&
        _cooldownFor(skill.name) <= 0;
  }

  void _tickSkillCooldowns() {
    for (final name in _skillCooldowns.keys.toList(growable: false)) {
      final next = (_skillCooldowns[name] ?? 0) - 1;
      if (next <= 0) {
        _skillCooldowns.remove(name);
      } else {
        _skillCooldowns[name] = next;
      }
    }
  }

  void _tickEnemySkillCooldowns() {
    for (final name in _enemySkillCooldowns.keys.toList(growable: false)) {
      final next = (_enemySkillCooldowns[name] ?? 0) - 1;
      if (next <= 0) {
        _enemySkillCooldowns.remove(name);
      } else {
        _enemySkillCooldowns[name] = next;
      }
    }
  }

  String get _enemyIntentTitle => switch (_enemyIntent) {
        _EnemyIntentKind.claw => '快速攻击',
        _EnemyIntentKind.heavy => '强力攻击',
        _EnemyIntentKind.guard => '防御姿态',
        _EnemyIntentKind.recover => '恢复状态',
        _EnemyIntentKind.skill => _enemyIntentSkill?.name ?? '特殊技能',
      };

  void _chooseNextEnemyIntent() {
    final roll = _random.nextInt(100);
    final availableSkills = _currentEnemy.skills.where((skill) {
      final cooldown = _enemySkillCooldowns[skill.name] ?? 0;
      return cooldown <= 0 &&
          _enemyQi >= skill.energyCost &&
          (skill.canSelfKill || _enemyHp > skill.healthCost);
    }).toList(growable: false);
    if (availableSkills.isNotEmpty && roll < 68) {
      _enemyIntentSkill = availableSkills[_random.nextInt(availableSkills.length)];
      _enemyIntent = _EnemyIntentKind.skill;
      return;
    }
    _enemyIntentSkill = null;
    if (_enemyHp / _enemyMaxHp < .38 && roll < 25) {
      _enemyIntent = _EnemyIntentKind.recover;
    } else if (roll < 50) {
      _enemyIntent = _EnemyIntentKind.claw;
    } else if (roll < 75) {
      _enemyIntent = _EnemyIntentKind.heavy;
    } else if (roll < 90) {
      _enemyIntent = _EnemyIntentKind.guard;
    } else {
      _enemyIntent = _enemyHp / _enemyMaxHp < .88
          ? _EnemyIntentKind.recover
          : _EnemyIntentKind.claw;
    }
  }

  Future<bool> _pause(int milliseconds) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return mounted;
  }

  Future<void> _evictUnusedBattleImage(String source) async {
    final path = source.trim();
    if (path.isEmpty) return;
    try {
      final ImageProvider provider =
          path.startsWith('http://') || path.startsWith('https://')
              ? NetworkImage(path)
              : AssetImage(path);
      await provider.evict();
    } catch (_) {
      // 图片缓存清理失败不应影响战斗流程。
    }
  }

  void _resetBattle({bool startEntrance = false}) {
    if (!_playerBreathController.isAnimating) {
      unawaited(_playerBreathController.repeat(reverse: true));
    }
    if (!_enemyBreathController.isAnimating) {
      unawaited(_enemyBreathController.repeat(reverse: true));
    }
    _playerHp = _playerMaxHp;
    _enemyIndex = 0;
    _enemyHp = _enemyStartingHp;
    _selectedSkillName = null;
    _draggingSkillName = null;
    _selectedItemId = null;
    _selectedCompanionId =
        _battleCompanions.isEmpty ? null : _battleCompanions.first.id;
    _selectedCompanionSkillId = null;
    _activeAssistCompanion = null;
    _activeAssistSkill = null;
    _activeSkillVfx = null;
    _skillVfxController.reset();
    _skillImpactController.reset();
    _companionAssistController.reset();
    _usedCompanionSkillIds.clear();
    _companionAssistUsedThisRound = false;
    _enemyStunnedByCompanion = 0;
    _companionCounterMin = 0;
    _companionCounterMax = 0;
    _companionCounterName = '';
    _itemCounts.clear();
    for (final item in _battleItems) {
      _itemCounts[item.id] = item.quantity;
    }
    _consumedItemCounts.clear();
    _itemUsesThisBattle = 0;
    _settlingItems = false;
    _settlementAccepted = false;
    _battleSettlement = const <String, dynamic>{};
    _settlementError = '';
    _playerQi = (_playerMaxQi * .40).round();
    _enemyQi = _enemyStartingQi;
    _enemyBurnTurns = 0;
    _enemyBurnDamage = 0;
    _playerBurnTurns = 0;
    _playerBurnDamage = 0;
    _playerStunnedTurns = 0;
    _enemyExposedTurns = 0;
    _enemyExposedHitBonus = 0;
    _enemyExposedExtraDamageMin = 0;
    _enemyExposedExtraDamageMax = 0;
    _round = 1;
    _playerGuarding = false;
    _playerDodging = false;
    _playerGuardReductionPercent = 0;
    _playerDodgeDifficultyBonus = 0;
    _enemyIntent = _EnemyIntentKind.claw;
    _enemyIntentSkill = null;
    _playerDamageCritical = false;
    _enemyDamageCritical = false;
    _skillCooldowns.clear();
    _enemySkillCooldowns.clear();
    _outcome = null;
    _busy = startEntrance;
    _entranceVisible = startEntrance;
    
    _activeCategory = _BattleCommandCategory.skills;
    
    _chooseNextEnemyIntent();
    _logs
      ..clear()
      ..add(
        _BattleLogEntry(
          label: '遭遇',
          before: '你遭遇了【$_enemyName】。对方已经摆出战斗姿态。',
          // 战斗 HUD 不再展示场景名称，遭遇日志也保持纯战斗信息。
          meta: '遭遇战',
          ),
      )
      ..addAll(
        <_BattleLogEntry>[
          if (_equipmentEffectSummary.isNotEmpty)
            _BattleLogEntry(
              label: '装备生效',
              before: '已载入${_playerEquipment.length}件穿戴装备。',
              meta: _equipmentEffectSummary,
              tone: _BattleLogTone.success,
            ),
          if (_currentEnemy.difficultyLabel.trim().isNotEmpty)
            _BattleLogEntry(
              label: '战力判定',
              before: <String>[
                _currentEnemy.difficultyLabel.trim(),
                if (_currentEnemy.realm.trim().isNotEmpty)
                  '对手境界：${_currentEnemy.realm.trim()}',
                if (_currentEnemy.condition.trim().isNotEmpty &&
                    _currentEnemy.condition.trim() != '正常')
                  '当前状态：${_currentEnemy.condition.trim()}',
              ].join(' · '),
              meta: _currentEnemy.openingEstimate.trim().isNotEmpty
                  ? _currentEnemy.openingEstimate.trim()
                  : '后端中立裁判 · 不进行玩家保护',
              tone: _currentEnemy.allowInstantDefeat
                  ? _BattleLogTone.enemy
                  : _BattleLogTone.neutral,
            ),
        ],
      )
      ..add(
        _BattleLogEntry(
          label: '敌方意图',
          before: _enemyIntentTitle,
          meta: '第1回合',
          tone: _BattleLogTone.enemy,
        ),
      );
    if (startEntrance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_entranceController.forward(from: 0));
      });
    } else if (mounted) {
      setState(() {});
    }
    _scrollLogToEnd();
  }

  void _scrollLogToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logController.hasClients) return;
      unawaited(
        _logController.animateTo(
          _logController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _addLog(_BattleLogEntry entry) {
    if (!mounted) return;
    _logs.add(entry);
    final overflow = _logs.length - _maxBattleLogEntries;
    if (overflow > 0) _logs.removeRange(0, overflow);
    _logRevision.value++;
    _scrollLogToEnd();
  }

  void _showCombatText(
    String text, {
    required bool onEnemy,
    required Color color,
    bool critical = false,
  }) {
    if (!mounted) return;
    setState(() {
      _combatText = text;
      _combatTextOnEnemy = onEnemy;
      _combatTextColor = color;
      _combatTextCritical = critical;
    });
    unawaited(_combatTextController.forward(from: 0));
  }


  Map<String, dynamic> _effectiveVfxSpec(YoranBattleSkill skill) {
    if (skill.vfxSpec.isNotEmpty) return _sanitizeBattleVfxSpec(skill.vfxSpec);
    return const <String, dynamic>{};
  }

  bool _isV19VisualTargetSpec(Map<String, dynamic> spec) {
    final mode = '${spec['render_mode'] ?? ''}'.trim().toLowerCase();
    final layers = spec['layers'];
    return mode == 'canvas2d_visual_target' || (layers is List && layers.isNotEmpty);
  }

  bool _isOpenVisualProgramSpec(Map<String, dynamic> spec) {
    final engine = '${spec['engine'] ?? ''}'.trim().toLowerCase();
    final version = YoranBattleSkill._asInt(spec['schema_version']);
    final program = spec['program'];
    return engine == 'open_visual_program' ||
        version >= 21 ||
        (program is List && program.isNotEmpty);
  }

  List<Map<String, dynamic>> _v19Layers(Map<String, dynamic> spec) {
    final raw = spec['layers'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  int _skillVfxDurationMs(YoranBattleSkill skill) {
    final spec = _effectiveVfxSpec(skill);
    if (spec.isEmpty) return 0;
    final raw = YoranBattleSkill._asInt(spec['duration_ms'], 1100);
    if (_isV19VisualTargetSpec(spec)) {
      // Preview timelines may intentionally be 5-6 seconds. In combat we keep
      // the same normalized choreography but compress wall-clock time so the
      // battle remains responsive.
      return (raw * .62).round().clamp(1600, 3600).toInt();
    }
    return raw.clamp(550, 3000).toInt();
  }

  double _skillVfxImpactProgress(YoranBattleSkill skill) {
    final spec = _effectiveVfxSpec(skill);

    // V21 carries the director's explicit contact moment. Battle timing must not
    // infer visual semantics from geometry or convert it back into an op menu.
    if (_isOpenVisualProgramSpec(spec)) {
      return _battleVfxDouble(spec['impact_at'], .62).clamp(.18, .94).toDouble();
    }

    if (_isV19VisualTargetSpec(spec)) {
      final layers = _v19Layers(spec);
      double? best;
      for (final layer in layers) {
        final hitStart = _battleVfxDouble(layer['hit_start'], -1);
        if (hitStart >= 0) {
          best = best == null ? hitStart : math.min(best, hitStart);
        }
        final op = '${layer['op'] ?? ''}'.trim().toLowerCase();
        final start = _battleVfxDouble(layer['start'], -1);
        if (start < 0) continue;
        if (const <String>{
          'impact_flash',
          'fracture_field',
          'crater_field',
          'shockwave',
          'debris_field',
        }.contains(op)) {
          best = best == null ? start : math.min(best, start);
        }
      }
      if (best != null) return best.clamp(.28, .88).toDouble();

      // If a generated V19 plan omitted explicit impact layers, use the end of
      // the delivery construct rather than a blind .52 midpoint.
      for (final layer in layers) {
        final op = '${layer['op'] ?? ''}'.trim().toLowerCase();
        if (const <String>{
          'beam',
          'projectile_orb',
          'creature_construct',
          'colossal_limb',
          'ribbon_field',
        }.contains(op)) {
          final end = _battleVfxDouble(layer['end'], -1);
          if (end >= 0) best = best == null ? end : math.min(best, end);
        }
      }
      return (best ?? .62).clamp(.32, .88).toDouble();
    }

    final rawSequence = spec['sequence'];
    if (rawSequence is! List || rawSequence.isEmpty) return .52;

    double? best;
    for (final raw in rawSequence.take(10)) {
      final item = YoranBattleSkill._stringMap(raw);
      if (item.isEmpty) continue;
      final type = '${item['type'] ?? ''}'.trim().toLowerCase();
      final at = _battleVfxDouble(item['at']).clamp(0.0, .95).toDouble();
      final duration = _battleVfxDouble(item['duration'], .3).clamp(.08, 1.0).toDouble();
      double? candidate;
      if (<String>{
        'explosion', 'shockwave', 'space_crack', 'screen_flash',
        'impact_lines', 'ground_crack', 'particle_burst', 'petal_burst',
      }.contains(type)) {
        candidate = at + math.min(.05, duration * .16);
      } else if (<String>{
        'slash', 'crescent_wave', 'projectile', 'projectile_swarm',
        'beam', 'dragon_trail', 'lotus', 'meteor', 'trail',
      }.contains(type)) {
        candidate = at + duration * .70;
      } else if (<String>{
        'lightning', 'ice_shards', 'fire_particles', 'force_field',
      }.contains(type)) {
        candidate = at + duration * .42;
      }
      if (candidate != null && candidate >= .24) {
        best = best == null ? candidate : math.min(best, candidate);
      }
    }
    return (best ?? .52).clamp(.30, .82).toDouble();
  }

  bool _skillLooksLikeSlash(YoranBattleSkill skill) {
    final spec = _effectiveVfxSpec(skill);
    if ('${spec['style'] ?? ''}'.trim().toLowerCase() == 'slash' ||
        '${spec['visual_identity'] ?? ''}'.trim().toLowerCase() == 'weapon_slash') {
      return true;
    }
    final rawSequence = spec['sequence'];
    if (rawSequence is List) {
      return rawSequence.take(10).any((raw) {
        final type = '${YoranBattleSkill._stringMap(raw)['type'] ?? ''}'.trim().toLowerCase();
        return type == 'slash' ||
            type == 'crescent_wave' ||
            type == 'blade_manifest' ||
            type == 'space_crack';
      });
    }
    return RegExp(r'斩|刀|剑').hasMatch(skill.name);
  }

  int _skillHitStopMs(YoranBattleSkill? skill, bool critical) {
    if (skill == null || !skill.hasVfx) return critical ? 120 : 60;
    final spec = _effectiveVfxSpec(skill);

    if (_isOpenVisualProgramSpec(spec)) {
      final strength = _battleVfxDouble(spec['hit_stop_strength'], .55).clamp(0.0, 1.0);
      var milliseconds = 58 + (strength * 82).round();
      if (critical) milliseconds += 34;
      return milliseconds.clamp(58, 176).toInt();
    }

    if (_isV19VisualTargetSpec(spec)) {
      var milliseconds = 62 + skill.quality.clamp(1, 10) * 5;
      if (_skillLooksLikeSlash(skill)) milliseconds += 18;
      final ops = _v19Layers(spec)
          .map((layer) => '${layer['op'] ?? ''}'.trim().toLowerCase())
          .toSet();
      if (ops.contains('colossal_limb') || ops.contains('crater_field')) {
        milliseconds += 24;
      }
      if (ops.contains('fracture_field') || ops.contains('shockwave')) {
        milliseconds += 10;
      }
      if (critical) milliseconds += 38;
      return milliseconds.clamp(72, 180).toInt();
    }

    final style = '${skill.vfxSpec['style'] ?? ''}'.trim().toLowerCase();
    var milliseconds = 48 + skill.quality.clamp(1, 10) * 4;
    if (_skillLooksLikeSlash(skill)) milliseconds += 18;
    final intensity = YoranBattleSkill._asInt(skill.vfxSpec['intensity'], skill.quality);
    if (style == 'ultimate' || intensity >= 8) milliseconds += 14;
    if (critical) milliseconds += 40;
    return milliseconds.clamp(58, 150).toInt();
  }

  void _startSkillVfx(
    YoranBattleSkill skill, {
    required bool hit,
    required bool critical,
  }) {
    final spec = _effectiveVfxSpec(skill);
    if (spec.isEmpty || !mounted) return;
    final duration = _skillVfxDurationMs(skill);
    _skillVfxController
      ..stop()
      ..duration = Duration(milliseconds: duration)
      ..value = 0;
    _skillImpactController.reset();
    setState(() {
      _activeSkillVfx = skill;
      _activeSkillVfxHit = hit;
      _activeSkillVfxCritical = critical;
    });
    unawaited(_skillVfxController.forward());
  }

  Future<bool> _advancePlayerSkillToImpact(
    YoranBattleSkill? skill, {
    required bool hit,
    required bool critical,
  }) async {
    if (skill == null || !skill.hasVfx) {
      unawaited(_playerAttackController.forward(from: 0));
      return _pause(245);
    }

    _startSkillVfx(skill, hit: hit, critical: critical);
    final duration = _skillVfxDurationMs(skill);
    final impactMs = math.max(245, (duration * _skillVfxImpactProgress(skill)).round());
    const attackLeadMs = 245;
    final chargeMs = math.max(0, impactMs - attackLeadMs);
    if (chargeMs > 0 && !await _pause(chargeMs)) return false;
    unawaited(_playerAttackController.forward(from: 0));
    return _pause(attackLeadMs);
  }

  Future<bool> _advanceCompanionSkillToImpact(
    YoranBattleSkill skill,
  ) async {
    if (!skill.hasVfx) return _pause(260);
    _startSkillVfx(skill, hit: true, critical: false);
    final duration = _skillVfxDurationMs(skill);
    final impactMs = math.max(260, (duration * _skillVfxImpactProgress(skill)).round());
    return _pause(impactMs);
  }

  Future<bool> _performSkillHitStop(
    YoranBattleSkill? skill, {
    required bool critical,
    bool stopPlayerAttack = true,
  }) async {
    final stopMs = _skillHitStopMs(skill, critical);
    if (stopPlayerAttack && _playerAttackController.isAnimating) {
      _playerAttackController.stop(canceled: false);
    }
    final shouldFreezeVfx = skill != null && skill.hasVfx && _skillVfxController.isAnimating;
    if (shouldFreezeVfx) _skillVfxController.stop(canceled: false);

    unawaited(critical ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
    if (!await _pause(stopMs)) return false;

    if (stopPlayerAttack && _playerAttackController.value < 1) {
      unawaited(_playerAttackController.forward());
    }
    if (shouldFreezeVfx && _skillVfxController.value < 1) {
      unawaited(_skillVfxController.forward());
    }
    unawaited(_skillImpactController.forward(from: 0));
    return true;
  }

  Widget _buildSkillVfxOverlay() {
    final skill = _activeSkillVfx;
    if (skill == null || !skill.hasVfx) return const SizedBox.shrink();
    final spec = _effectiveVfxSpec(skill);
    final isV19 = _isV19VisualTargetSpec(spec);

    return Positioned.fill(
      child: IgnorePointer(
        child: isV19
            ? ProceduralSkillVfx(
                key: ValueKey<String>('battle-v19-${skill.id}-${skill.name}'),
                vfxSpec: spec,
                animation: _skillVfxController,
                loop: false,
                tapToReplay: false,
                showDebugLabel: false,
                transparentBackground: true,
                drawVignette: true,
              )
            : AnimatedBuilder(
                animation: _skillVfxController,
                builder: (_, __) => AnimatedBuilder(
                  animation: _skillImpactController,
                  builder: (_, __) => CustomPaint(
                    painter: _BattleSkillVfxPainter(
                      spec: spec,
                      progress: _skillVfxController.value,
                      impactProgress: _skillImpactController.value,
                      targetSelf: skill.isSelfAction,
                      hit: _activeSkillVfxHit,
                      critical: _activeSkillVfxCritical,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _useSkill([String skillName = '普通攻击']) async {
    if (!_canAct) return;
    final skill = _skillFor(skillName);
    if (!_canUseSkill(skill.name)) {
      final reason = _cooldownFor(skill.name) > 0
          ? '${skill.name}仍需冷却 ${_cooldownFor(skill.name)} 回合。'
          : skill.resting && _playerQi >= _playerMaxQi
              ? '当前精力已满，无需休整。'
          : _playerQi < skill.energyCost
              ? '精力不足，${skill.name}需要 ${skill.energyCost} 点精力。'
              : '当前生命不足以承担${skill.name}的代价。';
      _addLog(
        _BattleLogEntry(
          label: skill.name,
          before: reason,
          meta: '本回合尚未消耗',
        ),
      );
      return;
    }

    if (skill.isSelfAction) {
      await _useSelfSkill(skill);
      return;
    }

    final exposed = _enemyExposedTurns > 0;
    final exposedHitBonus = exposed ? _enemyExposedHitBonus : 0;
    final roll = _d20();
    final enemyDodgeBonus = _enemyIntent == _EnemyIntentKind.skill &&
            (_enemyIntentSkill?.dodging ?? false)
        ? _enemyIntentSkill!.enemyHitDifficultyBonus
        : 0;
    final hitDifficulty = 11 + enemyDodgeBonus;
    final total =
        roll + skill.hitBonus + exposedHitBonus + _playerHitBonusShift;
    final baseHit = roll != 1 && (roll == 20 || total >= hitDifficulty);
    final equipmentHit = roll != 1 &&
        !baseHit &&
        _equipmentHitPercent > 0 &&
        _random.nextInt(100) < _equipmentHitPercent;
    final hit = baseHit || equipmentHit;
    final baseCritical = hit && (roll == 20 || (exposed && roll >= 19));
    final accessoryCritical = hit &&
        !baseCritical &&
        _equipmentCriticalPercent > 0 &&
        _random.nextInt(100) < _equipmentCriticalPercent;
    final critical = baseCritical || accessoryCritical;
    final exposedExtraDamage = hit && exposed && _enemyExposedExtraDamageMax > 0
        ? _rollBetween(
            _enemyExposedExtraDamageMin,
            _enemyExposedExtraDamageMax,
          )
        : 0;
    final damage = hit
        ? _rollSkillDamage(skill) + exposedExtraDamage
        : 0;

    final skillEnergyGain = _skillEnergyGain(skill, _playerMaxQi);
    setState(() {
      _tickSkillCooldowns();
      _playerQi = _clampPlayerQi(
        _playerQi - skill.energyCost + skillEnergyGain,
      );
      if (skill.healthCost > 0) {
        _playerHp = _clampPlayerHp(_playerHp - skill.healthCost);
      }
      if (skill.cooldown > 0) {
        _skillCooldowns[skill.name] = skill.cooldown;
      }
    });

    await _resolvePlayerAttack(
      actionName: skill.name,
      skillVfx: skill,
      hit: hit,
      critical: critical,
      damage: damage,
      burnTurns: skill.burnTurns,
      burnDamage: _skillBurnBaseDamage(skill),
      exposes: skill.exposes,
      exposeHitBonus: skill.exposeHitBonus,
      exposeExtraDamageMin: _powerDamageMin(skill.exposeExtraPowerPercent),
      exposeExtraDamageMax: _powerDamageMax(skill.exposeExtraPowerPercent),
      consumeExpose: exposed,
      piercesGuard: skill.piercesGuard,
      healAmount: _skillHealAmount(skill, _playerMaxHp),
      lifestealPercent: skill.lifestealPercent,
      stunTurns: skill.stunTurns,
      successText: '攻击正中目标，',
      failureText: '你的招式被$_enemyName敏捷地避开，未能命中。',
      meta: 'D20：$roll + ${skill.hitBonus}'
          '${_modifierLabel(_playerHitBonusShift, '阶位')}'
          '${exposedHitBonus > 0 ? ' + $exposedHitBonus破绽' : ''}'
          '${equipmentHit ? '  ·  装备命中修正' : ''}'
          '${accessoryCritical ? '  ·  饰品暴击' : ''}'
          '${exposedExtraDamage > 0 ? '  ·  破绽伤害+$exposedExtraDamage' : ''}'
          '  ·  难度：$hitDifficulty',
    );
  }

  Future<void> _useSelfSkill(YoranBattleSkill skill) async {
    if (!_canAct) return;
    final healthAfterCost = _clampPlayerHp(_playerHp - skill.healthCost);
    final healAmount = _skillHealAmount(skill, _playerMaxHp);
    final energyGain = _skillEnergyGain(skill, _playerMaxQi);
    final recovered = math.min(
      healAmount,
      _playerMaxHp - healthAfterCost,
    );
    final qiBefore = _playerQi;
    final qiAfter = _clampPlayerQi(
      _playerQi - skill.energyCost + energyGain,
    );
    final restoredEnergy = math.max(0, qiAfter - qiBefore);
    setState(() {
      _busy = true;

      _tickSkillCooldowns();
      _playerQi = qiAfter;
      _playerHp = _clampPlayerHp(healthAfterCost + recovered);
      if (skill.cooldown > 0) {
        _skillCooldowns[skill.name] = skill.cooldown;
      }
      if (skill.guarding) {
        _playerGuarding = true;
        _playerGuardReductionPercent = math.max(
          _playerGuardReductionPercent,
          math.max(1, skill.guardReductionPercent),
        );
      }
      if (skill.dodging) {
        _playerDodging = true;
        _playerDodgeDifficultyBonus = math.max(
          _playerDodgeDifficultyBonus,
          math.max(1, skill.enemyHitDifficultyBonus),
        );
      }
    });
    if (skill.hasVfx) {
      _startSkillVfx(skill, hit: true, critical: false);
      unawaited(_skillImpactController.forward(from: 0));
    }
    _addLog(
      _BattleLogEntry(
        label: skill.name,
        before: recovered > 0
            ? '你运转${skill.name}，恢复了 $recovered 点生命。'
            : skill.resting
                ? '你放缓呼吸并调整状态，恢复了$restoredEnergy点精力。'
            : skill.guarding
            ? '你稳住重心并集中注意，准备承受${_enemyIntentTitle}。'
            : skill.dodging
                ? '你放轻脚步，将注意力锁定在敌人的肩胯变化上。'
                : '你发动了${skill.name}。',
        meta: <String>[
          if (skill.guarding)
            '下次伤害降低${_playerGuardReductionPercent}%',
          if (skill.dodging)
            '敌方命中难度提高至${11 + _playerDodgeDifficultyBonus}',
          if (restoredEnergy > 0) '精力+$restoredEnergy',
          if (skill.healthCost > 0) '生命-${skill.healthCost}',
        ].join(' · '),
        tone: _BattleLogTone.success,
      ),
    );
    if (skill.guarding) {
      unawaited(_playerGuardController.forward(from: 0));
      unawaited(HapticFeedback.lightImpact());
    }
    if (recovered > 0) {
      unawaited(_playerHealController.forward(from: 0));
      _showCombatText(
        '+$recovered',
        onEnemy: false,
        color: _BattleColors.player,
      );
    } else if (skill.resting && restoredEnergy > 0) {
      unawaited(_playerRestController.forward(from: 0));
      unawaited(HapticFeedback.lightImpact());
      _showCombatText(
        '+$restoredEnergy',
        onEnemy: false,
        color: _BattleColors.energy,
      );
    }
    if (_playerHp <= 0) {
      await _finishBattle(YoranBattleOutcome.defeat);
      return;
    }
    if (!await _pause(720)) return;
    await _enemyAction();
  }

  Future<void> _resolvePlayerAttack({
    required String actionName,
    YoranBattleSkill? skillVfx,
    required bool hit,
    required int damage,
    required String successText,
    required String failureText,
    required String meta,
    bool critical = false,
    int burnTurns = 0,
    int burnDamage = 0,
    bool exposes = false,
    int exposeHitBonus = 0,
    int exposeExtraDamageMin = 0,
    int exposeExtraDamageMax = 0,
    bool consumeExpose = false,
    bool piercesGuard = false,
    int healAmount = 0,
    int lifestealPercent = 0,
    int stunTurns = 0,
  }) async {
    if (!_canAct) return;
    setState(() {
      _busy = true;
   
    });

    // 有 vfx_spec 时，先按技能自己的时间轴蓄力/飞行，在真正的视觉命中点
    // 再进入结算；没有 VFX 的普通攻击继续沿用原来的 245ms 冲刺命中点。
    if (!await _advancePlayerSkillToImpact(
      skillVfx,
      hit: hit,
      critical: critical,
    )) return;

    if (hit) {
      // 真正的“卡刀”：接触帧同时暂停角色攻击动画和技能 VFX。
      // 斩击/终结技/高品质以及暴击会得到更明显但仍很短的 hit-stop。
      if (!await _performSkillHitStop(skillVfx, critical: critical)) return;

      var resolvedDamage = critical ? (damage * 1.6).round() : damage;
      resolvedDamage = _scalePlayerDamage(resolvedDamage);
    
      final intentSkill = _enemyIntent == _EnemyIntentKind.skill
          ? _enemyIntentSkill
          : null;
      final guarded =
          _enemyIntent == _EnemyIntentKind.guard || (intentSkill?.guarding ?? false);
      if (guarded) {
        final reduction = intentSkill?.guardReductionPercent ?? 48;
        final remaining = (100 - reduction).clamp(10, 100).toInt();
        resolvedDamage = math.max(
          1,
          (resolvedDamage * (piercesGuard ? .82 : remaining / 100)).round(),
        );
      }
      final recovered = math.min(
        healAmount + (resolvedDamage * lifestealPercent / 100).round(),
        _playerMaxHp - _playerHp,
      );
      setState(() {
        _enemyHp = _clampEnemyHp(_enemyHp - resolvedDamage);
        if (recovered > 0) {
          _playerHp = _clampPlayerHp(_playerHp + recovered);
        }
        if (consumeExpose) {
          _enemyExposedTurns = 0;
          _enemyExposedHitBonus = 0;
          _enemyExposedExtraDamageMin = 0;
          _enemyExposedExtraDamageMax = 0;
        }
        if (exposes) {
          _enemyExposedTurns = 1;
          _enemyExposedHitBonus = exposeHitBonus.clamp(0, 4).toInt();
          _enemyExposedExtraDamageMin =
              exposeExtraDamageMin.clamp(0, 10).toInt();
          _enemyExposedExtraDamageMax = math
              .max(_enemyExposedExtraDamageMin, exposeExtraDamageMax)
              .clamp(0, 12)
              .toInt();
        }
        if (burnTurns > 0) {
          _enemyBurnTurns = math.max(_enemyBurnTurns, burnTurns);
          _enemyBurnDamage =
              math.max(_enemyBurnDamage, _scalePlayerDamage(burnDamage));
        }
        _enemyDamageCritical = critical;
      });
      unawaited(_enemyDamageController.forward(from: 0));
      unawaited(
        critical ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact(),
      );
      _showCombatText(
        '-$resolvedDamage',
        onEnemy: true,
        color: _BattleColors.enemy,
        critical: critical,
      );
      _addLog(
        _BattleLogEntry(
          label: critical ? '$actionName · 暴击' : actionName,
          before: critical ? '$successText力量在命中瞬间彻底爆发，造成 ' : successText,
          emphasis: '$resolvedDamage',
          after: guarded
              ? ' 点伤害。敌人以防御姿态削弱了冲击。'
              : ' 点伤害。',
          meta: '$meta'
              '${_equipmentAttackMultiplier > 1 ? ' · 装备威力×${_equipmentAttackMultiplier.toStringAsFixed(1)}' : ''}',
          tone: _BattleLogTone.damage,
        ),
      );
      if (recovered > 0) {
        unawaited(_playerHealController.forward(from: 0));
        _addLog(
          _BattleLogEntry(
            label: lifestealPercent > 0 ? '生命汲取' : '恢复',
            before: '技能效果令你恢复了 ',
            emphasis: '$recovered',
            after: ' 点生命。',
            tone: _BattleLogTone.heal,
          ),
        );
      }
      if (exposes) {
        _addLog(
          _BattleLogEntry(
            label: '破绽',
            before: '敌人的重心被扯乱。下一次攻击命中提高，掷出19也会暴击。',
            meta: <String>[
              if (_enemyExposedHitBonus > 0)
                '命中+$_enemyExposedHitBonus',
              if (_enemyExposedExtraDamageMax > 0)
                '额外伤害$_enemyExposedExtraDamageMin–$_enemyExposedExtraDamageMax',
              '持续至下一次攻击',
            ].join(' · '),
            tone: _BattleLogTone.success,
          ),
        );
      }
      if (burnTurns > 0) {
        _addLog(
          _BattleLogEntry(
            label: '持续伤害',
            before: '效果附着在目标身上，将在敌方行动前持续造成伤害。',
            meta: '$burnTurns回合 · 每回合$burnDamage伤害',
            tone: _BattleLogTone.damage,
          ),
        );
      }
      if (stunTurns > 0 && _enemyHp > 0) {
        _addLog(
          _BattleLogEntry(
            label: '眩晕',
            before: '$_enemyName暂时无法行动。',
            meta: '跳过本次敌方行动',
            tone: _BattleLogTone.success,
          ),
        );
      }
    } else {
      if (consumeExpose) {
        setState(() {
          _enemyExposedTurns = 0;
          _enemyExposedHitBonus = 0;
          _enemyExposedExtraDamageMin = 0;
          _enemyExposedExtraDamageMax = 0;
        });
      }
      unawaited(_enemyDodgeController.forward(from: 0));
      _addLog(
        _BattleLogEntry(
          label: actionName,
          before: failureText,
          meta: meta,
        ),
      );
    }

    if (_enemyHp <= 0) {
      if (!await _pause(620)) return;
      await _finishVictory();
      return;
    }

    if (hit && stunTurns > 0) {
      if (!await _pause(700)) return;
      await _openNextPlayerTurn();
      return;
    }
    if (!await _pause(900)) return;
    await _enemyAction();
  }

  Future<void> _finishVictory() async {
    final defeatedName = _enemyName;
    final defeatedPortrait = _enemyPortrait;
    _addLog(
      _BattleLogEntry(
        label: '击败',
        before: '你击败了【$defeatedName】。',
        meta: _hasNextEnemy
            ? '敌人 ${_enemyIndex + 1}/${_battleEnemies.length}'
            : '全部敌人已被击败',
        tone: _BattleLogTone.success,
      ),
    );

    if (_hasNextEnemy) {
      if (!await _pause(720)) return;
      setState(() {
        _enemyIndex++;
        _enemyHp = _enemyStartingHp;
        _enemyQi = _enemyStartingQi;
        _enemyBurnTurns = 0;
        _enemyBurnDamage = 0;
        _enemyIntentSkill = null;
        _enemySkillCooldowns.clear();
        _enemyExposedTurns = 0;
        _enemyExposedHitBonus = 0;
        _enemyExposedExtraDamageMin = 0;
        _enemyExposedExtraDamageMax = 0;
        _playerGuarding = false;
        _playerDodging = false;
        _playerGuardReductionPercent = 0;
        _playerDodgeDifficultyBonus = 0;
        _companionAssistUsedThisRound = false;
        _selectedCompanionSkillId = null;
        _enemyStunnedByCompanion = 0;
        _companionCounterMin = 0;
        _companionCounterMax = 0;
        _companionCounterName = '';
        _round++;
        _chooseNextEnemyIntent();
        _busy = true;
        _activeCategory = null;
      });
      _addLog(
        _BattleLogEntry(
          label: '下一名敌人',
          before: '【$_enemyName】进入战斗。',
          meta: '敌人 ${_enemyIndex + 1}/${_battleEnemies.length}',
          tone: _BattleLogTone.enemy,
        ),
      );
      if (!await _pause(620)) return;
      if (defeatedPortrait.trim().isNotEmpty &&
          defeatedPortrait != _enemyPortrait) {
        unawaited(_evictUnusedBattleImage(defeatedPortrait));
      }
      setState(() {
        _busy = false;
        _activeCategory = _BattleCommandCategory.skills;
      });
      return;
    }

    await _finishBattle(YoranBattleOutcome.victory);
  }

  YoranBattleItem? _battleItemById(String itemId) {
    for (final item in _battleItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  bool _canUseItem(String itemId) {
    final item = _battleItemById(itemId);
    if (item == null ||
        (_itemCounts[item.id] ?? 0) <= 0 ||
        _itemUsesThisBattle >= _maxItemUsesPerBattle) {
      return false;
    }
    final canRestoreHp = item.restoresHp && _playerHp < _playerMaxHp;
    final canRestoreSp = item.restoresSp && _playerQi < _playerMaxQi;
    return canRestoreHp || canRestoreSp;
  }

  Future<void> _useItem(String itemId) async {
    if (!_canAct) return;

    final item = _battleItemById(itemId);
    if (item == null) return;
    final count = _itemCounts[item.id] ?? 0;
    if (count <= 0) {
      _addLog(
        _BattleLogEntry(
          label: item.name,
          before: '你检查随身物品，却发现已经用完了。',
          meta: '物品耗尽',
        ),
      );
      return;
    }
    if (_itemUsesThisBattle >= _maxItemUsesPerBattle) {
      _addLog(
        _BattleLogEntry(
          label: item.name,
          before: '本场战斗的道具使用次数已耗尽。',
          meta: '本局道具 $_itemUsesThisBattle/$_maxItemUsesPerBattle',
        ),
      );
      return;
    }
    if (!_canUseItem(item.id)) {
      _addLog(
        _BattleLogEntry(
          label: item.name,
          before: '当前生命与精力状态无需使用这个道具。',
          meta: '无法使用',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final hpAmount = item.restoresHp
        ? (_playerMaxHp * item.restorePercent / 100).round()
        : 0;
    final spAmount = item.restoresSp
        ? (_playerMaxQi * item.restorePercent / 100).round()
        : 0;
    final hpRecovered = math.min(hpAmount, _playerMaxHp - _playerHp);
    final spRecovered = math.min(spAmount, _playerMaxQi - _playerQi);
    setState(() {
      _tickSkillCooldowns();
      _itemUsesThisBattle++;
      if (item.consumeOnUse) {
        _itemCounts[item.id] = math.max(0, count - 1);
        _consumedItemCounts[item.id] = (_consumedItemCounts[item.id] ?? 0) + 1;
      }
      _playerHp = _clampPlayerHp(_playerHp + hpRecovered);
      _playerQi = _clampPlayerQi(_playerQi + spRecovered);
    });

    if (hpRecovered > 0) {
      unawaited(_playerHealController.forward(from: 0));
      unawaited(HapticFeedback.lightImpact());
      _showCombatText('+$hpRecovered', onEnemy: false, color: _BattleColors.player);
    }
    if (spRecovered > 0) {
      unawaited(_playerRestController.forward(from: 0));
      unawaited(HapticFeedback.lightImpact());
      if (hpRecovered <= 0) {
        _showCombatText('+$spRecovered', onEnemy: false, color: _BattleColors.energy);
      }
    }

    final recoveryText = <String>[
      if (hpRecovered > 0) 'HP+$hpRecovered',
      if (spRecovered > 0) 'SP+$spRecovered',
    ].join(' · ');
    _addLog(
      _BattleLogEntry(
        label: item.name,
        before: '你使用${item.name}，',
        emphasis: recoveryText,
        after: '。',
        meta: '本局道具 $_itemUsesThisBattle/$_maxItemUsesPerBattle',
        tone: hpRecovered > 0 ? _BattleLogTone.heal : _BattleLogTone.success,
      ),
    );

    if (!await _pause(1100)) return;
    await _enemyAction();
  }

  Future<void> _confirmEscape() async {
    if (!_canAct) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(.66),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF0D0E10),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withOpacity(.12), width: .8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '逃跑',
                  style: TextStyle(
                    color: _BattleColors.text,
                    fontFamily: 'WenJinMinchoP0',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '逃跑需要进行判定；如果失败，对手仍会获得本回合行动机会。',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.46),
                    fontSize: 10.5,
                    height: 1.55,
                    letterSpacing: .25,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(.72),
                          side: BorderSide(
                            color: Colors.white.withOpacity(.12),
                            width: .8,
                          ),
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          '继续战斗',
                          style: TextStyle(fontSize: 11, letterSpacing: .4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _BattleColors.text,
                          foregroundColor: _BattleColors.background,
                          minimumSize: const Size.fromHeight(40),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          '尝试逃跑',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await _attemptEscape();
    }
  }

  Future<void> _attemptEscape() async {
    if (!_canAct) return;
    setState(() {
      _busy = true;
     
      _tickSkillCooldowns();
    });
    final roll = _d20();
    final dc = (14 + (_opponentHitBonusShift / 2).round())
        .clamp(8, 20)
        .toInt();
    if (roll + 4 >= dc) {
      _addLog(
        _BattleLogEntry(
          label: '逃跑',
          before: '你借着空隙遮蔽视线，迅速脱离了$_enemyName的追击。',
          meta: 'D20：$roll + 4  ·  难度：$dc',
          tone: _BattleLogTone.success,
        ),
      );
      await _finishBattle(YoranBattleOutcome.escaped);
      return;
    }

    _addLog(
      _BattleLogEntry(
        label: '逃跑失败',
        before: '$_enemyName封死了退路，你没能摆脱战斗。',
        meta: 'D20：$roll + 4  ·  难度：$dc',
        tone: _BattleLogTone.enemy,
      ),
    );
    if (!await _pause(650)) return;
    await _enemyAction();
  }

  Future<bool> _useEnemySkill(YoranBattleSkill skill) async {
    if (_enemyQi < skill.energyCost ||
        (!skill.canSelfKill && _enemyHp <= skill.healthCost)) {
      return false;
    }

    final healthAfterCost = _clampEnemyHp(_enemyHp - skill.healthCost);
    final enemyEnergyGain = _skillEnergyGain(skill, 100);
    setState(() {
      _enemyQi = _clampEnemyQi(_enemyQi - skill.energyCost + enemyEnergyGain);
      _enemyHp = healthAfterCost;
      if (skill.cooldown > 0) {
        _enemySkillCooldowns[skill.name] = skill.cooldown;
      }
    });

    if (skill.isSelfAction) {
      final recovered = math.min(
        _skillHealAmount(skill, _enemyMaxHp),
        _enemyMaxHp - _enemyHp,
      );
      if (recovered > 0) {
        setState(() => _enemyHp = _clampEnemyHp(_enemyHp + recovered));
        _showCombatText(
          '+$recovered',
          onEnemy: true,
          color: _BattleColors.player,
        );
      }
      _addLog(
        _BattleLogEntry(
          label: skill.name,
          before: recovered > 0
              ? '$_enemyName发动${skill.name}，恢复了 $recovered 点生命。'
              : skill.guarding
                  ? '$_enemyName以${skill.name}化解了你的攻势，并重新稳住架势。'
                  : skill.dodging
                      ? '$_enemyName施展${skill.name}避开正面交锋。'
                      : '$_enemyName发动了${skill.name}。',
          meta: <String>[
            if (skill.energyCost > 0) '精力-${skill.energyCost}',
            if (enemyEnergyGain > 0) '精力+$enemyEnergyGain',
            if (skill.healthCost > 0) '生命-${skill.healthCost}',
            if (skill.cooldown > 0) 'CD${skill.cooldown}',
          ].join(' · '),
          tone: _BattleLogTone.enemy,
        ),
      );
      if (_enemyHp <= 0) {
        await _finishVictory();
        return true;
      }
      await _openNextPlayerTurn();
      return true;
    }

    unawaited(_enemyAttackController.forward(from: 0));
    if (!await _pause(255)) return true;
    final roll = _d20();
    final hitBonus =
        (skill.hitBonus + _opponentHitBonusShift).clamp(-10, 20).toInt();
    final dc = 11 + (_playerDodging ? _playerDodgeDifficultyBonus : 0);
    final baseHit = roll != 1 && (roll == 20 || roll + hitBonus >= dc);
    final equipmentDodge = baseHit &&
        roll != 20 &&
        _equipmentDodgePercent > 0 &&
        _random.nextInt(100) < _equipmentDodgePercent;
    final hit = baseHit && !equipmentDodge;
    final critical = hit && roll == 20;
    
    if (!hit) {
      unawaited(_playerDodgeController.forward(from: 0));
      _showCombatText('闪避', onEnemy: false, color: _BattleColors.text);
      _addLog(
        _BattleLogEntry(
          label: equipmentDodge ? '装备闪避' : '${skill.name}落空',
          before: '你避开了$_enemyName发动的${skill.name}。',
          meta: 'D20：$roll + $hitBonus · 难度：$dc'
              '${equipmentDodge ? ' · 装备机动生效' : ''}',
          tone: _BattleLogTone.success,
        ),
      );
      if (_enemyHp <= 0) {
        await _finishVictory();
        return true;
      }
      await _openNextPlayerTurn();
      return true;
    }

    // ===== 新增：技能攻击的卡肉感 =====
    if (critical) {
      unawaited(HapticFeedback.heavyImpact());
    } else {
      unawaited(HapticFeedback.selectionClick());
    }
    if (!await _pause(critical ? 120 : 60)) return true;
    // =================================

    final rolledDamage = _rollSkillDamage(skill);
    var damage = _scaleOpponentDamage(
      critical ? (rolledDamage * 1.5).round() : rolledDamage,
    );
    final guarded = _playerGuarding;
    if (guarded) {
      final remainingPercent =
          (100 - _playerGuardReductionPercent).clamp(10, 100).toInt();
      damage = math.max(1, (damage * remainingPercent / 100).round());
    }
    final recovered = math.min(
      _skillHealAmount(skill, _enemyMaxHp) +
          (damage * skill.lifestealPercent / 100).round(),
      _enemyMaxHp - _enemyHp,
    );
    setState(() {
      _playerHp = _clampPlayerHp(_playerHp - damage);
      if (recovered > 0) _enemyHp = _clampEnemyHp(_enemyHp + recovered);
      final enemyBurnBase = _skillBurnBaseDamage(skill);
      if (skill.burnTurns > 0 && enemyBurnBase > 0) {
        _playerBurnTurns = math.max(_playerBurnTurns, skill.burnTurns);
        _playerBurnDamage = math.max(
          _playerBurnDamage,
          _scaleOpponentDamage(enemyBurnBase),
        );
      }
      if (skill.stunTurns > 0) {
        _playerStunnedTurns = math.max(_playerStunnedTurns, skill.stunTurns);
      }
      _playerDamageCritical = critical;
    });
    if (guarded) {
      unawaited(_playerGuardImpactController.forward(from: 0));
    }
    unawaited(_playerDamageController.forward(from: 0));
    unawaited(
      critical ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact(),
    );
    _showCombatText(
      '-$damage',
      onEnemy: false,
      color: _BattleColors.enemy,
      critical: critical,
    );
    _addLog(
      _BattleLogEntry(
        label: critical ? '${skill.name} · 暴击' : skill.name,
        before: '$_enemyName发动${skill.name}，造成 ',
        emphasis: '$damage',
        after: guarded
            ? ' 点伤害。你的防御化解了$_playerGuardReductionPercent%冲击。'
            : ' 点伤害。',
        meta: 'D20：$roll + $hitBonus · 难度：$dc'
            '${skill.energyCost > 0 ? ' · 精力-${skill.energyCost}' : ''}'
            '${skill.cooldown > 0 ? ' · CD${skill.cooldown}' : ''}',
        tone: _BattleLogTone.enemyDamage,
      ),
    );
    if (skill.burnTurns > 0 && _playerBurnDamage > 0) {
      _addLog(
        _BattleLogEntry(
          label: '持续伤害',
          before: '${skill.name}留下了持续伤害效果。',
          meta: '${skill.burnTurns}回合 · 每回合$_playerBurnDamage伤害',
          tone: _BattleLogTone.enemy,
        ),
      );
    }
    if (skill.stunTurns > 0) {
      _addLog(
        _BattleLogEntry(
          label: '眩晕',
          before: '你被${skill.name}压制，下一次行动将被跳过。',
          tone: _BattleLogTone.enemy,
        ),
      );
    }
    if (_playerHp <= 0) {
      await _finishBattle(YoranBattleOutcome.defeat);
      return true;
    }
    if (_enemyHp <= 0) {
      await _finishVictory();
      return true;
    }
    if (await _triggerCompanionCounter(damage)) return true;
    await _openNextPlayerTurn();
    return true;
  }

  Future<bool> _triggerCompanionCounter(int receivedDamage) async {
    if (receivedDamage <= 0 || _companionCounterMax <= 0 || _enemyHp <= 0) {
      return false;
    }
    final sourceName = _companionCounterName.isEmpty ? '支援角色' : _companionCounterName;
    final damage = math.min(
      _enemyHp,
      _scaleCompanionDamage(_rollBetween(_companionCounterMin, _companionCounterMax)),
    );
    setState(() {
      _enemyHp = _clampEnemyHp(_enemyHp - damage);
      _companionCounterMin = 0;
      _companionCounterMax = 0;
      _companionCounterName = '';
    });
    unawaited(_enemyDamageController.forward(from: 0));
    _showCombatText('-$damage', onEnemy: true, color: _BattleColors.energy);
    _addLog(
      _BattleLogEntry(
        label: '$sourceName · 援护反击',
        before: '$sourceName抓住敌方攻击后的空隙反击，造成 ',
        emphasis: '$damage',
        after: ' 点伤害。',
        meta: '反击效果已消耗',
        tone: _BattleLogTone.success,
      ),
    );
    if (!await _pause(360)) return true;
    if (_enemyHp <= 0) {
      await _finishVictory();
      return true;
    }
    return false;
  }

  Future<void> _enemyAction() async {
    if (!mounted || _enemyHp <= 0 || _outcome != null) return;
    _tickEnemySkillCooldowns();
    if (_enemyBurnTurns > 0) {
      final burnDamage = _enemyBurnDamage;
      setState(() {
        _enemyHp = _clampEnemyHp(_enemyHp - burnDamage);
        _enemyBurnTurns--;
        if (_enemyBurnTurns <= 0) _enemyBurnDamage = 0;
        _enemyDamageCritical = false;
      });
      unawaited(_enemyDamageController.forward(from: 0));
      _showCombatText(
        '-$burnDamage',
        onEnemy: true,
        color: const Color(0xFFFF9B56),
      );
      _addLog(
        _BattleLogEntry(
          label: '持续伤害',
          before: '附着的效果再次生效，造成 ',
          emphasis: '$burnDamage',
          after: ' 点持续伤害。',
          meta: _enemyBurnTurns > 0 ? '剩余$_enemyBurnTurns回合' : '效果结束',
          tone: _BattleLogTone.damage,
        ),
      );
      if (_enemyHp <= 0) {
        if (!await _pause(520)) return;
        await _finishVictory();
        return;
      }
      if (!await _pause(360)) return;
    }

    if (_enemyStunnedByCompanion > 0) {
      setState(() => _enemyStunnedByCompanion--);
      _addLog(
        _BattleLogEntry(
          label: '援战压制',
          before: '$_enemyName被援战技能压制，本次行动被打断。',
          meta: '敌方跳过行动',
          tone: _BattleLogTone.success,
        ),
      );
      await _openNextPlayerTurn();
      return;
    }

    if (_enemyIntent == _EnemyIntentKind.skill) {
      final selectedSkill = _enemyIntentSkill;
      if (selectedSkill != null && await _useEnemySkill(selectedSkill)) return;
      _enemyIntent = _EnemyIntentKind.claw;
      _enemyIntentSkill = null;
    }

    if (_enemyIntent == _EnemyIntentKind.guard) {
      _addLog(
        _BattleLogEntry(
          label: '防御姿态',
          before: '$_enemyName没有贸然追击，而是稳住姿态，等待你的下次动作。',
          meta: '敌方本回合不攻击',
          tone: _BattleLogTone.enemy,
        ),
      );
      await _openNextPlayerTurn();
      return;
    }

    if (_enemyIntent == _EnemyIntentKind.recover) {
      final recovered = math.min(16, _enemyMaxHp - _enemyHp);
      setState(() {
        _enemyHp = _clampEnemyHp(_enemyHp + recovered);
      });
      _showCombatText(
        '+$recovered',
        onEnemy: true,
        color: _BattleColors.player,
      );
      _addLog(
        _BattleLogEntry(
          label: '恢复状态',
          before: '$_enemyName短暂调整状态，恢复了 ',
          emphasis: '$recovered',
          after: ' 点生命。',
          meta: '敌方恢复效果',
          tone: _BattleLogTone.enemy,
        ),
      );
      await _openNextPlayerTurn();
      return;
    }

    // 1. 敌方开始冲刺攻击
    unawaited(_enemyAttackController.forward(from: 0));
    if (!await _pause(255)) return;

    // 2. 计算命中与暴击结果
    final heavy = _enemyIntent == _EnemyIntentKind.heavy;
    final roll = _d20();
    final hitBonus = (_currentEnemy.hitBonus +
            (heavy ? 1 : 0) +
            _opponentHitBonusShift)
        .clamp(-10, 20)
        .toInt();
    final dc = 11 + (_playerDodging ? _playerDodgeDifficultyBonus : 0);
    final baseHit = roll != 1 && (roll == 20 || roll + hitBonus >= dc);
    final equipmentDodge = baseHit &&
        roll != 20 &&
        _equipmentDodgePercent > 0 &&
        _random.nextInt(100) < _equipmentDodgePercent;
    final hit = baseHit && !equipmentDodge;
    final critical = hit && roll == 20;

    // 3. 处理未命中（闪避）
    if (!hit) {
      unawaited(_playerDodgeController.forward(from: 0));
      unawaited(HapticFeedback.selectionClick());
      _showCombatText(
        '闪避',
        onEnemy: false,
        color: _BattleColors.text,
      );
      _addLog(
        _BattleLogEntry(
          label: _playerDodging || equipmentDodge ? '闪避成功' : '攻击落空',
          before: _playerDodging || equipmentDodge
              ? '你提前捕捉到发力方向，侧身让攻击擦肩而过。'
              : '$_enemyName的攻击从你身侧掠过，没有命中。',
          meta: 'D20：$roll + $hitBonus  ·  难度：$dc'
              '${equipmentDodge ? '  ·  装备闪避' : ''}',
          tone: _playerDodging || equipmentDodge
              ? _BattleLogTone.success
              : _BattleLogTone.enemy,
        ),
      );
      await _openNextPlayerTurn();
      return;
    }

    // ===== 4. 新增：正确的卡肉感 (Hit-Stop) 位置 =====
    // 此时已经确认 hit 为 true，且我们已经知道了是否 critical 和 heavy
    if (critical || heavy) {
      unawaited(HapticFeedback.heavyImpact()); // 重击震动
    } else {
      unawaited(HapticFeedback.selectionClick()); // 轻度命中反馈
    }
    // 冻结画面：重击/暴击卡顿 120ms，普通攻击卡顿 60ms
    if (!await _pause(critical || heavy ? 120 : 60)) return;
    // =================================================

    // 5. 继续计算伤害并扣血
    final basicPower =
        _currentEnemy.basicAttackPowerPercent.clamp(35, 220).toInt();
    final rolledDamage = _rollPowerDamage(
      heavy ? (basicPower * 1.9).round() : basicPower,
    );
    var damage = _scaleOpponentDamage(
      critical ? (rolledDamage * 1.5).round() : rolledDamage,
    );
    final guarded = _playerGuarding;
    if (guarded) {
      final remainingPercent =
          (100 - _playerGuardReductionPercent).clamp(10, 100).toInt();
      damage = math.max(1, (damage * remainingPercent / 100).round());
    }
    setState(() {
      _playerHp = _clampPlayerHp(_playerHp - damage);
      _enemyQi = _clampEnemyQi(_enemyQi + 10);
      _playerDamageCritical = critical;
    });
    if (guarded) {
      unawaited(_playerGuardImpactController.forward(from: 0));
    }
    unawaited(_playerDamageController.forward(from: 0));
    unawaited(
      critical ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact(),
    );
    _showCombatText(
      '-$damage',
      onEnemy: false,
      color: _BattleColors.enemy,
      critical: critical,
    );
    _addLog(
      _BattleLogEntry(
        label: critical
            ? '敌方暴击'
            : heavy
                ? '蓄力重击'
                : '快速攻击',
        before: heavy
            ? '$_enemyName积蓄的力量瞬间释放，发动强力攻击，造成 '
            : '$_enemyName抓住空隙迅速进攻，造成 ',
        emphasis: '$damage',
        after: guarded
            ? ' 点伤害。你的防御化解了$_playerGuardReductionPercent%冲击。'
            : ' 点伤害。',
        meta: 'D20：$roll + $hitBonus  ·  难度：$dc',
        tone: _BattleLogTone.enemyDamage,
      ),
    );

    if (_playerHp <= 0) {
      await _finishBattle(YoranBattleOutcome.defeat);
      return;
    }
    if (await _triggerCompanionCounter(damage)) return;
    await _openNextPlayerTurn();
  }

  Future<void> _openNextPlayerTurn() async {
    if (!await _pause(520)) return;
    if (_playerBurnTurns > 0) {
      final damage = _playerBurnDamage;
      setState(() {
        _playerHp = _clampPlayerHp(_playerHp - damage);
        _playerBurnTurns--;
        if (_playerBurnTurns <= 0) _playerBurnDamage = 0;
        _playerDamageCritical = false;
      });
      unawaited(_playerDamageController.forward(from: 0));
      _showCombatText(
        '-$damage',
        onEnemy: false,
        color: const Color(0xFFFF9B56),
      );
      _addLog(
        _BattleLogEntry(
          label: '持续伤害',
          before: '敌方技能留下的效果再次生效，造成 ',
          emphasis: '$damage',
          after: ' 点伤害。',
          meta: _playerBurnTurns > 0 ? '剩余$_playerBurnTurns回合' : '效果结束',
          tone: _BattleLogTone.enemyDamage,
        ),
      );
      if (_playerHp <= 0) {
        await _finishBattle(YoranBattleOutcome.defeat);
        return;
      }
    }
    final stunned = _playerStunnedTurns > 0;
    setState(() {
      _round++;
      _companionAssistUsedThisRound = false;
      _selectedCompanionSkillId = null;
      if (stunned) _playerStunnedTurns--;
      _playerGuarding = false;
      _playerDodging = false;
      _playerGuardReductionPercent = 0;
      _playerDodgeDifficultyBonus = 0;
      _chooseNextEnemyIntent();
      _busy = stunned;
      _activeCategory = stunned ? null : _BattleCommandCategory.skills;
    });
    if (stunned) {
      _addLog(
        _BattleLogEntry(
          label: '行动受限',
          before: '你仍未从压制中恢复，本回合无法行动。',
          meta: '$_enemyName继续行动',
          tone: _BattleLogTone.enemy,
        ),
      );
      if (!await _pause(650)) return;
      await _enemyAction();
      return;
    }
    _addLog(
      _BattleLogEntry(
        label: '敌方意图',
        before: _enemyIntentTitle,
        meta: '第$_round回合',
        tone: _BattleLogTone.enemy,
      ),
    );
  }

  Future<void> _finishBattle(YoranBattleOutcome outcome) async {
    if (!mounted || _outcome != null) return;
    setState(() => _busy = true);
    if (!await _pause(650)) return;
    _playerBreathController.stop(canceled: false);
    _enemyBreathController.stop(canceled: false);
    setState(() => _outcome = outcome);
    // 胜利后立即进行权威结算，拿到奖励后留在结算页展示。
    // 失败不立即提交，玩家仍可无副作用地重新挑战。
    if (outcome == YoranBattleOutcome.victory) {
      await _settleBattle(outcome, returnAfterSettlement: false);
    }
  }

  List<YoranBattleItemConsumption> _battleConsumptions() {
    return _battleItems
        .where((item) => (_consumedItemCounts[item.id] ?? 0) > 0)
        .map((item) => YoranBattleItemConsumption(
              itemId: item.id,
              name: item.name,
              quantity: _consumedItemCounts[item.id]!,
            ))
        .toList(growable: false);
  }

  Future<void> _settleBattle(
    YoranBattleOutcome outcome, {
    required bool returnAfterSettlement,
  }) async {
    if (_settlingItems) return;
    if (_settlementAccepted) {
      if (returnAfterSettlement && mounted) Navigator.of(context).pop(outcome);
      return;
    }
    final consumptions = _battleConsumptions();
    setState(() {
      _settlingItems = true;
      _settlementError = '';
    });
    Map<String, dynamic>? settlement = const <String, dynamic>{};
    try {
      // 正式战斗无论是否使用道具都必须回传胜负。旧逻辑只在 consumptions
      // 非空时调用回调，会让绝大多数战斗永远停留在 active 状态。
      if (widget.onSettleItems != null) {
        settlement = await widget.onSettleItems!(consumptions, outcome);
      } else if (consumptions.isNotEmpty && widget.onConsumeItem != null) {
        // 兼容旧接入：仍然延迟到战斗结束才调用，不在使用瞬间扣库存。
        for (final consumption in consumptions) {
          final item = _battleItemById(consumption.itemId);
          if (item == null) continue;
          for (var i = 0; i < consumption.quantity; i++) {
            if (!await widget.onConsumeItem!(item)) {
              settlement = null;
              break;
            }
          }
          if (settlement == null) break;
        }
      }
    } catch (_) {
      settlement = null;
    }
    if (!mounted) return;
    if (settlement == null) {
      setState(() {
        _settlingItems = false;
        _settlementError = '战斗结算失败，请重试';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('战斗结算失败，请重试。')),
      );
      return;
    }
    setState(() {
      _settlingItems = false;
      _settlementAccepted = true;
      _battleSettlement = settlement!;
    });
    if (returnAfterSettlement) Navigator.of(context).pop(outcome);
  }

  Widget _buildCompanionAssistOverlay() {
    final companion = _activeAssistCompanion;
    final skill = _activeAssistSkill;
    if (companion == null || skill == null) return const SizedBox.shrink();
    final portrait = companion.portrait.trim().isNotEmpty
        ? companion.portrait
        : companion.avatar;

    // 援护要“大气”，但不靠华丽配饰：用大幅人物、全屏压暗、轻微推镜和排版制造电影感。
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _companionAssistController,
        builder: (context, _) {
          final t = _companionAssistController.value;
          double phase(double start, double end) =>
              ((t - start) / (end - start)).clamp(0.0, 1.0).toDouble();
          final enter = Curves.easeOutCubic.transform(phase(0, .22));
          final exit = Curves.easeInCubic.transform(phase(.80, 1));
          final opacity =
              (math.min(enter, 1 - exit)).clamp(0.0, 1.0).toDouble();
          final focus = math.sin(t * math.pi).clamp(0.0, 1.0).toDouble();

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > constraints.maxHeight * 1.15;
              final compact = constraints.maxWidth < 560 || constraints.maxHeight < 520;
              // 援护角色要一眼看清：大幅立绘从屏幕边缘切入，而不是小头像式展示。
              final portraitHeight = (constraints.maxHeight *
                      (wide ? 1.08 : (compact ? .78 : .84)))
                  .clamp(220.0, wide ? 620.0 : 680.0)
                  .toDouble();
              final portraitWidth = math
                  .min(
                    constraints.maxWidth * (wide ? .56 : .74),
                    portraitHeight * .92,
                  )
                  .toDouble();
              final slideX = -portraitWidth * .52 * (1 - enter) +
                  portraitWidth * .28 * exit;
              final portraitScale = .96 + enter * .08 - exit * .02;
              final bottom = wide
                  ? -portraitHeight * .08
                  : constraints.maxHeight * .025;
              final fallback = Center(
                child: Icon(
                  Icons.person_rounded,
                  size: portraitHeight * .30,
                  color: Colors.white.withOpacity(.22),
                ),
              );

              return Opacity(
                opacity: opacity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(
                      color: Colors.black.withOpacity(.10 + .12 * focus),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[
                            Colors.black.withOpacity(.42 * focus),
                            Colors.black.withOpacity(.15 * focus),
                            Colors.transparent,
                          ],
                          stops: const <double>[0, .48, 1],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-.58, .08),
                            radius: .72,
                            colors: <Color>[
                              Colors.white.withOpacity(.055 * focus),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 一道非常克制的电影式扫光，只负责把援护瞬间“拉开”。
                    Positioned(
                      left: -constraints.maxWidth * .28 +
                          constraints.maxWidth * 1.45 * phase(.02, .62),
                      top: -constraints.maxHeight * .12,
                      bottom: -constraints.maxHeight * .12,
                      width: constraints.maxWidth * .16,
                      child: Transform.rotate(
                        angle: -.12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.white.withOpacity(.04 * focus),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: wide ? -portraitWidth * .03 : -portraitWidth * .08,
                      bottom: bottom,
                      width: portraitWidth,
                      height: portraitHeight,
                      child: Transform.translate(
                        offset: Offset(slideX, 0),
                        child: Transform.scale(
                          scale: portraitScale,
                          alignment: Alignment.bottomCenter,
                          child: _BattleImage(
                            source: portrait,
                            fallback: fallback,
                            logicalWidth: portraitWidth,
                            maxCacheWidth: 900,
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: wide
                          ? constraints.maxWidth * .42
                          : constraints.maxWidth * .38,
                      right: compact ? 16 : constraints.maxWidth * .08,
                      bottom: wide
                          ? constraints.maxHeight * .18
                          : constraints.maxHeight * .20,
                      child: Transform.translate(
                        offset: Offset(slideX * .14, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  width: compact ? 28 : 42,
                                  height: 1,
                                  color: Colors.white.withOpacity(.34),
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  '援 护',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.72),
                                    fontSize: compact ? 9.5 : 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 3.0,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 7 : 9),
                            Text(
                              companion.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.64),
                                fontSize: compact ? 11 : 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: .8,
                              ),
                            ),
                            SizedBox(height: compact ? 3 : 5),
                            Text(
                              skill.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'WenJinMinchoP0',
                                fontSize: compact ? 23 : 31,
                                height: 1.02,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .5,
                                shadows: const <Shadow>[
                                  Shadow(color: Color(0xA0000000), blurRadius: 8),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 正式剧情战斗不能通过系统返回键绕过结算；预览模式没有结算回调，
      // 仍保持原本可直接退出的行为。
      canPop: widget.onSettleItems == null || _settlementAccepted,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _BattleColors.background,
        body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _playerAttackController,
              _enemyAttackController,
              _playerDamageController,
              _enemyDamageController,
            ]),
            child: _BattleSceneBackground(image: widget.sceneBackground),
            builder: (context, child) {
              final playerAttack = math.sin(_playerAttackController.value * math.pi);
              final enemyAttack = math.sin(_enemyAttackController.value * math.pi);
              final impact = math.max(
                math.sin(_playerDamageController.value * math.pi),
                math.sin(_enemyDamageController.value * math.pi),
              ).clamp(0.0, 1.0).toDouble();
              final focus = playerAttack - enemyAttack;
              return Transform.translate(
                offset: Offset(-focus * 3.4, impact * 1.1),
                child: Transform.scale(
                  scale: 1.0 + impact * .006,
                  alignment: const Alignment(.10, .10),
                  child: child,
                ),
              );
            },
          ),
          // 轻量电影式遮罩：只保证 HUD 可读，不压掉场景本身的颜色。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x5208090B),
                  Color(0x1C090A0C),
                  Color(0x00000000),
                  Color(0x10060709),
                  Color(0x5208090B),
                ],
                stops: <double>[0, .16, .45, .74, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.10),
                radius: 1.06,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x08000000),
                  Color(0x38000000),
                ],
                stops: <double>[0, .62, 1],
              ),
            ),
          ),
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _entranceController,
              curve: const Interval(.80, 1.0, curve: Curves.easeOutCubic), // 延后战斗界面出现
            ),
            child: _buildBattleBody(),
          ),
          // 技能 VFX 位于战斗舞台之上、结算/入场遮罩之下。
          // 它只读取已持久化的 vfx_spec，战斗过程中绝不请求 LLM。
          _buildSkillVfxOverlay(),
          _buildCompanionAssistOverlay(),
          if (_entranceVisible)
            _BattleEntranceOverlay(
              animation: _entranceController,
              playerName: widget.playerName,
              playerPortrait: widget.playerPortrait.isNotEmpty ? widget.playerPortrait : widget.playerAvatar,
              enemyName: _enemyName,
              enemyPortrait: _enemyPortrait,
            ),
          if (_outcome != null) _buildEndOverlay(_outcome!),
        ],
        ),
      ),
    );
  }

  Widget _buildBattleBody() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactHeight = constraints.maxHeight < 720;
          final landscapeMode =
              constraints.maxWidth > constraints.maxHeight * 1.12;

          if (landscapeMode) {
            final veryShort = constraints.maxHeight < 360;
            final roomyLandscape = constraints.maxHeight > 560;
            final statusHeight =
                veryShort ? 48.0 : (roomyLandscape ? 64.0 : 56.0);
            final historyHeight =
                veryShort ? 26.0 : (roomyLandscape ? 38.0 : 32.0);
            final commandRailWidth =
                veryShort ? 70.0 : (roomyLandscape ? 88.0 : 78.0);
            final companionRailWidth = _battleCompanions.isEmpty
                ? 8.0
                : (veryShort ? 46.0 : (roomyLandscape ? 60.0 : 54.0));
            final trayHeight =
                veryShort ? 128.0 : (roomyLandscape ? 152.0 : 136.0);
            final stageBottom = trayHeight -
                (veryShort ? 12.0 : (roomyLandscape ? 28.0 : 16.0));

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 中央舞台明确避开左右操作栏和底部手牌区，横屏不再依赖互相覆盖。
                Positioned(
                  left: commandRailWidth + 6,
                  right: companionRailWidth + 6,
                  top: statusHeight + historyHeight - 2,
                  bottom: stageBottom,
                  child: _buildStage(landscape: true),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  top: 0,
                  height: statusHeight,
                  child: _buildStatusBars(landscape: true),
                ),
                Positioned(
                  left: commandRailWidth + 12,
                  right: companionRailWidth + 12,
                  top: statusHeight - 2,
                  height: historyHeight,
                  child: _buildHistory(compact: true),
                ),
                Positioned(
                  left: 5,
                  top: statusHeight + historyHeight + 3,
                  bottom: 6,
                  width: commandRailWidth - 9,
                  child: _buildActionUiVisibility(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildLandscapeCommandRail(
                        veryShort: veryShort,
                      ),
                    ),
                  ),
                ),
                if (_battleCompanions.isNotEmpty)
                  Positioned(
                    right: 4,
                    top: statusHeight + historyHeight + 3,
                    bottom: 6,
                    width: companionRailWidth - 6,
                    child: _buildActionUiVisibility(
                      child: _buildLandscapeCompanionRail(
                        veryShort: veryShort,
                      ),
                    ),
                  ),
                Positioned(
                  left: commandRailWidth + 4,
                  right: companionRailWidth + 4,
                  bottom: 0,
                  height: trayHeight,
                  child: _buildActionUiVisibility(
                    child: _buildLandscapeCenterTray(
                      veryShort: veryShort,
                    ),
                  ),
                ),
                _buildSkillDropTarget(landscape: true),
              ],
            );
          }

          // 竖屏不再用很小的 flex 强塞战况文字。
          // 战况区按可用高度自适应 48~72px，剩余空间全部交给人物舞台。
          final historyHeight = (constraints.maxHeight * .085)
              .clamp(compactHeight ? 48.0 : 54.0, 72.0)
              .toDouble();

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Column(
                children: <Widget>[
                  _buildStatusBars(),
                  Expanded(child: _buildStage()),
                  SizedBox(
                    height: historyHeight,
                    child: _buildHistory(compact: compactHeight),
                  ),
                  _buildActionUiVisibility(
                    child: _buildControls(compact: compactHeight),
                  ),
                ],
              ),
              _buildSkillDropTarget(landscape: false),
            ],
          );
        },
      ),
    );
  }

  /// 技能卡可直接拖到战场中央释放。
  /// DragTarget 本身始终存在，但只有拖拽时才显示视觉反馈，避免平时抢画面。
  Widget _buildSkillDropTarget({required bool landscape}) {
    final visible = _draggingSkillName != null &&
        _activeCategory == _BattleCommandCategory.skills &&
        _canAct;

    return Align(
      alignment: landscape ? const Alignment(.08, -.08) : const Alignment(0, -.12),
      child: DragTarget<YoranBattleSkill>(
        onWillAccept: (skill) {
          if (skill == null || !visible) return false;
          return _canUseSkill(skill.name);
        },
        onAccept: (skill) {
          if (!_canUseSkill(skill.name)) return;
          setState(() {
            _draggingSkillName = null;
            _selectedSkillName = null;
          });
          unawaited(HapticFeedback.mediumImpact());
          unawaited(_useSkill(skill.name));
        },
        onLeave: (_) {
          // 保留拖拽态，真正结束时由 Draggable.onDragEnd 清理。
        },
        builder: (context, candidateData, rejectedData) {
          final hovering = candidateData.isNotEmpty;
          final rejected = rejectedData.isNotEmpty;
          final diameter = landscape ? 146.0 : 132.0;

          return AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: visible ? 1 : 0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              scale: hovering ? 1.08 : 1.0,
              child: Container(
                width: diameter,
                height: diameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      (hovering ? Colors.white : _BattleColors.text)
                          .withOpacity(hovering ? .10 : .035),
                      Colors.black.withOpacity(.04),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, .56, 1],
                  ),
                  border: Border.all(
                    color: rejected
                        ? _BattleColors.enemy.withOpacity(.72)
                        : Colors.white.withOpacity(hovering ? .72 : .24),
                    width: hovering ? 1.4 : .8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      hovering ? Icons.flash_on_rounded : Icons.my_location_rounded,
                      color: rejected
                          ? _BattleColors.enemy
                          : Colors.white.withOpacity(hovering ? .94 : .62),
                      size: hovering ? 27 : 23,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      rejected
                          ? '当前不可释放'
                          : hovering
                              ? '松手释放'
                              : '上滑松手释放',
                      style: TextStyle(
                        color: rejected
                            ? _BattleColors.enemy
                            : Colors.white.withOpacity(hovering ? .92 : .58),
                        fontSize: landscape ? 10.5 : 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBars({bool landscape = false}) {
    return Padding(
      padding: landscape
          ? const EdgeInsets.fromLTRB(10, 2, 10, 0)
          : const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row( 
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: _BattleStatusBar(
              name: widget.playerName,
              portrait: widget.playerAvatar.trim().isNotEmpty
                  ? widget.playerAvatar
                  : widget.playerPortrait,
              hp: _playerHp,
              maxHp: _playerMaxHp,
              qi: _playerQi,   
              maxQi: _playerMaxQi,
              alignEnd: false,
              damageAnimation: _playerDamageController,
              healAnimation: _playerHealController,
              isGuarding: _playerGuarding,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: landscape ? 8 : 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'ROUND',
                  style: TextStyle(
                    color: Colors.white70, 
                    fontSize: 7,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_round',
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic, 
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _BattleStatusBar(
              name: _enemyName,
              portrait: _enemyPortrait,
              hp: _enemyHp,
              maxHp: _enemyMaxHp,
              qi: _enemyQi,    
              maxQi: 100,      
              alignEnd: true,
              enemyIndex: _enemyIndex,
              enemyCount: _battleEnemies.length,
              damageAnimation: _enemyDamageController,
              isGuarding: _enemyIntent == _EnemyIntentKind.guard ||
                  (_enemyIntent == _EnemyIntentKind.skill &&
                      (_enemyIntentSkill?.guarding ?? false)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage({bool landscape = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageWidth = constraints.maxWidth;
        final stageHeight = constraints.maxHeight;
        final wide = landscape || stageWidth > stageHeight * 1.25;
        final compactLandscape = landscape && stageHeight < 340;
        final roomyLandscape = landscape && stageHeight > 430;

        // 横屏把人物主动缩小并上提，把底部中央完整留给技能手牌。
        // 竖屏仍沿用原本较饱满的构图。
        final narrow = stageWidth < 430;
        final playerHeight = (stageHeight * (landscape
                ? (compactLandscape ? .74 : .80)
                : (wide ? .86 : (narrow ? .82 : .86))))
            .clamp(
              landscape ? 118.0 : 140.0,
              landscape
                  ? (roomyLandscape ? 390.0 : 320.0)
                  : (wide ? 365.0 : 335.0),
            )
            .toDouble();
        final enemyHeight = (stageHeight * (landscape
                ? (compactLandscape ? .66 : .72)
                : (wide ? .76 : (narrow ? .72 : .76))))
            .clamp(
              landscape ? 108.0 : 128.0,
              landscape
                  ? (roomyLandscape ? 345.0 : 285.0)
                  : (wide ? 320.0 : 295.0),
            )
            .toDouble();
        // 横屏两侧还有操作栏/援助栏，因此人物画布再收窄一点。
        final playerWidth = math
            .min(
              stageWidth *
                  (landscape ? .32 : (wide ? .36 : (narrow ? .42 : .43))),
              playerHeight * .90,
            )
            .toDouble();
        final enemyWidth = math
            .min(
              stageWidth *
                  (landscape ? .30 : (wide ? .34 : (narrow ? .40 : .41))),
              enemyHeight * .90,
            )
            .toDouble();

        // 横屏不再把我方脚底压在屏幕外：双方整体上移，避免与手牌重叠。
        final playerLeft = landscape
            ? -playerWidth * .02
            : (wide ? -playerWidth * .08 : -playerWidth * .10);
        final playerBottom = landscape
            ? stageHeight * (compactLandscape ? .10 : .08)
            : (wide ? -playerHeight * .045 : -playerHeight * .03);
        final enemyRight = landscape
            ? -enemyWidth * .01
            : (wide ? -enemyWidth * .05 : -enemyWidth * .075);
        final enemyBottom = landscape
            ? stageHeight * (compactLandscape ? .16 : .12)
            : (wide ? stageHeight * .07 : stageHeight * .08);

        final cameraAnimation = Listenable.merge(<Listenable>[
          _playerAttackController,
          _enemyAttackController,
          _playerDamageController,
          _enemyDamageController,
        ]);

        return AnimatedBuilder(
          animation: cameraAnimation,
          builder: (context, _) {
            final playerAttack = math
                .sin(_playerAttackController.value * math.pi)
                .clamp(0.0, 1.0)
                .toDouble();
            final enemyAttack = math
                .sin(_enemyAttackController.value * math.pi)
                .clamp(0.0, 1.0)
                .toDouble();
            final playerImpact = math
                .sin(_playerDamageController.value * math.pi)
                .clamp(0.0, 1.0)
                .toDouble();
            final enemyImpact = math
                .sin(_enemyDamageController.value * math.pi)
                .clamp(0.0, 1.0)
                .toDouble();
            final attackPulse = math.max(playerAttack, enemyAttack).toDouble();
            final impactPulse = math.max(playerImpact, enemyImpact).toDouble();
            final focusX = playerAttack - enemyAttack;
            final cameraX = focusX * 5.0;
            final cameraY = -impactPulse * 2.0;
            final cameraScale = 1.0 + attackPulse * .007 + impactPulse * .010;

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                // 一层非常轻的地面空气感，不画透视网格、不伪造 3D 地板。
                Positioned(
                  left: -stageWidth * .08,
                  right: -stageWidth * .08,
                  bottom: -stageHeight * .04,
                  height: stageHeight * .38,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, .42),
                          radius: .92,
                          colors: <Color>[
                            Colors.black.withOpacity(.03),
                            Colors.black.withOpacity(.10),
                            Colors.transparent,
                          ],
                          stops: const <double>[0, .58, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: playerLeft - playerWidth * .03 + cameraX * .55,
                  bottom: playerBottom + playerHeight * .015,
                  width: playerWidth * 1.12,
                  height: math.max(24.0, playerHeight * .075).toDouble(),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: <Color>[
                          Color(0x80000000),
                          Color(0x2A000000),
                          Color(0x00000000),
                        ],
                        stops: <double>[0, .48, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: enemyRight + cameraX * .24,
                  bottom: enemyBottom - 1,
                  width: enemyWidth * 1.02,
                  height: math.max(20.0, enemyHeight * .060).toDouble(),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: <Color>[
                          Color(0x62000000),
                          Color(0x20000000),
                          Color(0x00000000),
                        ],
                        stops: <double>[0, .52, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: playerLeft + cameraX * .82,
                  bottom: playerBottom + cameraY * .72,
                  width: playerWidth,
                  height: playerHeight,
                  child: Transform.scale(
                    scale: cameraScale + playerAttack * .006,
                    alignment: Alignment.bottomCenter,
                    child: _AnimatedBattleFighter(
                      name: widget.playerName,
                      portrait: widget.playerPortrait,
                      width: playerWidth,
                      height: playerHeight,
                      isPlayer: true,
                      attack: _playerAttackController,
                      damage: _playerDamageController,
                      breath: _playerBreathController,
                      dodge: _playerDodgeController,
                      heal: _playerHealController,
                      rest: _playerRestController,
                      guard: _playerGuardController,
                      guardImpact: _playerGuardImpactController,
                      isGuarding: _playerGuarding,
                      criticalHit: _playerDamageCritical,
                      entrance: _entranceController,
                    ),
                  ),
                ),
                Positioned(
                  right: enemyRight - cameraX * .34,
                  bottom: enemyBottom + cameraY * .28,
                  width: enemyWidth,
                  height: enemyHeight,
                  child: Transform.scale(
                    scale: 1.0 + enemyAttack * .006 + impactPulse * .003,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 520),
                      child: _AnimatedBattleFighter(
                        key: ValueKey<int>(_enemyIndex),
                        name: _enemyName,
                        portrait: _enemyPortrait,
                        width: enemyWidth,
                        height: enemyHeight,
                        isPlayer: false,
                        attack: _enemyAttackController,
                        damage: _enemyDamageController,
                        breath: _enemyBreathController,
                        dodge: _enemyDodgeController,
                        criticalHit: _enemyDamageCritical,
                        entrance: _entranceController,
                      ),
                    ),
                  ),
                ),
                _buildCombatFeedback(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCombatFeedback() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _combatTextController,
        builder: (context, _) {
          if (_combatText.isEmpty || _combatTextController.value <= 0) {
            return const SizedBox.shrink();
          }
          final t = _combatTextController.value;
          final opacity = t < .62
              ? 1.0
              : (1 - (t - .62) / .38).clamp(0.0, 1.0).toDouble();
          final scale = _combatTextCritical
              ? 1.15 + math.sin(t * math.pi) * .30
              : .90 + math.sin(t * math.pi) * .15;
          return Align(
            alignment: Alignment(
              _combatTextOnEnemy ? .38 : -.58,
              _combatTextOnEnemy ? -.16 : -.04,
            ),
            child: Transform.translate(
              offset: Offset(0, -30 * Curves.easeOutCubic.transform(t)),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Text(
                    _combatText,
                    style: TextStyle(
                      color: _combatTextCritical
                          ? Colors.white
                          : _combatTextColor,
                      fontSize: _combatTextCritical ? 30 : 19,
                      fontWeight: _combatTextCritical
                          ? FontWeight.w900
                          : FontWeight.w800,
                      fontStyle: _combatTextCritical
                          ? FontStyle.italic
                          : FontStyle.normal,
                      letterSpacing: _combatTextCritical ? -.45 : .5,
                      height: .95,
                      shadows: _combatTextCritical
                          ? const <Shadow>[
                              Shadow(
                                color: Color(0xB3000000),
                                offset: Offset(0, 2),
                                blurRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

 Widget _buildHistory({bool compact = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (compact ? 56.0 : 68.0);
        final veryTight = height < 50;
        final tight = compact || height < 66;
        final showHeader = !veryTight;
        final showMeta = !tight && height >= 76;
        final statusLines = tight ? 1 : 2;

        return Container(
          margin: compact
              ? const EdgeInsets.fromLTRB(2, 0, 2, 3)
              : const EdgeInsets.fromLTRB(14, 0, 14, 5),
          padding: EdgeInsets.fromLTRB(
            compact ? 9 : 12,
            veryTight ? 4 : (tight ? 5 : 7),
            compact ? 9 : 12,
            veryTight ? 4 : (tight ? 5 : 7),
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                Color(0x00080A0C),
                Color(0x1F080A0C),
                Color(0x33080A0C),
                Color(0x1F080A0C),
                Color(0x00080A0C),
              ],
              stops: <double>[0, .16, .50, .84, 1],
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: ValueListenableBuilder<int>(
            valueListenable: _logRevision,
            builder: (context, _, __) {
              if (_logs.isEmpty) return const SizedBox.shrink();
              final latest = _logs.last;
              final latestIsIntent = latest.label == '敌方意图';

              if (veryTight) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: _BattleCurrentStatus(
                    entry: latest,
                    compact: true,
                    maxLines: 1,
                    showMeta: false,
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (showHeader)
                    Row(
                      children: <Widget>[
                        Text(
                          'TURN ${_round.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.32),
                            fontSize: tight ? 8.2 : 8.8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            height: 1,
                          ),
                        ),
                        const Spacer(),
                        if (!latestIsIntent)
                          Flexible(
                            child: Text(
                              'NEXT · $_enemyIntentTitle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _BattleColors.enemy.withOpacity(.66),
                                fontSize: tight ? 8.1 : 8.7,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .7,
                                height: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  SizedBox(height: tight ? 3 : 5),
                  _BattleCurrentStatus(
                    entry: latest,
                    compact: tight,
                    maxLines: statusLines,
                    showMeta: showMeta,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _handleConfirm() {
    if (!_canAct) return;
    if (_activeCategory == _BattleCommandCategory.companions) {
      final selected = _selectedCompanionSkill();
      if (selected == null) return;
      unawaited(_useCompanionSkill(selected.key, selected.value));
    } else if (_selectedSkillName != null) {
      final skill = _selectedSkillName!;
      setState(() {
        _selectedSkillName = null;
      });
      unawaited(_useSkill(skill));
    } else if (_selectedItemId != null) {
      final itemId = _selectedItemId!;
      setState(() {
        _selectedItemId = null;
      });
      unawaited(_useItem(itemId));
    }
  }

  void _openCompanionSkills(YoranBattleCompanion companion) {
    if (!_canAct) return;
    setState(() {
      _selectedCompanionId = companion.id;
      _selectedCompanionSkillId = null;
      _selectedSkillName = null;
      _selectedItemId = null;
      _activeCategory = _BattleCommandCategory.companions;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  Widget _buildCompanionAvatarStrip({
    bool large = false,
    bool vertical = false,
    bool dense = false,
  }) {
    final avatarSize = dense ? 32.0 : (large ? 42.0 : 38.0);
    return Flex(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: _battleCompanions.map((companion) {
        final selected =
            _activeCategory == _BattleCommandCategory.companions &&
                companion.id == _selectedCompanionId;
        final remaining = companion.skills
            .where((skill) => !_usedCompanionSkillIds.contains(skill.id))
            .length;
        final allUsed = remaining == 0;
        final source = companion.avatar.trim().isNotEmpty
            ? companion.avatar
            : companion.portrait;
        final fallback = Center(
          child: Text(
            companion.name.isEmpty
                ? '?'
                : String.fromCharCode(companion.name.runes.first),
            style: TextStyle(
              color: allUsed ? Colors.white30 : _BattleColors.energy,
              fontSize: dense ? 10.5 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: vertical ? 0 : 2,
            vertical: vertical ? (dense ? 2 : 3) : 0,
          ),
          child: Tooltip(
            message: _companionAssistUsedThisRound && !allUsed
                ? '${companion.name} · 本回合已援助，下一回合恢复'
                : '${companion.name} · 剩余$remaining个限定技',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _canAct ? () => _openCompanionSkills(companion) : null,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                scale: selected ? 1.06 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Colors.white.withOpacity(.94)
                          : Colors.white.withOpacity(allUsed ? .08 : .18),
                      width: selected ? 1.7 : .7,
                    ),
                    boxShadow: selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: Colors.white.withOpacity(.16),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : const <BoxShadow>[],
                  ),
                  padding: const EdgeInsets.all(1.5),
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Opacity(
                        opacity: allUsed ? .30 : 1,
                        child: ClipOval(
                          child: source.isEmpty
                              ? fallback
                              : _BattleImage(
                                  source: source,
                                  fallback: fallback,
                                  logicalWidth: avatarSize,
                                  maxCacheWidth:
                                      dense ? 128 : (large ? 168 : 152),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      if (_companionAssistUsedThisRound && !allUsed)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: dense ? 11 : 13,
                            height: dense ? 11 : 13,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xD90B0C0E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(.34),
                                width: .6,
                              ),
                            ),
                            child: Icon(
                              Icons.schedule_rounded,
                              size: dense ? 7 : 8.5,
                              color: Colors.white.withOpacity(.84),
                            ),
                          ),
                        ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          constraints: BoxConstraints(
                            minWidth: dense ? 11 : 13,
                            minHeight: dense ? 11 : 13,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xD90B0C0E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(.20),
                              width: .5,
                            ),
                          ),
                          child: Text(
                            '$remaining',
                            style: TextStyle(
                              color: allUsed
                                  ? Colors.white38
                                  : Colors.white.withOpacity(.90),
                              fontSize: dense ? 6.7 : 7.5,
                              height: 1,
                              fontWeight: FontWeight.w900,
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
        );
      }).toList(growable: false),
    );
  }

  bool _canConfirmCurrentSelection() {
    if (!_canAct) return false;
    if (_activeCategory == _BattleCommandCategory.items) {
      return _selectedItemId != null && _canUseItem(_selectedItemId!);
    }
    if (_activeCategory == _BattleCommandCategory.companions) {
      final selected = _selectedCompanionSkill();
      return !_companionAssistUsedThisRound &&
          selected != null &&
          !_usedCompanionSkillIds.contains(selected.value.id);
    }
    return _selectedSkillName != null && _canUseSkill(_selectedSkillName!);
  }

  Widget _buildActionUiVisibility({required Widget child}) {
    final visible = _canAct;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: child,
      ),
    );
  }

  Widget _buildLandscapeRailButton({
    required String label,
    required String symbol,
    required bool selected,
    required bool veryShort,
    required VoidCallback? onTap,
    bool emphasized = false,
  }) {
    final enabled = onTap != null;
    final light = selected || emphasized;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: veryShort ? 31 : 35,
        padding: EdgeInsets.symmetric(horizontal: veryShort ? 5 : 7),
        decoration: BoxDecoration(
          color: light
              ? const Color(0xFFF0EEE8).withOpacity(enabled ? 1 : .30)
              : Colors.black.withOpacity(.16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: light
                ? const Color(0xFFF0EEE8).withOpacity(enabled ? .88 : .28)
                : Colors.white.withOpacity(enabled ? .18 : .07),
            width: .8,
          ),
        ),
        child: Row(
          children: <Widget>[
            Text(
              symbol,
              style: TextStyle(
                color: light
                    ? const Color(0xFF0B0C0E).withOpacity(enabled ? .78 : .28)
                    : Colors.white.withOpacity(enabled ? .42 : .18),
                fontSize: veryShort ? 7.0 : 7.6,
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
            SizedBox(width: veryShort ? 4 : 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: light
                      ? const Color(0xFF0B0C0E).withOpacity(enabled ? 1 : .34)
                      : Colors.white.withOpacity(enabled ? .78 : .24),
                  fontSize: veryShort ? 9.6 : 10.4,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeCommandRail({required bool veryShort}) {
    final isItems = _activeCategory == _BattleCommandCategory.items;
    final isCompanions = _activeCategory == _BattleCommandCategory.companions;
    final isSkills = !isItems && !isCompanions;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.black.withOpacity(.34),
            Colors.black.withOpacity(.16),
            Colors.transparent,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          veryShort ? 4 : 5,
          veryShort ? 4 : 7,
          veryShort ? 4 : 6,
          veryShort ? 4 : 7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildLandscapeRailButton(
              label: '行动',
              symbol: '01',
              selected: isSkills,
              veryShort: veryShort,
              onTap: _canAct
                  ? () => _toggleCategory(_BattleCommandCategory.skills)
                  : null,
            ),
            SizedBox(height: veryShort ? 5 : 6),
            _buildLandscapeRailButton(
              label: '道具',
              symbol: '02',
              selected: isItems,
              veryShort: veryShort,
              onTap: _canAct
                  ? () => _toggleCategory(_BattleCommandCategory.items)
                  : null,
            ),
            SizedBox(height: veryShort ? 5 : 6),
            _buildLandscapeRailButton(
              label: '逃跑',
              symbol: '03',
              selected: false,
              veryShort: veryShort,
              onTap: _canAct ? () => unawaited(_confirmEscape()) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeCompanionRail({required bool veryShort}) {
    if (_battleCompanions.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: <Color>[
            Colors.black.withOpacity(.32),
            Colors.black.withOpacity(.12),
            Colors.transparent,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          veryShort ? 4 : 6,
          veryShort ? 5 : 7,
          veryShort ? 4 : 5,
          veryShort ? 5 : 7,
        ),
        child: Column(
          children: <Widget>[
            Text(
              '援助',
              style: TextStyle(
                color: Colors.white.withOpacity(.48),
                fontSize: veryShort ? 8.0 : 8.7,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: veryShort ? 3 : 5),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: _buildCompanionAvatarStrip(
                    vertical: true,
                    dense: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeActionSummary({required bool veryShort}) {
    final isItems = _activeCategory == _BattleCommandCategory.items;
    final isCompanions = _activeCategory == _BattleCommandCategory.companions;

    String title = '技能卡';
    String detail = '点击查看 · 上滑松手可直接释放';
    IconData icon = Icons.auto_awesome_rounded;

    if (isItems) {
      icon = Icons.inventory_2_outlined;
      title = '道具';
      final selected = _selectedItemId == null
          ? null
          : _battleItemById(_selectedItemId!);
      detail = selected == null
          ? '选择道具后点击右侧确认'
          : '${selected.name} · ${selected.effectLabel}';
    } else if (isCompanions) {
      icon = _companionAssistUsedThisRound
          ? Icons.schedule_rounded
          : Icons.person_add_alt_1_rounded;
      final selected = _selectedCompanionSkill();
      title = selected?.value.name ?? '角色援助';
      detail = selected != null
          ? selected.value.detail
          : (_companionAssistUsedThisRound
              ? '本回合援助已使用 · 下一回合恢复'
              : '从右侧选择角色，再选择援助技能');
    } else if (_selectedSkillName != null) {
      for (final skill in _availableSkills) {
        if (skill.name == _selectedSkillName) {
          title = skill.name;
          detail = skill.detail;
          break;
        }
      }
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: veryShort ? 6 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: veryShort ? 8 : 10,
        vertical: veryShort ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.24),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(.09), width: .7),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: veryShort ? 13 : 14,
            color: Colors.white.withOpacity(.60),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: veryShort ? 90 : 116),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(.92),
                fontSize: veryShort ? 9.5 : 10.2,
                fontWeight: FontWeight.w900,
                letterSpacing: .25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: veryShort ? 12 : 14,
            color: Colors.white.withOpacity(.12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(.62),
                fontSize: veryShort ? 8.5 : 9.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeConfirmButton({
    required bool veryShort,
    required bool enabled,
  }) {
    final size = veryShort ? 54.0 : 62.0;
    final borderColor = Colors.white.withOpacity(enabled ? .78 : .14);

    return Semantics(
      button: true,
      enabled: enabled,
      label: '确认当前行动',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _handleConfirm : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: enabled ? 1.0 : .94,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-.18, -.24),
                radius: .95,
                colors: <Color>[
                  Colors.white.withOpacity(enabled ? .20 : .045),
                  Colors.white.withOpacity(enabled ? .075 : .018),
                  Colors.transparent,
                ],
                stops: const <double>[0, .52, 1],
              ),
              border: Border.all(
                color: borderColor,
                width: enabled ? 1.35 : .8,
              ),
              boxShadow: enabled
                  ? <BoxShadow>[
                      BoxShadow(
                        color: Colors.white.withOpacity(.10),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: _BattleColors.energy.withOpacity(.10),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(veryShort ? 5 : 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(enabled ? .16 : .05),
                          width: .6,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.bolt_rounded,
                      size: veryShort ? 20 : 23,
                      color: Colors.white.withOpacity(enabled ? .94 : .24),
                    ),
                    SizedBox(height: veryShort ? 0 : 1),
                    Text(
                      '确认',
                      style: TextStyle(
                        color: Colors.white.withOpacity(enabled ? .86 : .22),
                        fontSize: veryShort ? 7.5 : 8.2,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeCenterTray({required bool veryShort}) {
    final isItems = _activeCategory == _BattleCommandCategory.items;
    final isCompanions = _activeCategory == _BattleCommandCategory.companions;
    final canConfirm = _canConfirmCurrentSelection();
    final content = isItems
        ? _buildItemCards(compact: true)
        : isCompanions
            ? _buildCompanionCards(compact: true)
            : _buildSkillCards(compact: true);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x00080A0C),
            Color(0x26080A0C),
            Color(0x84080A0C),
          ],
          stops: <double>[0, .28, 1],
        ),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: veryShort ? 28 : 32,
            child: _buildLandscapeActionSummary(veryShort: veryShort),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: content),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    veryShort ? 4 : 6,
                    veryShort ? 4 : 6,
                    veryShort ? 7 : 10,
                    veryShort ? 4 : 7,
                  ),
                  child: _buildLandscapeConfirmButton(
                    veryShort: veryShort,
                    enabled: canConfirm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls({required bool compact, bool landscape = false}) {
    // skills 是战斗页的默认模式。某些短暂状态（敌方行动、眩晕）
    // 会把 _activeCategory 暂时置空，但视觉上不应该让用户误以为切到了别的模式。
    final bool isItems = _activeCategory == _BattleCommandCategory.items;
    final bool isCompanions =
        _activeCategory == _BattleCommandCategory.companions;
    final bool isSkills = !isItems && !isCompanions;

    YoranBattleSkill? selectedSkill;
    if (isSkills && _selectedSkillName != null) {
      for (final skill in _availableSkills) {
        if (skill.name == _selectedSkillName) {
          selectedSkill = skill;
          break;
        }
      }
    }

    bool canConfirm = false;
    if (isSkills && _selectedSkillName != null) {
      canConfirm = _canAct && _canUseSkill(_selectedSkillName!);
    } else if (isItems) {
      canConfirm = _canAct &&
          _selectedItemId != null &&
          _canUseItem(_selectedItemId!);
    } else if (isCompanions) {
      final selected = _selectedCompanionSkill();
      canConfirm = _canAct &&
          !_companionAssistUsedThisRound &&
          selected != null &&
          !_usedCompanionSkillIds.contains(selected.value.id);
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x00080A0C),
            Color(0x18080A0C),
            Color(0x52080A0C),
            Color(0xA6080A0C),
          ],
          stops: <double>[0, .20, .60, 1],
        ),
      ),
      padding: EdgeInsets.only(
        top: landscape ? 6 : (compact ? 7 : 10),
        bottom: math.max(
          landscape ? 4.0 : (compact ? 4.0 : 10.0),
          MediaQuery.viewPaddingOf(context).bottom,
        ).toDouble(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: landscape ? 12 : (compact ? 8 : 16)),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _buildMenuTab(
                            label: '行动',
                            symbol: '01',
                            isSelected: isSkills,
                            large: landscape,
                            onTap: () {
                              if (_canAct) {
                                _toggleCategory(_BattleCommandCategory.skills);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildMenuTab(
                            label: '道具',
                            symbol: '02',
                            isSelected: isItems,
                            large: landscape,
                            onTap: () {
                              if (_canAct) {
                                _toggleCategory(_BattleCommandCategory.items);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildEscapeAction(large: landscape),
                          if (_battleCompanions.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 7),
                            _buildCompanionAvatarStrip(large: landscape),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: canConfirm ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !canConfirm,
                    child: FilledButton(
                      onPressed: canConfirm ? _handleConfirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF2F0EA),
                        foregroundColor: const Color(0xFF0B0C0E),
                        elevation: 0,
                        minimumSize: landscape
                            ? const Size(88, 42)
                            : const Size(72, 34),
                        padding: EdgeInsets.symmetric(
                          horizontal: landscape ? 20 : 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: TextStyle(
                          fontSize: landscape ? 13.5 : 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: landscape ? 1.2 : 1.0,
                        ),
                      ),
                      child: const Text('执行'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 技能说明永远占据固定高度：选中技能只替换内容，不改变整个操作区高度。
          // 这样点击/抬起卡牌时，手牌和上方战场都不会被重新顶动。
          SizedBox(
            height: compact ? 48 : 54,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: isCompanions
                  ? Container(
                      key: ValueKey<String>(
                        _companionAssistUsedThisRound
                            ? 'companion-rule-locked'
                            : 'companion-rule-ready',
                      ),
                      width: double.infinity,
                      margin: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 18,
                        vertical: 4,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: compact ? 6 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x32080A0C),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(.12),
                            width: .8,
                          ),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            _companionAssistUsedThisRound
                                ? Icons.schedule_rounded
                                : Icons.person_add_alt_1_rounded,
                            size: compact ? 15 : 17,
                            color: Colors.white.withOpacity(
                              _companionAssistUsedThisRound ? .82 : .68,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _companionAssistUsedThisRound
                                  ? '本回合援助已使用 · 下一回合恢复'
                                  : '援助每回合可发动 1 次 · 选择援助技能后执行',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(
                                  _companionAssistUsedThisRound ? .88 : .74,
                                ),
                                fontSize: compact ? 10.2 : 10.8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : selectedSkill == null
                      ? const SizedBox.expand(
                          key: ValueKey<String>('skill-detail-empty'),
                        )
                      : Container(
                          key: ValueKey<String>('skill-detail-${selectedSkill.name}'),
                      width: double.infinity,
                      margin: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 18,
                        vertical: 4,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: compact ? 6 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x3A080A0C),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(.10),
                            width: .7,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: compact ? 92 : 132,
                            ),
                            child: Text(
                              selectedSkill.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _BattleColors.text,
                                fontFamily: 'WenJinMinchoP0',
                                fontSize: 11.8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 1,
                            height: compact ? 15 : 19,
                            color: Colors.white.withOpacity(.16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedSkill.detail,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(.90),
                                fontSize: compact ? 10.5 : 11.0,
                                height: 1.24,
                                fontWeight: FontWeight.w500,
                                letterSpacing: .04,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          SizedBox(
            height: compact ? 142 : 148,
            child: isSkills
                ? _buildSkillCards()
                : isItems
                    ? _buildItemCards()
                    : _buildCompanionCards(),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTab({
    required String label,
    required String symbol,
    required bool isSelected,
    required VoidCallback onTap,
    bool large = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        height: large ? 42 : 36,
        padding: EdgeInsets.symmetric(horizontal: large ? 15 : 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF0EEE8)
              : Colors.white.withOpacity(.025),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF0EEE8)
                : Colors.white.withOpacity(.24),
            width: isSelected ? .9 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              symbol,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF0B0C0E)
                    : Colors.white.withOpacity(.52),
                fontSize: large ? 9.6 : 8.5,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF0B0C0E)
                    : Colors.white.withOpacity(.80),
                fontSize: large ? 14.0 : 12.2,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEscapeAction({bool large = false}) {
    return GestureDetector(
      onTap: _canAct ? () => unawaited(_confirmEscape()) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _canAct ? 1 : .36,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: large ? 42 : 36,
          padding: EdgeInsets.symmetric(horizontal: large ? 15 : 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.025),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(.24),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '03',
                style: TextStyle(
                  color: Colors.white.withOpacity(.52),
                  fontSize: large ? 9.6 : 8.5,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .3,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '逃跑',
                style: TextStyle(
                  color: Colors.white.withOpacity(.80),
                  fontSize: large ? 14.0 : 12.2,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettlementRewards(YoranBattleOutcome outcome) {
    if (outcome != YoranBattleOutcome.victory) {
      return Text(
        outcome == YoranBattleOutcome.defeat
            ? '重新挑战不会消耗本场使用的道具；继续剧情将接受本次失败。'
            : '脱离战斗不会获得战斗奖励。',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(.48),
          fontSize: 11.5,
          height: 1.55,
        ),
      );
    }
    if (_settlingItems) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 9),
            Text('正在结算奖励…', style: TextStyle(color: Colors.white60, fontSize: 11.5)),
          ],
        ),
      );
    }
    if (_settlementError.isNotEmpty) {
      return TextButton.icon(
        onPressed: () => unawaited(
          _settleBattle(outcome, returnAfterSettlement: false),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 15),
        label: Text(_settlementError),
      );
    }

    final rewards = <Widget>[];
    final rawScore = _battleSettlement['score_reward'];
    if (rawScore is Map) {
      final gained = int.tryParse('${rawScore['score'] ?? 0}') ?? 0;
      if (gained > 0) {
        rewards.add(_buildRewardRow(Icons.auto_awesome_rounded, '星块', '×$gained'));
      }
    }
    final rawAcquired = _battleSettlement['acquired'];
    if (rawAcquired is List) {
      for (final raw in rawAcquired) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final quantity = int.tryParse('${raw['quantity'] ?? 1}') ?? 1;
        final quality = int.tryParse('${raw['quality'] ?? 0}') ?? 0;
        rewards.add(_buildRewardRow(
          Icons.inventory_2_outlined,
          name,
          quality > 0
              ? 'Q$quality${quantity > 1 ? ' · ×$quantity' : ''}'
              : quantity > 1
                  ? '×$quantity'
                  : '获得',
        ));
      }
    }
    final rawSkill = _battleSettlement['skill_reward'];
    if (rawSkill is Map) {
      final name = '${rawSkill['name'] ?? ''}'.trim();
      if (name.isNotEmpty) {
        final quality = int.tryParse('${rawSkill['quality'] ?? 0}') ?? 0;
        rewards.add(_buildRewardRow(
          Icons.bolt_rounded,
          name,
          quality > 0 ? '新技能 · Q$quality' : '新技能',
        ));
      }
    }
    if (!_settlementAccepted) return const SizedBox(height: 18);
    if (rewards.isEmpty) {
      return Text(
        '本场没有额外战利品',
        style: TextStyle(color: Colors.white.withOpacity(.42), fontSize: 11.5),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '获得奖励',
          style: TextStyle(
            color: Colors.white.withOpacity(.48),
            fontSize: 10,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        ...rewards,
      ],
    );
  }

  Widget _buildRewardRow(IconData icon, String name, String trailing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        border: Border.all(color: Colors.white.withOpacity(.08), width: .7),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: _BattleColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 11.5)),
          ),
          Text(
            trailing,
            style: TextStyle(color: Colors.white.withOpacity(.50), fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _buildEndOverlay(YoranBattleOutcome outcome) {
    final title = switch (outcome) {
      YoranBattleOutcome.victory => '战斗胜利',
      YoranBattleOutcome.defeat => '战斗失败',
      YoranBattleOutcome.escaped => '逃跑成功',
    };

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: ColoredBox(
            color: const Color(0xC7000000),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(22, 23, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0E10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(.13),
            width: .8,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0xB8000000),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(width: 28, height: 2, color: _BattleColors.text),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _BattleColors.text,
                fontFamily: 'WenJinMinchoP0',
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.6,
              ),
            ),
            const SizedBox(height: 15),
            _buildSettlementRewards(outcome),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (outcome == YoranBattleOutcome.defeat) ...<Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: _settlingItems ? null : () => _resetBattle(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(.66),
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                              color: Colors.white.withOpacity(.12),
                              width: .8,
                            ),
                          ),
                        ),
                        child: const Text(
                          '重新挑战',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      onPressed: _settlingItems
                          ? null
                          : () => unawaited(_settleBattle(
                                outcome,
                                returnAfterSettlement: true,
                              )),
                      style: FilledButton.styleFrom(
                        backgroundColor: _BattleColors.text,
                        foregroundColor: _BattleColors.background,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white30,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        outcome == YoranBattleOutcome.victory
                            ? '领取并继续'
                            : '继续剧情',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleColors {
  static const Color background = Color(0xFF08090B);
  static const Color surface = Color(0xFF0D0E10);
  static const Color surfaceStrong = Color(0xFF151619);
  static const Color surfaceElevated = Color(0xFF191A1E);
  static const Color controlSurface = Color(0xFF0A0B0D);
  static const Color inputSurface = Color(0xFF1A1B1E);

  static const Color border = Color(0x18FFFFFF);
  static const Color borderBright = Color(0x32FFFFFF);
  static const Color accentBorder = Color(0x66FFFFFF);
  static const Color enemyBorder = Color(0x33B97A7A);

  static const Color text = Color(0xFFF1EFE9);
  static const Color mutedLight = Color(0xFFB8B6AF);
  static const Color muted = Color(0xFF777871);

  // 黑白为主体；状态色全部降饱和，只在反馈节点出现。
  static const Color accent = Color(0xFFE7E4DC);
  static const Color accentSoft = Color(0x1FE7E4DC);
  static const Color player = Color(0xFFA7B6AC);
  static const Color energy = Color(0xFF91A3B0);
  static const Color warning = Color(0xFFC6AE7A);
  static const Color enemy = Color(0xFFB97A7A);
}

/// 统一战斗页图片加载策略。图片只按当前显示宽度解码，避免手机浏览器
/// 把 2K/4K 原图全部展开成大尺寸纹理；同时兼容网络地址与本地资源路径。
class _BattleImage extends StatelessWidget {
  const _BattleImage({
    required this.source,
    required this.fallback,
    required this.logicalWidth,
    this.maxCacheWidth = 1280,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String source;
  final Widget fallback;
  final double logicalWidth;
  final int maxCacheWidth;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final path = source.trim();
    if (path.isEmpty) return fallback;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final cacheWidth = (logicalWidth * pixelRatio)
        .round()
        .clamp(1, maxCacheWidth)
        .toInt();
    final errorBuilder = (
      BuildContext _,
      Object __,
      StackTrace? ___,
    ) => fallback;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        alignment: alignment,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      path,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: errorBuilder,
    );
  }
}

class _BattleSceneBackground extends StatelessWidget {
  const _BattleSceneBackground({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    final path = image.trim();
    final fallback = const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF13233B),
            Color(0xFF0B1423),
          ],
        ),
      ),
    );
    if (path.isEmpty) return fallback;

    final imageWidget = _BattleImage(
      source: path,
      fallback: fallback,
      logicalWidth: MediaQuery.sizeOf(context).width,
      maxCacheWidth: 1600,
    );

    return RepaintBoundary(
      child: Transform.scale(scale: 1.06, child: imageWidget),
    );
  }
}

class _BattleStatusBar extends StatelessWidget {
  const _BattleStatusBar({
    required this.name,
    required this.portrait,
    required this.hp,
    required this.maxHp,
    required this.qi,
    required this.maxQi,
    this.alignEnd = false,
    this.enemyIndex,
    this.enemyCount = 0,
    required this.damageAnimation,
    this.healAnimation,
    this.isGuarding = false,
  });

  final String name;
  final String portrait;
  final int hp;
  final int maxHp;
  final int qi;
  final int maxQi;
  final bool alignEnd;
  final int? enemyIndex;
  final int enemyCount;
  final Animation<double> damageAnimation;
  final Animation<double>? healAnimation;
  final bool isGuarding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: damageAnimation,
      builder: (context, child) {
        final progress = (hp / maxHp).clamp(0.0, 1.0).toDouble();
        final qiProgress = (qi / maxQi).clamp(0.0, 1.0).toDouble();
        final sideColor = alignEnd ? _BattleColors.enemy : _BattleColors.player;
        final hpColor = progress <= .25 ? _BattleColors.enemy : _BattleColors.text;

        final damageWave = math.sin(damageAnimation.value * math.pi * 6) *
            (1 - damageAnimation.value);
        final shakeOffset = damageWave * 3.0;
        final flashOpacity =
            (math.sin(damageAnimation.value * math.pi).clamp(0.0, 1.0) * .18)
                .toDouble();
        final avatarFallback = Center(
          child: Text(
            name.isNotEmpty ? String.fromCharCode(name.runes.first) : '?',
            style: TextStyle(
              color: sideColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

        // HUD 头像直接展示内容本身，不再套黑色底板或描边框。
        // 只保留轻微圆角裁切，避免头像像一枚独立的 App 图标。
        Widget avatarWidget = SizedBox(
          width: 42,
          height: 42,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: portrait.isNotEmpty
                ? _BattleImage(
                    source: portrait,
                    fallback: avatarFallback,
                    logicalWidth: 42,
                    maxCacheWidth: 168,
                    fit: BoxFit.cover,
                  )
                : avatarFallback,
          ),
        );

        Widget infoWidget = Expanded(
          child: Column(
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                mainAxisAlignment:
                    alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: <Widget>[
                  if (!alignEnd)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: sideColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _BattleColors.text,
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  if (alignEnd)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(left: 6),
                      decoration: BoxDecoration(
                        color: sideColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 6,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment:
                        alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        width: constraints.maxWidth,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.62),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.white.withOpacity(.055),
                            width: .6,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * progress,
                        decoration: BoxDecoration(
                          color: hpColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 3,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment:
                        alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        width: constraints.maxWidth,
                        color: Colors.white.withOpacity(.09),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * qiProgress,
                        color: _BattleColors.energy.withOpacity(.96),
                      ),
                    ],
                  ),
                ),
              ),
              if (enemyIndex != null && enemyCount > 1) ...<Widget>[
                const SizedBox(height: 5),
                _EnemyRosterIndicator(
                  currentIndex: enemyIndex!,
                  count: enemyCount,
                ),
              ],
            ],
          ),
        );

        Widget content = Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          // 右上角敌方头像在横/竖屏都隐藏；左上角玩家头像保留。
          children: alignEnd
              ? <Widget>[infoWidget]
              : <Widget>[avatarWidget, const SizedBox(width: 10), infoWidget],
        );

        if (flashOpacity > 0) {
          content = ColorFiltered(
            colorFilter: ColorFilter.mode(
              _BattleColors.enemy.withOpacity(flashOpacity),
              BlendMode.srcATop,
            ),
            child: content,
          );
        }

        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: content,
          ),
        );
      },
    );
  }
}

class _EnemyRosterIndicator extends StatelessWidget {
  const _EnemyRosterIndicator({
    required this.currentIndex,
    required this.count,
  });

  final int currentIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(count.clamp(0, 5).toInt(), (index) {
        final defeated = index < currentIndex;
        final current = index == currentIndex;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-.38),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 14,
              height: 5,
              decoration: BoxDecoration(
                color: defeated
                    ? const Color(0x0DFFFFFF)
                    : _BattleColors.enemy.withOpacity(current ? 1 : .62),
                border: Border.all(
                  color: defeated
                      ? const Color(0x24FFFFFF)
                      : current
                          ? const Color(0xE6FFFFFF)
                          : _BattleColors.enemy.withOpacity(.72),
                  width: current ? 1 : .7,
                ),
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
        );
      }),
    );
  }
}

double _mix(num from, num to, double t) => from.toDouble() +
    (to.toDouble() - from.toDouble()) *
        t.clamp(0.0, 1.0).toDouble();

class _AnimatedBattleFighter extends StatelessWidget {
  const _AnimatedBattleFighter({
    super.key,
    required this.name,
    required this.portrait,
    required this.width,
    required this.height,
    required this.isPlayer,
    required this.attack,
    required this.damage,
    required this.breath,
    required this.entrance, 
    this.dodge,
    this.heal,
    this.rest,
    this.guard,
    this.guardImpact,
    this.isGuarding = false,
    this.criticalHit = false,
  });

  final String name;
  final String portrait;
  final double width;
  final double height;
  final bool isPlayer;
  final AnimationController attack;
  final AnimationController damage;
  final AnimationController breath;
  final Animation<double> entrance; 
  final AnimationController? dodge;
  final AnimationController? heal;
  final AnimationController? rest;
  final AnimationController? guard;
  final AnimationController? guardImpact;
  final bool isGuarding;
  final bool criticalHit;

  double _criticalReaction(double t) {
    if (!criticalHit || t <= 0 || t >= 1) return 0;
    if (t <= .18) {
      return Curves.easeOutCubic.transform((t / .18).clamp(0.0, 1.0));
    }
    if (t <= .34) return 1;
    return 1 - Curves.easeOutCubic.transform(
      ((t - .34) / .66).clamp(0.0, 1.0),
    );
  }

  double _dash(double t) {
    final direction = isPlayer ? 1.0 : -1.0;
    if (t <= .30) return _mix(0, -10 * direction, t / .30);
    if (t <= .62) return _mix(-10 * direction, 80 * direction, (t - .30) / .32);
    return _mix(80 * direction, 0, (t - .62) / .38);
  }

  double _dashScale(double t) {
    if (t <= .30) return _mix(1, .95, t / .30);
    if (t <= .62) return _mix(.95, 1.05, (t - .30) / .32);
    return _mix(1.05, 1, (t - .62) / .38);
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[attack, damage, breath, entrance];
    if (dodge != null) listenables.add(dodge!);
    if (heal != null) listenables.add(heal!);
    if (rest != null) listenables.add(rest!);
    if (guard != null) listenables.add(guard!);
    if (guardImpact != null) listenables.add(guardImpact!);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      child: RepaintBoundary(
        child: _BattlePortrait(
          name: name,
          portrait: portrait,
          width: width,
          height: height,
          isPlayer: isPlayer,
        ),
      ),
      builder: (context, child) {
        final entranceT = Curves.easeOutCubic.transform(
          ((entrance.value - 0.8) / 0.2).clamp(0.0, 1.0),
        );
        final entranceOffset = isPlayer 
            ? -72 * (1 - entranceT) 
            : 72 * (1 - entranceT);

        final damageWave = math.sin(damage.value * math.pi * 6) *
            (1 - damage.value);
        final dodgeWave = math.sin((dodge?.value ?? 0) * math.pi);
        final healT = heal?.value ?? 0;
        final restT = rest?.value ?? 0;
        final guardT = guard?.value ?? 0;
        final guardImpactT = guardImpact?.value ?? 0;
        final breathWave = math.sin(breath.value * math.pi);
        final criticalReaction = _criticalReaction(damage.value);
        final knockbackDirection = isPlayer ? -1.0 : 1.0;
        
        final x = _dash(attack.value) +
            damageWave * 8 +
            dodgeWave * 20 +
            entranceOffset +
            knockbackDirection * 20 * criticalReaction;
        final y = -dodgeWave * 20 - breathWave * 2.4 + 4 * criticalReaction;
        final scale = _dashScale(attack.value) *
            (1 + breathWave * .008) *
            (1 - .025 * criticalReaction);
        final damageFlash = math
            .sin(damage.value * math.pi)
            .clamp(0.0, 1.0)
            .toDouble();

        return Transform.translate(
          offset: Offset(x, y),
          child: Opacity(
            opacity: entranceT,
            child: Transform.rotate(
              angle: damageWave * .045 +
                  knockbackDirection * .18 * criticalReaction,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomCenter,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    const Color(0xFFF56C6C).withOpacity(damageFlash * .26),
                    BlendMode.srcATop,
                  ),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      if (isPlayer && healT > 0 && healT < 1)
                        ...List<Widget>.generate(10, (index) {
                          final phase = ((healT + index * .095) % 1.0);
                          final opacity = math
                              .sin(phase * math.pi)
                              .clamp(0.0, 1.0)
                              .toDouble();
                          const xOffsets = <double>[
                            -.30, -.21, -.12, -.04, .05,
                            .13, .22, .29, -.16, .17,
                          ];
                          final drift =
                              math.sin((phase + index) * math.pi * 2) * .025;
                          final size =
                              index % 3 == 0 ? 4.8 : (index.isEven ? 3.8 : 3.0);
                          return Positioned(
                            left: width * (.50 + xOffsets[index] + drift),
                            bottom: height * (.10 + phase * .62),
                            child: Opacity(
                              opacity: (opacity * .95).clamp(0.0, 1.0),
                              child: Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  color: _BattleColors.player,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: _BattleColors.player.withOpacity(.82),
                                      blurRadius: 9,
                                      spreadRadius: .8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      if (isPlayer && restT > 0 && restT < 1)
                        ...List<Widget>.generate(12, (index) {
                          final phase = ((restT + index * .078) % 1.0);
                          final opacity = math
                              .sin(phase * math.pi)
                              .clamp(0.0, 1.0)
                              .toDouble();
                          const xOffsets = <double>[
                            -.32, -.25, -.18, -.11, -.04, .04,
                            .11, .18, .25, .32, -.15, .15,
                          ];
                          final drift =
                              math.cos((phase * 1.4 + index) * math.pi * 2) * .03;
                          final wide = index % 4 == 0;
                          return Positioned(
                            left: width * (.50 + xOffsets[index] + drift),
                            bottom: height * (.08 + phase * .68),
                            child: Opacity(
                              opacity: (opacity * .98).clamp(0.0, 1.0),
                              child: Container(
                                width: wide ? 3.8 : 2.8,
                                height: wide ? 7.0 : 4.8,
                                decoration: BoxDecoration(
                                  color: _BattleColors.energy,
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: _BattleColors.energy.withOpacity(.88),
                                      blurRadius: 10,
                                      spreadRadius: .7,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      if (isPlayer && guardT > 0 && guardT < 1)
                        ...List<Widget>.generate(8, (index) {
                          const guardGold = Color(0xFFF6C85F);
                          const xOffsets = <double>[
                            -.28, -.20, -.12, -.04, .06, .14, .22, .30,
                          ];
                          final phase = ((guardT + index * .11) % 1.0);
                          final opacity = math
                              .sin(phase * math.pi)
                              .clamp(0.0, 1.0)
                              .toDouble();
                          final outward = (phase * .08) * (index < 4 ? -1 : 1);
                          final size = index.isEven ? 4.2 : 3.1;
                          return Positioned(
                            left: width * (.50 + xOffsets[index] + outward),
                            bottom: height * (.18 + phase * .50),
                            child: Opacity(
                              opacity: (opacity * .95).clamp(0.0, 1.0),
                              child: Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  color: guardGold,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: guardGold.withOpacity(.88),
                                      blurRadius: 10,
                                      spreadRadius: .8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      if (isPlayer && guardImpactT > 0 && guardImpactT < 1)
                        ...List<Widget>.generate(14, (index) {
                          const guardGold = Color(0xFFFFD36A);
                          const dx = <double>[
                            -.02, .02, -.06, .06, -.10, .10, -.14, .14,
                            -.18, .18, -.22, .22, -.26, .26,
                          ];
                          const dy = <double>[
                            .02, .04, .08, .10, .14, .16, .21, .23,
                            .29, .31, .38, .40, .47, .50,
                          ];
                          final burst = Curves.easeOutCubic.transform(guardImpactT);
                          final fade = (1 - guardImpactT).clamp(0.0, 1.0);
                          final longSpark = index % 3 == 0;
                          return Positioned(
                            left: width * (.50 + dx[index] * burst),
                            bottom: height * (.38 + dy[index] * burst),
                            child: Transform.rotate(
                              angle: dx[index] * 5.5,
                              child: Opacity(
                                opacity: fade,
                                child: Container(
                                  width: longSpark ? 2.4 : 3.4,
                                  height: longSpark ? 10.0 : 4.2,
                                  decoration: BoxDecoration(
                                    color: guardGold,
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: guardGold.withOpacity(.95),
                                        blurRadius: 11,
                                        spreadRadius: 1.0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      if (isPlayer && guardImpactT > 0 && guardImpactT < 1)
                        Positioned(
                          left: width * .32,
                          bottom: height * (.68 + guardImpactT * .08),
                          child: Opacity(
                            opacity: math
                                .sin(guardImpactT * math.pi)
                                .clamp(0.0, 1.0)
                                .toDouble(),
                            child: const Text(
                              '格挡',
                              style: TextStyle(
                                color: Color(0xFFFFD36A),
                                fontFamily: 'WenJinMinchoP0',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Color(0x99FFD36A),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (criticalHit && damage.value > 0 && damage.value < .58)
                        ...List<Widget>.generate(6, (index) {
                          const angles = <double>[
                            -.95, -.55, -.20, .20, .55, .95,
                          ];
                          const xOffsets = <double>[
                            -.22, -.12, -.04, .05, .14, .23,
                          ];
                          final burst = Curves.easeOutCubic.transform(
                            (damage.value / .58).clamp(0.0, 1.0),
                          );
                          final fade = (1 - damage.value / .58)
                              .clamp(0.0, 1.0)
                              .toDouble();
                          final longShard = index == 1 || index == 4;
                          return Positioned(
                            left: width * (.50 + xOffsets[index] * burst),
                            bottom: height * (.48 + (index.isEven ? .13 : -.04) * burst),
                            child: Transform.rotate(
                              angle: angles[index],
                              child: Opacity(
                                opacity: fade,
                                child: Container(
                                  width: longShard ? 2.2 : 1.8,
                                  height: longShard ? 18 : 12,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: const <BoxShadow>[
                                      BoxShadow(
                                        color: Color(0x99FFFFFF),
                                        blurRadius: 7,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      child!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BattlePortrait extends StatelessWidget {
  const _BattlePortrait({
    required this.name,
    required this.portrait,
    required this.width,
    required this.height,
    required this.isPlayer,
  });

  final String name;
  final String portrait;
  final double width;
  final double height;
  final bool isPlayer;

  @override
  Widget build(BuildContext context) {
    final fallback = _BattlePortraitFallback(
      name: name,
      isPlayer: isPlayer,
      width: width,
      height: height,
    );
    if (portrait.trim().isEmpty) return fallback;
    // 立绘必须完整显示。之前 fitHeight + ClipRect 会把较宽的敌方素材直接裁掉一半。
    // contain 会在当前自适应画布内保留完整人物，再由舞台尺寸控制视觉体量。
    final image = _BattleImage(
      source: portrait,
      fallback: fallback,
      logicalWidth: width,
      maxCacheWidth: 900,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
    );
    final display = isPlayer
        ? image
        : Transform.flip(
            flipX: true,
            child: image,
          );
    return SizedBox(width: width, height: height, child: display);
  }
}

class _BattlePortraitFallback extends StatelessWidget {
  const _BattlePortraitFallback({
    required this.name,
    required this.isPlayer,
    required this.width,
    required this.height,
  });

  final String name;
  final bool isPlayer;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = isPlayer ? _BattleColors.player : _BattleColors.enemy;
    final initial = name.trim().isEmpty ? '—' : name.trim().substring(0, 1);
    return SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: width * .72,
          height: height * .72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x2EFFFFFF), width: .8),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0x0FFFFFFF),
                Color(0x03000000),
              ],
            ),
          ),
          child: Text(
            initial,
            style: TextStyle(
              color: color.withOpacity(.55),
              fontFamily: 'WenJinMinchoP0',
              fontSize: math.min(width, height) * .27,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

enum _BattleLogTone {
  neutral,
  enemy,
  damage,
  enemyDamage,
  heal,
  success,
}

class _BattleLogEntry {
  const _BattleLogEntry({
    required this.label,
    required this.before,
    this.emphasis = '',
    this.after = '',
    this.meta = '',
    this.tone = _BattleLogTone.neutral,
  });

  final String label;
  final String before;
  final String emphasis;
  final String after;
  final String meta;
  final _BattleLogTone tone;
}

class _BattleCurrentStatus extends StatelessWidget {
  const _BattleCurrentStatus({
    required this.entry,
    this.compact = false,
    this.maxLines = 2,
    this.showMeta = true,
  });

  final _BattleLogEntry entry;
  final bool compact;
  final int maxLines;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final isIntent = entry.label == '敌方意图';
    final enemy = entry.tone == _BattleLogTone.enemy ||
        entry.tone == _BattleLogTone.enemyDamage;
    final emphasisColor = switch (entry.tone) {
      _BattleLogTone.heal || _BattleLogTone.success => _BattleColors.player,
      _BattleLogTone.damage || _BattleLogTone.enemyDamage => _BattleColors.enemy,
      _ => Colors.white,
    };

    if (isIntent) {
      return Row(
        children: <Widget>[
          Icon(
            Icons.visibility_outlined,
            size: compact ? 11.5 : 12.5,
            color: _BattleColors.enemy.withOpacity(.68),
          ),
          const SizedBox(width: 5),
          Text(
            '敌方意图',
            style: TextStyle(
              color: Colors.white.withOpacity(.46),
              fontSize: compact ? 8.8 : 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              entry.before,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: _BattleColors.enemy.withOpacity(.90),
                fontSize: compact ? 11.6 : 12.8,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
                height: 1.15,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: TextStyle(
              color: enemy
                  ? Colors.white.withOpacity(.80)
                  : Colors.white.withOpacity(.90),
              fontSize: compact ? 11.7 : 12.7,
              height: compact ? 1.22 : 1.30,
              fontWeight: FontWeight.w500,
              shadows: const <Shadow>[
                Shadow(color: Color(0x66000000), blurRadius: 2),
              ],
            ),
            children: <InlineSpan>[
              TextSpan(text: entry.before),
              if (entry.emphasis.isNotEmpty)
                TextSpan(
                  text: entry.emphasis,
                  style: TextStyle(
                    color: emphasisColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (entry.after.isNotEmpty) TextSpan(text: entry.after),
            ],
          ),
          maxLines: maxLines < 1 ? 1 : maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
        if (showMeta && entry.meta.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            entry.meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              color: Colors.white.withOpacity(.32),
              fontSize: compact ? 8.2 : 8.7,
              height: 1.05,
              fontWeight: FontWeight.w500,
              letterSpacing: .15,
            ),
          ),
        ],
      ],
    );
  }
}

class _BattleLogTile extends StatelessWidget {
  const _BattleLogTile({super.key, required this.entry});

  final _BattleLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final enemy = entry.tone == _BattleLogTone.enemy ||
        entry.tone == _BattleLogTone.enemyDamage;
        
    // 1. 整体提亮文字颜色
    final baseColor = enemy ? Colors.white.withOpacity(0.85) : Colors.white;
    final emphasisColor = switch (entry.tone) {
      _BattleLogTone.heal || _BattleLogTone.success => _BattleColors.player,
      _BattleLogTone.damage || _BattleLogTone.enemyDamage => _BattleColors.enemy,
      _ => baseColor,
    };
    final labelColor = switch (entry.tone) {
      _BattleLogTone.enemy || _BattleLogTone.enemyDamage => _BattleColors.enemy,
      _BattleLogTone.heal || _BattleLogTone.success => _BattleColors.player,
      _ => Colors.white, // 把默认的小标签也提亮成纯白
    };

    const textShadows = <Shadow>[
      Shadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, 3 * (1 - value)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (entry.label.isNotEmpty || entry.meta.isNotEmpty)
              Row(
                children: <Widget>[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: labelColor,
                      shape: BoxShape.rectangle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (entry.label.isNotEmpty)
                    Flexible(
                      flex: 2,
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 9.2,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .7,
                          shadows: textShadows, // 应用阴影
                        ),
                      ),
                    ),
                  if (entry.meta.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(
                        entry.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          shadows: textShadows,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            if (entry.label.isNotEmpty || entry.meta.isNotEmpty)
              const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: baseColor,
                  fontSize: 11.7,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  shadows: textShadows,
                ),
                children: <InlineSpan>[
                  TextSpan(text: entry.before),
                  if (entry.emphasis.isNotEmpty)
                    TextSpan(
                      text: entry.emphasis,
                      style: TextStyle(
                        color: emphasisColor,
                        fontWeight: FontWeight.w900, // 强调数值极其粗
                      ),
                    ),
                  if (entry.after.isNotEmpty) TextSpan(text: entry.after),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattleEntranceOverlay extends StatelessWidget {
  const _BattleEntranceOverlay({
    required this.animation,
    required this.playerName,
    required this.playerPortrait,
    required this.enemyName,
    required this.enemyPortrait,
  });

  final Animation<double> animation;
  final String playerName;
  final String playerPortrait;
  final String enemyName;
  final String enemyPortrait;

  static const ColorFilter _monochrome = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  double _phase(double value, double start, double end) {
    if (value <= start) return 0;
    if (value >= end) return 1;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value.clamp(0.0, 1.0);
          final reveal = Curves.easeOutCubic.transform(_phase(t, .02, .30));
          final exit = 1 - Curves.easeInCubic.transform(_phase(t, .72, 1.0));
          final contentOpacity = (reveal * exit).clamp(0.0, 1.0);

          final slashIn = Curves.easeOutCubic.transform(_phase(t, .08, .22));
          final slashOut = 1 - Curves.easeInCubic.transform(_phase(t, .34, .52));
          final slashOpacity = (slashIn * slashOut * exit).clamp(0.0, 1.0);

          final width = MediaQuery.sizeOf(context).width;
          final height = MediaQuery.sizeOf(context).height;
          final landscape = width > height * 1.15;
          if (exit <= 0) return const SizedBox.shrink();

          Widget portraitLayer({
            required String source,
            required Alignment alignment,
            required bool top,
            bool mirror = false,
          }) {
            if (source.trim().isEmpty) return const SizedBox.shrink();
            final slide = (1 - reveal) * (top ? -22.0 : 22.0);
            return Transform.translate(
              offset: Offset(0, slide),
              child: Opacity(
                opacity: (.56 * contentOpacity).clamp(0.0, 1.0),
                child: ColorFiltered(
                  colorFilter: _monochrome,
                  child: Transform.flip(
                    flipX: mirror,
                    child: _BattleImage(
                      source: source,
                      fallback: const SizedBox.shrink(),
                      logicalWidth: width,
                      maxCacheWidth: 1280,
                      fit: BoxFit.cover,
                      alignment: alignment,
                    ),
                  ),
                ),
              ),
            );
          }

          if (landscape) {
            final nameSize = (height * .075).clamp(20.0, 28.0).toDouble();
            return Opacity(
              opacity: exit,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Color(0xFF080908)),

                  // 横屏 VS：双方改为左右对峙，不再沿用竖屏的上下切片。
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * .56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        portraitLayer(
                          source: playerPortrait,
                          alignment: Alignment.center,
                          top: true,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: <Color>[
                                Color(0x16000000),
                                Color(0x42000000),
                                Color(0xE6080908),
                              ],
                              stops: <double>[0, .58, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: width * .56,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        portraitLayer(
                          source: enemyPortrait,
                          alignment: Alignment.center,
                          top: false,
                          mirror: true,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: <Color>[
                                Color(0x16000000),
                                Color(0x42000000),
                                Color(0xE6080908),
                              ],
                              stops: <double>[0, .58, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 1.10,
                        colors: <Color>[
                          Color(0x00101311),
                          Color(0x33000000),
                          Color(0xA8000000),
                        ],
                        stops: <double>[0, .66, 1],
                      ),
                    ),
                  ),

                  Center(
                    child: Transform.rotate(
                      angle: .09,
                      child: Transform.translate(
                        offset: Offset((slashIn - .5) * width * .08, 0),
                        child: Opacity(
                          opacity: slashOpacity,
                          child: Container(
                            width: 1.4,
                            height: height * 1.35,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0x00FFFFFF),
                                  Color(0x55FFFFFF),
                                  Color(0xFFFFFFFF),
                                  Color(0x55FFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                                stops: <double>[0, .28, .50, .72, 1],
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x55FFFFFF),
                                  blurRadius: 9,
                                  spreadRadius: .2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: width * .055,
                    right: width * .56,
                    bottom: height * .12,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: Transform.translate(
                        offset: Offset(-18 * (1 - reveal), 0),
                        child: Text(
                          playerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFF4F4F2),
                            fontSize: nameSize,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                            shadows: const <Shadow>[
                              Shadow(color: Color(0xA0000000), blurRadius: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: width * .56,
                    right: width * .055,
                    bottom: height * .12,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: Transform.translate(
                        offset: Offset(18 * (1 - reveal), 0),
                        child: Text(
                          enemyName.isEmpty ? '对手' : enemyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: const Color(0xFFE4E4E0),
                            fontSize: nameSize,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                            shadows: const <Shadow>[
                              Shadow(color: Color(0xA0000000), blurRadius: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: contentOpacity,
                      child: Transform.scale(
                        scale: .90 + .10 * reveal,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: height < 360 ? 13 : 16,
                            vertical: height < 360 ? 5 : 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC080908),
                            border: Border.all(
                              color: const Color(0x52FFFFFF),
                              width: .8,
                            ),
                          ),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'WenJinMinchoP0',
                              fontSize: height < 360 ? 21 : 25,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Opacity(
            opacity: exit,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const ColoredBox(color: Color(0xFF080908)),

                // 我方与敌方只保留低饱和立绘，不再使用绿/红阵营遮罩。
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: height * .54,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      portraitLayer(
                        source: playerPortrait,
                        alignment: Alignment.topCenter,
                        top: true,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x24000000),
                              Color(0x52000000),
                              Color(0xF2080908),
                            ],
                            stops: <double>[0, .56, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: height * .54,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      portraitLayer(
                        source: enemyPortrait,
                        alignment: Alignment.topCenter,
                        top: false,
                        mirror: true,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Color(0x24000000),
                              Color(0x52000000),
                              Color(0xF2080908),
                            ],
                            stops: <double>[0, .56, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 轻微中心暗角，让两张立绘自然融在一起，而不是上下两块色板。
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.05,
                      colors: <Color>[
                        Color(0x00101311),
                        Color(0x44000000),
                        Color(0xB8000000),
                      ],
                      stops: <double>[0, .62, 1],
                    ),
                  ),
                ),

                // 白色斜切闪线：只负责“切开”画面，不承担阵营配色。
                Center(
                  child: Transform.rotate(
                    angle: -0.075,
                    child: Transform.translate(
                      offset: Offset((slashIn - .5) * width * .22, 0),
                      child: Opacity(
                        opacity: slashOpacity,
                        child: Container(
                          width: width * 1.35,
                          height: 1.4,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                Color(0x00FFFFFF),
                                Color(0x55FFFFFF),
                                Color(0xFFFFFFFF),
                                Color(0x55FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                              stops: <double>[0, .30, .50, .70, 1],
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Color(0x55FFFFFF),
                                blurRadius: 9,
                                spreadRadius: .2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 双方名称。只用白/灰建立层级，不再用阵营色区分。
                Positioned(
                  left: 28,
                  right: 64,
                  top: height * .34,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Transform.translate(
                      offset: Offset(-18 * (1 - reveal), 0),
                      child: Text(
                        playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF4F4F2),
                          fontSize: 30,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3.2,
                          shadows: <Shadow>[
                            Shadow(color: Color(0xA0000000), blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 64,
                  right: 28,
                  bottom: height * .30,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Transform.translate(
                      offset: Offset(18 * (1 - reveal), 0),
                      child: Text(
                        enemyName.isEmpty ? '对手' : enemyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFFE4E4E0),
                          fontSize: 30,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3.2,
                          shadows: <Shadow>[
                            Shadow(color: Color(0xA0000000), blurRadius: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Center(
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Transform.scale(
                      scale: .90 + .10 * reveal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC080908),
                          border: Border.all(
                            color: const Color(0x52FFFFFF),
                            width: .8,
                          ),
                        ),
                        child: const Text(
                          'VS',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'WenJinMinchoP0',
                            fontSize: 27,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BattleCardHand extends StatefulWidget {
  const _BattleCardHand({
    required this.skills,
    required this.cooldowns,
    required this.playerQi,
    required this.playerHp,
    required this.enabled,
    required this.selectedSkillName,
    required this.onSkillSelected,
    required this.onSkillQuickCast,
    required this.onDragStateChanged,
    this.compact = false,
  });

  final List<YoranBattleSkill> skills;
  final Map<String, int> cooldowns;
  final int playerQi;
  final int playerHp;
  final bool enabled;
  final String? selectedSkillName;
  final ValueChanged<String> onSkillSelected;
  final ValueChanged<String> onSkillQuickCast;
  final ValueChanged<String?> onDragStateChanged;
  final bool compact;

  @override
  State<_BattleCardHand> createState() => _BattleCardHandState();
}

class _BattleCardHandState extends State<_BattleCardHand>
    with SingleTickerProviderStateMixin {
  double get _cardSpacing => widget.compact ? 58.0 : 70.0;
  double get _dragDistancePerCard => widget.compact ? 44.0 : 52.0;
  double get _maxAngle => widget.compact ? 0.24 : 0.30;
  double get _minScale => widget.compact ? 0.84 : 0.86;
  double get _cardWidth => widget.compact ? 76.0 : 92.0;
  double get _cardHeight => widget.compact ? 102.0 : 124.0;

  late final AnimationController _snapController;
  double _scrollPosition = 0.0;
  double _snapFrom = 0.0;
  double _snapTo = 0.0;
  Offset? _quickDragStartGlobal;
  Offset? _quickDragLatestGlobal;
  String? _activeDragSkillName;

  void _rememberQuickDragPointer(PointerDownEvent event) {
    _quickDragStartGlobal = event.position;
    _quickDragLatestGlobal = event.position;
  }

  void _updateQuickDrag(DragUpdateDetails details) {
    _quickDragLatestGlobal = details.globalPosition;
  }

  bool _shouldQuickCast(DraggableDetails details) {
    if (details.wasAccepted) return false;
    final start = _quickDragStartGlobal;
    final end = _quickDragLatestGlobal;
    if (start == null || end == null) return false;
    final dx = (end.dx - start.dx).abs();
    final upward = start.dy - end.dy;
    // 快捷出牌：明显向上拖出卡面后松手即可，不要求进入中央释放圈。
    // 同时保留方向判断，避免横向转手牌时误触释放。
    final threshold = widget.compact ? 34.0 : 42.0;
    return upward >= threshold && upward >= dx * .65;
  }

  void _clearQuickDragPointer() {
    _quickDragStartGlobal = null;
    _quickDragLatestGlobal = null;
  }

  @override
  void initState() {
    super.initState();
    _scrollPosition = widget.skills.isEmpty
        ? 0.0
        : (widget.skills.length - 1) / 2.0;
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_snapController.value);
        setState(() {
          _scrollPosition = _mix(_snapFrom, _snapTo, t);
        });
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        _scrollPosition = _snapTo;
      });
  }

  @override
  void didUpdateWidget(covariant _BattleCardHand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.skills.isEmpty) {
      _snapController.stop();
      _scrollPosition = 0.0;
      return;
    }
    if (widget.skills.length != oldWidget.skills.length) {
      _snapController.stop();
      _scrollPosition = _scrollPosition
          .clamp(0.0, (widget.skills.length - 1).toDouble())
          .toDouble();
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double _clampPosition(double value) {
    if (widget.skills.length <= 1) return 0.0;
    return value
        .clamp(0.0, (widget.skills.length - 1).toDouble())
        .toDouble();
  }

  void _selectCard(YoranBattleSkill skill, int index, {bool allowToggle = true}) {
    // 无论点击还是从侧边上滑，目标卡都会平滑回到中央主位。
    // 上滑开始时不重复触发同一张卡的 toggle，避免已选技能被意外取消。
    if (allowToggle || widget.selectedSkillName != skill.name) {
      widget.onSkillSelected(skill.name);
    }
    _animateToCard(index.toDouble());
  }

  void _animateToCard(double target, {bool selectCentered = false}) {
    final next = _clampPosition(target.roundToDouble());
    if (selectCentered && widget.skills.isNotEmpty) {
      final index = next.round().clamp(0, widget.skills.length - 1).toInt();
      final skill = widget.skills[index];
      if (widget.selectedSkillName != skill.name) {
        widget.onSkillSelected(skill.name);
      }
    }

    if ((_scrollPosition - next).abs() < 0.001) {
      if (mounted) setState(() => _scrollPosition = next);
      return;
    }

    _snapController.stop();
    _snapFrom = _scrollPosition;
    _snapTo = next;

    final distance = (_snapTo - _snapFrom).abs();
    _snapController.duration = Duration(
      milliseconds: (220 + distance * 55).clamp(220, 380).round(),
    );
    _snapController.forward(from: 0.0);
  }

  int _indexForTap(Offset localPosition, double handWidth) {
    if (widget.skills.length <= 1) return 0;
    final centerX = handWidth / 2;
    final relative = (localPosition.dx - centerX) / _cardSpacing;
    return (_scrollPosition + relative)
        .round()
        .clamp(0, widget.skills.length - 1)
        .toInt();
  }

  void _handleTap(TapUpDetails details, double handWidth) {
    if (!widget.enabled || widget.skills.isEmpty) return;
    final index = _indexForTap(details.localPosition, handWidth);
    _selectCard(widget.skills[index], index);
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.skills.length;
    if (count == 0) return const SizedBox.shrink();

    // 越靠近轮盘中心的卡越后绘制；选中卡永远最后绘制，避免被遮挡。
    // 手牌只构建中心附近的卡。远处卡片本来就在屏幕外，继续构建只会
    // 增加手机浏览器的布局与图层压力。
    final List<int> drawOrder = List<int>.generate(count, (i) => i)
        .where((index) {
          final selected = widget.skills[index].name == widget.selectedSkillName;
          return selected || (index - _scrollPosition).abs() <= 4.0;
        })
        .toList(growable: false);
    drawOrder.sort((a, b) {
      final aSelected = widget.skills[a].name == widget.selectedSkillName;
      final bSelected = widget.skills[b].name == widget.selectedSkillName;
      if (aSelected != bSelected) return aSelected ? 1 : -1;
      final aDistance = (a - _scrollPosition).abs();
      final bDistance = (b - _scrollPosition).abs();
      return bDistance.compareTo(aDistance);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final handWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // 视觉层和手势层彻底分开：卡片可以互相重叠，但每个技能拥有独立的
        // 70px 拖拽槽位。这样侧边露出的卡不会再被中央卡的矩形 hitbox 抢走。
        final visualCards = <Widget>[];
        final dragLanes = <Widget>[];

        for (final index in drawOrder) {
          final skill = widget.skills[index];
          final cooldown = widget.cooldowns[skill.name] ?? 0;
          final isSelected = skill.name == widget.selectedSkillName;
          final canUse = widget.enabled &&
              cooldown <= 0 &&
              (!skill.resting || widget.playerQi < 100) &&
              widget.playerQi >= skill.energyCost &&
              (skill.canSelfKill || widget.playerHp > skill.healthCost);

          final relative = index - _scrollPosition;
          final distance = relative.abs();
          final baseAngle =
              (relative * 0.095).clamp(-_maxAngle, _maxAngle).toDouble();
          final offsetX = relative * _cardSpacing;
          final baseOffsetY = math.min(
            distance * distance * (widget.compact ? 2.1 : 2.6),
            widget.compact ? 20.0 : 28.0,
          );
          final baseScale =
              (1.0 - distance * 0.045).clamp(_minScale, 1.0).toDouble();
          final focusOpacity = isSelected
              ? 1.0
              : (1.0 - distance * .10).clamp(.62, 1.0).toDouble();
          final draggingThis = _activeDragSkillName == skill.name;

          visualCards.add(
            Positioned(
              key: ValueKey('card_${skill.name}'),
              bottom: widget.compact ? 2 : 4,
              child: IgnorePointer(
                child: Opacity(
                  opacity: draggingThis ? .18 : focusOpacity,
                  child: Transform.translate(
                    offset: Offset(offsetX, baseOffsetY),
                    child: Transform.scale(
                      scale: baseScale,
                      child: Transform.rotate(
                        angle: baseAngle,
                        child: _BattleCard(
                          skill: skill,
                          cooldown: cooldown,
                          canUse: canUse,
                          isSelected: isSelected,
                          playerQi: widget.playerQi,
                          playerHp: widget.playerHp,
                          compact: widget.compact,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          if (!canUse) continue;

          dragLanes.add(
            Positioned(
              key: ValueKey('drag_lane_${skill.name}'),
              bottom: widget.compact ? 2 : 4,
              child: Transform.translate(
                offset: Offset(offsetX, baseOffsetY),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _rememberQuickDragPointer,
                  child: Draggable<YoranBattleSkill>(
                    data: skill,
                    axis: Axis.vertical,
                    affinity: Axis.vertical,
                    hitTestBehavior: HitTestBehavior.opaque,
                    maxSimultaneousDrags: 1,
                    onDragStarted: () {
                      final alreadySelected = widget.selectedSkillName == skill.name;
                      setState(() => _activeDragSkillName = skill.name);
                      _selectCard(skill, index, allowToggle: false);
                      widget.onDragStateChanged(skill.name);
                      // 新选中时父层已经提供触感；已选中的卡再次上滑时补一次起手反馈。
                      if (alreadySelected) {
                        unawaited(HapticFeedback.selectionClick());
                      }
                    },
                    onDragUpdate: _updateQuickDrag,
                    onDragEnd: (details) {
                      final quickCast = _shouldQuickCast(details);
                      if (mounted) {
                        setState(() => _activeDragSkillName = null);
                      }
                      widget.onDragStateChanged(null);
                      _clearQuickDragPointer();
                      if (quickCast) {
                        widget.onSkillQuickCast(skill.name);
                      }
                    },
                    feedback: Material(
                      color: Colors.transparent,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Transform.translate(
                          // 侧边卡向上拖出时，同时向手牌中央释放轴收拢。
                          offset: Offset(-offsetX * t, 0),
                          child: child,
                        ),
                        child: Transform.scale(
                          scale: widget.compact ? 1.05 : 1.08,
                          child: _BattleCard(
                            skill: skill,
                            cooldown: cooldown,
                            canUse: true,
                            isSelected: true,
                            playerQi: widget.playerQi,
                            playerHp: widget.playerHp,
                            compact: widget.compact,
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: SizedBox(
                      width: count <= 1 ? _cardWidth : _cardSpacing,
                      height: _cardHeight,
                    ),
                    child: SizedBox(
                      // 拖拽槽位按扇形间距切分，彼此不重叠；不需要先选中或居中。
                      width: count <= 1 ? _cardWidth : _cardSpacing,
                      height: _cardHeight,
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 轻点仍可查看/高亮技能，但它和快捷释放完全解耦。
          onTapUp: (details) => _handleTap(details, handWidth),
          onHorizontalDragStart: (_) {
            _snapController.stop();
          },
          onHorizontalDragUpdate: count <= 1
              ? null
              : (details) {
                  setState(() {
                    _scrollPosition = _clampPosition(
                      _scrollPosition - details.delta.dx / _dragDistancePerCard,
                    );
                  });
                },
          onHorizontalDragEnd: count <= 1
              ? null
              : (details) {
                  final velocity = details.primaryVelocity ?? 0.0;
                  final projected = _scrollPosition - velocity / 760.0;
                  _animateToCard(projected, selectCentered: true);
                },
          onHorizontalDragCancel: count <= 1
              ? null
              : () => _animateToCard(_scrollPosition, selectCentered: true),
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: <Widget>[
              ...visualCards,
              ...dragLanes,
            ],
          ),
        );
      },
    );
  }
}

/// 单张卡牌的美术呈现
/// 卡面使用通透的炭灰层级；选中态通过亮面、白边与极轻品质色光晕聚焦。
class _BattleCard extends StatelessWidget {
  const _BattleCard({
    super.key,
    required this.skill,
    required this.cooldown,
    required this.canUse,
    required this.isSelected,
    required this.playerQi,
    required this.playerHp,
    this.compact = false,
  });

  final YoranBattleSkill skill;
  final int cooldown;
  final bool canUse;
  final bool isSelected;
  final int playerQi;
  final int playerHp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool isEnergyShort = playerQi < skill.energyCost;
    final bool isLocked = !canUse;
    final quality = _battleSkillQualityColor(skill.quality);

    final borderColor = isSelected
        ? Colors.white.withOpacity(.94)
        : Colors.white.withOpacity(isLocked ? .07 : .20);
    final topSurface = isLocked
        ? const Color(0x6617191D)
        : (isSelected ? const Color(0xE34A4F58) : const Color(0xB5363941));
    final bottomSurface = isLocked
        ? const Color(0x73101215)
        : (isSelected ? const Color(0xD62B2F36) : const Color(0xA31A1D22));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 170),
      opacity: isLocked && !isSelected ? .40 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        width: compact ? 76 : 92,
        height: compact ? 102 : 124,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[topSurface, bottomSurface],
          ),
          borderRadius: BorderRadius.circular(compact ? 8 : 10),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.25 : .8,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: quality.withOpacity(.16),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(.30),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: 0,
              left: compact ? 8 : 10,
              right: compact ? 8 : 10,
              child: Container(
                height: 2,
                color: isLocked
                    ? Colors.white12
                    : (isSelected ? Colors.white : quality.withOpacity(.84)),
              ),
            ),
            if (skill.energyCost > 0)
              Positioned(
                top: compact ? 5 : 7,
                left: compact ? 5 : 7,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 5 : 6,
                    vertical: compact ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: isEnergyShort
                        ? _BattleColors.enemy.withOpacity(.14)
                        : Colors.white.withOpacity(.075),
                    borderRadius: BorderRadius.circular(compact ? 4 : 5),
                    border: Border.all(
                      color: isEnergyShort
                          ? _BattleColors.enemy.withOpacity(.48)
                          : Colors.white.withOpacity(.18),
                      width: .8,
                    ),
                  ),
                  child: Text(
                    'SP -${skill.energyCost}',
                    style: TextStyle(
                      color: isEnergyShort
                          ? _BattleColors.enemy
                          : Colors.white.withOpacity(.92),
                      fontSize: compact ? 8.0 : 9.6,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .18,
                    ),
                  ),
                ),
              ),
            if (cooldown > 0)
              Positioned(
                top: compact ? 7 : 9,
                right: compact ? 7 : 9,
                child: Text(
                  'CD $cooldown',
                  style: TextStyle(
                    color: _BattleColors.enemy.withOpacity(.74),
                    fontSize: compact ? 7.3 : 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
              ),
            Positioned(
              top: compact ? 23 : 28,
              left: 0,
              right: 0,
              child: Center(
                child: _BattleSkillTypeIcon(
                  skill: skill,
                  size: compact ? 18 : 22,
                  color: isLocked
                      ? Colors.white24
                      : (isSelected ? Colors.white : quality.withOpacity(.90)),
                ),
              ),
            ),
            Positioned(
              left: compact ? 6 : 7,
              right: compact ? 6 : 7,
              top: compact ? 48 : 58,
              child: Text(
                skill.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isLocked ? Colors.white30 : _BattleColors.text,
                  fontFamily: 'WenJinMinchoP0',
                  fontSize: compact ? 11.3 : 13.5,
                  height: 1.10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .2,
                ),
              ),
            ),
            Positioned(
              left: compact ? 6 : 8,
              right: compact ? 6 : 8,
              bottom: compact ? 7 : 9,
              child: Text(
                _battleSkillTypeName(skill.iconType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(isLocked ? .18 : .34),
                  fontSize: compact ? 7.2 : 8.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


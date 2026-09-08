import 'dart:async';
import 'dart:math' as math;
import 'dart:ui'; // 用于毛玻璃模糊效果

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'novel_asr_stream_service.dart';
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
    this.basicAttackMin = 5,
    this.basicAttackMax = 8,
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
  final int basicAttackMin;
  final int basicAttackMax;
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
/// [fromState] 可直接消费 `protagonist.status['skills']` 中的字符串或字典，
/// 并读取 SkillDesigner 生成的 `battle_spec`。这样开发者测试与正式战斗
/// 不再只显示技能名称，而是真正使用后端给出的伤害、消耗、冷却和附加效果。
class YoranBattleSkill {
  const YoranBattleSkill({
    this.id = '',
    required this.name,
    required this.detail,
    this.archetype = 'direct',
    this.quality = 0,
    this.minDamage = 0,
    this.maxDamage = 0,
    this.hitBonus = 4,
    this.energyCost = 0,
    this.energyGain = 0,
    this.cooldown = 0,
    this.burnTurns = 0,
    this.burnDamage = 0,
    this.healAmount = 0,
    this.lifestealPercent = 0,
    this.healthCost = 0,
    this.stunTurns = 0,
    this.guardReductionPercent = 0,
    this.enemyHitDifficultyBonus = 0,
    this.exposeHitBonus = 0,
    this.exposeExtraDamageMin = 0,
    this.exposeExtraDamageMax = 0,
    this.exposes = false,
    this.guarding = false,
    this.dodging = false,
    this.resting = false,
    this.piercesGuard = false,
    this.targetSelf = false,
    this.canSelfKill = false,
    this.counterMin = 0,
    this.counterMax = 0,
  });

  final String id;
  final String name;
  final String detail;
  final String archetype;
  final int quality;
  final int minDamage;
  final int maxDamage;
  final int hitBonus;
  final int energyCost;
  final int energyGain;
  final int cooldown;
  final int burnTurns;
  final int burnDamage;
  final int healAmount;
  final int lifestealPercent;
  final int healthCost;
  final int stunTurns;
  final int guardReductionPercent;
  final int enemyHitDifficultyBonus;
  final int exposeHitBonus;
  final int exposeExtraDamageMin;
  final int exposeExtraDamageMax;
  final bool exposes;
  final bool guarding;
  final bool dodging;
  final bool resting;
  final bool piercesGuard;
  final bool targetSelf;
  final bool canSelfKill;
  final int counterMin;
  final int counterMax;

  bool get isSelfAction => targetSelf || guarding || dodging || resting;

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
    if (counterMax > 0) return 'counter';
    if (stunTurns > 0) return 'stun';
    if (healAmount > 0 && maxDamage <= 0) return 'heal';
    if ((energyGain > 0 || resting) && maxDamage <= 0) return 'energy';
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
    if (raw is String) {
      final name = raw.trim();
      if (name.isEmpty) return null;
      return YoranBattleSkill(
        name: name,
        detail: '暂无技能描述',
        quality: 3,
        minDamage: 10,
        maxDamage: 15,
        hitBonus: 4,
        energyCost: 12,
        cooldown: 1,
      );
    }
    final skill = _stringMap(raw);
    final name = '${skill['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;

    final spec = _stringMap(skill['battle_spec']);
    if (spec.isEmpty) {
      final description = '${skill['description'] ?? ''}'.trim();
      return YoranBattleSkill(
        name: name,
        detail: description.isEmpty ? '暂无技能描述' : description,
        quality: 3,
        minDamage: 10,
        maxDamage: 15,
        hitBonus: 4,
        energyCost: 12,
        cooldown: 1,
      );
    }

    final damage = _stringMap(spec['damage']);
    var burnTurns = 0;
    var burnDamage = 0;
    var healAmount = 0;
    var energyGain = 0;
    var lifestealPercent = 0;
    var stunTurns = 0;
    var guardReductionPercent = 0;
    var enemyHitDifficultyBonus = 0;
    var exposeHitBonus = 0;
    var exposeExtraDamageMin = 0;
    var exposeExtraDamageMax = 0;
    var guarding = false;
    var dodging = false;
    var exposes = false;
    var counterMin = 0;
    var counterMax = 0;
    final effects = spec['effects'];
    if (effects is List) {
      for (final rawEffect in effects.take(2)) {
        final effect = _stringMap(rawEffect);
        switch ('${effect['type'] ?? ''}'.trim().toLowerCase()) {
          case 'damage_over_time':
            burnTurns = _asInt(effect['duration']).clamp(0, 3).toInt();
            burnDamage = _asInt(effect['damage']).clamp(0, 60).toInt();
            break;
          case 'evade':
            dodging = true;
            enemyHitDifficultyBonus =
                _asInt(effect['enemy_hit_difficulty_bonus'], 5).clamp(1, 8).toInt();
            break;
          case 'guard':
            guarding = true;
            guardReductionPercent =
                _asInt(effect['reduction_percent'], 50).clamp(10, 75).toInt();
            break;
          case 'heal':
            healAmount = _asInt(effect['amount']).clamp(0, 100).toInt();
            break;
          case 'energy_restore':
            energyGain = _asInt(effect['amount']).clamp(0, 100).toInt();
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
            final extraDamage = _stringMap(effect['extra_damage']);
            exposeExtraDamageMin =
                _asInt(extraDamage['min']).clamp(0, 10).toInt();
            exposeExtraDamageMax = math
                .max(exposeExtraDamageMin, _asInt(extraDamage['max']))
                .clamp(0, 12)
                .toInt();
            break;
          case 'counter':
            final counterDamage = _stringMap(effect['damage']);
            counterMin = _asInt(counterDamage['min']).clamp(0, 60).toInt();
            counterMax = math
                .max(counterMin, _asInt(counterDamage['max']))
                .clamp(0, 60)
                .toInt();
            break;
        }
      }
    }

    final minDamage = _asInt(damage['min']).clamp(0, 60).toInt();
    final maxDamage = math
        .max(minDamage, _asInt(damage['max']))
        .clamp(0, 60)
        .toInt();
    final energyCost = _asInt(spec['energy_cost']).clamp(0, 40).toInt();
    final cooldown = _asInt(spec['cooldown']).clamp(0, 3).toInt();
    final quality = _asInt(spec['quality']).clamp(0, 10).toInt();
    
    final designNote = '${spec['design_note'] ?? skill['description'] ?? ''}'.trim();
    return YoranBattleSkill(
      id: '${skill['id'] ?? ''}'.trim(),
      name: name,
      detail: designNote.isEmpty ? '暂无技能描述' : designNote,
      archetype: '${spec['archetype'] ?? skill['category'] ?? 'direct'}'
          .trim()
          .toLowerCase(),
      quality: quality,
      minDamage: minDamage,
      maxDamage: maxDamage,
      hitBonus: _asInt(spec['hit_bonus'], 4).clamp(0, 10).toInt(),
      energyCost: energyCost,
      energyGain: energyGain,
      cooldown: cooldown,
      burnTurns: burnTurns,
      burnDamage: burnDamage,
      healAmount: healAmount,
      lifestealPercent: lifestealPercent,
      healthCost: _asInt(spec['health_cost']).clamp(0, 100).toInt(),
      stunTurns: stunTurns,
      guardReductionPercent: guardReductionPercent,
      enemyHitDifficultyBonus: enemyHitDifficultyBonus,
      exposeHitBonus: exposeHitBonus,
      exposeExtraDamageMin: exposeExtraDamageMin,
      exposeExtraDamageMax: exposeExtraDamageMax,
      exposes: exposes,
      guarding: guarding,
      dodging: dodging,
      piercesGuard: '${spec['archetype'] ?? ''}'.trim().toLowerCase() == 'control',
      targetSelf: '${spec['target'] ?? ''}'.trim().toLowerCase() == 'self',
      canSelfKill: _asBool(spec['can_self_kill']),
      counterMin: counterMin,
      counterMax: counterMax,
    );
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
  });

  final String id;
  final String name;
  final String avatar;
  final String portrait;
  final List<YoranBattleSkill> skills;

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
    );
  }
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
    this.affixes = const <String, int>{},
  });

  final String id;
  final String name;
  final String slot;
  final int quality;
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
    final affixes = _normalizeAffixes(
      raw['affixes'] ?? raw['affix_stats'] ?? raw['affixStats'],
    );
    return YoranBattleEquipment(
      id: id.isEmpty ? 'equipment_${slot}_$name' : id,
      name: name,
      slot: slot,
      quality: quality,
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
    final basicMin = _int(basicAttack['min'], 5).clamp(1, 25).toInt();
    final basicMax = math
        .max(basicMin, _int(basicAttack['max'], 8))
        .clamp(1, 25)
        .toInt();
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
        basicAttackMin: basicMin,
        basicAttackMax: basicMax,
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
    minDamage: 5,
    maxDamage: 8,
    hitBonus: 6,
  ),
  YoranBattleSkill(
    name: '休整',
    detail: '放缓呼吸并调整状态，恢复大量精力',
    archetype: 'energy',
    energyGain: 20,
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
    minDamage: 9,
    maxDamage: 12,
    hitBonus: 4,
    energyCost: 15,
    cooldown: 1,
    piercesGuard: true,
  ),
];

/// 需要启用战斗语音输入时，传入剧情控制器持有的 `controller.socket`。
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
  static const int _maxBattleLogEntries = 120;
  static const Duration _maximumSpeechDuration = Duration(seconds: 30);
  static const Duration _speechTranscriptionTimeout = Duration(seconds: 10);

  final math.Random _random = math.Random();
  final TextEditingController _actionController = TextEditingController();
  final FocusNode _actionFocus = FocusNode();
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
  late final AnimationController _playerBreathController;
  late final AnimationController _enemyBreathController;

  NovelAsrStreamService? _asr;
  bool _speechStarting = false;
  bool _isListening = false;
  bool _micHeld = false;
  bool _speechFinishing = false;
  String _speechBaseText = '';
  int _speechSessionId = 0;
  Future<void>? _speechStartFuture;
  Stopwatch? _speechHoldWatch;
  Timer? _speechLimitTimer;

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
  String? _selectedItemId;
  String? _selectedCompanionId;
  String? _selectedCompanionSkillId;
  YoranBattleCompanion? _activeAssistCompanion;
  YoranBattleSkill? _activeAssistSkill;
  final Set<String> _usedCompanionSkillIds = <String>{};
  bool _companionAssistUsedThisRound = false;
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
  bool _busy = true;
  bool _entranceVisible = true;
  YoranBattleOutcome? _outcome;
  
  _BattleCommandCategory? _activeCategory = _BattleCommandCategory.skills;
  
  final List<_BattleLogEntry> _logs = <_BattleLogEntry>[];
  final ValueNotifier<int> _logRevision = ValueNotifier<int>(0);

  bool get _speechBusy =>
      _speechStarting || _isListening || _micHeld || _speechFinishing;
  bool get _canAct =>
      !_busy && _outcome == null && !_entranceVisible && !_speechBusy;
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
    final hpAffix = _equipmentAffixTotal('max_hp_percent', cap: 40);
    final energyAffix = _equipmentAffixTotal('max_energy_percent', cap: 40);
    final attackAffix = _equipmentAffixTotal('attack_percent', cap: 40);
    final defenseAffix = _equipmentAffixTotal('defense_percent', cap: 15);
    final hitAffix = _equipmentAffixTotal('hit_percent', cap: 24);
    final dodgeAffix = _equipmentAffixTotal('dodge_percent', cap: 16);
    final criticalAffix = _equipmentAffixTotal('critical_percent', cap: 24);

    _playerMaxHp =
        (_baseMaxHp * (1 + upperQuality * .10 + hpAffix / 100)).round();
    _playerMaxQi =
        (_baseMaxQi * (1 + faceQuality * .10 + energyAffix / 100)).round();
    _equipmentAttackMultiplier = 1 + handheldQuality * .10 + attackAffix / 100;
    // 下装提供固定减伤，词条最多再补15%；总减伤封顶65%。
    final defenseReduction =
        (lowerQuality * .05 + defenseAffix / 100).clamp(0.0, .65).toDouble();
    _equipmentDefenseMultiplier = 1 - defenseReduction;
    _equipmentHitPercent =
        (_qualityForSlot('head') * 3 + hitAffix).clamp(0, 45).toInt();
    _equipmentDodgePercent =
        (_qualityForSlot('feet') + dodgeAffix).clamp(0, 25).toInt();
    _equipmentCriticalPercent =
        (_accessoryQualityTotal() + criticalAffix).clamp(0, 50).toInt();
    // 整场战斗共享道具次数：基础2次，背包每1点品质额外增加1次。
    // 未装备背包为2次，Q1为3次，Q10为12次；跨回合、连续敌人均不重置。
    _maxItemUsesPerBattle = 2 + backQuality;
    _playerHp = _playerMaxHp;
    _playerQi = (_playerMaxQi * .40).round();
    for (final item in _battleItems) {
      _itemCounts[item.id] = item.quantity;
    }
    _actionFocus.addListener(_handleActionFocusChanged);
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
    _playerBreathController = _controller(3900)
      ..value = .18
      ..repeat(reverse: true);
    _enemyBreathController = _controller(4400)
      ..value = .62
      ..repeat(reverse: true);
    final socketService = widget.socketService;
    if (socketService != null) {
      _asr = NovelAsrStreamService(socketService: socketService);
    }

    _resetBattle(startEntrance: true);
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
    if (oldWidget.socketService == widget.socketService) return;
    _speechSessionId++;
    _speechLimitTimer?.cancel();
    unawaited(_asr?.dispose());
    final socketService = widget.socketService;
    _asr = socketService == null
        ? null
        : NovelAsrStreamService(socketService: socketService);
    _speechStarting = false;
    _isListening = false;
    _micHeld = false;
    _speechFinishing = false;
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
    _playerBreathController.dispose();
    _enemyBreathController.dispose();
    _speechSessionId++;
    _speechLimitTimer?.cancel();
    _speechHoldWatch?.stop();
    unawaited(_asr?.dispose());
    _actionFocus.removeListener(_handleActionFocusChanged);
    _actionController.dispose();
    _actionFocus.dispose();
    _logController.dispose();
    _logRevision.dispose();
    super.dispose();
  }

  void _handleActionFocusChanged() {
    if (mounted) setState(() {});
  }

  void _toggleCategory(_BattleCommandCategory category) {
    if (!_canAct || _speechBusy) return;
    _actionFocus.unfocus();
    if (_activeCategory == category) return;
    setState(() {
      _activeCategory = category;
    });
  }

  String _mergeSpeechText(String base, String spoken) {
    final words = spoken.trim();
    if (words.isEmpty) return base;
    if (base.isEmpty) return words;
    if (RegExp(r'\s$').hasMatch(base)) return '$base$words';

    final last = base.runes.isEmpty ? 0 : base.runes.last;
    final first = words.runes.isEmpty ? 0 : words.runes.first;
    bool isCjk(int rune) =>
        (rune >= 0x3400 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF);
    return isCjk(last) && isCjk(first) ? '$base$words' : '$base $words';
  }

  void _commitSpeechText(int sessionId, String spoken) {
    if (!mounted || sessionId != _speechSessionId) return;
    final nextText = _mergeSpeechText(_speechBaseText, spoken);
    if (nextText.trim().isEmpty) return;
    _actionController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _beginHoldListening() async {
    if (!_canAct || _speechBusy) return;
    final asr = _asr;
    if (asr == null) {
      _showSpeechMessage('语音服务未连接，请从剧情控制器传入 socketService。');
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(
      reason: SnackBarClosedReason.hide,
    );
    final sessionId = ++_speechSessionId;
    _speechBaseText = _actionController.text;
    _speechHoldWatch = Stopwatch()..start();
    _speechLimitTimer?.cancel();
    _speechLimitTimer = Timer(_maximumSpeechDuration, () {
      if (!mounted ||
          sessionId != _speechSessionId ||
          (!_micHeld && !_isListening && !_speechStarting)) {
        return;
      }
      unawaited(_finishHoldListening());
    });
    _actionFocus.unfocus();
    setState(() {
      _activeCategory = null;
      _micHeld = true;
      _speechStarting = true;
    });

    final startFuture = asr.start();
    _speechStartFuture = startFuture;
    try {
      await startFuture;
      if (!mounted || sessionId != _speechSessionId) {
        await asr.cancel();
        return;
      }
      setState(() {
        _speechStarting = false;
        _isListening = _micHeld;
      });
    } on NovelAsrStreamException catch (error) {
      if (!mounted || sessionId != _speechSessionId) return;
      _speechLimitTimer?.cancel();
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _micHeld = false;
      });
      _showSpeechMessage(error.message);
    } catch (_) {
      if (!mounted || sessionId != _speechSessionId) return;
      _speechLimitTimer?.cancel();
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _micHeld = false;
      });
      _showSpeechMessage('无法启动语音输入，请重试。');
    } finally {
      if (identical(_speechStartFuture, startFuture)) {
        _speechStartFuture = null;
      }
    }
  }


  // 渲染技能卡片
  Widget _buildSkillCards() {
    return _BattleCardHand(
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
    );
  }

  // 渲染道具卡片
  Widget _buildItemCards() {
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
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        physics: const BouncingScrollPhysics(),
        itemCount: _battleItems.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = _battleItems[index];
          final count = _itemCounts[item.id] ?? 0;
          final isSelected = _selectedItemId == item.id;
          final isEmpty = count <= 0;
          final accent = item.restoresHp && !item.restoresSp
              ? _BattleColors.player
              : item.restoresSp && !item.restoresHp
                  ? _BattleColors.energy
                  : Colors.white;

          return AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: isSelected ? const Offset(0, -0.075) : Offset.zero,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              scale: isSelected ? 1.025 : 1.0,
              child: GestureDetector(
                onTap: (!isEmpty && _canAct) ? () {
                  setState(() {
                    if (_selectedItemId == item.id) {
                      _selectedItemId = null;
                    } else {
                      _selectedItemId = item.id;
                      _selectedSkillName = null;
                    }
                  });
                  unawaited(HapticFeedback.selectionClick());
                } : null,
                child: ClipRect( // 新增毛玻璃裁剪区
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // 增加毛玻璃特效
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 84,
                      height: 120,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.12)
                            : (isEmpty
                                ? const Color(0x24000000)
                                : const Color(0x3D000000)),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white.withOpacity(0.78)
                              : Colors.white.withOpacity(isEmpty ? 0.04 : 0.085),
                          width: isSelected ? 0.95 : 0.75,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Positioned(
                            top: 6, right: 6,
                            child: Text('x$count', style: TextStyle(color: isEmpty ? Colors.white30 : Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                          ),
                          Positioned(
                            top: 7,
                            left: 7,
                            child: Text(
                              'Q${item.quality}',
                              style: TextStyle(
                                color: isEmpty ? Colors.white24 : accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(item.name, textAlign: TextAlign.center, style: TextStyle(color: isEmpty ? Colors.white30 : Colors.white, fontFamily: 'WenJinMinchoP0', fontSize: 14, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          Positioned(
                            left: 4,
                            right: 4,
                            bottom: 7,
                            child: Text(
                              item.effectLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isEmpty ? Colors.white24 : accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              bottom: -24, left: -24, right: -24,
                              child: Text(
                                item.detail.isEmpty ? item.effectLabel : '${item.detail} · ${item.effectLabel}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 10, shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 4)]),
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
        },
      ),
    );
  }

  Widget _buildCompanionSkillCard(
    YoranBattleSkill skill, {
    required bool compact,
  }) {
    final used = _usedCompanionSkillIds.contains(skill.id);
    final selected = _selectedCompanionSkillId == skill.id;
    final disabled = used || _companionAssistUsedThisRound || !_canAct;
    final accent = _battleSkillQualityColor(skill.quality);
    return GestureDetector(
      onTap: disabled
          ? null
          : () {
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
              ? const Color(0xCC111318)
              : selected
                  ? accent.withOpacity(.18)
                  : const Color(0xD9141820),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(.92)
                : used
                    ? Colors.white.withOpacity(.10)
                    : accent.withOpacity(.66),
            width: selected ? 1.6 : 1.05,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withOpacity(.30),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _BattleSkillTypeIcon(
                  skill: skill,
                  size: compact ? 15 : 18,
                  color: disabled ? Colors.white30 : accent,
                ),
                SizedBox(width: compact ? 5 : 7),
                Expanded(
                  child: Text(
                    skill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: used ? Colors.white30 : Colors.white,
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (used)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: Colors.white24,
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
                  color: used ? Colors.white24 : Colors.white60,
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
                        : _companionAssistUsedThisRound
                            ? '本回合已援战'
                            : '限定技 · 0精力',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled ? Colors.white30 : accent,
                      fontSize: compact ? 8 : 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!compact)
                  Text(
                    _battleSkillTypeName(skill.iconType),
                    style: TextStyle(
                      color: used ? Colors.white24 : accent.withOpacity(.86),
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

  Widget _buildCompanionCards() {
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
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        final rowCount = (entries.length / columns).ceil();
        const gap = 8.0;
        final compact = rowCount > 1;
        final rows = <Widget>[];
        for (var row = 0; row < rowCount; row++) {
          final cells = <Widget>[];
          for (var column = 0; column < columns; column++) {
            final index = row * columns + column;
            cells.add(
              Expanded(
                child: index < entries.length
                    ? _buildCompanionSkillCard(
                        entries[index].value,
                        compact: compact,
                      )
                    : const SizedBox.shrink(),
              ),
            );
            if (column < columns - 1) cells.add(const SizedBox(width: gap));
          }
          rows.add(Expanded(child: Row(children: cells)));
          if (row < rowCount - 1) rows.add(const SizedBox(height: gap));
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
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
    unawaited(_companionAssistController.forward(from: 0));
    unawaited(HapticFeedback.mediumImpact());
    if (!await _pause(260)) return;

    final rolledDamage = skill.maxDamage > 0
        ? _scalePlayerDamage(_rollBetween(skill.minDamage, skill.maxDamage))
        : 0;
    final actualDamage = math.min(_enemyHp, rolledDamage);
    final recovered = math.min(
      skill.healAmount + (actualDamage * skill.lifestealPercent / 100).round(),
      _playerMaxHp - _playerHp,
    );
    final beforeQi = _playerQi;
    setState(() {
      _enemyHp = _clampEnemyHp(_enemyHp - actualDamage);
      _playerHp = _clampPlayerHp(_playerHp + recovered);
      _playerQi = _clampPlayerQi(_playerQi + skill.energyGain);
      if (skill.burnTurns > 0 && skill.burnDamage > 0) {
        _enemyBurnTurns = math.max(_enemyBurnTurns, skill.burnTurns);
        _enemyBurnDamage = math.max(_enemyBurnDamage, skill.burnDamage);
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
        _enemyExposedExtraDamageMin = math.max(
          _enemyExposedExtraDamageMin,
          skill.exposeExtraDamageMin,
        );
        _enemyExposedExtraDamageMax = math.max(
          _enemyExposedExtraDamageMax,
          skill.exposeExtraDamageMax,
        );
      }
      if (skill.stunTurns > 0) {
        _enemyStunnedByCompanion = math.max(_enemyStunnedByCompanion, 1);
      }
      if (skill.counterMax > 0) {
        _companionCounterMin = skill.counterMin;
        _companionCounterMax = skill.counterMax;
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

  Future<void> _finishHoldListening({bool commit = true}) async {
    if (_speechFinishing) return;
    final asr = _asr;
    if (asr == null) return;

    _speechLimitTimer?.cancel();
    _speechLimitTimer = null;
    final sessionId = _speechSessionId;
    final hadActiveSession =
        _micHeld || _isListening || _speechStarting || asr.isSessionOpen;
    if (!hadActiveSession) return;

    final heldFor = _speechHoldWatch?.elapsed ?? Duration.zero;
    _speechHoldWatch?.stop();
    _speechHoldWatch = null;
    final tooShort =
        commit && heldFor < NovelAsrStreamService.minimumSpeechDuration;
    if (mounted) {
      setState(() {
        _micHeld = false;
        _speechStarting = false;
        _isListening = false;
        _speechFinishing = commit && !tooShort;
      });
    }

    var speechCommitted = false;
    try {
      if (!commit || tooShort) {
        final starting = _speechStartFuture;
        if (starting != null) {
          try {
            await starting;
          } catch (_) {}
        }
        if (sessionId != _speechSessionId) return;
        await asr.cancel();
        if (tooShort && mounted && sessionId == _speechSessionId) {
          _showSpeechMessage('说话太短了', lightweight: true);
        }
      } else {
        final finalText = await (() async {
          final starting = _speechStartFuture;
          if (starting != null) {
            try {
              await starting;
            } catch (_) {}
          }
          if (sessionId != _speechSessionId || !asr.isSessionOpen) return '';
          return asr.stopAndGetFinal();
        })().timeout(_speechTranscriptionTimeout);
        if (finalText.trim().isNotEmpty) {
          _commitSpeechText(sessionId, finalText);
          speechCommitted = true;
        }
      }
    } on TimeoutException {
      unawaited(asr.dispose());
      if (identical(_asr, asr)) {
        final socketService = widget.socketService;
        _asr = socketService == null
            ? null
            : NovelAsrStreamService(socketService: socketService);
      }
      if (commit && mounted && sessionId == _speechSessionId) {
        _showSpeechMessage('识别超时，已放弃', lightweight: true);
      }
    } on NovelAsrStreamException catch (error) {
      if (commit && mounted && sessionId == _speechSessionId) {
        final code = error.code.trim().toUpperCase();
        if (code == 'AUDIO_TOO_SHORT') {
          _showSpeechMessage('说话太短了', lightweight: true);
        } else if (code == 'NO_VOICE' ||
            code == 'EMPTY_RESULT' ||
            code == 'EMPTY_AUDIO') {
          _showSpeechMessage('未识别到语音', lightweight: true);
        } else {
          _showSpeechMessage(error.message);
        }
      }
    } catch (_) {
      if (commit && mounted && sessionId == _speechSessionId) {
        _showSpeechMessage('语音识别失败，请再试一次。');
      }
    } finally {
      if (!mounted || sessionId != _speechSessionId) return;
      setState(() {
        _speechStarting = false;
        _isListening = false;
        _speechFinishing = false;
      });
      if (speechCommitted) _actionFocus.requestFocus();
    }
  }

  void _showSpeechMessage(String message, {bool lightweight = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar(reason: SnackBarClosedReason.hide)
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: lightweight ? TextAlign.center : TextAlign.start,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          duration: Duration(milliseconds: lightweight ? 700 : 1500),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              lightweight ? Colors.transparent : const Color(0xE6111413),
          elevation: lightweight ? 0 : 3,
          width: lightweight ? 128 : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(lightweight ? 0 : 10),
          ),
        ),
      );
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
      minDamage: 10,
      maxDamage: 15,
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

  String _skillDetail(String skillName) {
    final skill = _skillFor(skillName);
    final cooldown = _cooldownFor(skill.name);
    if (cooldown > 0) return '冷却中 · $cooldown回合';
    if (skill.resting && _playerQi >= _playerMaxQi) return '精力已满';
    if (_playerQi < skill.energyCost) return '精力不足 · 需要${skill.energyCost}';
    if (!skill.canSelfKill && _playerHp <= skill.healthCost) {
      return '生命不足 · 需要保留至少1点生命';
    }
    return skill.detail;
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
    if (_speechBusy) {
      _micHeld = false;
      unawaited(_finishHoldListening(commit: false));
    }
    _actionController.clear();
    _playerHp = _playerMaxHp;
    _enemyIndex = 0;
    _enemyHp = _enemyStartingHp;
    _selectedSkillName = null;
    _selectedItemId = null;
    _selectedCompanionId =
        _battleCompanions.isEmpty ? null : _battleCompanions.first.id;
    _selectedCompanionSkillId = null;
    _activeAssistCompanion = null;
    _activeAssistSkill = null;
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
          meta: widget.sceneTitle.trim().isEmpty
              ? '遭遇战'
              : <String>[
                  widget.sceneTitle.trim(),
                  if (widget.sceneSubtitle.trim().isNotEmpty)
                    widget.sceneSubtitle.trim(),
                ].join(' · '),
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
        ? _rollBetween(skill.minDamage, skill.maxDamage) + exposedExtraDamage
        : 0;

    setState(() {
      _tickSkillCooldowns();
      _playerQi = _clampPlayerQi(
        _playerQi - skill.energyCost + skill.energyGain,
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
      hit: hit,
      critical: critical,
      damage: damage,
      burnTurns: skill.burnTurns,
      burnDamage: skill.burnDamage,
      exposes: skill.exposes,
      exposeHitBonus: skill.exposeHitBonus,
      exposeExtraDamageMin: skill.exposeExtraDamageMin,
      exposeExtraDamageMax: skill.exposeExtraDamageMax,
      consumeExpose: exposed,
      piercesGuard: skill.piercesGuard,
      healAmount: skill.healAmount,
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
    final recovered = math.min(
      skill.healAmount,
      _playerMaxHp - healthAfterCost,
    );
    final qiBefore = _playerQi;
    final qiAfter = _clampPlayerQi(
      _playerQi - skill.energyCost + skill.energyGain,
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
    _actionFocus.unfocus();
    _addLog(
      _BattleLogEntry(
        label: skill.name,
        before: recovered > 0
            ? '你运转${skill.name}，恢复了 $recovered 点生命。'
            : skill.resting
                ? '你放缓呼吸并调整状态，恢复了${skill.energyGain}点精力。'
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
          if (skill.energyGain > 0) '精力+${skill.energyGain}',
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

  int _difficultyFor(String action) {
    if (RegExp(r'致命|秒杀|斩首|要害').hasMatch(action)) return 18;
    if (RegExp(r'沙|佯攻|引诱|绕后|地形|观察|破绽').hasMatch(action)) {
      return 10;
    }
    return 12;
  }

  Future<void> _submitCustomAction() async {
    if (!_canAct) return;
    final action = _actionController.text.trim();
    if (action.isEmpty) return;
    _actionController.clear();
    _actionFocus.unfocus();

    if (RegExp(r'防御|格挡|护住|架住').hasMatch(action)) {
      await _useCustomStance(action, dodging: false);
      return;
    }
    if (RegExp(r'闪避|躲开|翻滚|后撤').hasMatch(action)) {
      await _useCustomStance(action, dodging: true);
      return;
    }
    if (RegExp(r'休整|休息|调息|恢复精力').hasMatch(action)) {
      await _useSelfSkill(_skillFor('休整'));
      return;
    }

    final tactical =
        RegExp(r'沙|佯攻|引诱|绕后|地形|观察|破绽').hasMatch(action);
    final lethal = RegExp(r'致命|秒杀|斩首|要害').hasMatch(action);
    final energyCost = lethal ? 20 : (tactical ? 8 : 0);
    if (_playerQi < energyCost) {
      _addLog(
        _BattleLogEntry(
          label: action,
          before: '精力不足，这个行动需要$energyCost点精力。',
          meta: '本回合尚未消耗',
        ),
      );
      return;
    }
    final enemyDodgeBonus = _enemyIntent == _EnemyIntentKind.skill &&
            (_enemyIntentSkill?.dodging ?? false)
        ? _enemyIntentSkill!.enemyHitDifficultyBonus
        : 0;
    final dc = _difficultyFor(action) + enemyDodgeBonus;
    final exposed = _enemyExposedTurns > 0;
    final exposedHitBonus = exposed ? _enemyExposedHitBonus : 0;
    final roll = _d20();
    final total = roll + 4 + exposedHitBonus + _playerHitBonusShift;
    final baseSuccess = roll != 1 && (roll == 20 || total >= dc);
    final equipmentHit = roll != 1 &&
        !baseSuccess &&
        _equipmentHitPercent > 0 &&
        _random.nextInt(100) < _equipmentHitPercent;
    final success = baseSuccess || equipmentHit;
    final baseCritical = success && (roll == 20 || (exposed && roll >= 19));
    final accessoryCritical = success &&
        !baseCritical &&
        _equipmentCriticalPercent > 0 &&
        _random.nextInt(100) < _equipmentCriticalPercent;
    final critical = baseCritical || accessoryCritical;
    final baseDamage = !success
        ? 0
        : lethal
            ? _rollBetween(18, 28)
            : tactical
                ? _rollBetween(7, 11)
                : _rollBetween(5, 8);
    final exposedExtraDamage = success && exposed && _enemyExposedExtraDamageMax > 0
        ? _rollBetween(
            _enemyExposedExtraDamageMin,
            _enemyExposedExtraDamageMax,
          )
        : 0;
    final damage = baseDamage + exposedExtraDamage;

    setState(() {
      _tickSkillCooldowns();
      _playerQi = _clampPlayerQi(_playerQi - energyCost);
    });
    await _resolvePlayerAttack(
      actionName: action,
      hit: success,
      critical: critical,
      damage: damage,
      exposes: tactical,
      exposeHitBonus: tactical ? 2 : 0,
      exposeExtraDamageMin: tactical ? 3 : 0,
      exposeExtraDamageMax: tactical ? 5 : 0,
      consumeExpose: exposed,
      piercesGuard: tactical,
      successText: tactical
          ? '你的判断奏效，敌人的注意力被误导，'
          : lethal
              ? '你冒险抓住了稍纵即逝的要害，'
              : '行动成功，',
      failureText: lethal
          ? '这个动作过于冒险，$_enemyName提前封住了要害。'
          : '$_enemyName识破了你的意图，你没能形成有效攻击。',
      meta: 'D20：$roll + 4'
          '${_modifierLabel(_playerHitBonusShift, '阶位')}'
          '${exposedHitBonus > 0 ? ' + $exposedHitBonus破绽' : ''}'
          '${equipmentHit ? '  ·  装备命中修正' : ''}'
          '${accessoryCritical ? '  ·  饰品暴击' : ''}'
          '  ·  难度：$dc'
          '${energyCost > 0 ? '  ·  精力-$energyCost' : ''}'
          '${tactical ? '  ·  战术有利' : ''}',
    );
  }

  Future<void> _useCustomStance(
    String action, {
    required bool dodging,
  }) async {
    if (!_canAct) return;
    final energyCost = dodging ? 10 : 5;
    if (_playerQi < energyCost) {
      _addLog(
        _BattleLogEntry(
          label: action,
          before: '精力不足，这个行动需要$energyCost点精力。',
          meta: '本回合尚未消耗',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;

      _tickSkillCooldowns();
      _playerQi = _clampPlayerQi(_playerQi - energyCost);
      if (dodging) {
        _playerDodging = true;
        _playerDodgeDifficultyBonus = math.max(_playerDodgeDifficultyBonus, 5);
      } else {
        _playerGuarding = true;
        _playerGuardReductionPercent = math.max(_playerGuardReductionPercent, 50);
      }
    });
    _addLog(
      _BattleLogEntry(
        label: action,
        before: dodging
            ? '你没有贸然出手，而是预判攻击轨迹，准备侧身避让。'
            : '你稳住下盘，将力量集中在防御上。',
        meta: dodging
            ? '精力-10 · 敌方命中难度提高至16'
            : '精力-5 · 下次伤害降低50%',
        tone: _BattleLogTone.success,
      ),
    );
    if (!dodging) {
      unawaited(_playerGuardController.forward(from: 0));
      unawaited(HapticFeedback.lightImpact());
    }
    if (!await _pause(720)) return;
    await _enemyAction();
  }

  Future<void> _resolvePlayerAttack({
    required String actionName,
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
    _actionFocus.unfocus();

    unawaited(_playerAttackController.forward(from: 0));
    // 这是攻击冲刺到“命中点”的时间
    if (!await _pause(245)) return; 

    if (hit) {
      // ===== 新增：卡肉感 (Hit-Stop) =====
      // 在武器接触的瞬间，先给一次短促震动反馈
      if (critical) {
        unawaited(HapticFeedback.heavyImpact());
      } else {
        unawaited(HapticFeedback.selectionClick()); // 轻微的接触感
      }
      
      // 画面冻结：普通攻击卡顿 60ms，暴击卡顿 120ms (模拟武器陷入肉体或护甲的阻力)
      if (!await _pause(critical ? 120 : 60)) return; 
      // =================================

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
    _actionFocus.unfocus();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(.34),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.085),
                  border: Border.all(
                    color: Colors.white.withOpacity(.12),
                    width: .8,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '逃跑',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'WenJinMinchoP0',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '逃跑需要进行判定；如果失败，对手仍会获得本回合行动机会。',
                      style: TextStyle(
                        color: Color(0xAFFFFFFF),
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
                                color: Colors.white.withOpacity(.14),
                                width: .8,
                              ),
                              minimumSize: const Size.fromHeight(40),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
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
                              backgroundColor: Colors.white.withOpacity(.96),
                              foregroundColor: const Color(0xFF111512),
                              minimumSize: const Size.fromHeight(40),
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: const Text(
                              '确认逃跑',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
            ),
          ),
        );
      },
    );

    if (!mounted || confirmed != true || !_canAct) return;
    await _attemptEscape();
  }

  Future<void> _attemptEscape() async {
    if (!_canAct) return;
    setState(() {
      _busy = true;
     
      _tickSkillCooldowns();
    });
    _actionFocus.unfocus();
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
    setState(() {
      _enemyQi = _clampEnemyQi(_enemyQi - skill.energyCost + skill.energyGain);
      _enemyHp = healthAfterCost;
      if (skill.cooldown > 0) {
        _enemySkillCooldowns[skill.name] = skill.cooldown;
      }
    });

    if (skill.isSelfAction) {
      final recovered = math.min(skill.healAmount, _enemyMaxHp - _enemyHp);
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
            if (skill.energyGain > 0) '精力+${skill.energyGain}',
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

    final rolledDamage = _rollBetween(skill.minDamage, skill.maxDamage);
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
      skill.healAmount + (damage * skill.lifestealPercent / 100).round(),
      _enemyMaxHp - _enemyHp,
    );
    setState(() {
      _playerHp = _clampPlayerHp(_playerHp - damage);
      if (recovered > 0) _enemyHp = _clampEnemyHp(_enemyHp + recovered);
      if (skill.burnTurns > 0 && skill.burnDamage > 0) {
        _playerBurnTurns = math.max(_playerBurnTurns, skill.burnTurns);
        _playerBurnDamage = math.max(
          _playerBurnDamage,
          _scaleOpponentDamage(skill.burnDamage),
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
    if (skill.burnTurns > 0 && skill.burnDamage > 0) {
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
      _scalePlayerDamage(_rollBetween(_companionCounterMin, _companionCounterMax)),
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
    final baseMin = _currentEnemy.basicAttackMin.clamp(1, 25).toInt();
    final baseMax = math
        .max(baseMin, _currentEnemy.basicAttackMax)
        .clamp(1, 25)
        .toInt();
    final rolledDamage = heavy
        ? _rollBetween(
            math.max(baseMin + 4, (baseMin * 1.8).round()),
            math.max(baseMax + 8, (baseMax * 2.4).round()),
          )
        : _rollBetween(baseMin, baseMax);
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
    final accent = _battleSkillQualityColor(skill.quality);
    final portrait = companion.portrait.trim().isNotEmpty
        ? companion.portrait
        : companion.avatar;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _companionAssistController,
        builder: (context, _) {
          final t = _companionAssistController.value;
          double phase(double start, double end) =>
              ((t - start) / (end - start)).clamp(0.0, 1.0).toDouble();
          final enter = Curves.easeOutCubic.transform(phase(0, .24));
          final exit = Curves.easeInCubic.transform(phase(.76, 1));
          final opacity =
              (math.min(enter, 1 - exit)).clamp(0.0, 1.0).toDouble();

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final panelHeight = (constraints.maxHeight * (compact ? .34 : .40))
                  .clamp(190.0, 320.0)
                  .toDouble();
              final slideX = -constraints.maxWidth * .58 * (1 - enter) +
                  constraints.maxWidth * .30 * exit;
              final fallback = Center(
                child: Icon(
                  Icons.person_rounded,
                  size: panelHeight * .42,
                  color: accent.withOpacity(.55),
                ),
              );

              return Opacity(
                opacity: opacity,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(color: Colors.black.withOpacity(.18 * opacity)),
                    Center(
                      child: Transform.translate(
                        offset: Offset(slideX, 0),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: panelHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              Positioned.fill(
                                left: -28,
                                right: -28,
                                child: Transform.rotate(
                                  angle: -.035,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: <Color>[
                                          Colors.black.withOpacity(.92),
                                          accent.withOpacity(.34),
                                          Colors.black.withOpacity(.84),
                                        ],
                                        stops: const <double>[0, .58, 1],
                                      ),
                                      border: Border.symmetric(
                                        horizontal: BorderSide(
                                          color: accent.withOpacity(.72),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: compact ? -8 : 20,
                                top: -panelHeight * .14,
                                bottom: -panelHeight * .03,
                                width: constraints.maxWidth * (compact ? .58 : .48),
                                child: _BattleImage(
                                  source: portrait,
                                  fallback: fallback,
                                  logicalWidth: constraints.maxWidth * .5,
                                  maxCacheWidth: 900,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                ),
                              ),
                              Positioned(
                                left: constraints.maxWidth * (compact ? .43 : .46),
                                right: compact ? 18 : 48,
                                top: panelHeight * .22,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        _BattleSkillTypeIcon(
                                          skill: skill,
                                          size: compact ? 20 : 25,
                                          color: accent,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '限定技',
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: compact ? 10 : 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      companion.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: compact ? 12 : 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      skill.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'WenJinMinchoP0',
                                        fontSize: compact ? 22 : 31,
                                        height: 1.08,
                                        fontWeight: FontWeight.w800,
                                        shadows: const <Shadow>[
                                          Shadow(color: Colors.black, blurRadius: 8),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
          _BattleSceneBackground(image: widget.sceneBackground),
          // 正式战斗背景统一压暗到约 64% 亮度。
          // 只压场景背景，不影响角色立绘、战斗特效和白色毛玻璃 UI。
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x5C000000),
            ),
          ),
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _entranceController,
              curve: const Interval(.80, 1.0, curve: Curves.easeOutCubic), // 延后战斗界面出现
            ),
            child: _buildBattleBody(),
          ),
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
          final landscapePhone = constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight <= 560 &&
              constraints.maxWidth <= 1100;

          // 手机横屏使用独立布局：左边专注战斗舞台，右边集中战况与操作。
          // 不再把“舞台 / 记录 / 指令”全部上下堆叠，避免横屏纵向空间被压扁。
          if (landscapePhone) {
            final veryShort = constraints.maxHeight < 360;
            final sidePanelWidth = (constraints.maxWidth * .42)
                .clamp(310.0, 410.0)
                .toDouble();
            return Column(
              children: <Widget>[
                SizedBox(
                  height: veryShort ? 54 : 60,
                  child: _buildStatusBars(landscape: true),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      0,
                      8,
                      veryShort ? 2 : 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: _buildStage(landscape: true),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: sidePanelWidth,
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: _buildHistory(compact: true),
                              ),
                              _buildControls(compact: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // 竖屏 / PC 保持原来的纵向战斗布局。
          return Column(
            children: <Widget>[
              _buildStatusBars(),
              Expanded(
                flex: compactHeight ? 48 : 54,
                child: _buildStage(),
              ),
              Expanded(
                flex: compactHeight ? 24 : 29,
                child: _buildHistory(),
              ),
              _buildControls(compact: compactHeight),
            ],
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

  Widget _buildSceneCaption() {
    final title = widget.sceneTitle.trim();
    final subtitle = widget.sceneSubtitle.trim();
    if (title.isEmpty && subtitle.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _BattleColors.text,
                fontFamily: 'WenJinMinchoP0',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
              ),
            ),
          if (title.isNotEmpty && subtitle.isNotEmpty)
            const SizedBox(height: 4),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _BattleColors.mutedLight,
                fontSize: 8,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage({bool landscape = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 横屏和竖屏分别计算舞台尺寸，但双方始终共用同一组 width / height。
        // 横屏优先按舞台高度放大，保证主角与对手视觉体量一致。
        final height = landscape
            ? (constraints.maxHeight - 2).clamp(150.0, 340.0).toDouble()
            : (constraints.maxHeight - 4).clamp(0.0, 300.0).toDouble();
        final width = landscape
            ? math.min(
                ((constraints.maxWidth - 24) / 2).clamp(105.0, 250.0),
                height * .72,
              ).toDouble()
            : ((constraints.maxWidth - 30) / 2)
                .clamp(105.0, 210.0)
                .toDouble();
        
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, left: 72, right: 72),
                child: _buildSceneCaption(),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 42),
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[Color(0x4A000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            // 恢复为 Row 左右平齐站位，底部对齐 (CrossAxisAlignment.end) 让立绘稳稳踩在地上
            Padding(
              padding: EdgeInsets.fromLTRB(
                landscape ? 4 : 6,
                landscape ? 1 : 3,
                landscape ? 4 : 6,
                landscape ? 0 : 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _AnimatedBattleFighter(
                    name: widget.playerName,
                    portrait: widget.playerPortrait,
                    width: width,
                    height: height,
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    child: _AnimatedBattleFighter(
                      key: ValueKey<int>(_enemyIndex),
                      name: _enemyName,
                      portrait: _enemyPortrait,
                      width: width,
                      height: height,
                      isPlayer: false,
                      attack: _enemyAttackController,
                      damage: _enemyDamageController,
                      breath: _enemyBreathController,
                      dodge: _enemyDodgeController,
                      criticalHit: _enemyDamageCritical,
                      entrance: _entranceController,
                    ),
                  ),
                ],
              ),
            ),
            _buildCombatFeedback(),
          ],
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
              _combatTextOnEnemy ? .56 : -.56,
              -.24,
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
    return Container(
      margin: compact
          ? const EdgeInsets.fromLTRB(2, 0, 2, 4)
          : const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: compact
          ? const EdgeInsets.fromLTRB(8, 5, 8, 5)
          : const EdgeInsets.fromLTRB(10, 9, 10, 7),
      decoration: const BoxDecoration(
        // 去除生硬边框，改为轻微的渐变，避免文字看不清
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x00000000), // 顶部完全透明
            Color(0x1A000000),
            Color(0x3D000000), // 底部微暗，自然融入下方操作区
          ],
        ),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _logRevision,
        builder: (context, _, __) {
          if (_logs.isEmpty) return const SizedBox.shrink();
          final latest = _logs.last;
          final historyStart = math.max(0, _logs.length - 10).toInt();
          final historyEnd = math.max(historyStart, _logs.length - 1).toInt();
          final history = _logs.sublist(historyStart, historyEnd);
          final latestIsIntent = latest.label == '敌方意图';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(2, 0, 2, compact ? 4 : 7),
                child: Row(
                  children: <Widget>[
                    Text(
                      '战况 · 第$_round回合',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.48),
                        fontSize: compact ? 8.9 : 9.6,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .65,
                      ),
                    ),
                    const Spacer(),
                    if (!latestIsIntent)
                      Text(
                        '敌方意图 · $_enemyIntentTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _BattleColors.enemy.withOpacity(.72),
                          fontSize: compact ? 8.8 : 9.4,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .35,
                        ),
                      ),
                  ],
                ),
              ),
              _BattleCurrentStatus(entry: latest),
              if (history.isNotEmpty) ...<Widget>[
                SizedBox(height: compact ? 3 : 5),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const <PointerDeviceKind>{
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView.separated(
                      controller: _logController,
                      padding: const EdgeInsets.fromLTRB(2, 3, 2, 5),
                      physics: const BouncingScrollPhysics(),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => SizedBox(height: compact ? 3 : 5),
                      itemBuilder: (_, index) {
                        final age = history.length <= 1
                            ? 1.0
                            : (index + 1) / history.length;
                        return Opacity(
                          opacity: .24 + .46 * age,
                          child: _BattleLogTile(
                            key: ValueKey<String>(
                              'battle-history-$index-${history[index].label}',
                            ),
                            entry: history[index],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
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
    _actionFocus.unfocus();
    setState(() {
      _selectedCompanionId = companion.id;
      _selectedCompanionSkillId = null;
      _selectedSkillName = null;
      _selectedItemId = null;
      _activeCategory = _BattleCommandCategory.companions;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  Widget _buildCompanionAvatarStrip() {
    return Row(
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
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: '${companion.name} · 剩余$remaining个限定技',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _canAct ? () => _openCompanionSkills(companion) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: selected
                      ? _BattleColors.energy.withOpacity(.15)
                      : Colors.black.withOpacity(.24),
                  border: Border.all(
                    color: selected
                        ? _BattleColors.energy
                        : Colors.white.withOpacity(allUsed ? .04 : .14),
                    width: selected ? 1.4 : .8,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Opacity(
                      opacity: allUsed ? .34 : 1,
                      child: ClipRect(
                        child: source.isEmpty
                            ? fallback
                            : _BattleImage(
                                source: source,
                                fallback: fallback,
                                logicalWidth: 30,
                                maxCacheWidth: 120,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        alignment: Alignment.center,
                        color: allUsed
                            ? const Color(0xCC343840)
                            : const Color(0xD90B1423),
                        child: Text(
                          '$remaining',
                          style: TextStyle(
                            color: allUsed
                                ? Colors.white38
                                : _BattleColors.energy,
                            fontSize: 7.5,
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
        );
      }).toList(growable: false),
    );
  }

  Widget _buildControls({required bool compact}) {
    final bool isSkills = _activeCategory == _BattleCommandCategory.skills;
    final bool isItems = _activeCategory == _BattleCommandCategory.items;
    final bool isCompanions =
        _activeCategory == _BattleCommandCategory.companions;

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
        color: Colors.transparent, // 移除暗色背景和顶部分界线，彻底透明化
      ),
      padding: EdgeInsets.only(
        top: compact ? 6 : 15,
        bottom: math.max(
          compact ? 4.0 : 12.0,
          MediaQuery.viewPaddingOf(context).bottom,
        ).toDouble(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 18),
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
                            symbol: '✦',
                            isSelected: isSkills,
                            onTap: () {
                              if (_canAct) {
                                _toggleCategory(_BattleCommandCategory.skills);
                              }
                            },
                          ),
                          const SizedBox(width: 7),
                          _buildMenuTab(
                            label: '道具',
                            symbol: '▣',
                            isSelected: isItems,
                            onTap: () {
                              if (_canAct) {
                                _toggleCategory(_BattleCommandCategory.items);
                              }
                            },
                          ),
                          const SizedBox(width: 7),
                          _buildEscapeAction(),
                          if (_battleCompanions.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 7),
                            _buildCompanionAvatarStrip(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: canConfirm ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !canConfirm,
                    child: FilledButton.icon(
                      onPressed: canConfirm ? _handleConfirm : null,
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: const Text('确定'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(.96),
                        foregroundColor: const Color(0xFF111512),
                        elevation: 0,
                        minimumSize: const Size(76, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 6 : 13),
          SizedBox(
            height: 140,
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
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(.095)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(.16)
                : Colors.transparent,
            width: .7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 17,
              height: 17,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -.4),
                  child: Text(
                    symbol,
                    textAlign: TextAlign.center,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withOpacity(.94)
                          : Colors.white.withOpacity(.42),
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: TextStyle(
                color: isSelected
                    ? Colors.white.withOpacity(.94)
                    : Colors.white.withOpacity(.52),
                fontSize: 12.5,
                height: 1,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEscapeAction() {
    return GestureDetector(
      onTap: _canAct ? () => unawaited(_confirmEscape()) : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: _canAct ? 1 : .42,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0x26000000),
            border: Border.all(
              color: Colors.white.withOpacity(.07),
              width: .7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              Icon(
                Icons.directions_run_rounded,
                size: 14,
                color: Colors.white54,
              ),
              SizedBox(width: 5),
              Text(
                '逃跑',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .55,
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final scale = .97 + (.03 * value);
        return Opacity(
          opacity: value,
          child: ColoredBox(
            color: const Color(0x52000000),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: Transform.scale(
                  scale: scale,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 340,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.075),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 0.85,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'WenJinMinchoP0',
                fontSize: 21,
                fontWeight: FontWeight.w600,
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
                          foregroundColor: Colors.white.withOpacity(0.72),
                          backgroundColor: Colors.white.withOpacity(0.035),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.12),
                              width: 0.8,
                            ),
                          ),
                        ),
                        child: const Text(
                          '重新挑战',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .4),
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
                        backgroundColor: _BattleColors.accent,
                        foregroundColor: const Color(0xFF0F140F),
                        disabledBackgroundColor: Colors.white.withOpacity(0.05),
                        disabledForegroundColor: Colors.white.withOpacity(0.30),
                        padding: EdgeInsets.zero,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: Text(
                        _settlingItems
                            ? '结算中…'
                            : outcome == YoranBattleOutcome.defeat
                                ? '接受失败并继续'
                                : '继续剧情',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
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
        ),
      ),
    );
  }
}

class _BattleColors {
  static const Color background = Color(0xFF0A0C0B);
  static const Color surface = Colors.transparent;
  static const Color surfaceStrong = Color(0x0DFFFFFF);
  static const Color surfaceElevated = Colors.transparent;
  static const Color controlSurface = Colors.transparent;
  static const Color inputSurface = Color(0x0DFFFFFF);
  
  static const Color border = Colors.transparent;
  static const Color borderBright = Color(0x1AFFFFFF);
  static const Color accentBorder = Color(0x33FFFFFF);
  static const Color enemyBorder = Colors.transparent;
  
  static const Color text = Color(0xFFF2F5F8);
  static const Color mutedLight = Color(0xFFC0CDC6);
  static const Color muted = Color(0xFF8A9A91);
  
  static const Color accent = Color(0xFF81F670);
  static const Color accentSoft = Color(0x2681F670);
  static const Color player = Color(0xFF81F670);
  static const Color energy = Color(0xFF4DA3FF);
  static const Color warning = Color(0xFFF4C873);
  static const Color enemy = Color(0xFFFF7474);
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
      child: Transform.scale(scale: 1.025, child: imageWidget),
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
    final listenables = <Listenable>[damageAnimation];

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, child) {
        final progress = (hp / maxHp).clamp(0.0, 1.0).toDouble();
        final qiProgress = (qi / maxQi).clamp(0.0, 1.0).toDouble();
        final sideColor = alignEnd ? _BattleColors.enemy : _BattleColors.player;

        Color hpColor;
        if (progress > 0.5) {
          hpColor = sideColor;
        } else if (progress > 0.25) {
          hpColor = _BattleColors.warning;
        } else {
          hpColor = _BattleColors.enemy;
        }

        final damageWave = math.sin(damageAnimation.value * math.pi * 6) *
            (1 - damageAnimation.value);
        final shakeOffset = damageWave * 3.5;
        final flashOpacity = (math.sin(damageAnimation.value * math.pi).clamp(0.0, 1.0) * 0.22).toDouble();
        final avatarFallback = Center(
          child: Text(
            name.isNotEmpty ? String.fromCharCode(name.runes.first) : '?',
            style: TextStyle(
              color: sideColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        Widget avatarWidget = AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x36000000),
            border: Border.all(
              color: Colors.white.withOpacity(0.09),
              width: 0.75,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: portrait.isNotEmpty
              ? _BattleImage(
                  source: portrait,
                  fallback: avatarFallback,
                  logicalWidth: 36,
                  maxCacheWidth: 144,
                )
              : avatarFallback,
        );

        Widget infoWidget = Expanded(
          child: Column(
            crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text( 
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _BattleColors.text,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w500, 
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 4,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        width: constraints.maxWidth,
                        color: _BattleColors.inputSurface,
                      ),
                      Stack(
                        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                        children: <Widget>[
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutCubic,
                            width: constraints.maxWidth * progress,
                            color: hpColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2), 
              SizedBox(
                height: 1.5,
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        width: constraints.maxWidth,
                        color: Colors.white.withOpacity(0.04), 
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * qiProgress,
                        decoration: BoxDecoration(
                          color: alignEnd 
                              ? _BattleColors.enemy.withOpacity(0.7) 
                              : _BattleColors.energy,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: (alignEnd ? _BattleColors.enemy : _BattleColors.energy)
                                  .withOpacity(0.6),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (enemyIndex != null && enemyCount > 1) ...<Widget>[
                const SizedBox(height: 6),
                _EnemyRosterIndicator(
                  currentIndex: enemyIndex!,
                  count: enemyCount,
                ),
              ],
            ],
          ),
        );

        Widget content = Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: alignEnd
              ? <Widget>[infoWidget, const SizedBox(width: 10), avatarWidget]
              : <Widget>[avatarWidget, const SizedBox(width: 10), infoWidget],
        );

        if (flashOpacity > 0) {
          content = ColorFiltered(
            colorFilter: ColorFilter.mode(
              const Color(0xFFF56C6C).withOpacity(flashOpacity),
              BlendMode.srcATop,
            ),
            child: content,
          );
        }

        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.transparent, // 取消底层的大黑底与边框
            ),
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
    final image = ClipRect(
      child: _BattleImage(
        source: portrait,
        fallback: fallback,
        logicalWidth: width,
        maxCacheWidth: 900,
        // 双方立绘共用固定画布，并统一按高度适配。
        // 相比 contain，可避免一张图因为原始宽高比不同而显得明显更矮。
        fit: BoxFit.fitHeight,
        alignment: Alignment.bottomCenter,
      ),
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
  const _BattleCurrentStatus({required this.entry});

  final _BattleLogEntry entry;

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isIntent)
            Row(
              children: <Widget>[
                Icon(
                  Icons.visibility_outlined,
                  size: 12.5,
                  color: _BattleColors.enemy.withOpacity(.72),
                ),
                const SizedBox(width: 6),
                Text(
                  '敌方意图',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.52),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    entry.before,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _BattleColors.enemy.withOpacity(.92),
                      fontSize: 13.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .25,
                    ),
                  ),
                ),
              ],
            )
          else
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: enemy
                      ? Colors.white.withOpacity(.82)
                      : Colors.white.withOpacity(.92),
                  fontSize: 13.1,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0x70000000), blurRadius: 2),
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
            ),
          if (entry.meta.isNotEmpty && !isIntent) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              entry.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(.35),
                fontSize: 8.9,
                height: 1.15,
                fontWeight: FontWeight.w500,
                letterSpacing: .2,
              ),
            ),
          ],
        ],
      ),
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
  });

  final List<YoranBattleSkill> skills;
  final Map<String, int> cooldowns;
  final int playerQi;
  final int playerHp;
  final bool enabled;
  final String? selectedSkillName;
  final ValueChanged<String> onSkillSelected;

  @override
  State<_BattleCardHand> createState() => _BattleCardHandState();
}

class _BattleCardHandState extends State<_BattleCardHand>
    with SingleTickerProviderStateMixin {
  static const double _cardSpacing = 60.0;
  static const double _maxAngle = 0.42;
  static const double _minScale = 0.82;

  late final AnimationController _snapController;
  double _scrollPosition = 0.0;
  double _snapFrom = 0.0;
  double _snapTo = 0.0;

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

  void _animateToCard(double target) {
    final next = _clampPosition(target.roundToDouble());
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _snapController.stop();
      },
      onHorizontalDragUpdate: count <= 1
          ? null
          : (details) {
              setState(() {
                // 手指向左拖，轮盘向下一张技能滚动。
                _scrollPosition = _clampPosition(
                  _scrollPosition - details.delta.dx / _cardSpacing,
                );
              });
            },
      onHorizontalDragEnd: count <= 1
          ? null
          : (details) {
              // 根据松手速度做一小段惯性预测，再吸附到最近的一张。
              final velocity = details.primaryVelocity ?? 0.0;
              final projected = _scrollPosition - velocity / 950.0;
              _animateToCard(projected);
            },
      onHorizontalDragCancel: count <= 1
          ? null
          : () => _animateToCard(_scrollPosition),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: drawOrder.map((index) {
          final skill = widget.skills[index];
          final cooldown = widget.cooldowns[skill.name] ?? 0;
          final isSelected = skill.name == widget.selectedSkillName;

          final canUse = widget.enabled &&
              cooldown <= 0 &&
              (!skill.resting || widget.playerQi < 100) &&
              widget.playerQi >= skill.energyCost &&
              (skill.canSelfKill || widget.playerHp > skill.healthCost);

          // 核心：每一帧都根据“卡片索引 - 当前轮盘位置”重新计算扇形。
          // 因此拖动 2.0 -> 2.5 -> 3.0 时，所有卡都会一起旋转滚动。
          final double relative = index - _scrollPosition;
          final double distance = relative.abs();
          final double baseAngle =
              (relative * 0.12).clamp(-_maxAngle, _maxAngle).toDouble();
          final double offsetX = relative * _cardSpacing;
          final double baseOffsetY = math.min(distance * distance * 4.5, 58.0);
          final double baseScale =
              (1.0 - distance * 0.045).clamp(_minScale, 1.0).toDouble();

          return Positioned(
            key: ValueKey('card_${skill.name}'),
            bottom: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: isSelected ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              builder: (context, t, child) {
                // 选中时仍保留原来的直立 + 上弹效果。
                final double currentAngle = baseAngle * (1 - t);
                final double currentOffsetY =
                    -baseOffsetY + (44.0 + baseOffsetY) * t;
                final double currentScale = _mix(baseScale, 1.025, t);

                return Transform.translate(
                  offset: Offset(offsetX, -currentOffsetY),
                  child: Transform.scale(
                    scale: currentScale,
                    child: Transform.rotate(
                      angle: currentAngle,
                      child: child,
                    ),
                  ),
                );
              },
              child: GestureDetector(
                onTap: () => widget.onSkillSelected(skill.name),
                behavior: HitTestBehavior.opaque,
                child: _BattleCard(
                  skill: skill,
                  cooldown: cooldown,
                  canUse: canUse,
                  isSelected: isSelected,
                  playerQi: widget.playerQi,
                  playerHp: widget.playerHp,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 单张卡牌的美术呈现
/// 单张卡牌：烟熏半透明 HUD + 白色选中态。
class _BattleCard extends StatelessWidget {
  const _BattleCard({
    super.key,
    required this.skill,
    required this.cooldown,
    required this.canUse,
    required this.isSelected,
    required this.playerQi,
    required this.playerHp,
  });

  final YoranBattleSkill skill;
  final int cooldown;
  final bool canUse;
  final bool isSelected;
  final int playerQi;
  final int playerHp;

  @override
  Widget build(BuildContext context) {
    // 判定不可用的具体原因
    final bool isEnergyShort = playerQi < skill.energyCost;
    final bool isHpShort = !skill.canSelfKill && playerHp <= skill.healthCost;
    final bool isLocked = !canUse;

    // 交互选中统一使用白色
    Color borderColor;
    if (isSelected) {
      borderColor = Colors.white.withOpacity(0.78);
    } else if (isLocked) {
      borderColor = Colors.white.withOpacity(0.045);
    } else {
      borderColor = Colors.white.withOpacity(0.085);
    }

    Color bgColor = isSelected
        ? Colors.white.withOpacity(0.12)
        : (isLocked ? const Color(0x24000000) : const Color(0x3D000000));

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isLocked && !isSelected ? 0.65 : 1.0, 
          child: ClipRect( // 新增毛玻璃裁剪区
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // 增加毛玻璃特效
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 84,  
                height: 120, 
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.zero, 
                  color: bgColor, 
                  border: Border.all(
                    color: borderColor,
                    width: isSelected ? 0.95 : 0.75,
                  ),
                  boxShadow: null,
                ),
                child: Stack(
                  children: <Widget>[
                    // 左上角：精力消耗
                    if (skill.energyCost > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Text(
                          '${skill.energyCost}',
                          style: TextStyle(
                            color: isEnergyShort 
                                ? _BattleColors.enemy 
                                : (isSelected ? Colors.white : Colors.white70),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            shadows: null,
                          ),
                        ),
                      ),
                    // 右上角：CD冷却
                    if (cooldown > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Text(
                          '${cooldown}CD',
                          style: TextStyle(
                            color: _BattleColors.enemy.withOpacity(0.82),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _BattleSkillTypeIcon(
                          skill: skill,
                          size: 17,
                          color: isLocked
                              ? Colors.white24
                              : (isSelected
                                  ? Colors.white
                                  : _battleSkillQualityColor(skill.quality)),
                        ),
                      ),
                    ),
                    // 技能名称
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 19, 4, 0),
                        child: Text(
                          skill.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isLocked 
                                ? Colors.white30 
                                : (isSelected ? Colors.white : Colors.white.withOpacity(0.85)), 
                            fontFamily: 'WenJinMinchoP0',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
        // 选中时的悬浮描述
        Positioned(
          bottom: -30, 
          width: 140, 
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: isSelected ? 1.0 : 0.0,
            child: IgnorePointer(
              child: Text(
                skill.detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70, 
                  fontSize: 10,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
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

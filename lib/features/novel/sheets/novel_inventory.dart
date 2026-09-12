part of '../novel_sheets.dart';

// ============================================================================
// 背包页
// ============================================================================

const Color _inventoryInk = Color(0xFF090E1A);
const Color _inventoryInkSoft = Color(0xFF111A2C);
const Color _inventoryBlue = Color(0xFF506FEF);
const Color _inventoryGold = Color(0xFFC9B778);
const Color _inventoryGoldSoft = Color(0xFF86794D);
const Color _inventoryHighEnhancement = Color(0xFFE75B62);
const Color _inventoryText = Color(0xFFF2F0E8);
const Color _inventoryTextSoft = Color(0xFFB9C0D0);
const Color _inventoryMuted = Color(0xFF737C91);


enum _InventoryViewportMode { portrait, landscape, desktop }

_InventoryViewportMode _inventoryViewportMode(
  BoxConstraints constraints,
  bool desktopMode,
) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  final phoneLandscape =
      width > height && height <= 540 && width <= 1100;
  if (phoneLandscape) return _InventoryViewportMode.landscape;

  final phonePortrait = height >= width && width <= 640;
  if (phonePortrait) return _InventoryViewportMode.portrait;

  if (desktopMode) return _InventoryViewportMode.desktop;
  return width > height
      ? _InventoryViewportMode.landscape
      : _InventoryViewportMode.portrait;
}

Future<void> showNovelInventorySheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('inventory', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _GameStyleInventoryPage(controller: controller),
    );
  });
}

class NovelInventoryTab extends StatelessWidget {
  const NovelInventoryTab({
    super.key,
    required this.controller,
  });

  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    return _GameStyleInventoryPage(
      controller: controller,
      embedded: true,
    );
  }
}

class _GameStyleSkillView {
  const _GameStyleSkillView({
    required this.name,
    this.mastery = '',
    this.description = '',
    this.isAbility = false,
  });

  final String name;
  final String mastery;
  final String description;
  final bool isAbility;
}

class _GameStyleInventoryPage extends StatefulWidget {
  const _GameStyleInventoryPage({
    required this.controller,
    this.embedded = false,
  });

  final NovelGameController controller;
  final bool embedded;

  @override
  State<_GameStyleInventoryPage> createState() => _GameStyleInventoryPageState();
}

class _GameStyleInventoryPageState extends State<_GameStyleInventoryPage> {
  bool loading = true;
  String busy = '';
  bool _skillsExpanded = false;
  bool _equippedExpanded = false;
  int _filterIndex = 0;

  static const Set<String> _wearableTypes = <String>{
    'weapon',
    'wearable',
    'armor',
    'accessory',
    'head',
    'face',
    'upper',
    'lower',
    'feet',
    'back',
    'handheld',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await Future.wait<void>(<Future<void>>[
      widget.controller.refreshInventory(notify: false),
      widget.controller.refreshCharacterStatus(notify: false),
    ]);
    if (mounted) setState(() => loading = false);
  }

  List<NovelInventoryItem> _allItems(NovelInventoryData data) {
    final result = <NovelInventoryItem>[];
    final seen = <String>{};
    for (final item in <NovelInventoryItem>[
      ...data.storyItems,
      ...data.consumables,
    ]) {
      final key = item.id.trim().isNotEmpty
          ? 'id:${item.id.trim()}'
          : '${item.itemType.trim()}:${item.name.trim()}';
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  String _itemSlot(NovelInventoryItem item) {
    final raw = item.raw;
    final explicit = stringValue(raw['slot'] ?? raw['wear_slot']).trim().toLowerCase();
    if (explicit.isNotEmpty) {
      if (explicit.contains('头')) return 'head';
      if (explicit.contains('面')) return 'face';
      if (explicit.contains('上身') || explicit.contains('上装') || explicit.contains('衣')) return 'upper';
      if (explicit.contains('下身') || explicit.contains('下装') || explicit.contains('裤')) return 'lower';
      if (explicit.contains('足') || explicit.contains('脚') || explicit.contains('鞋')) return 'feet';
      if (explicit.contains('背') || explicit.contains('披风') || explicit.contains('翅膀')) return 'back';
      if (explicit.contains('手持') || explicit.contains('武器') || explicit == 'weapon' || explicit == 'handheld') return 'handheld';
      if (explicit.contains('饰') || explicit.contains('首饰') || explicit.contains('项链') || explicit.contains('戒指')) return 'accessory';
      return explicit;
    }
    return switch (item.itemType.trim().toLowerCase()) {
      'weapon' => 'handheld',
      'wearable' || 'armor' => 'upper',
      'accessory' => 'accessory',
      _ => '',
    };
  }

  bool _isWearable(NovelInventoryItem item) {
    return item.isEquipped ||
        _wearableTypes.contains(item.itemType.trim().toLowerCase()) ||
        _itemSlot(item).isNotEmpty;
  }

  String _typeLabel(String type) {
    return switch (type.trim().toLowerCase()) {
      'consumable' => '消耗品',
      'material' => '材料',
      'quest' => '任务物品',
      'gift' => '赠礼',
      'blind_box' => '特殊物品',
      'lucky_card' => '特殊物品',
      'weapon' => '手持',
      'wearable' || 'armor' => '穿戴',
      'accessory' => '饰品',
      _ => '物品',
    };
  }

  String _displayTypeLabel(NovelInventoryItem item) {
    return switch (_itemSlot(item)) {
      'handheld' => '手持',
      'head' => '头部',
      'face' => '面部',
      'upper' => '上身',
      'lower' => '下身',
      'feet' => '足部',
      'back' => '背部',
      'accessory' => '饰品',
      _ => _typeLabel(item.itemType),
    };
  }

  int _equipmentQuality(NovelInventoryItem item) {
    return _inventoryItemQuality(item);
  }

  int _equipmentEnhancement(NovelInventoryItem item) {
    final raw = item.raw;
    return intValue(
      raw['enhancement_level'] ?? raw['enhancementLevel'],
    ).clamp(0, 10).toInt();
  }

  int _enhanceStoneQuantity() {
    for (final item in widget.controller.inventory.consumables) {
      if (item.itemType.trim().toLowerCase() == 'enhance_stone') {
        return item.quantity.clamp(0, 999999).toInt();
      }
    }
    return 0;
  }

  int _enhancementForSlot(
    List<NovelInventoryItem> equipped,
    String slot,
  ) {
    var level = 0;
    for (final item in equipped) {
      if (_itemSlot(item) == slot) {
        level = math.max(level, _equipmentEnhancement(item));
      }
    }
    return level.clamp(0, 10).toInt();
  }

  int _accessoryEnhancementTotal(List<NovelInventoryItem> equipped) {
    final levels = equipped
        .where((item) => _itemSlot(item) == 'accessory')
        .map(_equipmentEnhancement)
        .toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return levels.take(3).fold<int>(0, (sum, value) => sum + value)
        .clamp(0, 30)
        .toInt();
  }

  String _enhancementEffect(NovelInventoryItem item) {
    return _enhancementEffectForLevel(item, _equipmentEnhancement(item));
  }

  String _enhancementEffectForLevel(NovelInventoryItem item, int rawLevel) {
    final level = rawLevel.clamp(0, 10).toInt();
    if (level <= 0) return '尚未强化';
    return switch (_itemSlot(item)) {
      'handheld' => '威力额外 +${level * 3}%',
      'upper' => '生命额外 +${level * 3}%',
      'face' => '精力额外 +${level * 3}%',
      'lower' => '防护额外 +$level%',
      'head' => '精准额外 +$level%',
      'feet' => '机动额外 +${level ~/ 2}%',
      'accessory' => '爆发强化贡献约 +${(level * .30).toStringAsFixed(1)}%',
      'back' => '携行额外 +${level ~/ 5}次',
      _ => '强化 +$level',
    };
  }

  static const Map<String, String> _affixDisplayNames = <String, String>{
    'attack_percent': '威力',
    'max_hp_percent': '生命',
    'max_energy_percent': '精力',
    'defense_percent': '防护',
    'hit_percent': '精准',
    'dodge_percent': '机动',
    'critical_percent': '爆发',
  };

  static const Map<String, int> _affixCaps = <String, int>{
    'attack_percent': 5,
    'max_hp_percent': 5,
    'max_energy_percent': 5,
    'defense_percent': 3,
    'hit_percent': 3,
    'dodge_percent': 2,
    'critical_percent': 3,
  };

  Map<String, int> _itemAffixes(NovelInventoryItem item) {
    final result = <String, int>{};

    void add(dynamic rawKey, dynamic rawValue) {
      final key = stringValue(rawKey).trim().toLowerCase();
      final cap = _affixCaps[key];
      if (cap == null) return;
      final value = intValue(rawValue).clamp(0, cap).toInt();
      if (value <= 0) return;
      result[key] = math.max(result[key] ?? 0, value);
    }

    final raw = item.raw['affixes'] ??
        item.raw['affix_stats'] ??
        item.raw['affixStats'];
    if (raw is Map) {
      raw.forEach(add);
    } else if (raw is List) {
      for (final entry in raw.take(5)) {
        if (entry is! Map) continue;
        add(entry['key'] ?? entry['type'], entry['value']);
      }
    }
    return result;
  }

  int _affixTotal(
    List<NovelInventoryItem> equipped,
    String key, {
    required int cap,
  }) {
    var total = 0;
    for (final item in equipped) {
      total += _itemAffixes(item)[key] ?? 0;
    }
    return total.clamp(0, cap).toInt();
  }

  int _accessoryQualityTotal(List<NovelInventoryItem> equipped) {
    final qualities = equipped
        .where((item) => _itemSlot(item) == 'accessory')
        .map(_equipmentQuality)
        .toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    return qualities.take(3).fold<int>(0, (sum, value) => sum + value)
        .clamp(0, 30)
        .toInt();
  }

  String _baseEquipmentEffect(NovelInventoryItem item) {
    final quality = _equipmentQuality(item);
    return switch (_itemSlot(item)) {
      'handheld' => '威力 +${quality * 10}%',
      'upper' => '生命 +${quality * 10}%',
      'face' => '精力 +${quality * 10}%',
      'lower' => '防护 +${quality * 5}%',
      'head' => '精准 +${quality * 3}%',
      'feet' => '机动 +$quality%',
      'accessory' => '爆发 +$quality%',
      'back' => '携行 +$quality次',
      _ => '无固定战斗加成',
    };
  }

  int _qualityForSlot(
    List<NovelInventoryItem> equipped,
    String slot, {
    bool stack = false,
  }) {
    var quality = 0;
    for (final item in equipped) {
      if (_itemSlot(item) == slot) {
        if (stack) {
          quality += (_equipmentQuality(item) / 2).ceil();
        } else {
          quality = math.max(quality, _equipmentQuality(item));
        }
      }
    }
    return quality.clamp(0, 10).toInt();
  }

  Widget _equipmentBonusPanel(
    List<NovelInventoryItem> equipped, {
    bool dense = false,
  }) {
    final upperEnhancement = _enhancementForSlot(equipped, 'upper');
    final faceEnhancement = _enhancementForSlot(equipped, 'face');
    final handheldEnhancement = _enhancementForSlot(equipped, 'handheld');
    final lowerEnhancement = _enhancementForSlot(equipped, 'lower');
    final headEnhancement = _enhancementForSlot(equipped, 'head');
    final feetEnhancement = _enhancementForSlot(equipped, 'feet');
    final backEnhancement = _enhancementForSlot(equipped, 'back');
    final accessoryEnhancementTotal =
        _accessoryEnhancementTotal(equipped);

    final hp = (_qualityForSlot(equipped, 'upper') * 10 +
            upperEnhancement * 3 +
            _affixTotal(equipped, 'max_hp_percent', cap: 40))
        .clamp(0, 170)
        .toInt();
    final energy = (_qualityForSlot(equipped, 'face') * 10 +
            faceEnhancement * 3 +
            _affixTotal(equipped, 'max_energy_percent', cap: 40))
        .clamp(0, 170)
        .toInt();
    final attack = (_qualityForSlot(equipped, 'handheld') * 10 +
            handheldEnhancement * 3 +
            _affixTotal(equipped, 'attack_percent', cap: 40))
        .clamp(0, 170)
        .toInt();
    final defense = (_qualityForSlot(equipped, 'lower') * 5 +
            lowerEnhancement +
            _affixTotal(equipped, 'defense_percent', cap: 15))
        .clamp(0, 65)
        .toInt();
    final hit = (_qualityForSlot(equipped, 'head') * 3 +
            headEnhancement +
            _affixTotal(equipped, 'hit_percent', cap: 24))
        .clamp(0, 45)
        .toInt();
    final dodge = (_qualityForSlot(equipped, 'feet') +
            (feetEnhancement ~/ 2) +
            _affixTotal(equipped, 'dodge_percent', cap: 16))
        .clamp(0, 25)
        .toInt();
    final accessoryEnhancementCritical =
        (accessoryEnhancementTotal * .30).round();
    final critical = (_accessoryQualityTotal(equipped) +
            accessoryEnhancementCritical +
            _affixTotal(equipped, 'critical_percent', cap: 24))
        .clamp(0, 50)
        .toInt();
    final backQuality = _qualityForSlot(equipped, 'back');
    final itemUses = 2 + backQuality + (backEnhancement ~/ 5);

    final bonuses = <_EquipmentBonusValue>[
      _EquipmentBonusValue('生命', hp, 170, '+$hp%'),
      _EquipmentBonusValue('精力', energy, 170, '+$energy%'),
      _EquipmentBonusValue('威力', attack, 170, '+$attack%'),
      _EquipmentBonusValue('防护', defense, 65, '+$defense%'),
      _EquipmentBonusValue('精准', hit, 45, '+$hit%'),
      _EquipmentBonusValue('机动', dodge, 25, '+$dodge%'),
      _EquipmentBonusValue('爆发', critical, 50, '+$critical%'),
      _EquipmentBonusValue('携行', itemUses - 2, 12, '${itemUses}次'),
    ];

    return Padding(
      padding: EdgeInsets.only(top: dense ? 8 : 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: dense ? 5 : 8,
          crossAxisSpacing: dense ? 10 : 16,
          mainAxisExtent: dense ? 14 : 16,
        ),
        itemCount: bonuses.length,
        itemBuilder: (context, index) {
          final bonus = bonuses[index];
          return _EquipmentBonusMeter(
            label: bonus.label,
            level: bonus.level,
            valueText: bonus.valueText,
          );
        },
      ),
    );
  }

  List<_GameStyleSkillView> _skills(NovelCharacter? host) {
    final status = host?.status ?? const <String, dynamic>{};
    final result = <_GameStyleSkillView>[];
    final names = <String>{};
    final rawSkills = status['skills'];
    if (rawSkills is List) {
      for (final raw in rawSkills) {
        if (raw is String) {
          final name = raw.trim();
          if (name.isNotEmpty && names.add(name)) {
            result.add(_GameStyleSkillView(name: name));
          }
          continue;
        }
        if (raw is Map) {
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          final name = stringValue(map['name']).trim();
          if (name.isEmpty || !names.add(name)) continue;
          result.add(_GameStyleSkillView(
            name: name,
            mastery: stringValue(map['mastery']).trim(),
            description: stringValue(map['description']).trim(),
          ));
        }
      }
    }
    final rawAbilities = status['abilities'];
    if (rawAbilities is List) {
      for (final raw in rawAbilities) {
        final name = stringValue(raw).trim();
        if (name.isNotEmpty && names.add(name)) {
          result.add(_GameStyleSkillView(name: name, isAbility: true));
        }
      }
    }
    return result;
  }

  Future<void> _toggleWear(NovelInventoryItem item) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = item.id);
    try {
      await widget.controller.setEquipped(item, !item.isEquipped);
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  int _enhancementSuccessRateForTarget(int targetLevel) {
    return switch (targetLevel.clamp(1, 10).toInt()) {
      1 => 100,
      2 => 100,
      3 => 95,
      4 => 90,
      5 => 85,
      6 => 75,
      7 => 65,
      8 => 50,
      9 => 35,
      10 => 20,
      _ => 0,
    };
  }

  Future<JsonMap> _requestEnhanceEquipment(NovelInventoryItem item) {
    // 正式链路：Inventory UI -> NovelGameController -> NovelBackend -> HTTP -> Gateway -> Router。
    return widget.controller.enhanceNovelEquipment(item);
  }

  Future<void> _showItemDetail(NovelInventoryItem item) async {
    final wearable = _isWearable(item);
    final quality = _inventoryItemQuality(item);
    final qualityColor = _inventoryQualityColor(quality);
    var enhancement = _equipmentEnhancement(item);
    var enhanceStoneQuantity = _enhanceStoneQuantity();
    var enhancing = false;
    var flashText = '';
    bool? flashSuccess;
    var flashSerial = 0;
    final affixes = _itemAffixes(item).entries.toList(growable: false);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情',
      barrierColor: Colors.black.withOpacity(.72),
      pageBuilder: (outerDialogContext, _, __) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final targetEnhancement = (enhancement + 1).clamp(1, 10).toInt();
            final enhancementRate =
                _enhancementSuccessRateForTarget(targetEnhancement);
            final canEnhance = wearable &&
                enhancement < 10 &&
                enhanceStoneQuantity > 0 &&
                !enhancing &&
                busy.isEmpty;
            final enhanceTone = enhancement > 5
                ? _inventoryHighEnhancement
                : _inventoryGold;

            void showFlash({required bool success, required String text}) {
              final serial = ++flashSerial;
              setDialogState(() {
                flashSuccess = success;
                flashText = text;
              });
              Future<void>.delayed(const Duration(milliseconds: 950), () {
                if (!dialogContext.mounted || serial != flashSerial) return;
                setDialogState(() {
                  flashText = '';
                  flashSuccess = null;
                });
              });
            }

            Future<void> enhanceNow() async {
              if (!canEnhance) return;
              setDialogState(() => enhancing = true);
              if (mounted) setState(() => busy = 'enhance:${item.id}');

              try {
                final payload = await _requestEnhanceEquipment(item);
                final success = boolValue(payload['success']);
                final level = intValue(
                  payload['enhancement_level'],
                  success ? enhancement + 1 : enhancement,
                ).clamp(0, 10).toInt();
                final stoneLeft = intValue(
                  payload['enhance_stone_quantity'],
                  math.max(0, enhanceStoneQuantity - 1),
                ).clamp(0, 999999).toInt();

                if (!mounted || !dialogContext.mounted) return;
                setDialogState(() {
                  enhancement = level;
                  enhanceStoneQuantity = stoneLeft;
                  enhancing = false;
                });
                showFlash(
                  success: success,
                  text: success ? '强化成功  +$level' : '强化失败',
                );
                setState(() {});
              } catch (error) {
                if (!mounted || !dialogContext.mounted) return;
                setDialogState(() => enhancing = false);
                showFlash(
                  success: false,
                  text: error is NovelBackendException && error.message.trim().isNotEmpty
                      ? error.message.trim()
                      : '强化失败',
                );
              } finally {
                if (mounted) setState(() => busy = '');
                if (dialogContext.mounted && enhancing) {
                  setDialogState(() => enhancing = false);
                }
              }
            }

            Widget effectRow(String label, String value, {Color? valueColor}) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 62,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: _inventoryMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: valueColor ?? _inventoryText,
                          fontSize: 11.3,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final screen = MediaQuery.of(dialogContext).size;
            final dialogHeight = math.min(610.0, screen.height * .88);

            return Center(
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 330,
                    height: dialogHeight,
                    child: Stack(
                      children: <Widget>[
                        Container(
                          decoration: BoxDecoration(
                            color: _inventoryInkSoft,
                            border: Border.all(
                              color: _inventoryGold.withOpacity(.28),
                              width: .8,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 32,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Column(
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 15, 10, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: qualityColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 7,
                                            runSpacing: 4,
                                            children: <Widget>[
                                              Text(
                                                wearable
                                                    ? '品质 $quality · ${affixes.length}条词条'
                                                    : '品质 $quality',
                                                style: const TextStyle(
                                                  color: _inventoryMuted,
                                                  fontSize: 10.3,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (wearable && enhancement > 0)
                                                _InventoryEnhancementStars(
                                                  level: enhancement,
                                                  compact: true,
                                                  showLabel: true,
                                                ),
                                              Text(
                                                _displayTypeLabel(item),
                                                style: const TextStyle(
                                                  color: _inventoryTextSoft,
                                                  fontSize: 10.3,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '关闭',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(
                                        width: 32,
                                        height: 32,
                                      ),
                                      onPressed: enhancing
                                          ? null
                                          : () => Navigator.of(dialogContext).pop(),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 19,
                                        color: enhancing
                                            ? _inventoryMuted
                                            : _inventoryTextSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: .7,
                                color: Colors.white.withOpacity(.08),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        item.description.trim().isEmpty
                                            ? '暂无详细描述'
                                            : item.description.trim(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _inventoryTextSoft,
                                          fontSize: 11.2,
                                          height: 1.48,
                                        ),
                                      ),
                                      if (item.quantity > 1) ...<Widget>[
                                        const SizedBox(height: 5),
                                        Text(
                                          '持有 ×${item.quantity}',
                                          style: const TextStyle(
                                            color: _inventoryMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                      if (wearable) ...<Widget>[
                                        const SizedBox(height: 12),
                                        Container(
                                          height: .7,
                                          color: Colors.white.withOpacity(.07),
                                        ),
                                        const SizedBox(height: 9),
                                        effectRow('基础效果', _baseEquipmentEffect(item)),
                                        AnimatedSwitcher(
                                          duration: const Duration(milliseconds: 180),
                                          child: Container(
                                            key: ValueKey<int>(enhancement),
                                            child: effectRow(
                                              '强化效果',
                                              _enhancementEffectForLevel(item, enhancement),
                                              valueColor: enhancement <= 0
                                                  ? _inventoryMuted
                                                  : enhanceTone,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(.032),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: enhanceStoneQuantity > 0
                                                  ? Colors.white.withOpacity(.07)
                                                  : _inventoryHighEnhancement.withOpacity(.28),
                                            ),
                                          ),
                                          child: Row(
                                            children: <Widget>[
                                              SizedBox(
                                                width: 19,
                                                height: 19,
                                                child: Image.asset(
                                                  'assets/images/enhance_stone.webp',
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, __, ___) => const Icon(
                                                    Icons.diamond_outlined,
                                                    size: 15,
                                                    color: _inventoryGold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 7),
                                              Text(
                                                '玄石 ×$enhanceStoneQuantity',
                                                style: TextStyle(
                                                  color: enhanceStoneQuantity > 0
                                                      ? _inventoryText
                                                      : _inventoryHighEnhancement,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                enhancement >= 10
                                                    ? '已满级'
                                                    : '成功率 $enhancementRate%',
                                                style: const TextStyle(
                                                  color: _inventoryMuted,
                                                  fontSize: 9.6,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 40,
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: enhancement >= 10
                                                  ? Colors.white.withOpacity(.05)
                                                  : enhanceStoneQuantity <= 0
                                                      ? Colors.white.withOpacity(.045)
                                                      : enhanceTone.withOpacity(.18),
                                              foregroundColor: enhancement >= 10 ||
                                                      enhanceStoneQuantity <= 0
                                                  ? _inventoryMuted
                                                  : _inventoryText,
                                              disabledBackgroundColor:
                                                  Colors.white.withOpacity(.045),
                                              disabledForegroundColor: _inventoryMuted,
                                              side: BorderSide(
                                                color: canEnhance
                                                    ? enhanceTone.withOpacity(.72)
                                                    : Colors.white.withOpacity(.10),
                                                width: canEnhance ? 1.05 : .8,
                                              ),
                                              elevation: 0,
                                              padding: EdgeInsets.zero,
                                              shape: const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(4),
                                                ),
                                              ),
                                            ),
                                            onPressed: canEnhance ? enhanceNow : null,
                                            child: enhancing
                                                ? const SizedBox.square(
                                                    dimension: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 1.6,
                                                      color: _inventoryText,
                                                    ),
                                                  )
                                                : Text(
                                                    enhancement >= 10 ? '已满级' : '强化',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: .5,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          '附加词条',
                                          style: TextStyle(
                                            color: _inventoryMuted,
                                            fontSize: 10.3,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        if (affixes.isEmpty)
                                          const Text(
                                            '无额外词条',
                                            style: TextStyle(
                                              color: _inventoryMuted,
                                              fontSize: 10.8,
                                            ),
                                          )
                                        else
                                          ...affixes.map((affix) {
                                            final label =
                                                _affixDisplayNames[affix.key] ?? '属性';
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 3),
                                              child: Row(
                                                children: <Widget>[
                                                  Expanded(
                                                    child: Text(
                                                      label,
                                                      style: const TextStyle(
                                                        color: _inventoryTextSoft,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '+${affix.value}%',
                                                    style: const TextStyle(
                                                      color: _inventoryGold,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (wearable) ...<Widget>[
                                Container(
                                  height: .7,
                                  color: Colors.white.withOpacity(.08),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 42,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: item.isEquipped
                                            ? Colors.white.withOpacity(.07)
                                            : _inventoryBlue.withOpacity(.24),
                                        foregroundColor: item.isEquipped
                                            ? _inventoryTextSoft
                                            : _inventoryText,
                                        side: BorderSide(
                                          color: item.isEquipped
                                              ? Colors.white.withOpacity(.12)
                                              : _inventoryGold.withOpacity(.44),
                                          width: .9,
                                        ),
                                        elevation: 0,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(4),
                                          ),
                                        ),
                                      ),
                                      onPressed: busy.isNotEmpty || enhancing
                                          ? null
                                          : () {
                                              Navigator.of(dialogContext).pop();
                                              unawaited(_toggleWear(item));
                                            },
                                      child: Text(
                                        item.isEquipped ? '卸下' : '穿上',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Positioned(
                          left: 28,
                          right: 28,
                          top: 66,
                          child: IgnorePointer(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) {
                                final curved = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                );
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: .88, end: 1)
                                        .animate(curved),
                                    child: child,
                                  ),
                                );
                              },
                              child: flashText.isEmpty
                                  ? const SizedBox.shrink()
                                  : Center(
                                      key: ValueKey<int>(flashSerial),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (flashSuccess == true
                                                  ? _inventoryGold
                                                  : _inventoryHighEnhancement)
                                              .withOpacity(.94),
                                          borderRadius: BorderRadius.circular(99),
                                          boxShadow: const <BoxShadow>[
                                            BoxShadow(
                                              color: Color(0x66000000),
                                              blurRadius: 12,
                                              offset: Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          flashText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFF11131A),
                                            fontSize: 11.3,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
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
          },
        );
      },
    );
  }
  Widget _hero(
    NovelCharacter? host,
    List<NovelInventoryItem> equipped,
    List<_GameStyleSkillView> skills, {
    bool landscape = false,
  }) {
    final name = host?.name.trim().isNotEmpty == true
        ? host!.name
        : widget.controller.protagonistName;
    final status = host?.status ?? const <String, dynamic>{};
    final identity = stringValue(status['identity'] ?? host?.persona['identity']).trim();
    final level = stringValue(status['level']).trim();
    final condition = widget.controller.protagonistCondition.trim();
    final avatar = host?.avatarUrl.trim() ?? '';
    final fallbackAsset = host?.gender.trim() == '女'
        ? 'assets/images/female.webp'
        : 'assets/images/male.webp';

    final metaTags = [identity, level, condition]
        .where((s) => s.isNotEmpty)
        .join('  ·  ');

    return Padding(
      padding: landscape
          ? const EdgeInsets.fromLTRB(14, 6, 18, 8)
          : const EdgeInsets.fromLTRB(16, 8, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: landscape ? 46 : 56,
                height: landscape ? 46 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _inventoryGold.withOpacity(landscape ? .24 : .42),
                    width: landscape ? .7 : 1,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _inventoryBlue.withOpacity(landscape ? .10 : .22),
                      blurRadius: landscape ? 9 : 16,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: CdnUtil.resize(avatar, width: 256),
                  assetCandidates: <String>[fallbackAsset],
                  fit: BoxFit.cover,
                  fallbackText: name,
                ),
              ),
              SizedBox(width: landscape ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _inventoryText,
                        fontSize: landscape ? 15.5 : 18,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: landscape ? .35 : .5,
                      ),
                    ),
                    if (metaTags.isNotEmpty) ...[
                      SizedBox(height: landscape ? 3 : 4),
                      Text(
                        metaTags,
                        style: TextStyle(
                          color: _inventoryTextSoft,
                          fontSize: landscape ? 9.4 : 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          
          _equipmentBonusPanel(equipped, dense: landscape),
          
          if (skills.isNotEmpty) ...<Widget>[
            SizedBox(height: landscape ? 10 : 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: landscape
                      ? Text(
                          '技能  ${skills.length}',
                          style: const TextStyle(
                            color: _inventoryTextSoft,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5,
                          ),
                        )
                      : _GameStyleSectionTitle(
                          title: '技能',
                          count: skills.length,
                        ),
                ),
                if (skills.length > 3)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _skillsExpanded = !_skillsExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                        child: Text(
                          _skillsExpanded ? '收起' : '展开',
                          style: const TextStyle(
                            color: _inventoryMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: landscape ? 5 : 8),
            Wrap(
              spacing: landscape ? 5 : 6,
              runSpacing: landscape ? 5 : 6,
              children: skills.take(_skillsExpanded ? skills.length : 3).map((skill) {
                final meta = skill.isAbility
                    ? '能力'
                    : (skill.mastery.isEmpty ? '' : skill.mastery);
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: landscape ? 7 : 8,
                    vertical: landscape ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: _inventoryInkSoft.withOpacity(landscape ? .32 : .72),
                    borderRadius: BorderRadius.circular(landscape ? 2 : 4),
                    border: landscape
                        ? null
                        : Border.all(color: Colors.white.withOpacity(.06)),
                  ),
                  child: Text(
                    meta.isEmpty ? skill.name : '${skill.name} · $meta',
                    style: TextStyle(
                      color: _inventoryTextSoft,
                      fontSize: landscape ? 9.2 : 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          
          if (equipped.isNotEmpty) ...<Widget>[
            SizedBox(height: landscape ? 10 : 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: landscape
                      ? Text(
                          '当前穿戴  ${equipped.length}',
                          style: const TextStyle(
                            color: _inventoryTextSoft,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5,
                          ),
                        )
                      : _GameStyleSectionTitle(
                          title: '当前穿戴',
                          count: equipped.length,
                        ),
                ),
                if (equipped.length > 3)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _equippedExpanded = !_equippedExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          _equippedExpanded ? '收起' : '展开',
                          style: const TextStyle(
                            color: _inventoryMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: landscape ? 5 : 8),
            Wrap(
              spacing: landscape ? 6 : 8,
              runSpacing: landscape ? 6 : 8,
              children: equipped
                  .take(_equippedExpanded ? equipped.length : 3)
                  .map((item) {
                final quality = _inventoryItemQuality(item);
                final qualityColor = _inventoryQualityColor(quality);
                final enhancement = _equipmentEnhancement(item);
                final itemBusy = busy.isNotEmpty && busy == item.id;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: itemBusy ? null : () => unawaited(_showItemDetail(item)),
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: EdgeInsets.fromLTRB(
                        landscape ? 7 : 8,
                        landscape ? 4 : 6,
                        landscape ? 6 : 6,
                        landscape ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: _inventoryInkSoft.withOpacity(landscape ? .34 : .74),
                        borderRadius: BorderRadius.circular(landscape ? 2 : 4),
                        border: landscape
                            ? null
                            : Border.all(color: qualityColor.withOpacity(.22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: qualityColor,
                                fontSize: landscape ? 9.6 : 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (enhancement > 0) ...<Widget>[
                            const SizedBox(width: 6),
                            _InventoryEnhancementStars(
                              level: enhancement,
                              compact: true,
                              showLabel: true,
                            ),
                          ],
                          const SizedBox(width: 6),
                          if (itemBusy)
                            const SizedBox.square(
                              dimension: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.4,
                                color: _inventoryMuted,
                              ),
                            )
                          else
                            const Text(
                              '详情',
                              style: TextStyle(
                                color: _inventoryMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGlassPanel({
    required Widget child,
    bool quiet = false,
  }) {
    final radius = BorderRadius.circular(quiet ? 2 : 6);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: quiet ? 8 : 18,
          sigmaY: quiet ? 8 : 18,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _inventoryInkSoft.withOpacity(quiet ? .20 : .55),
            borderRadius: radius,
            border: quiet
                ? null
                : Border.all(
                    color: Colors.white.withOpacity(.08),
                    width: .8,
                  ),
            boxShadow: quiet
                ? const <BoxShadow>[]
                : <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _inventoryList(
    List<NovelInventoryItem> items, {
    bool isDesktop = false,
    bool dense = false,
  }) {
    return Padding(
      padding: isDesktop
          ? EdgeInsets.symmetric(
              horizontal: dense ? 12 : 24,
              vertical: dense ? 8 : 24,
            )
          : const EdgeInsets.fromLTRB(16, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: isDesktop ? 64 : 32),
              alignment: Alignment.center,
              child: Text(
                loading ? '正在整理…' : '空空如也',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _inventoryMuted,
                  fontSize: 11,
                ),
              ),
            )
          else
            isDesktop
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 500 ? 2 : 1;
                      const spacing = 12.0;
                      final itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: List.generate(items.length, (index) {
                          return SizedBox(
                            width: itemWidth,
                            child: _buildAnimatedRow(
                              items[index],
                              index,
                              dense: dense,
                            ),
                          );
                        }),
                      );
                    },
                  )
                : Column(
                    children: <Widget>[
                      for (var index = 0; index < items.length; index++) ...<Widget>[
                        _buildAnimatedRow(
                          items[index],
                          index,
                          dense: dense,
                        ),
                        if (index != items.length - 1)
                          const SizedBox(height: 6),
                      ],
                    ],
                  ),
        ],
      ),
    );
  }

  Widget _buildAnimatedRow(
    NovelInventoryItem item,
    int index, {
    bool dense = false,
  }) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('$_filterIndex-${item.id}-${item.name}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + math.min(index, 6) * 35),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(10 * (1 - value), 0),
          child: child,
        ),
      ),
      child: _GameStyleInventoryRow(
        item: item,
        typeLabel: _displayTypeLabel(item),
        wearable: _isWearable(item),
        enhancementLevel: _equipmentEnhancement(item),
        busy: busy == item.id,
        onTap: () => _showItemDetail(item),
        onWear: () => _toggleWear(item),
        dense: dense,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final host = widget.controller.protagonist;
        final data = widget.controller.inventory;
        final items = _allItems(data)
          ..sort((a, b) {
            final qualityCompare =
                _inventoryItemQuality(b).compareTo(_inventoryItemQuality(a));
            if (qualityCompare != 0) return qualityCompare;
            return a.name.compareTo(b.name);
          });
        final equipped = items
            .where((item) => _isWearable(item) && item.isEquipped)
            .toList();
        final skills = _skills(host);
        final backpackItems = items.where((item) => !item.isEquipped).toList();
        final filteredItems = backpackItems.where((item) {
          if (_filterIndex == 1) return _isWearable(item);
          if (_filterIndex == 2) return !_isWearable(item);
          return true;
        }).toList();

        Widget desktopLayout() {
          return Column(
            children: <Widget>[
              _InventoryHeader(
                horizontalPadding: EdgeInsets.zero,
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 4,
                        child: _buildGlassPanel(
                          child: ListView(
                            padding: const EdgeInsets.only(top: 12, bottom: 24),
                            children: <Widget>[_hero(host, equipped, skills)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: _buildGlassPanel(
                                child: RefreshIndicator(
                                  onRefresh: _refresh,
                                  color: _inventoryGold,
                                  backgroundColor: _inventoryInkSoft,
                                  child: ListView(
                                    padding: EdgeInsets.zero,
                                    children: <Widget>[
                                      _inventoryList(
                                        filteredItems,
                                        isDesktop: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _inventoryFilterBar(isDesktop: true),
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

        Widget portraitLayout() {
          return Column(
            children: <Widget>[
              _InventoryHeader(
                horizontalPadding: EdgeInsets.zero,
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: _inventoryGold,
                  backgroundColor: _inventoryInkSoft,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      SliverToBoxAdapter(child: _hero(host, equipped, skills)),
                      if (filteredItems.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _inventoryList(filteredItems),
                        )
                      else
                        SliverToBoxAdapter(
                          child: _inventoryList(filteredItems),
                        ),
                    ],
                  ),
                ),
              ),
              _inventoryFilterBar(),
            ],
          );
        }

        Widget landscapeLayout() {
          return Column(
            children: <Widget>[
              _InventoryHeader(
                dense: true,
                showTitle: false,
                horizontalPadding: EdgeInsets.zero,
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 4,
                      child: _buildGlassPanel(
                        quiet: false, // 恢复跑团风格的外围线条与玻璃质感
                        child: ListView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 8, bottom: 12),
                          children: <Widget>[
                            _hero(
                              host,
                              equipped,
                              skills,
                              landscape: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: <Widget>[
                          Expanded(
                            child: _buildGlassPanel(
                              quiet: false, // 恢复跑团风格的外围线条与玻璃质感
                              child: RefreshIndicator(
                                onRefresh: _refresh,
                                color: _inventoryGold,
                                backgroundColor: _inventoryInkSoft,
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  children: <Widget>[
                                    _inventoryList(
                                      filteredItems,
                                      isDesktop: true,
                                      dense: false,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _inventoryFilterBar(
                            isDesktop: true,
                            dense: true,
                            quiet: false, // 恢复底部三个按钮的边框线条
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return _InventoryBackdrop(
          child: SafeArea(
            bottom: false,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - value)),
                  child: child,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mode = _inventoryViewportMode(
                    constraints,
                    widget.controller.desktopMode,
                  );

                  switch (mode) {
                    case _InventoryViewportMode.desktop:
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1440),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(46, 14, 54, 12),
                            child: desktopLayout(),
                          ),
                        ),
                      );
                    case _InventoryViewportMode.landscape:
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                        child: landscapeLayout(),
                      );
                    case _InventoryViewportMode.portrait:
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                            child: portraitLayout(),
                          ),
                        ),
                      );
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _inventoryFilterBar({
    bool isDesktop = false,
    bool dense = false,
    bool quiet = false,
  }) {
    final child = Center(
      child: Container(
        height: dense ? 34 : 44,
        constraints: BoxConstraints(maxWidth: dense ? 300 : 360),
        decoration: BoxDecoration(
          color: _inventoryInkSoft.withOpacity(quiet ? .28 : .65),
          borderRadius: BorderRadius.circular(quiet ? 2 : 6),
          border: quiet
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(.08),
                  width: .8,
                ),
          boxShadow: quiet
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Expanded(child: _buildFilterBtn('全部', 0, quiet: quiet)),
            Expanded(child: _buildFilterBtn('穿戴', 1, quiet: quiet)),
            Expanded(child: _buildFilterBtn('道具', 2, quiet: quiet)),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: dense ? 2 : 8),
          child: child,
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        child: child,
      ),
    );
  }

  Widget _buildFilterBtn(
    String label,
    int index, {
    bool quiet = false,
  }) {
    final selected = _filterIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _filterIndex = index),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: selected
              ? BoxDecoration(
                  color: _inventoryBlue.withOpacity(0.2), 
                  borderRadius: BorderRadius.circular(quiet ? 2 : 6),
                  border: quiet
                      ? null
                      : Border.all(
                          color: _inventoryGold.withOpacity(.3),
                        ),
                  boxShadow: quiet
                      ? const <BoxShadow>[]
                      : <BoxShadow>[
                          BoxShadow(
                            color: _inventoryBlue.withOpacity(.12),
                            blurRadius: 8,
                          ),
                        ],
                )
              : const BoxDecoration(),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _inventoryGold : _inventoryMuted,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryBackdrop extends StatelessWidget {
  const _InventoryBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF070B15),
            Color(0xFF101A30),
            _inventoryInk,
          ],
          stops: <double>[0, .56, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            left: -180,
            top: -250,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _inventoryGold.withOpacity(.12)),
              ),
            ),
          ),
          Positioned(
            right: -220,
            bottom: -300,
            child: Container(
              width: 620,
              height: 620,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    _inventoryBlue.withOpacity(.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    this.onClose,
    this.horizontalPadding = const EdgeInsets.symmetric(horizontal: 20),
    this.dense = false,
    this.showTitle = true,
  });

  final VoidCallback? onClose;
  final EdgeInsetsGeometry horizontalPadding;
  final bool dense;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: showTitle ? (dense ? 42 : 64) : (onClose != null ? 40 : 4),
      child: Padding(
        padding: horizontalPadding,
        child: Row(
          children: <Widget>[
            if (showTitle)
              Expanded(
                child: Text(
                  '背包',
                  style: TextStyle(
                    color: _inventoryText,
                    fontSize: dense ? 16 : 20,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              )
            else
              const Spacer(),
            if (onClose != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(99),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: _inventoryTextSoft,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _inventoryItemQuality(NovelInventoryItem item) {
  final rawQuality = item.raw['quality'];
  final quality = rawQuality is num
      ? rawQuality.round()
      : int.tryParse('$rawQuality') ?? 1;
  return quality.clamp(1, 10).toInt();
}

Color _inventoryQualityColor(int quality) {
  final value = quality.clamp(1, 10).toInt();

  return switch (value) {
    10 => const Color(0xFFFF7B7B),
    9 => const Color(0xFFFF83B7),
    8 => const Color(0xFF70D8D0),
    7 => const Color(0xFFFFAA58),
    6 => const Color(0xFFE3C66B),
    5 => const Color(0xFFB89AE8),
    4 => const Color(0xFF83B7EC),
    3 => const Color(0xFF77C890),
    2 => const Color(0xFF8FB99A),
    _ => const Color(0xFFB9C0D0),
  };
}

class _QualitySegments extends StatelessWidget {
  const _QualitySegments({
    required this.level,
    this.height = 4.5, 
  });

  final int level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0, 10).toInt();
    const activeColor = _inventoryGold;
    
    return Row(
      children: List<Widget>.generate(3, (index) { 
        final segmentMax = (index + 1) * 3.33;
        final segmentMin = index * 3.33;
        double fillFraction = 0.0;
        
        if (normalized >= segmentMax) {
          fillFraction = 1.0;
        } else if (normalized > segmentMin) {
          fillFraction = (normalized - segmentMin) / 3.33;
        }

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 3),
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.07),
                      borderRadius: BorderRadius.circular(2), 
                    ),
                  ),
                  if (fillFraction > 0)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fillFraction,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _EquipmentBonusValue {
  const _EquipmentBonusValue(
    this.label,
    this.rawValue,
    this.maxValue,
    this.valueText,
  );

  final String label;
  final int rawValue;
  final int maxValue;
  final String valueText;

  int get level {
    if (maxValue <= 0 || rawValue <= 0) return 0;
    return ((rawValue / maxValue) * 10).round().clamp(1, 10).toInt();
  }
}

class _EquipmentBonusMeter extends StatelessWidget {
  const _EquipmentBonusMeter({
    required this.label,
    required this.level,
    required this.valueText,
  });

  final String label;
  final int level;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0, 10).toInt();
    return Semantics(
      label: '$label $valueText',
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 29,
            child: Text(
              label,
              style: const TextStyle(
                color: _inventoryMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 32, 
            child: Text(
              valueText,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _inventoryGold,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _QualitySegments(level: normalized),
          ),
        ],
      ),
    );
  }
}

class _InventoryEnhancementStars extends StatelessWidget {
  const _InventoryEnhancementStars({
    required this.level,
    this.compact = false,
    this.showLabel = false,
  });

  final int level;
  final bool compact;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0, 10).toInt();
    if (normalized <= 0) return const SizedBox.shrink();
    final secondStage = normalized > 5;
    final visibleStars = secondStage ? normalized - 5 : normalized;
    final color = secondStage ? _inventoryHighEnhancement : _inventoryGold;
    final size = compact ? 8.5 : 10.5;

    return Semantics(
      label: '强化 +$normalized',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showLabel) ...<Widget>[
            Text(
              '+$normalized',
              style: TextStyle(
                color: color,
                fontSize: compact ? 8.2 : 9.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            SizedBox(width: compact ? 3 : 4),
          ],
          ...List<Widget>.generate(5, (index) {
            return Icon(
              Icons.star_rounded,
              size: size,
              color: index < visibleStars
                  ? color
                  : color.withOpacity(.16),
            );
          }),
        ],
      ),
    );
  }
}


class _GameStyleInventoryRow extends StatelessWidget {
  const _GameStyleInventoryRow({
    required this.item,
    required this.typeLabel,
    required this.wearable,
    required this.enhancementLevel,
    required this.busy,
    required this.onTap,
    required this.onWear,
    this.dense = false,
  });

  final NovelInventoryItem item;
  final String typeLabel;
  final bool wearable;
  final int enhancementLevel;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onWear;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final equipped = wearable && item.isEquipped;
    final quality = _inventoryItemQuality(item);
    final qualityColor = _inventoryQualityColor(quality);
    final description = item.description.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 14,
            vertical: dense ? 7 : 9,
          ),
          decoration: BoxDecoration(
            color: _inventoryInkSoft.withOpacity(dense ? .34 : .68),
            borderRadius: BorderRadius.circular(dense ? 2 : 4),
            border: dense
                ? null
                : Border.all(color: qualityColor.withOpacity(.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: qualityColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        if (enhancementLevel > 0) ...<Widget>[
                          const SizedBox(width: 7),
                          _InventoryEnhancementStars(
                            level: enhancementLevel,
                            compact: true,
                            showLabel: true,
                          ),
                        ],
                        if (equipped) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: _inventoryBlue.withOpacity(.14),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: _inventoryGold.withOpacity(.2)),
                            ),
                            child: const Text(
                              '已穿戴',
                              style: TextStyle(
                                color: _inventoryGold,
                                fontSize: 8.5,
                                height: 1.0,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .25,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4), // 缩短标题与描述的间距
                    Text(
                      description.isEmpty ? '点击查看详情' : description,
                      maxLines: 1, // 强制限制为单行
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: description.isEmpty
                            ? _inventoryMuted
                            : _inventoryTextSoft,
                        fontSize: 10.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 50,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _inventoryMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                child: wearable
                    ? InkWell(
                        onTap: busy ? null : onWear,
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 26, // 进一步压缩按钮高度
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: equipped
                                ? Colors.white.withOpacity(.07)
                                : _inventoryBlue.withOpacity(.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: equipped
                                  ? Colors.white.withOpacity(.08)
                                  : _inventoryGold.withOpacity(.22),
                            ),
                          ),
                          child: busy
                              ? SizedBox.square(
                                  dimension: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: equipped
                                        ? Colors.white
                                        : _inventoryGold,
                                  ),
                                )
                              : Text(
                                  equipped ? '卸下' : '穿戴',
                                  style: TextStyle(
                                    color: equipped
                                        ? Colors.white
                                        : _inventoryText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: item.quantity > 1
                            ? Text(
                                '×${item.quantity}',
                                maxLines: 1,
                                style: const TextStyle(
                                  color: _inventoryTextSoft,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameStyleMetaText extends StatelessWidget {
  const _GameStyleMetaText(
    this.text, {
    this.accent = false,
    this.lightTheme = false,
  });

  final String text;
  final bool accent;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _inventoryInkSoft.withOpacity(.72),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _inventoryGold.withOpacity(.16)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent ? _inventoryGold : _inventoryTextSoft,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
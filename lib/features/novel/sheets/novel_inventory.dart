part of '../novel_sheets.dart';

// ============================================================================
// 背包页
// ============================================================================

const Color _inventoryInk = Color(0xFF090E1A);
const Color _inventoryInkSoft = Color(0xFF111A2C);
const Color _inventoryBlue = Color(0xFF506FEF);
const Color _inventoryGold = Color(0xFFC9B778);
const Color _inventoryGoldSoft = Color(0xFF86794D);
const Color _inventoryText = Color(0xFFF2F0E8);
const Color _inventoryTextSoft = Color(0xFFB9C0D0);
const Color _inventoryMuted = Color(0xFF737C91);

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

  Widget _equipmentBonusPanel(List<NovelInventoryItem> equipped) {
    final hp = (_qualityForSlot(equipped, 'upper') * 10 +
            _affixTotal(equipped, 'max_hp_percent', cap: 40))
        .clamp(0, 140)
        .toInt();
    final energy = (_qualityForSlot(equipped, 'face') * 10 +
            _affixTotal(equipped, 'max_energy_percent', cap: 40))
        .clamp(0, 140)
        .toInt();
    final attack = (_qualityForSlot(equipped, 'handheld') * 10 +
            _affixTotal(equipped, 'attack_percent', cap: 40))
        .clamp(0, 140)
        .toInt();
    final defense = (_qualityForSlot(equipped, 'lower') * 5 +
            _affixTotal(equipped, 'defense_percent', cap: 15))
        .clamp(0, 65)
        .toInt();
    final hit = (_qualityForSlot(equipped, 'head') * 3 +
            _affixTotal(equipped, 'hit_percent', cap: 24))
        .clamp(0, 45)
        .toInt();
    final dodge = (_qualityForSlot(equipped, 'feet') +
            _affixTotal(equipped, 'dodge_percent', cap: 16))
        .clamp(0, 25)
        .toInt();
    final critical = (_accessoryQualityTotal(equipped) +
            _affixTotal(equipped, 'critical_percent', cap: 24))
        .clamp(0, 50)
        .toInt();
    final backQuality = _qualityForSlot(equipped, 'back');
    
    final bonuses = <_EquipmentBonusValue>[
      _EquipmentBonusValue('生命', hp, 140, '+$hp%'),
      _EquipmentBonusValue('精力', energy, 140, '+$energy%'),
      _EquipmentBonusValue('威力', attack, 140, '+$attack%'),
      _EquipmentBonusValue('防护', defense, 65, '+$defense%'),
      _EquipmentBonusValue('精准', hit, 45, '+$hit%'),
      _EquipmentBonusValue('机动', dodge, 25, '+$dodge%'),
      _EquipmentBonusValue('爆发', critical, 50, '+$critical%'),
      _EquipmentBonusValue('携行', backQuality, 10, '${2 + backQuality}次'),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          mainAxisSpacing: 8, 
          crossAxisSpacing: 16, 
          mainAxisExtent: 16, 
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

  Future<void> _showItemDetail(NovelInventoryItem item) async {
    final wearable = _isWearable(item);
    final quality = _inventoryItemQuality(item);
    final qualityColor = _inventoryQualityColor(quality); 
    final affixes = _itemAffixes(item).entries.toList(growable: false);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情',
      barrierColor: Colors.black.withOpacity(.72),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 320, 
                maxHeight: MediaQuery.of(dialogContext).size.height * .82,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: _inventoryInkSoft,
                  border: Border.all(color: _inventoryGold.withOpacity(.28), width: .8),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 14)),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.name,
                            style: TextStyle(
                              color: qualityColor, 
                              fontSize: 16, 
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _displayTypeLabel(item),
                          style: const TextStyle(
                            color: _inventoryTextSoft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      wearable
                          ? '品质 $quality  ·  ${affixes.length}条词条'
                          : '品质 $quality',
                      style: const TextStyle(
                        color: _inventoryMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.quantity > 1) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '持有 ×${item.quantity}',
                        style: const TextStyle(color: _inventoryTextSoft, fontSize: 10.5),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(height: .7, color: Colors.white.withOpacity(.08)),
                    const SizedBox(height: 12),
                    Text(
                      item.description.trim().isEmpty ? '暂无详细描述' : item.description.trim(),
                      style: const TextStyle(
                        color: _inventoryTextSoft,
                        fontSize: 11.5,
                        height: 1.6,
                      ),
                    ),
                    if (wearable) ...<Widget>[
                      const SizedBox(height: 14),
                      Container(height: .7, color: Colors.white.withOpacity(.08)),
                      const SizedBox(height: 12),
                      const Text(
                        '基础效果',
                        style: TextStyle(
                          color: _inventoryMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _baseEquipmentEffect(item),
                        style: const TextStyle(
                          color: _inventoryText,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '附加词条',
                        style: TextStyle(
                          color: _inventoryMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (affixes.isEmpty)
                        const Text(
                          '无额外词条',
                          style: TextStyle(
                            color: _inventoryMuted,
                            fontSize: 11,
                          ),
                        )
                      else
                        ...affixes.map((affix) {
                          final label = _affixDisplayNames[affix.key] ?? '属性';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4), 
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: _inventoryTextSoft,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '+${affix.value}%',
                                  style: const TextStyle(
                                    color: _inventoryGold,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextButton(
                            style: ButtonStyle(
                              foregroundColor: const WidgetStatePropertyAll(
                                _inventoryTextSoft,
                              ),
                              overlayColor: WidgetStateProperty.resolveWith<Color?>(
                                (states) {
                                  if (states.contains(WidgetState.hovered)) return const Color(0x0A000000);
                                  if (states.contains(WidgetState.pressed)) return const Color(0x12000000);
                                  return Colors.transparent;
                                },
                              ),
                              splashFactory: NoSplash.splashFactory,
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              '关闭',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ),
                        if (wearable) ...<Widget>[
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: item.isEquipped
                                    ? Colors.white.withOpacity(.07)
                                    : _inventoryBlue.withOpacity(.26),
                                foregroundColor: item.isEquipped
                                    ? _inventoryTextSoft
                                    : _inventoryText,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(4)),
                                ),
                              ),
                              onPressed: busy.isNotEmpty
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(_toggleWear(item));
                                    },
                              child: Text(item.isEquipped ? '卸下' : '穿戴'),
                            ),
                          ),
                        ],
                      ],
                    ),
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

  Widget _hero(NovelCharacter? host, List<NovelInventoryItem> equipped, List<_GameStyleSkillView> skills) {
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
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 56, 
                height: 56, 
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _inventoryGold.withOpacity(.42), width: 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _inventoryBlue.withOpacity(.22),
                      blurRadius: 16, 
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _inventoryText,
                        fontSize: 18, 
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    if (metaTags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        metaTags,
                        style: const TextStyle(
                          color: _inventoryTextSoft,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          
          _equipmentBonusPanel(equipped),
          
          if (skills.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16), 
            Row(
              children: <Widget>[
                Expanded(
                  child: _GameStyleSectionTitle(title: '技能', count: skills.length),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, 
              runSpacing: 6,
              children: skills.take(_skillsExpanded ? skills.length : 3).map((skill) {
                final meta = skill.isAbility
                    ? '能力'
                    : (skill.mastery.isEmpty ? '' : skill.mastery);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                  decoration: BoxDecoration(
                    color: _inventoryInkSoft.withOpacity(.72),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(.06)),
                  ),
                  child: Text(
                    meta.isEmpty ? skill.name : '${skill.name} · $meta',
                    style: const TextStyle(
                      color: _inventoryTextSoft,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          
          if (equipped.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16), 
            Row(
              children: <Widget>[
                Expanded(
                  child: _GameStyleSectionTitle(
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, 
              runSpacing: 8,
              children: equipped
                  .take(_equippedExpanded ? equipped.length : 3)
                  .map((item) {
                final quality = _inventoryItemQuality(item);
                final qualityColor = _inventoryQualityColor(quality);
                final itemBusy = busy.isNotEmpty && busy == item.id;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: itemBusy ? null : () => unawaited(_showItemDetail(item)),
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                      decoration: BoxDecoration(
                        color: _inventoryInkSoft.withOpacity(.74),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: qualityColor.withOpacity(.22)),
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
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
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

  // 桌面端微圆角磨砂玻璃容器，有效分离背景光效和文字信息，使文字清晰可读
  Widget _buildGlassPanel({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _inventoryInkSoft.withOpacity(0.55),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 0.8,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
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

  Widget _inventoryList(List<NovelInventoryItem> items, {bool isDesktop = false}) {
    return Padding(
      padding: isDesktop
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 24)
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
                      // 桌面端利用 Wrap 自动实现双列或多列排布
                      final crossAxisCount = constraints.maxWidth > 500 ? 2 : 1;
                      const spacing = 12.0;
                      final itemWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: List.generate(items.length, (index) {
                          return SizedBox(
                            width: itemWidth,
                            child: _buildAnimatedRow(items[index], index),
                          );
                        }),
                      );
                    },
                  )
                : Column(
                    children: <Widget>[
                      for (var index = 0; index < items.length; index++) ...<Widget>[
                        _buildAnimatedRow(items[index], index),
                        if (index != items.length - 1)
                          const SizedBox(height: 6),
                      ],
                    ],
                  ),
        ],
      ),
    );
  }

  // 提取公用的带动画的列表行组件
  Widget _buildAnimatedRow(NovelInventoryItem item, int index) {
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
        busy: busy == item.id,
        onTap: () => _showItemDetail(item),
        onWear: () => _toggleWear(item),
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
                  // 模式只认共享的手机 / 电脑状态。
                  final isDesktop = widget.controller.desktopMode;

                  // 这里对齐人物页真正的“页面主体”边距，
                  // 不再误用人物聊天框为了避让 HUD 设置的专用边距。
                  final pageLeftInset = isDesktop ? 46.0 : 10.0;
                  final pageRightInset = isDesktop ? 54.0 : 12.0;
                  final contentMaxWidth = isDesktop ? 1440.0 : 560.0;
                  final pageTopInset = isDesktop ? 14.0 : 4.0;
                  final pageBottomInset = isDesktop ? 12.0 : 4.0;

                  Widget pageContent;

                  if (isDesktop) {
                    pageContent = Column(
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
                                // 左侧：人物、穿戴与技能。
                                Expanded(
                                  flex: 4,
                                  child: _buildGlassPanel(
                                    child: ListView(
                                      padding: const EdgeInsets.only(
                                        top: 12,
                                        bottom: 24,
                                      ),
                                      children: <Widget>[
                                        _hero(host, equipped, skills),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // 右侧：物品区与分类栏。
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
                  } else {
                    pageContent = Column(
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
                                SliverToBoxAdapter(
                                  child: _hero(host, equipped, skills),
                                ),
                                if (filteredItems.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _inventoryList(
                                      filteredItems,
                                      isDesktop: false,
                                    ),
                                  )
                                else
                                  SliverToBoxAdapter(
                                    child: _inventoryList(
                                      filteredItems,
                                      isDesktop: false,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _inventoryFilterBar(isDesktop: false),
                      ],
                    );
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          pageLeftInset,
                          pageTopInset,
                          pageRightInset,
                          pageBottomInset,
                        ),
                        child: pageContent,
                      ),
                    ),
                  );
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
  }) {
    final child = Center(
      child: Container(
        height: 44,
        constraints: const BoxConstraints(maxWidth: 360), 
        decoration: BoxDecoration(
          color: _inventoryInkSoft.withOpacity(0.65), 
          borderRadius: BorderRadius.circular(6), // 强化微圆角特征
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Expanded(child: _buildFilterBtn('全部', 0)),
            Expanded(child: _buildFilterBtn('穿戴', 1)),
            Expanded(child: _buildFilterBtn('道具', 2)),
          ],
        ),
      ),
    );

    if (isDesktop) {
      return SafeArea(
        top: false,
        child: Padding(
          // 横屏模式下稍微离开底部安全区，保持呼吸感
          padding: const EdgeInsets.only(bottom: 8),
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

  Widget _buildFilterBtn(String label, int index) {
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
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _inventoryGold.withOpacity(0.3)), 
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _inventoryBlue.withOpacity(0.12),
                      blurRadius: 8,
                    )
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
  });

  final VoidCallback? onClose;
  final EdgeInsetsGeometry horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64, 
      child: Padding(
        padding: horizontalPadding,
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '背包',
                style: TextStyle(
                  color: _inventoryText,
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
            ),
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

class _GameStyleInventoryRow extends StatelessWidget {
  const _GameStyleInventoryRow({
    required this.item,
    required this.typeLabel,
    required this.wearable,
    required this.busy,
    required this.onTap,
    required this.onWear,
  });

  final NovelInventoryItem item;
  final String typeLabel;
  final bool wearable;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onWear;

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
          // 极致压缩列表项的上下边距
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _inventoryInkSoft.withOpacity(.68),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: qualityColor.withOpacity(.18)),
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
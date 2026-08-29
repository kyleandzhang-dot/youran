part of '../novel_sheets.dart';

// ============================================================================
// 背包页
// 页面入口 / 对外入口：
//   - showNovelInventorySheet(...)
//   - NovelInventoryTab
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

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

/// 主游戏底部 Tab 使用的背包页。
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
    // 面向玩家的文案保持世界观中立：底层仍可使用 weapon / armor 等技术类型，
    // 但爱情、校园、都市、悬疑等非战斗剧本中不直接显示“武器 / 防具”。
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
    // 槽位名称只描述“放在哪里 / 怎么携带”，不描述战斗用途。
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

  int _qualityForSlot(
    List<NovelInventoryItem> equipped,
    String slot, {
    bool stack = false, // 新增：是否允许多件装备叠加属性
  }) {
    var quality = 0;
    for (final item in equipped) {
      if (_itemSlot(item) == slot) {
        if (stack) {
          // 可叠加槽位（当前用于饰品→爆发）按半额品质计入。
          // 避免单件 Q10 饰品直接把爆发顶满；两件高品质饰品才可能接近/达到 10。
          quality += (_equipmentQuality(item) / 2).ceil();
        } else {
          quality = math.max(quality, _equipmentQuality(item)); // 取最高值
        }
      }
    }
    return quality.clamp(0, 10).toInt();
  }

  Widget _equipmentBonusPanel(List<NovelInventoryItem> equipped) {
    final bonuses = <MapEntry<String, int>>[
      MapEntry('生命', _qualityForSlot(equipped, 'upper')),
      MapEntry('精力', _qualityForSlot(equipped, 'face')),
      MapEntry('威力', _qualityForSlot(equipped, 'handheld')),
      MapEntry('防护', _qualityForSlot(equipped, 'lower')),
      MapEntry('精准', _qualityForSlot(equipped, 'head')),
      MapEntry('机动', _qualityForSlot(equipped, 'feet')),
      // 饰品支持多件穿戴，开启 stack: true 让属性叠加
      MapEntry('爆发', _qualityForSlot(equipped, 'accessory', stack: true)),
      MapEntry('携行', _qualityForSlot(equipped, 'back')),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
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
            label: bonus.key,
            level: bonus.value,
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
    final qualityColor = _inventoryQualityColor(quality); // 提取品质颜色

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
              constraints: const BoxConstraints(maxWidth: 330),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: _archiveSurface,
                  border: Border.all(color: _archiveLine, width: .8),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x22000000), blurRadius: 28, offset: Offset(0, 12)),
                  ],
                ),
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
                              color: qualityColor, // 标题直接使用品质颜色
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _typeLabel(item.itemType),
                          style: const TextStyle(
                            color: Color(0xFF646660),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    // 彻底去掉了显示 Q5 徽章、品质名称和进度条的 Row
                    if (item.quantity > 1) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        '持有 ×${item.quantity}',
                        style: const TextStyle(color: Color(0xFF696B65), fontSize: 10.5),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(height: .7, color: _archiveLine),
                    const SizedBox(height: 14),
                    Text(
                      item.description.trim().isEmpty ? '暂无详细描述' : item.description.trim(),
                      style: const TextStyle(
                        color: Color(0xFF3D3E3A),
                        fontSize: 12,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              '关闭',
                              style: TextStyle(color: Color(0xFF60625C), fontSize: 11.5),
                            ),
                          ),
                        ),
                        if (wearable) ...<Widget>[
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: item.isEquipped
                                    ? _archiveSurfaceSoft
                                    : _archiveText, // <--- 换回统一的高级黑深色
                                foregroundColor: item.isEquipped
                                    ? _archiveMuted
                                    : Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero, // <--- 确保是绝对直角
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

    // 把原本一个个带绿色背景的标签，合并成一行干净的灰字
    final metaTags = [identity, level, condition]
        .where((s) => s.isNotEmpty)
        .join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0), // 顶部间距收紧（从 8 改为 4）
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _archiveLine, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: CdnUtil.resize(avatar, width: 256),
                  assetCandidates: <String>[fallbackAsset],
                  fit: BoxFit.cover,
                  fallbackText: name,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF22231F),
                        fontSize: 20,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    if (metaTags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        metaTags,
                        style: const TextStyle(
                          color: _archiveMutedSoft, // 使用现在的灰色字体颜色
                          fontSize: 11,
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
            const SizedBox(height: 14), // 区块间距收紧
            Row(
              children: <Widget>[
                Expanded(
                  child: _GameStyleSectionTitle(title: '技能', count: skills.length, lightTheme: true),
                ),
                if (skills.length > 3)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _skillsExpanded = !_skillsExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          _skillsExpanded ? '收起' : '展开',
                          style: const TextStyle(
                            color: _archiveMuted, // 用灰色，不喧宾夺主
                            fontSize: 10.5,
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
              spacing: 7,
              runSpacing: 7,
              children: skills.take(_skillsExpanded ? skills.length : 3).map((skill) {
                final meta = skill.isAbility
                    ? '能力'
                    : (skill.mastery.isEmpty ? '' : skill.mastery);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: _archiveSurfaceSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    meta.isEmpty ? skill.name : '${skill.name} · $meta',
                    style: const TextStyle(
                      color: Color(0xFF383A35),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          
          if (equipped.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14), // 区块间距收紧
            Row(
              children: <Widget>[
                Expanded(
                  child: _GameStyleSectionTitle(
                    title: '当前穿戴',
                    count: equipped.length,
                    lightTheme: true,
                  ),
                ),
                if (equipped.length > 3)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _equippedExpanded = !_equippedExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          _equippedExpanded ? '收起' : '展开',
                          style: const TextStyle(
                            color: _archiveMuted,
                            fontSize: 10.5,
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
              spacing: 12,
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
                    // 当前穿戴区本身就是装备管理入口：点击整项直接卸下。
                    onTap: itemBusy ? null : () => unawaited(_toggleWear(item)),
                    borderRadius: BorderRadius.circular(5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: _archiveSurfaceSoft,
                        borderRadius: BorderRadius.circular(5),
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
                                fontSize: 10.8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          if (itemBusy)
                            const SizedBox.square(
                              dimension: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.4,
                                color: _archiveMuted,
                              ),
                            )
                          else
                            const Text(
                              '卸下',
                              style: TextStyle(
                                color: Color(0xFF5E625D),
                                fontSize: 9.5,
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

  Widget _inventoryList(List<NovelInventoryItem> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Text(
                loading ? '正在整理…' : '空空如也',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF62645F),
                  fontSize: 11.5,
                ),
              ),
            )
          else
            Column(
              children: <Widget>[
                for (var index = 0; index < items.length; index++) ...<Widget>[
                  _GameStyleInventoryRow(
                    item: items[index],
                    typeLabel: _displayTypeLabel(items[index]),
                    wearable: _isWearable(items[index]),
                    busy: busy == items[index].id,
                    onTap: () => _showItemDetail(items[index]),
                    onWear: () => _toggleWear(items[index]),
                  ),
                  if (index != items.length - 1)
                    const SizedBox(height: 4),
                ],
              ],
            ),
        ],
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
            // 全部物品统一按品质从高到低排序；同品质再按名称排序。
            final qualityCompare = _inventoryItemQuality(b).compareTo(_inventoryItemQuality(a));
            if (qualityCompare != 0) return qualityCompare;
            return a.name.compareTo(b.name);
          });
        final equipped = items
            .where((item) => _isWearable(item) && item.isEquipped)
            .toList();
        final skills = _skills(host);

        // 已穿戴物品只存在于“当前穿戴”区域，不再在背包列表中重复出现。
        final backpackItems = items.where((item) => !item.isEquipped).toList();

        // 底部分类只过滤真正留在背包里的物品。
        final filteredItems = backpackItems.where((item) {
          if (_filterIndex == 1) return _isWearable(item); // 装备：未穿戴的可穿戴物品
          if (_filterIndex == 2) return !_isWearable(item); // 道具：不能穿戴的物品
          return true; // 全部
        }).toList();

        return _GameStyleBackdrop(
          controller: widget.controller,
          embedded: widget.embedded,
          lightTheme: true,
          child: Column(
            children: <Widget>[
              _GameStyleHeader(
                title: '背包',
                english: 'INVENTORY',
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
                lightTheme: true,
              ),
              Expanded(
                child: ColoredBox(
                  color: _archiveBackground,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 8 : 26,
                          compact ? 2 : 8,
                          compact ? 8 : 26,
                          compact ? 2 : 6,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: _archiveAccent,
                              backgroundColor: _archiveSurface,
                              child: CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: <Widget>[
                                  SliverToBoxAdapter(
                                    child: _hero(host, equipped, skills),
                                  ),
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
                        ),
                      );
                    },
                  ),
                ),
              ),
              _inventoryFilterBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _inventoryFilterBar() {
    return ColoredBox(
      color: _archiveBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Row(
                children: <Widget>[
                  Expanded(child: _buildFilterBtn('全部', 0)),
                  const SizedBox(width: 1),
                  Expanded(child: _buildFilterBtn('穿戴', 1)),
                  const SizedBox(width: 1),
                  Expanded(child: _buildFilterBtn('道具', 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 底部三等分分类：填充、直角。只用选中态主题绿，其余保持浅灰。
  Widget _buildFilterBtn(String label, int index) {
    final selected = _filterIndex == index;
    return Material(
      color: selected ? _archiveThemeGreen : _archiveSurfaceSoft,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        onTap: () => setState(() => _filterIndex = index),
        borderRadius: BorderRadius.zero,
        child: SizedBox(
          height: 42,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? NovelPalette.accentDark : _archiveMuted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ),
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

  // 背包是白底，品质色必须优先保证文字可读性。
  // 不再使用粉白、浅蓝、浅绿这类低对比度颜色，全部压到中深色阶。
  return switch (value) {
    10 => const Color(0xFFB23A3A), // 神话 · 深红
    9 => const Color(0xFFA13E68),  // 至臻 · 深玫红
    8 => const Color(0xFF2F7772),  // 创世 · 深青
    7 => const Color(0xFFAD5A16),  // 传说 · 深橙
    6 => const Color(0xFF87691F),  // 史诗 · 深金
    5 => const Color(0xFF70509B),  // 稀有 · 深紫
    4 => const Color(0xFF3F6E9E),  // 精良 · 深蓝
    3 => const Color(0xFF34724A),  // 优秀 · 深绿
    2 => const Color(0xFF55775A),  // 进阶 · 墨绿
    _ => const Color(0xFF444844),  // 普通 · 深灰
  };
}

class _QualitySegments extends StatelessWidget {
  const _QualitySegments({
    required this.level,
    this.height = 4, // 高度调细一点，视觉更扁平精致
  });

  final int level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0, 10).toInt();
    const activeColor = _archiveThemeGreen; // 顶部属性数值统一使用项目主题绿
    
    return Row(
      children: List<Widget>.generate(3, (index) { // 改为 3 格
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
                      color: const Color(0xFFE8ECE8),
                      borderRadius: BorderRadius.circular(2), // 微圆角
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

class _EquipmentBonusMeter extends StatelessWidget {
  const _EquipmentBonusMeter({
    required this.label,
    required this.level,
  });

  final String label;
  final int level;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0, 10).toInt();
    return Semantics(
      label: '$label加成$normalized级',
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 29,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF565C56),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
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
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 背包列表只显示未穿戴物品，不再预留“已穿戴”状态竖条的空白。
              // 第一列：名称与描述。宽度自适应，但不会挤动右侧两列。
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
                          const SizedBox(width: 8),
                          const Text(
                            '已穿戴',
                            style: TextStyle(
                              color: _archiveThemeGreen,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .25,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description.isEmpty ? '点击查看详情' : description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: description.isEmpty
                            ? _archiveMutedSoft
                            : _archiveMuted,
                        fontSize: 10.8,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // 第二列：所有类型/槽位都使用同一个固定宽度与同一个右边界。
              // 因此“上身 / 饰品 / 手持 / 消耗品”等会严格落在同一垂线上。
              SizedBox(
                width: 58,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _archiveMutedSoft,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .25,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 第三列固定 54px：装备显示穿戴/卸下；普通物品显示数量。
              // 即使这一格没有内容也保留宽度，确保第二列绝不会左右漂移。
              SizedBox(
                width: 54,
                child: wearable
                    ? InkWell(
                        onTap: busy ? null : onWear,
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: equipped
                                ? const Color(0xFF222522)
                                : _archiveSurfaceSoft,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: busy
                              ? SizedBox.square(
                                  dimension: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: equipped
                                        ? Colors.white
                                        : _archiveMuted,
                                  ),
                                )
                              : Text(
                                  equipped ? '卸下' : '穿戴',
                                  style: TextStyle(
                                    color: equipped
                                        ? Colors.white
                                        : _archiveText,
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
                                  color: _archiveMuted,
                                  fontSize: 10.5,
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
        // 白绿主题下使用淡绿底色
        color: lightTheme 
            ? NovelPalette.accent.withOpacity(.12) 
            : Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          // 白绿主题下使用绿色文字
          color: lightTheme
              ? NovelPalette.accentDeep
              : (accent
                  ? const Color(0xFFD9DEE4)
                  : const Color(0xFFA5ABB3)),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

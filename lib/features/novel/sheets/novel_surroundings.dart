part of '../novel_sheets.dart';

// 页面入口 / 对外入口：
//   - showNovelSurroundingsDeveloperPreview(...)
//   - NovelSurroundingsTab
// 其余 `_Surround...` 类型均为探索页内部节点、拖拽、合成、拾取与教程实现。

// ============================================================================
// 当前场景“周围”互动页
// 走路探索版：格子仅作为后台坐标与事件数据，不绘制格子或雾霾遮罩。
// ============================================================================

const Color _themeGreen = NovelPalette.accent;

typedef NovelSurroundingsPreviewBattleLauncher = Future<String?> Function({
  required String enemyName,
  required int quality,
  required bool elite,
});

Future<void> showNovelSurroundingsDeveloperPreview(
  BuildContext context,
  NovelGameController controller, {
  NovelSurroundingsPreviewBattleLauncher? previewBattleLauncher,
}) async {
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false, // 允许透视下层路由
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        return Material(
          color: Colors.transparent, // 彻底移除不透明底色
          child: NovelSurroundingsTab(
            controller: controller,
            developerPreview: true,
            previewBattleLauncher: previewBattleLauncher,
            onClose: () => Navigator.of(routeContext).maybePop(),
          ),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class NovelSurroundingsTab extends StatelessWidget {
  const NovelSurroundingsTab({
    super.key,
    required this.controller,
    this.developerPreview = false,
    this.previewBattleLauncher,
    this.onClose,
  });

  final NovelGameController controller;
  final bool developerPreview;
  final NovelSurroundingsPreviewBattleLauncher? previewBattleLauncher;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _NovelSurroundingsPage(
      controller: controller,
      developerPreview: developerPreview,
      previewBattleLauncher: previewBattleLauncher,
      embedded: false,
      onClose: onClose,
    );
  }
}

/// 剧情主页底部的常驻探索舞台。
///
/// 与完整“周围”页面共用同一套远端探索状态、掉落和战斗入口，
/// 但只渲染走路场景，不显示独立页面标题栏、背包面板或关闭按钮。
class NovelSurroundingsInlineDock extends StatelessWidget {
  const NovelSurroundingsInlineDock({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final NovelGameController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _SurroundFogPrototype(
      controller: controller,
      developerPreview: false,
      embedded: true,
      movementEnabled: enabled,
    );
  }
}

enum _SurroundNodeType {
  environment,
  container,
  item,
  target,
  product,
  encounter,
}

Color _surroundQualityColor(int quality) {
  const colors = <Color>[
    Color(0xFFE5E7EB), // 1 白
    Color(0xFFA7F3D0), // 2 浅绿
    Color(0xFFF9A8D4), // 3 粉
    Color(0xFF7DD3FC), // 4 天蓝
    Color(0xFF3B82F6), // 5 深蓝
    Color(0xFF5F7F6A), // 6 墨茶绿
    Color(0xFFF59E0B), // 7 橙
    Color(0xFFA855F7), // 8 紫
    Color(0xFFEF4444), // 9 红
    Color(0xFFF4C95D), // 10 金
  ];
  final index = quality.clamp(1, 10).toInt() - 1;
  return colors[index];
}

String _surroundRewardAsset(String itemType) {
  return switch (itemType.trim().toLowerCase()) {
    'score' => 'assets/images/xing.webp',
    'gift' => 'assets/images/gift.webp',
    'lucky_card' => 'assets/images/lucky_card.webp',
    _ => '',
  };
}

class _SurroundNodeDef {
  const _SurroundNodeDef({
    required this.id,
    required this.label,
    required this.type,
    required this.position,
    this.text = '',
    this.children = const <String>[],
    this.collectible = false,
    this.enemyCount = 0,
    this.eliteCount = 0,
    this.quality = 1,
  });

  final String id;
  final String label;
  final _SurroundNodeType type;
  final Offset position;
  final String text;
  final List<String> children;
  final bool collectible;
  final int enemyCount;
  final int eliteCount;
  final int quality;
}

class _SurroundRecipe {
  const _SurroundRecipe({
    required this.a,
    required this.b,
    required this.result,
    required this.label,
    required this.text,
    this.consume = const <String>[],
    this.keep = const <String>[],
    this.resultType = _SurroundNodeType.product,
    this.resultCollectible = false,
  });

  final String a;
  final String b;
  final String result;
  final String label;
  final String text;
  final List<String> consume;
  final List<String> keep;
  final _SurroundNodeType resultType;
  final bool resultCollectible;
}

class _SurroundPreset {
  const _SurroundPreset({
    required this.rootId,
    required this.defs,
    required this.initialVisible,
    required this.recipes,
    required this.defaultGoal,
  });

  final String rootId;
  final Map<String, _SurroundNodeDef> defs;
  final Set<String> initialVisible;
  final List<_SurroundRecipe> recipes;
  final String defaultGoal;
}

class _SurroundInfo {
  const _SurroundInfo({
    required this.text,
    this.title = '',
    this.consume = const <String>[],
    this.keep = const <String>[],
    this.created = const <String>[],
    this.gain = const <String>[],
  });

  final String text;
  final String title;
  final List<String> consume;
  final List<String> keep;
  final List<String> created;
  final List<String> gain;
}

class _NovelSurroundingsPage extends StatefulWidget {
  const _NovelSurroundingsPage({
    required this.controller,
    this.embedded = false,
    this.developerPreview = false,
    this.previewBattleLauncher,
    this.onClose,
  });

  final NovelGameController controller;
  final bool embedded;
  final bool developerPreview;
  final NovelSurroundingsPreviewBattleLauncher? previewBattleLauncher;
  final VoidCallback? onClose;

  @override
  State<_NovelSurroundingsPage> createState() => _NovelSurroundingsPageState();
}

class _NovelSurroundingsPageState extends State<_NovelSurroundingsPage> {
  late _SurroundPreset _preset;
  final Map<String, Offset> _customPositions = <String, Offset>{};
  final Set<String> _visible = <String>{};
  final Set<String> _discovered = <String>{};
  final Set<String> _revealing = <String>{};
  final Set<String> _collected = <String>{};
  final Set<String> _consumed = <String>{};
  final Set<String> _collecting = <String>{};

  String _sceneKey = '';
  String _payloadSignature = '';
  String _activeId = '';
  String? _draggingId;
  String? _mergeTargetId;
  bool _expanding = false;
  OverlayEntry? _collectedToastEntry;
  _SurroundInfo _info = const _SurroundInfo(
    title: '操作提示',
    text: '点击带“+”的节点继续探索；拖动物品进行组合，最终物品点击即可拾取。',
  );

  @override
  void initState() {
    super.initState();
    if (widget.developerPreview) {
      _sceneKey = 'developer-surroundings-preview';
      _preset = _developerPreviewPreset();
      _visible.addAll(_preset.initialVisible);
      _discovered.addAll(_preset.initialVisible);
      _activeId = _preset.rootId;
      _info = const _SurroundInfo(
        title: '完整交互预览',
        text: '先拖动材料完成两段组合，再点击最终成品放入背包。',
      );
      return;
    }
    _sceneKey = _currentSceneKey();
    _preset = _emptyPreset(widget.controller.locationTitle.trim());
    _syncFromController(notify: false);
    widget.controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.surroundingsData.isNotEmpty) return;
      unawaited(widget.controller.loadSurroundings());
    });
  }

  @override
  void dispose() {
    _collectedToastEntry?.remove();
    _collectedToastEntry = null;
    if (!widget.developerPreview) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    super.dispose();
  }

  String _currentSceneKey() {
    final dataKey = stringValue(
      widget.controller.surroundingsData['scene_key'] ??
          widget.controller.surroundingsAvailability['scene_key'],
    ).trim();
    if (dataKey.isNotEmpty) return dataKey;
    return '${widget.controller.locationTitle.trim()}\u0000${widget.controller.locationSubtitle.trim()}';
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncFromController();
  }

  _SurroundPreset _emptyPreset(String sceneTitle) {
    return _SurroundPreset(
      rootId: '',
      defs: const <String, _SurroundNodeDef>{},
      initialVisible: const <String>{},
      recipes: const <_SurroundRecipe>[],
      defaultGoal: sceneTitle.isEmpty ? '调查当前场景' : '调查$sceneTitle',
    );
  }

  _SurroundPreset _developerPreviewPreset() {
    return const _SurroundPreset(
      rootId: 'preview_scene',
      defs: <String, _SurroundNodeDef>{
        'preview_scene': _SurroundNodeDef(
          id: 'preview_scene',
          label: '海滩边缘',
          type: _SurroundNodeType.environment,
          position: Offset(.50, .50),
          text: '潮水退去后，海滩边缘留下了几处值得翻看的角落。',
          children: <String>[
            'preview_drift_pile',
            'preview_rock_side',
          ],
        ),
        'preview_drift_pile': _SurroundNodeDef(
          id: 'preview_drift_pile',
          label: '漂流物堆',
          type: _SurroundNodeType.container,
          position: Offset(.34, .34),
          text: '这里缠着几件被海水冲上岸的材料。',
          children: <String>[
            'preview_branch',
            'preview_vine',
          ],
        ),
        'preview_rock_side': _SurroundNodeDef(
          id: 'preview_rock_side',
          label: '礁石边缘',
          type: _SurroundNodeType.container,
          position: Offset(.70, .34),
          text: '礁石边缘夹着一些可以利用的碎片。',
          children: <String>[
            'preview_stone',
          ],
        ),
        'preview_branch': _SurroundNodeDef(
          id: 'preview_branch',
          label: '干燥长枝',
          type: _SurroundNodeType.item,
          position: Offset(.22, .72),
          text: '一根足够结实的长枝，可以继续加工。',
        ),
        'preview_stone': _SurroundNodeDef(
          id: 'preview_stone',
          label: '尖锐石片',
          type: _SurroundNodeType.item,
          position: Offset(.76, .70),
          text: '边缘锋利，可以削尖木材。',
        ),
        'preview_vine': _SurroundNodeDef(
          id: 'preview_vine',
          label: '柔韧藤条',
          type: _SurroundNodeType.item,
          position: Offset(.40, .78),
          text: '足够结实，可以用来捆扎。',
        ),
        'preview_sharp_branch': _SurroundNodeDef(
          id: 'preview_sharp_branch',
          label: '削好的长棍',
          type: _SurroundNodeType.product,
          position: Offset(.56, .62),
          text: '长枝已经削尖，可以继续和藤条组合。',
        ),
        'preview_product': _SurroundNodeDef(
          id: 'preview_product',
          label: '简易椰钩',
          type: _SurroundNodeType.product,
          position: Offset(.64, .78),
          text: '已经制作完成，可以拾取。',
          collectible: true,
        ),
      },
      initialVisible: <String>{
        'preview_scene',
        'preview_drift_pile',
        'preview_rock_side',
      },
      recipes: <_SurroundRecipe>[
        _SurroundRecipe(
          a: 'preview_branch',
          b: 'preview_stone',
          result: 'preview_sharp_branch',
          label: '削好的长棍',
          text: '石片削去了长枝多余的部分，得到一根尖锐而结实的长棍。',
          consume: <String>['preview_branch', 'preview_stone'],
          resultType: _SurroundNodeType.product,
        ),
        _SurroundRecipe(
          a: 'preview_sharp_branch',
          b: 'preview_vine',
          result: 'preview_product',
          label: '简易椰钩',
          text: '藤条把削好的长棍固定成了简易椰钩。',
          consume: <String>['preview_sharp_branch', 'preview_vine'],
          resultType: _SurroundNodeType.product,
          resultCollectible: true,
        ),
      ],
      defaultGoal: '先点击“漂流物堆”和“礁石边缘”展开材料，再拖动完成两段合成，最后拾取成品。',
    );
  }

  String _signatureOf(JsonMap payload) {
    return <String>[
      stringValue(payload['scene_key']),
      stringValue(payload['status']),
      (payload['visible'] is List ? payload['visible'] as List : const <dynamic>[]).join(','),
      (payload['discovered'] is List ? payload['discovered'] as List : const <dynamic>[]).join(','),
      (payload['claimed'] is List ? payload['claimed'] as List : const <dynamic>[]).join(','),
      stringValue(asJsonMap(payload['event'])['text']),
    ].join('|');
  }

  _SurroundNodeType _nodeTypeOf(dynamic value) {
    return switch (stringValue(value).trim().toLowerCase()) {
      'container' => _SurroundNodeType.container,
      'item' => _SurroundNodeType.item,
      'target' => _SurroundNodeType.target,
      'product' => _SurroundNodeType.product,
      'encounter' => _SurroundNodeType.encounter,
      _ => _SurroundNodeType.environment,
    };
  }

  Offset _defaultNodePosition(int index) {
    const positions = <Offset>[
      Offset(.50, .50),
      Offset(.68, .30),
      Offset(.32, .30),
      Offset(.32, .70),
      Offset(.68, .70),
      Offset(.16, .17),
      Offset(.36, .14),
      Offset(.64, .14),
      Offset(.84, .18),
      Offset(.15, .83),
      Offset(.36, .86),
      Offset(.64, .86),
      Offset(.85, .82),
      Offset(.50, .20),
    ];
    return positions[index % positions.length];
  }

  List<Offset> _rootBranchPositions(int count) {
    if (count <= 0) return const <Offset>[];
    if (count == 1) return const <Offset>[Offset(.50, .34)];
    if (count == 2) {
      return const <Offset>[Offset(.40, .38), Offset(.60, .38)];
    }
    if (count == 3) {
      return const <Offset>[
        Offset(.50, .33),
        Offset(.38, .60),
        Offset(.62, .60),
      ];
    }
    if (count == 4) {
      return const <Offset>[
        Offset(.61, .38),
        Offset(.39, .38),
        Offset(.39, .62),
        Offset(.61, .62),
      ];
    }
    return List<Offset>.generate(count, (index) {
      final angle = -math.pi / 2 + math.pi * 2 * index / count;
      return Offset(
        .5 + math.cos(angle) * .19,
        .5 + math.sin(angle) * .17,
      );
    });
  }

  List<Offset> _branchChildPositions(Offset branch, int count) {
    if (count <= 0) return const <Offset>[];
    final outwardAngle = math.atan2(branch.dy - .5, branch.dx - .5);
    final spread = count == 1
        ? 0.0
        : math.min(math.pi * .24, math.pi * .10 * (count - 1));
    return List<Offset>.generate(count, (index) {
      final progress = count == 1 ? 0.0 : index / (count - 1) - .5;
      final angle = outwardAngle + spread * progress;
      const distance = .16;
      return Offset(
        (branch.dx + math.cos(angle) * distance).clamp(.10, .90).toDouble(),
        (branch.dy + math.sin(angle) * distance).clamp(.12, .90).toDouble(),
      );
    });
  }

  int _stableNodeHash(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  Map<String, Offset> _graphNodePositions(
    String rootId,
    Map<String, _SurroundNodeDef> defs,
    int sceneSeed,
  ) {
    final result = <String, Offset>{};
    final root = defs[rootId];
    if (root != null) {
      result[rootId] = const Offset(.5, .5);
      final branchIds = root.children;
      final branchPositions = _rootBranchPositions(branchIds.length);
      for (var index = 0; index < branchIds.length; index++) {
        final positionIndex = branchPositions.isEmpty
            ? 0
            : (index + sceneSeed.abs()) % branchPositions.length;
        result[branchIds[index]] = branchPositions[positionIndex];
      }

      final visited = <String>{};

      void layoutDeeperChildren(String parentId, int depth) {
        if (!visited.add(parentId)) return;
        final parentDef = defs[parentId];
        final parentPosition = result[parentId];
        if (parentDef == null || parentPosition == null) return;
        final children = parentDef.children;
        if (children.isEmpty) return;
        final outwardAngle = math.atan2(
          parentPosition.dy - .5,
          parentPosition.dx - .5,
        );
        final spread = children.length <= 1
            ? 0.0
            : math.min(math.pi * .32, math.pi * .10 * (children.length - 1));
        for (var index = 0; index < children.length; index++) {
          final childId = children[index];
          if (!result.containsKey(childId)) {
            final progress = children.length == 1
                ? 0.0
                : index / (children.length - 1) - .5;
            final angle = outwardAngle + spread * progress;
            final distance = math.max(.08, .11 - depth * .008);
            result[childId] = Offset(
              (parentPosition.dx + math.cos(angle) * distance)
                  .clamp(.08, .92)
                  .toDouble(),
              (parentPosition.dy + math.sin(angle) * distance)
                  .clamp(.09, .91)
                  .toDouble(),
            );
          }
          layoutDeeperChildren(childId, depth + 1);
        }
      }

      for (var branchIndex = 0; branchIndex < branchIds.length; branchIndex++) {
        final branchId = branchIds[branchIndex];
        final branchDef = defs[branchId];
        final branchPosition = result[branchId];
        if (branchDef == null || branchPosition == null) continue;
        final childPositions = _branchChildPositions(
          branchPosition,
          branchDef.children.length,
        );
        for (var childIndex = 0;
            childIndex < branchDef.children.length;
            childIndex++) {
          result[branchDef.children[childIndex]] = childPositions[childIndex];
        }
        for (final childId in branchDef.children) {
          layoutDeeperChildren(childId, 1);
        }
      }
    }

    final occupied = result.values.toList();
    final orphanIds = defs.keys.where((id) => !result.containsKey(id)).toList()
      ..sort();
    for (final id in orphanIds) {
      final seed = _stableNodeHash('$sceneSeed:$id');
      var angle = math.pi * 2 * (seed % 360) / 360;
      var candidate = const Offset(.5, .2);
      for (var attempt = 0; attempt < 10; attempt++) {
        candidate = Offset(
          (.5 + math.cos(angle) * .36).clamp(.08, .92).toDouble(),
          (.5 + math.sin(angle) * .34).clamp(.09, .91).toDouble(),
        );
        if (occupied.every((other) => (other - candidate).distance >= .105)) {
          break;
        }
        angle += math.pi * .61803398875;
      }
      result[id] = candidate;
      occupied.add(candidate);
    }
    return result;
  }

  _SurroundPreset _presetFromPayload(JsonMap payload) {
    final nodeMaps = (payload['nodes'] is List ? payload['nodes'] as List : const <dynamic>[])
        .map(asJsonMap)
        .where((node) => stringValue(node['id']).trim().isNotEmpty)
        .toList();
    final parsedDefs = <String, _SurroundNodeDef>{};
    for (var index = 0; index < nodeMaps.length; index++) {
      final node = nodeMaps[index];
      final id = stringValue(node['id']).trim();
      final children = (node['children'] is List ? node['children'] as List : const <dynamic>[])
          .map(stringValue)
          .where((child) => child.trim().isNotEmpty)
          .toList();
      final encounter = asJsonMap(node['encounter']);
      parsedDefs[id] = _SurroundNodeDef(
        id: id,
        label: stringValue(node['label'], id),
        type: _nodeTypeOf(node['type']),
        position: _defaultNodePosition(index),
        text: stringValue(node['text']),
        children: children,
        collectible: boolValue(node['collectible']),
        enemyCount: intValue(encounter['enemy_count']),
        eliteCount: intValue(encounter['elite_count']),
        quality: intValue(encounter['quality'], 1),
      );
    }
    final rootId = stringValue(payload['root_id']).trim();
    final sceneSeed = intValue(payload['scene_seed']);
    final layoutPositions = _graphNodePositions(
      rootId,
      parsedDefs,
      sceneSeed,
    );
    final defs = <String, _SurroundNodeDef>{
      for (final entry in parsedDefs.entries)
        entry.key: _SurroundNodeDef(
          id: entry.value.id,
          label: entry.value.label,
          type: entry.value.type,
          position: layoutPositions[entry.key] ?? entry.value.position,
          text: entry.value.text,
          children: entry.value.children,
          collectible: entry.value.collectible,
          enemyCount: entry.value.enemyCount,
          eliteCount: entry.value.eliteCount,
          quality: entry.value.quality,
        ),
    };
    final recipes = <_SurroundRecipe>[];
    for (final raw in payload['recipes'] is List ? payload['recipes'] as List : const <dynamic>[]) {
      final recipe = asJsonMap(raw);
      final a = stringValue(recipe['a']).trim();
      final b = stringValue(recipe['b']).trim();
      final result = stringValue(recipe['result']).trim();
      if (a.isEmpty || b.isEmpty || result.isEmpty) continue;
      final resultDef = defs[result];
      recipes.add(_SurroundRecipe(
        a: a,
        b: b,
        result: result,
        label: stringValue(recipe['label'], resultDef?.label ?? result),
        text: stringValue(recipe['text'], '组合成功。'),
        consume: (recipe['consume'] is List ? recipe['consume'] as List : <dynamic>[a, b])
            .map(stringValue)
            .where((id) => id.trim().isNotEmpty)
            .toList(),
        resultType: resultDef?.type ?? _SurroundNodeType.product,
        resultCollectible: resultDef?.collectible ?? false,
      ));
    }
    final initial = (payload['initial_visible'] is List
            ? payload['initial_visible'] as List
            : const <dynamic>[])
        .map(stringValue)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    return _SurroundPreset(
      rootId: rootId,
      defs: defs,
      initialVisible: initial,
      recipes: recipes,
      defaultGoal: stringValue(payload['goal'], '调查当前场景'),
    );
  }

  void _syncFromController({bool notify = true}) {
    final payload = widget.controller.surroundingsData;
    final nextSceneKey = _currentSceneKey();
    final nextSignature = payload.isEmpty ? '' : _signatureOf(payload);

    void apply() {
      if (nextSceneKey != _sceneKey) {
        _sceneKey = nextSceneKey;
        _payloadSignature = '';
        _preset = _emptyPreset(widget.controller.locationTitle.trim());
        _visible.clear();
        _discovered.clear();
        _collected.clear();
        _consumed.clear();
        _collecting.clear();
        _customPositions.clear();
        _activeId = '';
      }
      if (payload.isEmpty || nextSignature == _payloadSignature) return;
      _payloadSignature = nextSignature;
      final previousVisible = Set<String>.of(_visible);
      _preset = _presetFromPayload(payload);
      _visible
        ..clear()
        ..addAll((payload['visible'] is List ? payload['visible'] as List : const <dynamic>[])
            .map(stringValue));
      _discovered
        ..clear()
        ..addAll((payload['discovered'] is List ? payload['discovered'] as List : const <dynamic>[])
            .map(stringValue));
      _collected
        ..clear()
        ..addAll((payload['claimed'] is List ? payload['claimed'] as List : const <dynamic>[])
            .map(stringValue));

      final event = asJsonMap(payload['event']);
      final eventConsumed = (event['consumed'] is List
              ? event['consumed'] as List
              : const <dynamic>[])
          .map(stringValue)
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      _consumed.addAll(eventConsumed);

      _visible.removeAll(_consumed);
      _customPositions.removeWhere((id, _) => !_visible.contains(id));
      _revealing.removeAll(_consumed);
      _collecting.removeAll(_consumed);
      if (_activeId.isEmpty || !_visible.contains(_activeId)) {
        _activeId = _preset.rootId;
      }
      _draggingId = null;
      _mergeTargetId = null;
      final added = _visible.difference(previousVisible);
      _revealing.addAll(added);

      final eventText = stringValue(event['text']).trim();
      if (eventText.isNotEmpty) {
        _info = _SurroundInfo(
          title: stringValue(event['title']),
          text: eventText,
          consume: (event['consumed'] is List ? event['consumed'] as List : const <dynamic>[])
              .map(stringValue)
              .toList(),
          created: (event['created'] is List ? event['created'] as List : const <dynamic>[])
              .map(stringValue)
              .toList(),
          gain: (event['claimed'] is List ? event['claimed'] as List : const <dynamic>[])
              .map(stringValue)
              .toList(),
        );
      } else if (previousVisible.isEmpty) {
        _info = _SurroundInfo(
          title: '当前调查',
          text: _preset.defaultGoal,
        );
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
    if (_revealing.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(_revealing.clear);
      });
    }
  }

  Map<String, _SurroundNodeDef> get _allDefs => _preset.defs;

  _SurroundNodeDef? _defOf(String id) => _preset.defs[id];

  Offset _positionOf(String id) =>
      _customPositions[id] ?? _defOf(id)?.position ?? const Offset(.5, .5);

  String? _parentOf(String id) {
    for (final entry in _allDefs.entries) {
      if (entry.value.children.contains(id)) return entry.key;
    }
    return null;
  }

  bool _isExplorable(String id) {
    final def = _defOf(id);
    if (def == null || def.children.isEmpty) return false;
    return def.children.any(
      (child) => !_discovered.contains(child) && !_consumed.contains(child),
    );
  }

  bool _isExhausted(String id) {
    final def = _defOf(id);
    if (def == null || def.children.isEmpty) return false;
    return def.children.every(_discovered.contains);
  }

  bool _isDraggable(String id) {
    final def = _defOf(id);
    if (def == null || def.collectible) return false;
    final type = def.type;
    return type == _SurroundNodeType.item || type == _SurroundNodeType.product;
  }

  _SurroundRecipe? _recipeFor(String a, String b) {
    for (final recipe in _preset.recipes) {
      if ((recipe.a == a && recipe.b == b) ||
          (recipe.a == b && recipe.b == a)) {
        return recipe;
      }
    }
    return null;
  }

  String _labelOf(String id) => _defOf(id)?.label ?? id;

  void _resetLayout() {
    setState(() {
      _customPositions.clear();
      _draggingId = null;
      _mergeTargetId = null;
    });
  }

  Future<void> _selectNode(String id) async {
    if (_expanding || _draggingId != null || _collecting.contains(id)) return;
    final def = _defOf(id);
    if (def == null) return;

    if (def.collectible) {
      await _collectNode(id, def);
      return;
    }

    if (def.type == _SurroundNodeType.encounter) {
      widget.onClose?.call();
      await Future<void>.delayed(Duration.zero);
      await widget.controller.startSurroundEncounter(
        nodeId: id,
        targetName: def.label,
      );
      return;
    }

    final hidden = def.children
        .where((child) =>
            !_discovered.contains(child) && !_consumed.contains(child))
        .toList();
    if (hidden.isEmpty) {
      setState(() {
        _activeId = id;
        _info = _SurroundInfo(
          title: def.label,
          text: def.text.isEmpty
              ? (_isExhausted(id) ? '这里已经搜索过，没有更多内容了。' : '暂时没有更多发现。')
              : def.text,
        );
      });
      return;
    }

    setState(() {
      _activeId = id;
      _expanding = true;
      _info = _SurroundInfo(
        title: def.label,
        text: '正在查看周围…',
      );
    });

    if (widget.developerPreview) {
      setState(() {
        _expanding = false;
        _visible.addAll(hidden);
        _discovered.addAll(hidden);
        _revealing.addAll(hidden);
        _info = _SurroundInfo(
          title: def.label,
          text: hidden.length == 1
              ? '你发现了「${_labelOf(hidden.first)}」。'
              : '你发现了${hidden.map(_labelOf).join('、')}。',
        );
      });
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _revealing.removeAll(hidden));
      });
      return;
    }

    try {
      await widget.controller.investigateSurroundNode(id);
      if (!mounted) return;
      setState(() => _expanding = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _expanding = false;
        _info = _SurroundInfo(
          title: def.label,
          text: widget.controller.surroundingsError.isEmpty
              ? '调查失败，请重试。'
              : widget.controller.surroundingsError,
        );
      });
    }
  }

  Future<void> _collectNode(String id, _SurroundNodeDef def) async {
    setState(() {
      _collecting.add(id);
      _activeId = id;
      _info = _SurroundInfo(
        title: def.label,
        text: '正在放入背包…',
      );
    });
    if (widget.developerPreview) {
      await Future<void>.delayed(const Duration(milliseconds: 520));
      if (!mounted) return;
      setState(() {
        _collecting.remove(id);
        _collected.add(id);
        _visible.remove(id);
        _customPositions.remove(id);
        _activeId = _preset.rootId;
        _info = _SurroundInfo(
          title: '已放入背包',
          text: '「${def.label}」已放入背包。（开发者预览，不写入存档）',
          gain: <String>[id],
        );
      });
      _showCollectedToast(def.label);
      return;
    }
    try {
      final payload = await widget.controller.claimSurroundReward(id);
      if (!mounted) return;
      final reward = asJsonMap(payload['reward']);
      final rewardName = stringValue(reward['name'], def.label);
      final rewardType = stringValue(
        reward['type'] ?? reward['item_type'],
      ).trim().toLowerCase();
      final isScore = rewardType == 'score';
      final isRareShopItem =
          rewardType == 'gift' || rewardType == 'lucky_card';
      final rewardAmount = intValue(
        reward['score'] ?? reward['quantity'],
        1,
      );
      final rewardAsset = stringValue(
        reward['image_asset'],
        _surroundRewardAsset(rewardType),
      ).trim();
      final bonusRewards = (payload['bonus_rewards'] is List
              ? payload['bonus_rewards'] as List
              : const <dynamic>[])
          .map(asJsonMap)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final bonusLabels = bonusRewards.map((bonus) {
        final name = stringValue(bonus['name'], '额外奖励');
        final amount = intValue(bonus['score'] ?? bonus['quantity'], 1);
        return '$name ×$amount';
      }).toList(growable: false);
      final bonusAssets = bonusRewards
          .map((bonus) => stringValue(
                bonus['image_asset'],
                _surroundRewardAsset(stringValue(
                  bonus['type'] ?? bonus['item_type'],
                )),
              ).trim())
          .where((asset) => asset.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _collecting.remove(id);
        _info = _SurroundInfo(
          title: isScore
              ? '获得星块'
              : isRareShopItem
                  ? '稀有发现'
                  : '已放入背包',
          text: (isScore || isRareShopItem
              ? '探索中发现$rewardName ×$rewardAmount。'
              : '「$rewardName」已放入背包。') +
              (bonusLabels.isEmpty ? '' : ' 额外发现：${bonusLabels.join('、')}。'),
          gain: <String>[id],
        );
      });
      _showCollectedToast(
        bonusLabels.isEmpty
            ? rewardName
            : '$rewardName + ${bonusLabels.join('、')}',
        assetPath: rewardAsset,
        assetPaths: bonusAssets,
        scoreAmount: isScore ? rewardAmount : 0,
        quantity: rewardAmount,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _collecting.remove(id);
        _info = _SurroundInfo(
          title: def.label,
          text: widget.controller.surroundingsError.isEmpty
              ? '领取失败，请重试。'
              : widget.controller.surroundingsError,
        );
      });
    }
  }

  void _showCollectedToast(
    String rewardName, {
    String assetPath = '',
    List<String> assetPaths = const <String>[],
    int scoreAmount = 0,
    int quantity = 1,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _collectedToastEntry?.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        return Positioned(
          top: media.padding.top + media.size.height * .33,
          left: 24,
          right: 24,
          child: _SurroundPickupRewardToast(
            assetPath: assetPath,
            assetPaths: assetPaths,
            text: scoreAmount > 0
                ? '获得星块 ×$scoreAmount'
                : '获得$rewardName${quantity > 1 ? ' ×$quantity' : ''}',
            onCompleted: () {
              if (_collectedToastEntry != entry) return;
              entry.remove();
              _collectedToastEntry = null;
            },
          ),
        );
      },
    );

    _collectedToastEntry = entry;
    overlay.insert(entry);
  }

  void _beginDrag(String id) {
    if (!_isDraggable(id)) return;
    setState(() {
      _draggingId = id;
      _mergeTargetId = null;
      _activeId = id;
    });
  }

  void _updateDrag(String id, DragUpdateDetails details, Size size) {
    if (_draggingId != id || size.width <= 0 || size.height <= 0) return;
    final current = _positionOf(id);
    final next = Offset(
      (current.dx + details.delta.dx / size.width).clamp(.055, .945).toDouble(),
      (current.dy + details.delta.dy / size.height).clamp(.075, .925).toDouble(),
    );

    String? nearest;
    var nearestDistance = double.infinity;
    for (final other in _visible) {
      if (other == id || _recipeFor(id, other) == null) continue;
      final distance = (_positionOf(other) - next).distance;
      if (distance < .13 && distance < nearestDistance) {
        nearest = other;
        nearestDistance = distance;
      }
    }

    setState(() {
      _customPositions[id] = next;
      _mergeTargetId = nearest;
    });
  }

  void _finishDrag(String id) {
    if (_draggingId != id) return;
    final target = _mergeTargetId;
    if (target != null && _recipeFor(id, target) != null) {
      unawaited(_performMerge(id, target));
      return;
    }

    setState(() {
      _draggingId = null;
      _mergeTargetId = null;
      _customPositions[id] = _avoidOverlap(id, _positionOf(id));
    });
  }

  Offset _avoidOverlap(String id, Offset start) {
    var result = start;
    for (var pass = 0; pass < 5; pass++) {
      var moved = false;
      for (final other in _visible) {
        if (other == id) continue;
        final op = _positionOf(other);
        final delta = result - op;
        final distance = delta.distance;
        if (distance >= .115) continue;
        final direction = distance < .002
            ? const Offset(1, 0)
            : delta / distance;
        result += direction * (.115 - distance + .008);
        result = Offset(
          result.dx.clamp(.055, .945).toDouble(),
          result.dy.clamp(.075, .925).toDouble(),
        );
        moved = true;
      }
      if (!moved) break;
    }
    return result;
  }

  Future<void> _performMerge(String a, String b) async {
    final recipe = _recipeFor(a, b);
    if (recipe == null) return;
    final pa = _positionOf(a);
    final pb = _positionOf(b);
    final resultPosition = Offset(
      ((pa.dx + pb.dx) / 2).clamp(.08, .92).toDouble(),
      ((pa.dy + pb.dy) / 2).clamp(.10, .90).toDouble(),
    );

    setState(() {
      _draggingId = null;
      _mergeTargetId = null;
      _info = _SurroundInfo(
        title: '正在组合',
        text: '正在确认这两个物品能否产生作用…',
      );
    });
    if (widget.developerPreview) {
      setState(() {
        _consumed.addAll(recipe.consume);
        for (final id in recipe.consume) {
          _visible.remove(id);
          _customPositions.remove(id);
          _revealing.remove(id);
          _collecting.remove(id);
        }
        _visible.add(recipe.result);
        _discovered.add(recipe.result);
        _customPositions[recipe.result] = resultPosition;
        _revealing.add(recipe.result);
        _activeId = recipe.result;
        _info = _SurroundInfo(
          title: '组合成功',
          text: recipe.text,
          consume: recipe.consume,
          keep: recipe.keep,
          created: <String>[recipe.result],
        );
      });
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _revealing.remove(recipe.result));
      });
      return;
    }

    try {
      await widget.controller.combineSurroundNodes(a, b);
      if (!mounted) return;
      setState(() {
        _consumed.addAll(recipe.consume);
        _visible.removeAll(recipe.consume);
        for (final id in recipe.consume) {
          _customPositions.remove(id);
          _revealing.remove(id);
          _collecting.remove(id);
        }
        _customPositions[recipe.result] = resultPosition;
        _activeId = recipe.result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _info = _SurroundInfo(
          title: '组合失败',
          text: widget.controller.surroundingsError.isEmpty
              ? '组合没有成功，请重试。'
              : widget.controller.surroundingsError,
        );
      });
    }
  }

  Future<void> _showTutorial() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(.45),
      builder: (dialogContext) {
        final screenHeight = MediaQuery.sizeOf(dialogContext).height;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 380,
              maxHeight: math.min(650.0, screenHeight * .82),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.075),
                    border: Border.all(
                      color: Colors.white.withOpacity(.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 15, 12, 11),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const Text(
                                    '玩法教程',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .25,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '探索 · 组合 · 获得',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 9.8,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: .35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 1, color: Colors.white.withOpacity(0.1)),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: const Column(
                            children: <Widget>[
                              _SurroundTutorialStep(
                                number: '01',
                                icon: Icons.touch_app_outlined,
                                title: '点击探索',
                                text: '看到带“+”的节点就可以点开，新的物品和可互动位置会逐步出现。',
                                visual: _SurroundTutorialVisual.explore,
                              ),
                              _SurroundTutorialStep(
                                number: '02',
                                icon: Icons.open_with_rounded,
                                title: '拖动组合',
                                text: '拖动物品靠近另一个节点；出现绿色高亮时，松手即可尝试组合。',
                                visual: _SurroundTutorialVisual.merge,
                              ),
                              _SurroundTutorialStep(
                                number: '03',
                                icon: Icons.inventory_2_outlined,
                                title: '拾取成品',
                                text: '可获得的最终成品会变成绿色。点击它，物品就会进入你的背包。',
                                visual: _SurroundTutorialVisual.collect,
                              ),
                              _SurroundTutorialStep(
                                number: '04',
                                icon: Icons.center_focus_weak_rounded,
                                title: '整理画布',
                                text: '节点拖乱了就点右下角归位。它只整理位置，不会清除探索或组合进度。',
                                visual: _SurroundTutorialVisual.arrange,
                                last: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          height: 38,
                          child: Material(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              borderRadius: BorderRadius.circular(6),
                              child: const Center(
                                child: Text(
                                  '知道了',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .2,
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
          ),
        );
      },
    );
  }

  Widget _buildRemoteState() {
    final loading = widget.controller.isSurroundingsLoading;
    final error = widget.controller.surroundingsError.trim();
    final available = boolValue(
      widget.controller.surroundingsData['available'] ??
          widget.controller.surroundingsAvailability['available'],
    );
    final reason = stringValue(
      widget.controller.surroundingsData['reason'] ??
          widget.controller.surroundingsAvailability['reason'],
    ).trim();
    final text = loading
        ? '正在观察当前场景…'
        : error.isNotEmpty
            ? error
            : available
                ? '调查内容正在准备。'
                : (reason.isEmpty ? '当前位置暂时没有可调查内容。' : reason);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 310),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _themeGreen,
                  ),
                )
              else
                Icon(
                  available ? Icons.radar_rounded : Icons.visibility_off_outlined,
                  size: 25,
                  color: Colors.white.withOpacity(0.4),
                ),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 14,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!loading && error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => unawaited(
                    widget.controller.loadSurroundings(force: true),
                  ),
                  child: const Text('重新调查', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final sceneTitle = widget.developerPreview
            ? '海滩边缘'
            : widget.controller.locationTitle.trim().isEmpty
                ? '当前场景'
                : widget.controller.locationTitle.trim();
        final title = '探索 · $sceneTitle';
        final closeAction = widget.onClose ??
            (widget.embedded ? null : () => Navigator.of(context).maybePop());

        final useFogGrid = widget.developerPreview ||
            widget.controller.surroundingsData.isEmpty ||
            boolValue(widget.controller.surroundingsData['grid_mode']);
        
        if (useFogGrid) {
          return _SurroundFogPrototype(
            controller: widget.controller,
            developerPreview: widget.developerPreview,
            previewBattleLauncher: widget.previewBattleLauncher,
            onClose: closeAction,
          );
        }

        // 与世界地图同款的深空滤镜和渐变光效
        return Material(
          color: widget.embedded ? Colors.transparent : Colors.black.withOpacity(0.34),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!widget.embedded)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -.08),
                          radius: 1.08,
                          colors: <Color>[
                            Color(0x164DA26A),
                            Color(0x0FFFFFFF),
                            Color(0x05000000),
                          ],
                          stops: <double>[0, .58, 1],
                        ),
                      ),
                    ),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        final compact = viewport.maxWidth < 620;
                        final horizontalInset = compact ? 12.0 : 28.0;
                        final verticalInset = compact ? 14.0 : 28.0;
                        final maxWindowWidth = math.max(0.0, viewport.maxWidth - horizontalInset * 2);
                        final maxWindowHeight = math.max(0.0, viewport.maxHeight - verticalInset * 2);
                        final windowWidth = math.min(760.0, maxWindowWidth);
                        final windowHeight = math.min(
                          compact ? 680.0 : 720.0,
                          maxWindowHeight * (compact ? .94 : .86),
                        );

                        return Center(
                          child: SizedBox(
                            width: windowWidth,
                            height: windowHeight,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                      width: 0.5,
                                    ),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      _SurroundingsHeader(
                                        title: title,
                                        onClose: closeAction,
                                      ),
                                      Expanded(
                                        child: _allDefs.isEmpty
                                            ? _buildRemoteState()
                                            : Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  compact ? 8 : 14,
                                                  compact ? 6 : 10,
                                                  compact ? 8 : 14,
                                                  0,
                                                ),
                                                child: Column(
                                                  children: <Widget>[
                                                    Expanded(
                                                      child: _SurroundStage(
                                                        defs: _allDefs,
                                                        visible: _visible,
                                                        positions: <String, Offset>{
                                                          for (final id in _visible)
                                                            id: _positionOf(id),
                                                        },
                                                        parentOf: _parentOf,
                                                        isExplorable: _isExplorable,
                                                        isExhausted: _isExhausted,
                                                        isDraggable: _isDraggable,
                                                        activeId: _activeId,
                                                        draggingId: _draggingId,
                                                        mergeTargetId: _mergeTargetId,
                                                        revealing: _revealing,
                                                        collecting: _collecting,
                                                        onResetLayout: _resetLayout,
                                                        onTutorial: _showTutorial,
                                                        onTap: _selectNode,
                                                        onDragStart: _beginDrag,
                                                        onDragUpdate: _updateDrag,
                                                        onDragEnd: _finishDrag,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: compact ? 106 : 102,
                                                      child: _SurroundInfoPanel(
                                                        info: _info,
                                                        labelOf: _labelOf,
                                                      ),
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _FogTileKind {
  empty,
  genericItem,
  normalEnemy,
  eliteEnemy,
  branch,
  stone,
  vine,
  coconutTree,
  bottle,
  scavenge,
  cache,
  hazard,
}

class _FogDrop {
  const _FogDrop({
    required this.name,
    required this.amount,
    required this.quality,
  });

  final String name;
  final int amount;
  final int quality;
}

class _FogTileDef {
  const _FogTileDef({
    required this.kind,
    required this.label,
    required this.text,
    this.quality = 1,
    this.energyBonus = 0,
    this.rare = false,
    this.nodeId = '',
    this.collectible = false,
  });

  final _FogTileKind kind;
  final String label;
  final String text;
  final int quality;
  final int energyBonus;
  final bool rare;
  final String nodeId;
  final bool collectible;
}

class _SurroundFogPrototype extends StatefulWidget {
  const _SurroundFogPrototype({
    required this.controller,
    required this.developerPreview,
    this.previewBattleLauncher,
    this.onClose,
    this.embedded = false,
    this.movementEnabled = true,
  });

  final NovelGameController controller;
  final bool developerPreview;
  final NovelSurroundingsPreviewBattleLauncher? previewBattleLauncher;
  final VoidCallback? onClose;
  final bool embedded;
  final bool movementEnabled;

  @override
  State<_SurroundFogPrototype> createState() => _SurroundFogPrototypeState();
}

class _SurroundFogPrototypeState extends State<_SurroundFogPrototype>
    with SingleTickerProviderStateMixin {
  static const int _columns = 6;
  static const int _rows = 6;
  static const int _startIndex = 20;
  static const Color _dangerRed = Color(0xFFD96F6F);
  static const Color _rareGold = Color(0xFFD8BF7A);

  Map<int, _FogTileDef> _tiles = <int, _FogTileDef>{};
  final Map<int, List<_FogDrop>> _lootByTile = <int, List<_FogDrop>>{};
  final Set<int> _revealed = <int>{};
  final Set<int> _searched = <int>{};
  final Map<String, int> _bag = <String, int>{};
  final Map<String, int> _bagQuality = <String, int>{};
  OverlayEntry? _rewardToastEntry;
  int? _scoreOverride;

  int _seed = 0;
  int _coconutBaseReward = 1;
  String _message = '';
  bool _completed = false;
  bool _developerBattleOpening = false;
  String _remoteSceneKey = '';

  // 走路探索：格子仍作为后台数据坐标，但不再作为 UI 展示。
  late final AnimationController _walkTicker;
  Duration _walkLastElapsed = Duration.zero;
  Offset _walkInput = Offset.zero;
  Offset? _walkTapTarget; // dx = 世界 X，dy = 纵深比例。
  double _playerWorldX = 0;
  double _playerDepth = .74;
  double _walkWorldWidth = 900;
  double _walkStageHeight = 420;
  bool _walkLayoutReady = false;
  bool _playerFacingLeft = false;
  bool _playerMoving = false;
  Uint8List? _previewBackgroundBytes;
  Uint8List? _previewPortraitBytes;
  final Set<int> _walkPendingReveal = <int>{};

  bool get _remote => !widget.developerPreview;

  @override
  void initState() {
    super.initState();
    _walkTicker = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    )
      ..addListener(_tickWalk)
      ..repeat();
    if (_remote) {
      widget.controller.addListener(_handleRemoteChanged);
      _syncRemote();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.controller.surroundingsData.isNotEmpty) return;
        unawaited(widget.controller.loadSurroundings());
      });
    } else {
      _startNewRun();
    }
  }

  @override
  void dispose() {
    _rewardToastEntry?.remove();
    _rewardToastEntry = null;
    _walkTicker
      ..removeListener(_tickWalk)
      ..dispose();
    if (_remote) widget.controller.removeListener(_handleRemoteChanged);
    super.dispose();
  }

  void _handleRemoteChanged() {
    if (!mounted) return;
    setState(_syncRemote);
  }

  void _syncRemote() {
    final payload = widget.controller.surroundingsData;
    if (payload.isEmpty) {
      _message = widget.controller.isSurroundingsLoading
          ? '正在生成当前场景的探索内容…'
          : '当前探索内容尚未载入。';
      return;
    }
    final nextSceneKey = stringValue(payload['scene_key']).trim();
    final sceneChanged = nextSceneKey != _remoteSceneKey;
    _remoteSceneKey = nextSceneKey;
    _seed = intValue(payload['scene_seed']);
    _tiles = _generateRemoteMap(payload);
    _revealed
      ..clear()
      ..addAll((payload['grid_revealed'] is List
              ? payload['grid_revealed'] as List
              : const <dynamic>[20])
          .map(intValue));
    // 走路探索版不再读取 grid_energy：客户端探索没有体力限制。
    _completed = stringValue(payload['status']) == 'exhausted';
    if (sceneChanged) {
      _bag.clear();
      _bagQuality.clear();
      _walkLayoutReady = false;
      _playerWorldX = 0;
      _walkTapTarget = null;
      _walkInput = Offset.zero;
    }
    _searched.clear();
    final resolved = (payload['resolved_encounters'] is List
            ? payload['resolved_encounters'] as List
            : const <dynamic>[])
        .map(stringValue)
        .toSet();
    final claimed = (payload['claimed'] is List
            ? payload['claimed'] as List
            : const <dynamic>[])
        .map(stringValue)
        .toSet();
    final consumed = (payload['consumed'] is List
            ? payload['consumed'] as List
            : const <dynamic>[])
        .map(stringValue)
        .toSet();
    for (final entry in _tiles.entries) {
      if (resolved.contains(entry.value.nodeId) ||
          claimed.contains(entry.value.nodeId) ||
          consumed.contains(entry.value.nodeId)) {
        _searched.add(entry.key);
      }
    }
    final eventText = stringValue(asJsonMap(payload['event'])['text']).trim();
    _message = eventText.isNotEmpty
        ? eventText
        : stringValue(payload['goal'], '在场景中自由走动并调查周围。');
  }

  Map<int, _FogTileDef> _generateRemoteMap(JsonMap payload) {
    final layout = payload['grid_layout'] is List
        ? payload['grid_layout'] as List
        : const <dynamic>[];
    final nodeMap = <String, JsonMap>{};
    for (final raw in payload['grid_nodes'] is List
        ? payload['grid_nodes'] as List
        : const <dynamic>[]) {
      final node = asJsonMap(raw);
      final id = stringValue(node['id']).trim();
      if (id.isNotEmpty) nodeMap[id] = node;
    }
    final result = <int, _FogTileDef>{};
    for (var index = 0; index < math.min(36, layout.length); index++) {
      final id = stringValue(layout[index]).trim();
      final node = nodeMap[id];
      if (id.isEmpty || node == null) continue;
      final encounter = asJsonMap(node['encounter']);
      final reward = asJsonMap(node['reward_preview']);
      final tier = stringValue(encounter['tier']).trim();
      final nodeType = stringValue(node['type']).trim();
      final kind = encounter.isNotEmpty
          ? (tier == 'elite'
              ? _FogTileKind.eliteEnemy
              : _FogTileKind.normalEnemy)
          : nodeType == 'container'
              ? _FogTileKind.scavenge
              : _FogTileKind.genericItem;
      result[index] = _FogTileDef(
        kind: kind,
        label: encounter.isNotEmpty
            ? stringValue(encounter['name'], stringValue(node['label'], id))
            : stringValue(node['label'], id),
        text: stringValue(node['text']),
        quality: intValue(encounter['quality'] ?? reward['quality'], 1),
        rare: tier == 'elite' || nodeType == 'product',
        nodeId: id,
        collectible: boolValue(node['collectible']),
      );
    }
    return result;
  }

  int _newSeed() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return (now ^ identityHashCode(this) ^ math.Random().nextInt(0x3fffffff)) &
        0x7fffffff;
  }

  void _startNewRun({int? seed}) {
    _seed = seed ?? _newSeed();
    _lootByTile.clear();
    _tiles = _generateMap(_seed);
    _revealed
      ..clear()
      ..add(_startIndex);
    _searched.clear();
    _bag.clear();
    _bagQuality.clear();
    _completed = false;
    _walkLayoutReady = false;
    _playerWorldX = 0;
    _walkTapTarget = null;
    _walkInput = Offset.zero;
    _coconutBaseReward = 1 + math.Random(_seed ^ 0x5F3759DF).nextInt(2);
    _message = '自由走动探索。走近区域会自动发现周围内容，发现目标后可直接调查。';
  }

  int _quality(math.Random random, {int min = 1, int max = 6}) {
    return min + random.nextInt(max - min + 1);
  }

  List<_FogDrop> _makeScavengeLoot(math.Random random, {bool rare = false}) {
    final normalPool = <String>[
      '木枝',
      '石片',
      '藤条',
      '布条',
      '生锈铁片',
      '贝壳碎片',
      '干粮碎包',
    ];
    final rarePool = <String>[
      '旧银币',
      '防水火柴',
      '密封干粮',
      '海蓝饰片',
      '旧式指南针',
    ];

    final count = rare ? 1 + random.nextInt(2) : 1 + random.nextInt(3);
    final drops = <_FogDrop>[];
    for (var i = 0; i < count; i++) {
      final pool = rare && i == 0 ? rarePool : normalPool;
      final name = pool[random.nextInt(pool.length)];
      drops.add(
        _FogDrop(
          name: name,
          amount: name == '旧银币' ? 1 + random.nextInt(2) : 1,
          quality: rare && i == 0
              ? _quality(random, min: 6, max: 9)
              : _quality(random, min: 1, max: rare ? 7 : 5),
        ),
      );
    }
    return drops;
  }

  Map<int, _FogTileDef> _generateMap(int seed) {
    final random = math.Random(seed);
    final used = <int>{_startIndex};
    final result = <int, _FogTileDef>{};
    final all = List<int>.generate(_rows * _columns, (index) => index)
      ..remove(_startIndex);

    int pick(
      bool Function(int index) test, {
      List<int> avoid = const <int>[],
      int minDistanceFromAvoid = 0,
    }) {
      final candidates = all.where((index) {
        if (used.contains(index) || !test(index)) return false;
        if (minDistanceFromAvoid > 0 &&
            avoid.any(
              (other) => _gridDistance(index, other) < minDistanceFromAvoid,
            )) {
          return false;
        }
        return true;
      }).toList()
        ..shuffle(random);
      if (candidates.isEmpty) {
        final fallback = all.where((index) => !used.contains(index)).toList()
          ..shuffle(random);
        final chosen = fallback.first;
        used.add(chosen);
        return chosen;
      }
      final chosen = candidates.first;
      used.add(chosen);
      return chosen;
    }

    final tree = pick((index) => _gridDistance(index, _startIndex) >= 3);
    final branch = pick((index) => _gridDistance(index, _startIndex) <= 2);
    final stone = pick(
      (index) => _gridDistance(index, _startIndex) <= 3,
      avoid: <int>[branch],
      minDistanceFromAvoid: 2,
    );
    final vine = pick(
      (index) => _gridDistance(index, _startIndex) >= 2 &&
          _gridDistance(index, _startIndex) <= 3,
      avoid: <int>[branch, stone],
      minDistanceFromAvoid: 2,
    );
    final scavengeA = pick(
      (index) => _gridDistance(index, _startIndex) >= 1 &&
          _gridDistance(index, _startIndex) <= 3,
      avoid: <int>[branch, stone, vine],
      minDistanceFromAvoid: 1,
    );
    final scavengeB = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[scavengeA, tree],
      minDistanceFromAvoid: 2,
    );
    final cache = pick(
      (index) => _gridDistance(index, _startIndex) >= 3,
      avoid: <int>[tree, scavengeB],
      minDistanceFromAvoid: 2,
    );
    final bottle = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[cache],
      minDistanceFromAvoid: 2,
    );
    final extraBranch = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[branch],
      minDistanceFromAvoid: 2,
    );

    result[branch] = _FogTileDef(
      kind: _FogTileKind.branch,
      label: '干燥长枝',
      text: '一根晒得很干的长枝，长度刚好可以加工成工具。',
      quality: _quality(random, min: 2, max: 5),
    );
    result[stone] = _FogTileDef(
      kind: _FogTileKind.stone,
      label: '尖锐石片',
      text: '边缘很锋利，也许能拿来加工木材。',
      quality: _quality(random, min: 2, max: 5),
    );
    result[vine] = _FogTileDef(
      kind: _FogTileKind.vine,
      label: '柔韧藤条',
      text: '被海风吹干的藤条依然很结实，适合捆扎。',
      quality: _quality(random, min: 2, max: 5),
    );
    result[tree] = const _FogTileDef(
      kind: _FogTileKind.coconutTree,
      label: '低矮椰树',
      text: '树冠上挂着成熟椰子，但徒手够不到。',
    );
    result[bottle] = _FogTileDef(
      kind: _FogTileKind.bottle,
      label: '漂流瓶',
      text: '瓶口被蜡封住了，里面似乎塞着一张纸。',
      quality: _quality(random, min: 3, max: 6),
    );
    result[extraBranch] = _FogTileDef(
      kind: _FogTileKind.branch,
      label: '短木枝',
      text: '一截干木枝，可以作为备用材料。',
      quality: _quality(random, min: 1, max: 4),
    );

    final normalScavengeLabels = <String>[
      '漂流物堆',
      '破布包',
      '潮线杂物',
      '搁浅木箱',
    ]..shuffle(random);
    result[scavengeA] = _FogTileDef(
      kind: _FogTileKind.scavenge,
      label: normalScavengeLabels[0],
      text: '这里堆着一些被潮水留下的东西，也许能翻出可用物资。',
    );
    result[scavengeB] = _FogTileDef(
      kind: _FogTileKind.scavenge,
      label: normalScavengeLabels[1],
      text: '表面看起来很普通，但里面可能混着还能利用的东西。',
    );
    _lootByTile[scavengeA] = _makeScavengeLoot(random);
    _lootByTile[scavengeB] = _makeScavengeLoot(random);

    final rareLabels = <String>[
      '半埋木匣',
      '破损补给箱',
      '冲上海滩的密封包',
      '贝壳堆下的暗匣',
    ]..shuffle(random);
    result[cache] = _FogTileDef(
      kind: _FogTileKind.cache,
      label: rareLabels.first,
      text: '这处搜刮点保存得异常完整，里面很可能有更好的东西。',
      energyBonus: 2 + random.nextInt(2),
      rare: true,
    );
    _lootByTile[cache] = _makeScavengeLoot(random, rare: true);

    final hazardA = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[branch, stone, vine],
      minDistanceFromAvoid: 1,
    );
    final hazardB = pick(
      (index) => _gridDistance(index, _startIndex) >= 3,
      avoid: <int>[hazardA, tree],
      minDistanceFromAvoid: 2,
    );
    result[hazardA] = const _FogTileDef(
      kind: _FogTileKind.hazard,
      label: '礁石缝',
      text: '脚下一滑，尖锐礁石逼得你绕路。',
    );
    result[hazardB] = const _FogTileDef(
      kind: _FogTileKind.hazard,
      label: '寄居蟹群',
      text: '你惊动了一群寄居蟹，只能退开重新找路。',
    );

    final normalEnemyA = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[hazardA, hazardB],
      minDistanceFromAvoid: 1,
    );
    final normalEnemyB = pick(
      (index) => _gridDistance(index, _startIndex) >= 2,
      avoid: <int>[normalEnemyA],
      minDistanceFromAvoid: 2,
    );
    final eliteEnemy = pick(
      (index) => _gridDistance(index, _startIndex) >= 3,
      avoid: <int>[normalEnemyA, normalEnemyB],
      minDistanceFromAvoid: 2,
    );
    result[normalEnemyA] = const _FogTileDef(
      kind: _FogTileKind.normalEnemy,
      label: '流浪鬣狗',
      text: '开发者预览普通敌人。',
      quality: 2,
    );
    result[normalEnemyB] = const _FogTileDef(
      kind: _FogTileKind.normalEnemy,
      label: '流浪鬣狗',
      text: '开发者预览普通敌人。',
      quality: 1,
    );
    result[eliteEnemy] = const _FogTileDef(
      kind: _FogTileKind.eliteEnemy,
      label: '巨型潮蜥',
      text: '开发者预览高级敌人。',
      quality: 5,
      rare: true,
    );

    return result;
  }

  _FogTileDef _tileAt(int index) {
    return _tiles[index] ??
        const _FogTileDef(
          kind: _FogTileKind.empty,
          label: '空地',
          text: '这里暂时没有发现可以带走的东西。',
        );
  }

  int _rowOf(int index) => index ~/ _columns;
  int _columnOf(int index) => index % _columns;

  int _gridDistance(int a, int b) {
    return math.max(
      (_rowOf(a) - _rowOf(b)).abs(),
      (_columnOf(a) - _columnOf(b)).abs(),
    );
  }

  Iterable<int> _neighbors(int index) sync* {
    final row = _rowOf(index);
    final col = _columnOf(index);
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = row + dr;
        final nc = col + dc;
        if (nr < 0 || nr >= _rows || nc < 0 || nc >= _columns) continue;
        yield nr * _columns + nc;
      }
    }
  }

  bool _isFrontier(int index) {
    if (_revealed.contains(index)) return false;
    return _neighbors(index).any(_revealed.contains);
  }

  bool _isInteresting(_FogTileKind kind) {
    return kind == _FogTileKind.genericItem ||
        kind == _FogTileKind.branch ||
        kind == _FogTileKind.stone ||
        kind == _FogTileKind.vine ||
        kind == _FogTileKind.coconutTree ||
        kind == _FogTileKind.bottle ||
        kind == _FogTileKind.scavenge ||
        kind == _FogTileKind.cache;
  }

  int _nearbyInterest(int index) {
    return _neighbors(index)
        .where((other) =>
            !_revealed.contains(other) && _isInteresting(_tileAt(other).kind))
        .length;
  }

  int _nearbyDanger(int index) {
    return _neighbors(index)
        .where((other) =>
            !_revealed.contains(other) &&
            (_tileAt(other).kind == _FogTileKind.hazard ||
                _tileAt(other).kind == _FogTileKind.normalEnemy ||
                _tileAt(other).kind == _FogTileKind.eliteEnemy))
        .length;
  }

  bool get _hasHook => (_bag['简易椰钩'] ?? 0) > 0;
  int get _hookQuality => _bagQuality['简易椰钩'] ?? 1;
  int get _foundCount => _searched.length;
  bool get _canCraftSharpStick => (_bag['木枝'] ?? 0) > 0 && (_bag['石片'] ?? 0) > 0;
  bool get _canCraftHook => (_bag['削尖长棍'] ?? 0) > 0 && (_bag['藤条'] ?? 0) > 0;

  List<JsonMap> get _remoteRecipes => (widget.controller.surroundingsData['recipes']
              is List
          ? widget.controller.surroundingsData['recipes'] as List
          : const <dynamic>[])
      .map(asJsonMap)
      .where((recipe) => recipe.isNotEmpty)
      .toList();

  Set<String> get _remoteVisible =>
      (widget.controller.surroundingsData['visible'] is List
              ? widget.controller.surroundingsData['visible'] as List
              : const <dynamic>[])
          .map(stringValue)
          .where((id) => id.isNotEmpty)
          .toSet();

  JsonMap? get _availableRemoteRecipe {
    if (!_remote) return null;
    final visible = _remoteVisible;
    for (final recipe in _remoteRecipes) {
      final a = stringValue(recipe['a']).trim();
      final b = stringValue(recipe['b']).trim();
      final result = stringValue(recipe['result']).trim();
      if (a.isNotEmpty && b.isNotEmpty && result.isNotEmpty &&
          visible.contains(a) && visible.contains(b) &&
          !visible.contains(result)) {
        return recipe;
      }
    }
    return null;
  }

  bool _isRemoteRecipeInput(String nodeId) {
    if (!_remote || nodeId.isEmpty) return false;
    return _remoteRecipes.any((recipe) =>
        stringValue(recipe['a']) == nodeId ||
        stringValue(recipe['b']) == nodeId);
  }

  String _remoteNodeLabel(String nodeId) {
    for (final tile in _tiles.values) {
      if (tile.nodeId == nodeId) return tile.label;
    }
    return nodeId;
  }

  String? get _availableCraftResult {
    if (_remote) {
      final recipe = _availableRemoteRecipe;
      if (recipe == null) return null;
      return _remoteNodeLabel(stringValue(recipe['result']));
    }
    if (!_hasHook && _canCraftHook) return '简易椰钩';
    if (!_hasHook && _canCraftSharpStick) return '削尖长棍';
    return null;
  }

  List<String> get _availableCraftInputs {
    if (_remote) {
      final recipe = _availableRemoteRecipe;
      if (recipe == null) return const <String>[];
      return <String>[
        _remoteNodeLabel(stringValue(recipe['a'])),
        _remoteNodeLabel(stringValue(recipe['b'])),
      ];
    }
    return switch (_availableCraftResult) {
      '简易椰钩' => const <String>['削尖长棍', '藤条'],
      '削尖长棍' => const <String>['木枝', '石片'],
      _ => const <String>[],
    };
  }

  String get _availableCraftSummary {
    final result = _availableCraftResult;
    final inputs = _availableCraftInputs;
    if (result == null || inputs.length != 2) return '';
    return '${inputs[0]} + ${inputs[1]} → $result';
  }

  void _craftAvailableRecipe() {
    if (_remote) {
      final recipe = _availableRemoteRecipe;
      if (recipe != null) unawaited(_combineRemoteRecipe(recipe));
      return;
    }
    final result = _availableCraftResult;
    if (result == null) return;
    setState(() {
      if (result == '削尖长棍') {
        final resultQuality = _craftedQuality('木枝', '石片', bonus: 1);
        if (_consumeItem('木枝') && _consumeItem('石片')) {
          _addItem('削尖长棍', quality: resultQuality);
          _message = _canCraftHook
              ? '制作完成：获得「削尖长棍」· ${_qualityLabel(resultQuality)}。✦ 已可继续制作「简易椰钩」。'
              : '制作完成：获得「削尖长棍」· ${_qualityLabel(resultQuality)}。搜到藤条后会自动提示下一步制作。';
        }
        return;
      }
      if (result == '简易椰钩') {
        final resultQuality = _craftedQuality('削尖长棍', '藤条', bonus: 1);
        if (_consumeItem('削尖长棍') && _consumeItem('藤条')) {
          _addItem('简易椰钩', quality: resultQuality);
          _message = '制作完成：获得「简易椰钩」· ${_qualityLabel(resultQuality)}！地图上的椰子树现在可以调查。';
        }
      }
    });
  }

  String _craftHintAfterPickup() {
    final summary = _availableCraftSummary;
    return summary.isEmpty ? '' : ' ✦ 已发现可制作：$summary。';
  }

  void _reset() {
    if (_remote) {
      unawaited(widget.controller.loadSurroundings(force: true));
      return;
    }
    setState(() => _startNewRun());
  }

  void _tapTile(int index) {
    if (_developerBattleOpening) return;
    if (_remote) {
      unawaited(_tapRemoteTile(index));
      return;
    }
    if (!_revealed.contains(index)) {
      _revealTile(index);
      return;
    }
    _interactWithRevealed(index);
  }

  Future<void> _openDeveloperBattle(int index, _FogTileDef tile) async {
    final launcher = widget.previewBattleLauncher;
    if (launcher == null || _developerBattleOpening) {
      if (launcher == null) {
        setState(() => _message = '当前开发者入口尚未接入战斗页面。');
      }
      return;
    }

    setState(() {
      _developerBattleOpening = true;
      _message = '正在进入与「${tile.label}」的战斗…';
    });
    try {
      final outcome = await launcher(
        enemyName: tile.label,
        quality: tile.quality,
        elite: tile.kind == _FogTileKind.eliteEnemy,
      );
      if (!mounted) return;
      setState(() {
        switch (outcome) {
          case 'victory':
            _searched.add(index);
            _message = '战斗胜利：「${tile.label}」已处理。本次测试不产生掉落。';
            break;
          case 'defeat':
            _message = '战斗失败。「${tile.label}」仍可再次挑战。';
            break;
          case 'escaped':
            _message = '已从测试战斗中逃跑。「${tile.label}」仍可再次挑战。';
            break;
          default:
            _message = '已退出测试战斗。「${tile.label}」仍可再次挑战。';
        }
      });
    } finally {
      if (mounted) setState(() => _developerBattleOpening = false);
    }
  }

  Future<void> _combineRemoteRecipe(JsonMap recipe) async {
    if (widget.controller.isSurroundingsActionRunning) return;
    final a = stringValue(recipe['a']).trim();
    final b = stringValue(recipe['b']).trim();
    if (a.isEmpty || b.isEmpty) return;
    setState(() => _message = '正在组合「${_remoteNodeLabel(a)}」与「${_remoteNodeLabel(b)}」…');
    try {
      final payload = await widget.controller.combineSurroundNodes(a, b);
      if (!mounted) return;
      final event = asJsonMap(payload['event']);
      setState(() {
        _message = stringValue(event['text'], '组合成功，新的物品格已经出现。');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = widget.controller.surroundingsError.trim().isEmpty
            ? '组合失败，请重试。'
            : widget.controller.surroundingsError.trim();
      });
    }
  }

  Future<void> _tapRemoteTile(int index) async {
    if (widget.controller.isSurroundingsActionRunning) return;
    if (!_revealed.contains(index)) {
      try {
        await widget.controller.investigateSurroundNode('grid_$index');
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _message = widget.controller.surroundingsError.trim().isEmpty
              ? '探索这片区域失败，请重试。'
              : widget.controller.surroundingsError.trim();
        });
      }
      return;
    }

    if (index == _startIndex) {
      setState(() => _message = '这里是探索起点。继续向场景深处走动。');
      return;
    }
    final tile = _tileAt(index);
    if (tile.nodeId.isEmpty) {
      setState(() => _message = '这里暂时没有发现可以带走的东西。');
      return;
    }
    if (_searched.contains(index)) {
      setState(() => _message = '「${tile.label}」已经处理过了。');
      return;
    }
    if (tile.kind == _FogTileKind.normalEnemy ||
        tile.kind == _FogTileKind.eliteEnemy) {
      widget.onClose?.call();
      await Future<void>.delayed(Duration.zero);
      await widget.controller.startSurroundEncounter(
        nodeId: tile.nodeId,
        targetName: tile.label,
      );
      return;
    }
    if (_isRemoteRecipeInput(tile.nodeId)) {
      setState(() {
        _message = _availableRemoteRecipe == null
            ? '「${tile.label}」是可组合材料，已保留。继续寻找与其匹配的材料。'
            : '合成材料已经凑齐，请使用下方的“制作”按钮。';
      });
      return;
    }
    if (!tile.collectible) {
      setState(() => _message = tile.text.isEmpty ? '这里没有更多发现。' : tile.text);
      return;
    }
    try {
      final payload = await widget.controller.claimSurroundReward(tile.nodeId);
      if (!mounted) return;
      final reward = asJsonMap(payload['reward']);
      final name = stringValue(reward['name'], tile.label);
      final rewardType = stringValue(
        reward['type'] ?? reward['item_type'],
      ).trim().toLowerCase();
      final isScore = rewardType == 'score';
      final isRareShopItem =
          rewardType == 'gift' || rewardType == 'lucky_card';
      final quantity = intValue(
        reward['score'] ?? reward['quantity'],
        1,
      );
      final quality = intValue(reward['quality'], tile.quality).clamp(1, 10).toInt();
      final rewardAsset = stringValue(
        reward['image_asset'],
        _surroundRewardAsset(rewardType),
      ).trim();
      final newScore = intValue(reward['new_score'], -1);
      final bonusRewards = (payload['bonus_rewards'] is List
              ? payload['bonus_rewards'] as List
              : const <dynamic>[])
          .map(asJsonMap)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final bonusLabels = bonusRewards.map((bonus) {
        final bonusName = stringValue(bonus['name'], '额外奖励');
        final bonusAmount = intValue(bonus['score'] ?? bonus['quantity'], 1);
        return '$bonusName ×$bonusAmount';
      }).toList(growable: false);
      final bonusAssets = bonusRewards
          .map((bonus) => stringValue(
                bonus['image_asset'],
                _surroundRewardAsset(stringValue(
                  bonus['type'] ?? bonus['item_type'],
                )),
              ).trim())
          .where((asset) => asset.isNotEmpty)
          .toList(growable: false);
      final bonusScore = bonusRewards
          .where((bonus) => stringValue(
                bonus['type'] ?? bonus['item_type'],
              ).trim().toLowerCase() == 'score')
          .map((bonus) => intValue(bonus['new_score'], -1))
          .fold<int>(-1, (current, value) => math.max(current, value).toInt());
      setState(() {
        if (isScore && newScore >= 0) _scoreOverride = newScore;
        if (bonusScore >= 0) _scoreOverride = bonusScore;
        if (!isScore && !isRareShopItem) {
          _addItem(name, amount: quantity, quality: quality);
        }
        _message = (isScore || isRareShopItem
            ? '探索中发现$name ×$quantity。'
            : '获得「$name${quantity > 1 ? ' ×$quantity' : ''}」· ${_qualityLabel(quality)}。') +
            (bonusLabels.isEmpty ? '' : ' 额外发现：${bonusLabels.join('、')}。');
      });
      _showRemoteRewardToast(
        text: isScore
            ? '获得星块 ×$quantity'
            : '获得$name${quantity > 1 ? ' ×$quantity' : ''}' +
                (bonusLabels.isEmpty ? '' : ' + ${bonusLabels.join('、')}'),
        assetPath: rewardAsset,
        assetPaths: bonusAssets,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = widget.controller.surroundingsError.trim().isEmpty
            ? '领取失败，请重试。'
            : widget.controller.surroundingsError.trim();
      });
    }
  }

  void _showRemoteRewardToast({
    required String text,
    String assetPath = '',
    List<String> assetPaths = const <String>[],
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _rewardToastEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        return Positioned(
          top: media.padding.top + media.size.height * .33,
          left: 24,
          right: 24,
          child: _SurroundPickupRewardToast(
            text: text,
            assetPath: assetPath,
            assetPaths: assetPaths,
            onCompleted: () {
              if (_rewardToastEntry != entry) return;
              entry.remove();
              _rewardToastEntry = null;
            },
          ),
        );
      },
    );
    _rewardToastEntry = entry;
    overlay.insert(entry);
  }

  void _revealTile(int index) {
    if (_revealed.contains(index)) return;
    final tile = _tileAt(index);
    setState(() {
      _revealed.add(index);

      switch (tile.kind) {
        case _FogTileKind.empty:
          _message = '你走进一片安静区域，视野向前展开。';
          break;
        case _FogTileKind.hazard:
          _searched.add(index);
          _message = '${tile.text} 你及时避开了危险。';
          break;
        case _FogTileKind.coconutTree:
          _message = _hasHook
              ? '发现「${tile.label}」。简易椰钩可以处理这里。'
              : '发现「${tile.label}」。${tile.text}';
          break;
        case _FogTileKind.scavenge:
          _message = '发现搜刮点「${tile.label}」。靠近后调查可以翻找物资。';
          break;
        case _FogTileKind.cache:
          _message = '发现稀有搜刮点「${tile.label}」！';
          break;
        case _FogTileKind.normalEnemy:
        case _FogTileKind.eliteEnemy:
          _message = '前方发现「${tile.label}」。继续靠近可以选择交战。';
          break;
        default:
          _message = '发现「${tile.label}」· ${_qualityLabel(tile.quality)}。';
          break;
      }
    });
  }

  int _cascadeReveal(int origin) {
    final queue = <int>[origin];
    final visited = <int>{origin};
    var opened = 0;

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final next in _neighbors(current)) {
        if (visited.contains(next) || _revealed.contains(next)) continue;
        visited.add(next);
        final tile = _tileAt(next);
        if (tile.kind == _FogTileKind.hazard ||
            tile.kind == _FogTileKind.normalEnemy ||
            tile.kind == _FogTileKind.eliteEnemy) continue;

        _revealed.add(next);
        opened += 1;
        if (tile.kind == _FogTileKind.empty &&
            _nearbyInterest(next) == 0 &&
            _nearbyDanger(next) == 0) {
          queue.add(next);
        }
      }
    }
    return opened;
  }

  void _interactWithRevealed(int index) {
    if (index == _startIndex) {
      setState(() => _message = '这里是探索起点。继续走动即可调查周围，也可以随时安全撤离。');
      return;
    }

    final tile = _tileAt(index);
    if (_searched.contains(index)) {
      setState(() => _message = '「${tile.label}」已经处理过了。');
      return;
    }

    switch (tile.kind) {
      case _FogTileKind.empty:
        final clue = _nearbyInterest(index);
        final danger = _nearbyDanger(index);
        setState(() {
          _message = danger > 0
              ? '周围还有 $clue 个未探索目标，同时有 $danger 处隐藏危险。'
              : clue > 0
                  ? '周围还有 $clue 个未探索目标。'
                  : '这里没有更多发现。';
        });
        break;
      case _FogTileKind.hazard:
        setState(() => _message = '这里的危险已经避开了。');
        break;
      case _FogTileKind.coconutTree:
        if (!_hasHook) {
          setState(() => _message = '椰子还在高处。需要一件能勾住树冠的长柄工具。');
          return;
        }
        setState(() {
          _searched.add(index);
          final qualityBonus = _hookQuality >= 6 ? 1 : 0;
          final reward = _coconutBaseReward + qualityBonus;
          _addItem(
            '椰子',
            amount: reward,
            quality: math.max(2, math.min(7, _hookQuality)),
          );
          _completed = true;
          final bonusText = <String>[
            if (qualityBonus > 0) '高品质工具 +1',
          ];
          _message = bonusText.isEmpty
              ? '椰钩勾住果柄——获得「椰子 ×$reward」！核心目标完成，现在可以安全撤离。'
              : '椰钩勾住果柄——获得「椰子 ×$reward」！${bonusText.join('、')}。可以现在撤离，也可以继续寻找稀有搜刮点。';
        });
        break;
      case _FogTileKind.branch:
        _collect(index, '木枝', quality: tile.quality);
        break;
      case _FogTileKind.stone:
        _collect(index, '石片', quality: tile.quality);
        break;
      case _FogTileKind.vine:
        _collect(index, '藤条', quality: tile.quality);
        break;
      case _FogTileKind.bottle:
        _collect(index, '漂流瓶', quality: tile.quality);
        break;
      case _FogTileKind.scavenge:
      case _FogTileKind.cache:
        _lootScavengePoint(index, tile);
        break;
      case _FogTileKind.genericItem:
        _collect(index, tile.label, quality: tile.quality);
        break;
      case _FogTileKind.normalEnemy:
      case _FogTileKind.eliteEnemy:
        unawaited(_openDeveloperBattle(index, tile));
        break;
    }
  }

  void _lootScavengePoint(int index, _FogTileDef tile) {
    final drops = _lootByTile[index] ?? const <_FogDrop>[];
    setState(() {
      _searched.add(index);
      for (final drop in drops) {
        _addItem(drop.name, amount: drop.amount, quality: drop.quality);
      }
      final summary = drops.isEmpty
          ? '没有找到可用物品'
          : drops
              .map(
                (drop) =>
                    '${drop.name}${drop.amount > 1 ? ' ×${drop.amount}' : ''} · ${_qualityLabel(drop.quality)}',
              )
              .join('、');
      final craftHint = _craftHintAfterPickup();
      _message = tile.rare
          ? '稀有搜刮：$summary。$craftHint'
          : '搜刮完成：$summary。$craftHint';
    });
  }

  void _collect(int index, String itemName, {required int quality}) {
    setState(() {
      _searched.add(index);
      _addItem(itemName, quality: quality);
      final craftHint = _craftHintAfterPickup();
      _message = craftHint.isEmpty
          ? '获得「$itemName」· ${_qualityLabel(quality)}。'
          : '获得「$itemName」· ${_qualityLabel(quality)}。$craftHint';
    });
  }

  void _addItem(String name, {int amount = 1, int quality = 1}) {
    _bag[name] = (_bag[name] ?? 0) + amount;
    final currentQuality = _bagQuality[name] ?? 0;
    if (quality > currentQuality) _bagQuality[name] = quality;
  }

  bool _consumeItem(String name, {int amount = 1}) {
    final current = _bag[name] ?? 0;
    if (current < amount) return false;
    final next = current - amount;
    if (next <= 0) {
      _bag.remove(name);
      _bagQuality.remove(name);
    } else {
      _bag[name] = next;
    }
    return true;
  }

  int _craftedQuality(String a, String b, {int bonus = 0}) {
    final qa = _bagQuality[a] ?? 1;
    final qb = _bagQuality[b] ?? 1;
    return math.min(10, math.max(1, ((qa + qb) / 2).round() + bonus));
  }

  String _qualityLabel(int quality) {
    if (quality <= 2) return '普通';
    if (quality <= 4) return '良好';
    if (quality <= 6) return '精良';
    if (quality <= 8) return '稀有';
    if (quality == 9) return '史诗';
    return '传说';
  }

  Color _qualityColor(int quality) {
    if (quality >= 9) return _rareGold.withOpacity(.96);
    if (quality >= 7) return const Color(0xFFC58AF9).withOpacity(.94);
    if (quality >= 5) return const Color(0xFF74A8F7).withOpacity(.92);
    if (quality >= 3) return _themeGreen.withOpacity(.90);
    return Colors.white.withOpacity(.50);
  }

  int _withdrawBonus() => 0;

  Future<void> _showWithdrawDialog() async {
    final bonus = _withdrawBonus();
    final entries = _bag.entries.toList();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(.42),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.075),
                    border: Border.all(
                      color: Colors.white.withOpacity(.11),
                      width: .8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _completed ? '安全撤离 · 目标已完成' : '提前撤离 · 保留当前战利品',
                              style: TextStyle(
                                color: Colors.white.withOpacity(.94),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '自由探索',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.40),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Container(height: 1, color: Colors.white.withOpacity(.07)),
                      const SizedBox(height: 11),
                      Text(
                        entries.isEmpty
                            ? '本轮还没有获得战利品。'
                            : entries
                                .map((entry) {
                                  final q = _bagQuality[entry.key] ?? 1;
                                  return '${entry.key}${entry.value > 1 ? ' ×${entry.value}' : ''} · ${_qualityLabel(q)}';
                                })
                                .join('\n'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(.72),
                          fontSize: 10,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(.11),
                                    width: .8,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                child: Text(
                                  '继续探索',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.62),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  if (bonus > 0) {
                                    setState(() {
                                      _addItem('新鲜椰肉', amount: bonus, quality: 4);
                                    });
                                  }
                                  widget.onClose?.call();
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor: _themeGreen,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                child: Text(
                                  '确定带走并离开',
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(.78),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
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
          ),
        );
      },
    );
  }

  Future<void> _pickWalkPreviewImage({required bool portrait}) async {
    // 开发者完整预览可上传背景/立绘；正文底部嵌入版至少允许临时上传背景图测试效果。
    if (!widget.developerPreview && !widget.embedded) return;
    try {
      // 与项目现有角色立绘上传逻辑保持一致。
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      if (!mounted || file == null || file.bytes == null) return;
      final bytes = file.bytes!;
      if (bytes.isEmpty) {
        setState(() => _message = '图片读取失败，请换一张 PNG / JPG / WEBP 再试。');
        return;
      }
      setState(() {
        if (portrait) {
          _previewPortraitBytes = bytes;
          _message = '主角立绘已载入。现在可以直接在场景里走动测试比例与待机效果。';
        } else {
          _previewBackgroundBytes = bytes;
          _message = '场景背景已载入。走动时镜头会跟随主角横向移动。';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = '选择图片失败，请重试。');
    }
  }

  void _ensureWalkLayout(double worldWidth, double stageHeight) {
    final oldWidth = _walkWorldWidth;
    _walkWorldWidth = worldWidth;
    _walkStageHeight = stageHeight;
    if (!_walkLayoutReady) {
      final start = _walkTilePoint(_startIndex, worldWidth, stageHeight);
      _playerWorldX = start.dx;
      _playerDepth = (start.dy / stageHeight)
          .clamp(widget.embedded ? .58 : .50, .91)
          .toDouble();
      _walkLayoutReady = true;
      return;
    }
    if (oldWidth > 0 && (oldWidth - worldWidth).abs() > .5) {
      _playerWorldX = (_playerWorldX * worldWidth / oldWidth)
          .clamp(32.0, math.max(32.0, worldWidth - 32.0))
          .toDouble();
    }
  }

  Offset _walkTilePoint(int index, double worldWidth, double stageHeight) {
    final row = _rowOf(index);
    final col = _columnOf(index);
    final x = (col + .5) / _columns * worldWidth;
    final depth = .50 + (row / math.max(1, _rows - 1)) * .40;
    return Offset(x, stageHeight * depth);
  }

  double _walkDistanceToIndex(int index) {
    final point = _walkTilePoint(index, _walkWorldWidth, _walkStageHeight);
    final playerY = _walkStageHeight * _playerDepth;
    final dx = point.dx - _playerWorldX;
    final dy = (point.dy - playerY) * 1.75;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _setWalkInput(Offset value) {
    if (!widget.movementEnabled) return;
    final length = value.distance;
    final normalized = length > 1 ? value / length : value;
    setState(() {
      _walkInput = normalized;
      if (normalized.distanceSquared > .002) _walkTapTarget = null;
    });
  }

  void _stopWalkInput() {
    if (_walkInput == Offset.zero) return;
    setState(() => _walkInput = Offset.zero);
  }

  void _setWalkTapTarget(TapDownDetails details, double cameraX) {
    if (!widget.movementEnabled) return;
    final local = details.localPosition;
    final targetDepth = (local.dy / math.max(1.0, _walkStageHeight))
        .clamp(widget.embedded ? .58 : .50, .91)
        .toDouble();
    setState(() {
      _walkTapTarget = Offset(
        (cameraX + local.dx)
            .clamp(32.0, math.max(32.0, _walkWorldWidth - 32.0))
            .toDouble(),
        targetDepth,
      );
    });
  }

  void _tickWalk() {
    if (!mounted || !_walkLayoutReady) return;
    if (!widget.movementEnabled) {
      if (_walkInput != Offset.zero || _walkTapTarget != null || _playerMoving) {
        setState(() {
          _walkInput = Offset.zero;
          _walkTapTarget = null;
          _playerMoving = false;
        });
      }
      return;
    }
    final elapsed = _walkTicker.lastElapsedDuration ?? Duration.zero;
    if (_walkLastElapsed == Duration.zero) {
      _walkLastElapsed = elapsed;
      return;
    }
    final rawDt = (elapsed - _walkLastElapsed).inMicroseconds / 1000000.0;
    _walkLastElapsed = elapsed;
    if (rawDt <= 0) return;
    final dt = rawDt.clamp(0.0, .05).toDouble();

    var input = _walkInput;
    final target = _walkTapTarget;
    if (input.distanceSquared <= .002 && target != null) {
      final dx = target.dx - _playerWorldX;
      final dyPx = (target.dy - _playerDepth) * _walkStageHeight;
      final distance = math.sqrt(dx * dx + dyPx * dyPx);
      if (distance < 8) {
        _walkTapTarget = null;
        input = Offset.zero;
      } else {
        input = Offset(dx / distance, dyPx / distance);
      }
    }

    final moving = input.distanceSquared > .002;
    if (!moving) {
      if (_playerMoving) setState(() => _playerMoving = false);
      return;
    }

    const speed = 235.0;
    final nextX = (_playerWorldX + input.dx * speed * dt)
        .clamp(32.0, math.max(32.0, _walkWorldWidth - 32.0))
        .toDouble();
    final nextDepth = (_playerDepth +
            input.dy * speed * dt / math.max(1.0, _walkStageHeight))
        .clamp(widget.embedded ? .58 : .50, .91)
        .toDouble();
    final facingLeft = input.dx < -.05
        ? true
        : input.dx > .05
            ? false
            : _playerFacingLeft;

    setState(() {
      _playerWorldX = nextX;
      _playerDepth = nextDepth;
      _playerFacingLeft = facingLeft;
      _playerMoving = true;
    });
    _discoverByWalking();
  }

  void _discoverByWalking() {
    int? nearest;
    var best = double.infinity;
    for (var index = 0; index < _rows * _columns; index++) {
      if (_revealed.contains(index) || _walkPendingReveal.contains(index)) continue;
      final distance = _walkDistanceToIndex(index);
      if (distance < 68 && distance < best) {
        best = distance;
        nearest = index;
      }
    }
    if (nearest == null) return;
    if (_remote) {
      unawaited(_revealRemoteByWalking(nearest));
    } else {
      _revealTile(nearest);
    }
  }

  Future<void> _revealRemoteByWalking(int index) async {
    if (_walkPendingReveal.contains(index) || _revealed.contains(index)) return;
    if (widget.controller.isSurroundingsActionRunning) return;
    _walkPendingReveal.add(index);
    try {
      await widget.controller.investigateSurroundNode('grid_$index');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = widget.controller.surroundingsError.trim().isEmpty
            ? '这片区域暂时无法调查，请继续走动或稍后重试。'
            : widget.controller.surroundingsError.trim();
      });
    } finally {
      _walkPendingReveal.remove(index);
    }
  }

  int? _nearestWalkInteractableIndex({double maxDistance = 86}) {
    int? nearest;
    var best = maxDistance;
    for (var index = 0; index < _rows * _columns; index++) {
      if (index == _startIndex || !_revealed.contains(index) || _searched.contains(index)) {
        continue;
      }
      final tile = _tileAt(index);
      if (tile.kind == _FogTileKind.empty || tile.kind == _FogTileKind.hazard) continue;
      final distance = _walkDistanceToIndex(index);
      if (distance < best) {
        best = distance;
        nearest = index;
      }
    }
    return nearest;
  }

  IconData _walkTileIcon(_FogTileKind kind) {
    return switch (kind) {
      _FogTileKind.normalEnemy => Icons.warning_amber_rounded,
      _FogTileKind.eliteEnemy => Icons.local_fire_department_outlined,
      _FogTileKind.coconutTree => Icons.park_outlined,
      _FogTileKind.scavenge => Icons.search_rounded,
      _FogTileKind.cache => Icons.inventory_2_outlined,
      _FogTileKind.bottle => Icons.local_drink_outlined,
      _FogTileKind.branch => Icons.horizontal_rule_rounded,
      _FogTileKind.stone => Icons.landscape_outlined,
      _FogTileKind.vine => Icons.grass_rounded,
      _FogTileKind.genericItem => Icons.diamond_outlined,
      _ => Icons.circle_outlined,
    };
  }

  Color _walkTileColor(_FogTileDef tile) {
    if (tile.kind == _FogTileKind.normalEnemy || tile.kind == _FogTileKind.eliteEnemy) {
      return _dangerRed;
    }
    if (tile.rare || tile.kind == _FogTileKind.cache) return _rareGold;
    return _themeGreen;
  }

  Widget _buildWalkObject(int index, double cameraX) {
    final tile = _tileAt(index);
    if (!_revealed.contains(index) || tile.kind == _FogTileKind.empty || index == _startIndex) {
      return const SizedBox.shrink();
    }
    final point = _walkTilePoint(index, _walkWorldWidth, _walkStageHeight);
    final searched = _searched.contains(index);
    final accent = _walkTileColor(tile);
    final near = _walkDistanceToIndex(index) < 90;
    return Positioned(
      left: point.dx - cameraX - 46,
      top: point.dy - 66,
      width: 92,
      height: 62,
      child: IgnorePointer(
        ignoring: searched,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: searched ? .24 : 1,
          child: GestureDetector(
            onTap: () => _tapTile(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: near ? 34 : 30,
                  height: near ? 34 : 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.42),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withOpacity(near ? .86 : .46),
                      width: near ? 1.2 : .8,
                    ),
                    boxShadow: <BoxShadow>[
                      if (near)
                        BoxShadow(
                          color: accent.withOpacity(.18),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: Icon(
                    _walkTileIcon(tile.kind),
                    size: near ? 17 : 15,
                    color: accent.withOpacity(.94),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxWidth: 88),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.48),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    searched ? '已调查' : tile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(searched ? .38 : .86),
                      fontSize: 8.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _walkImageSource(
    String source, {
    required BoxFit fit,
    Alignment alignment = Alignment.center,
    Widget? fallback,
  }) {
    final value = source.trim();
    if (value.isEmpty) return fallback ?? const SizedBox.shrink();
    if (value.startsWith('assets/')) {
      return Image.asset(
        value,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
      );
    }
    return Image.network(
      value,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
    );
  }

  Widget _walkPlayerFallback() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: widget.embedded ? 36 : 42,
        height: widget.embedded ? 70 : 82,
        decoration: BoxDecoration(
          color: const Color(0xFF182428).withOpacity(.96),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(18),
            bottom: Radius.circular(7),
          ),
          border: Border.all(
            color: Colors.white.withOpacity(.18),
            width: .8,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(.46),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '主角',
          style: TextStyle(
            color: Colors.white.withOpacity(.74),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildWalkPlayer(double cameraX) {
    final playerY = _walkStageHeight * _playerDepth;
    final depthScale = .86 + ((_playerDepth - .50) / .41).clamp(0.0, 1.0) * .18;
    final portraitBytes = _previewPortraitBytes;
    final protagonist = widget.controller.protagonist;
    // 正文底部探索优先使用玩家已经创建好的“主角立绘”。
    // 只有立绘 URL 为空时才退回头像，避免正常情况下显示成头像小圆图。
    final protagonistPortrait = protagonist?.portraitUrl.trim() ?? '';
    final protagonistAvatar = protagonist?.avatarUrl.trim() ?? '';
    final portraitSource = protagonistPortrait.isNotEmpty
        ? protagonistPortrait
        : protagonistAvatar;
    // 嵌入正文底部时，人物不能沿用独立探索页的大尺寸。
    // 按当前舞台高度动态缩放，让完整立绘（尤其头部/脚部）更容易留在画面内。
    final playerHeight = widget.embedded
        ? (_walkStageHeight * .42).clamp(72.0, 96.0).toDouble()
        : 132.0;
    final playerWidth = widget.embedded
        ? (playerHeight * .64).clamp(46.0, 62.0).toDouble()
        : 88.0;
    return Positioned(
      left: _playerWorldX - cameraX - playerWidth / 2,
      top: playerY - playerHeight,
      width: playerWidth,
      height: playerHeight,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: widget.movementEnabled ? 1 : .74,
          child: AnimatedBuilder(
            animation: _walkTicker,
            builder: (context, child) {
              final seconds = (_walkTicker.lastElapsedDuration?.inMilliseconds ?? 0) / 1000.0;
              final bob = _playerMoving
                  ? math.sin(seconds * 11.5) * 2.0
                  : math.sin(seconds * 2.2) * 1.0;
              final breath = _playerMoving ? 1.0 : 1.0 + math.sin(seconds * 2.2) * .008;
              return Transform.translate(
                offset: Offset(0, bob),
                child: Transform.scale(
                  scaleX: (_playerFacingLeft ? -1.0 : 1.0) * depthScale,
                  scaleY: depthScale * breath,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              );
            },
            child: portraitBytes != null
                ? Image.memory(
                    portraitBytes,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.high,
                  )
                : portraitSource.isNotEmpty
                    ? _walkImageSource(
                        portraitSource,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        fallback: _walkPlayerFallback(),
                      )
                    : _walkPlayerFallback(),
          ),
        ),
      ),
    );
  }

  Widget _buildWalkJoystick() {
    final size = widget.embedded ? 58.0 : 82.0;
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          final delta = details.localPosition - Offset(size / 2, size / 2);
          _setWalkInput(delta / (size / 2));
        },
        onPanUpdate: (details) {
          final delta = details.localPosition - Offset(size / 2, size / 2);
          _setWalkInput(delta / (size / 2));
        },
        onPanEnd: (_) => _stopWalkInput(),
        onPanCancel: _stopWalkInput,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.10), width: .8),
              ),
            ),
            Transform.translate(
              offset: _walkInput * 20,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(.22), width: .8),
                ),
                child: Icon(
                  Icons.control_camera_rounded,
                  size: 15,
                  color: Colors.white.withOpacity(.62),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalkStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = math.max(1.0, constraints.maxWidth);
        final stageHeight = math.max(170.0, constraints.maxHeight);
        // 正文底部是“单屏横版舞台”，不再强行做 1.9 屏的超宽世界。
        // 原来把一张 16:9 场景硬撑到近两屏宽，再用 cover，会把上下裁掉很多。
        // 嵌入模式保持接近当前可视宽度，人物仍可左右走动；独立探索页继续保留横向卷轴。
        final worldWidth = widget.embedded
            ? viewportWidth
            : math.max(
                viewportWidth * 1.90,
                stageHeight * (16 / 9),
              ).toDouble();
        _ensureWalkLayout(worldWidth, stageHeight);
        final cameraX = (_playerWorldX - viewportWidth * .5)
            .clamp(0.0, math.max(0.0, worldWidth - viewportWidth))
            .toDouble();
        final nearest = _nearestWalkInteractableIndex();
        final goal = _remote
            ? stringValue(widget.controller.surroundingsData['goal'], '调查当前场景')
            : '自由探索海滩，收集材料并寻找目标';

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _setWalkTapTarget(details, cameraX),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned(
                  left: -cameraX,
                  top: 0,
                  width: worldWidth,
                  height: stageHeight,
                  child: _previewBackgroundBytes != null
                      ? Image.memory(
                          _previewBackgroundBytes!,
                          // 底部横版优先完整保留场景的左右信息；
                          // 16:9 / 2:1 场景只会产生很轻的上下裁切或留白。
                          fit: widget.embedded ? BoxFit.fitWidth : BoxFit.cover,
                          alignment: widget.embedded
                              ? Alignment.bottomCenter
                              : Alignment.center,
                          filterQuality: FilterQuality.high,
                        )
                      : widget.controller.world.backgroundUrl.trim().isNotEmpty
                          ? _walkImageSource(
                              widget.controller.world.backgroundUrl.trim(),
                              fit: widget.embedded ? BoxFit.fitWidth : BoxFit.cover,
                              alignment: widget.embedded
                                  ? Alignment.bottomCenter
                                  : Alignment.center,
                              fallback: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0xFF273B3B),
                                Color(0xFF17272A),
                                Color(0xFF0C1417),
                              ],
                              stops: <double>[0, .55, 1],
                            ),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Positioned(
                                left: worldWidth * .12,
                                top: stageHeight * .28,
                                child: Icon(
                                  Icons.park_rounded,
                                  size: 120,
                                  color: Colors.black.withOpacity(.16),
                                ),
                              ),
                              Positioned(
                                left: worldWidth * .63,
                                top: stageHeight * .31,
                                child: Icon(
                                  Icons.landscape_rounded,
                                  size: 150,
                                  color: Colors.black.withOpacity(.18),
                                ),
                              ),
                            ],
                          ),
                        ),
                            )
                          : DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0xFF273B3B),
                                Color(0xFF17272A),
                                Color(0xFF0C1417),
                              ],
                              stops: <double>[0, .55, 1],
                            ),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Positioned(
                                left: worldWidth * .12,
                                top: stageHeight * .28,
                                child: Icon(
                                  Icons.park_rounded,
                                  size: 120,
                                  color: Colors.black.withOpacity(.16),
                                ),
                              ),
                              Positioned(
                                left: worldWidth * .63,
                                top: stageHeight * .31,
                                child: Icon(
                                  Icons.landscape_rounded,
                                  size: 150,
                                  color: Colors.black.withOpacity(.18),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                ...List<Widget>.generate(
                  _rows * _columns,
                  (index) => _buildWalkObject(index, cameraX),
                ),
                _buildWalkPlayer(cameraX),
                Positioned(
                  left: widget.embedded ? 9 : 12,
                  top: widget.embedded ? 7 : 11,
                  right: widget.embedded
                      ? 94
                      : (widget.developerPreview ? 116 : 9),
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.36),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(.08), width: .6),
                          ),
                          child: Text(
                            goal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.82),
                              fontSize: 9.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.movementEnabled
                              ? '拖动摇杆或点击地面移动 · 走近自动探索'
                              : '剧情输出中 · 移动暂时锁定',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.42),
                            fontSize: 7.7,
                            fontWeight: FontWeight.w600,
                            shadows: const <Shadow>[Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.embedded)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _walkInlineBackgroundButton(),
                  )
                else if (widget.developerPreview)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      children: <Widget>[
                        _walkToolButton(
                          icon: Icons.image_outlined,
                          tooltip: '选择场景背景图',
                          onTap: () => unawaited(_pickWalkPreviewImage(portrait: false)),
                        ),
                        const SizedBox(width: 5),
                        _walkToolButton(
                          icon: Icons.person_outline_rounded,
                          tooltip: '选择主角立绘',
                          onTap: () => unawaited(_pickWalkPreviewImage(portrait: true)),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  left: widget.embedded ? 8 : 12,
                  bottom: widget.embedded ? 8 : 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: widget.movementEnabled ? 1 : .34,
                    child: IgnorePointer(
                      ignoring: !widget.movementEnabled,
                      child: _buildWalkJoystick(),
                    ),
                  ),
                ),
                if (nearest != null)
                  Positioned(
                    left: 104,
                    right: 12,
                    bottom: 15,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.movementEnabled
                              ? () => _tapTile(nearest)
                              : null,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 260),
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.56),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _walkTileColor(_tileAt(nearest)).withOpacity(.48),
                                width: .8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  _walkTileIcon(_tileAt(nearest).kind),
                                  size: 14,
                                  color: _walkTileColor(_tileAt(nearest)).withOpacity(.92),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    '${_tileAt(nearest).kind == _FogTileKind.normalEnemy || _tileAt(nearest).kind == _FogTileKind.eliteEnemy ? '交战' : '调查'} · ${_tileAt(nearest).label}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.88),
                                      fontSize: 9.4,
                                      fontWeight: FontWeight.w800,
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _walkInlineBackgroundButton() {
    final replaced = _previewBackgroundBytes != null;
    return Tooltip(
      message: replaced ? '重新选择探索背景图' : '上传探索背景图',
      child: Material(
        color: Colors.black.withOpacity(.42),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Colors.white.withOpacity(replaced ? .22 : .12),
            width: .7,
          ),
          borderRadius: BorderRadius.zero,
        ),
        child: InkWell(
          onTap: () => unawaited(_pickWalkPreviewImage(portrait: false)),
          borderRadius: BorderRadius.zero,
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    replaced ? Icons.image_rounded : Icons.add_photo_alternate_outlined,
                    size: 14,
                    color: Colors.white.withOpacity(.82),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    replaced ? '更换背景' : '上传背景',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.82),
                      fontSize: 9.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _walkToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withOpacity(.40),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 16, color: Colors.white.withOpacity(.78)),
          ),
        ),
      ),
    );
  }

  Widget _inventoryChip(String item, int count) {
    final important = item == '简易椰钩' || item == '椰子' || item == '新鲜椰肉';
    final quality = _bagQuality[item] ?? 1;
    final qualityColor = _qualityColor(quality);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: important
            ? _themeGreen.withOpacity(.055)
            : Colors.white.withOpacity(.040),
        border: Border.all(
          color: quality >= 9
              ? _rareGold.withOpacity(.44)
              : important
                  ? _themeGreen.withOpacity(.38)
                  : Colors.white.withOpacity(.09),
          width: .7,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                item,
                style: TextStyle(
                  color: Colors.white.withOpacity(.88),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count > 1) ...<Widget>[
                const SizedBox(width: 5),
                Text(
                  '×$count',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.40),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _qualityLabel(quality),
            style: TextStyle(
              color: qualityColor,
              fontSize: 6.9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildContextActionBar() {
    final craftResult = _availableCraftResult;
    if (craftResult != null) {
      final summary = _availableCraftSummary;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: _themeGreen.withOpacity(.045),
          border: Border(
            left: BorderSide(
              color: _themeGreen.withOpacity(.55),
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.auto_fix_high_rounded,
              size: 14,
              color: _themeGreen.withOpacity(.88),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '可制作',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.88),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.40),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _craftAvailableRecipe,
                borderRadius: BorderRadius.zero,
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  color: _themeGreen.withOpacity(.88),
                  child: const Text(
                    '制作',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_completed) {
      return _contextHint(
        icon: Icons.flag_outlined,
        text: '核心目标已完成。本轮收获已经可以结算。',
        accent: _themeGreen,
      );
    }

    if (_hasHook) {
      return _contextHint(
        icon: Icons.park_outlined,
        text: '简易椰钩已完成。找到椰树后可以直接调查。',
        accent: _themeGreen,
      );
    }

    return null;
  }

  Widget _contextHint({
    required IconData icon,
    required String text,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.018),
        border: Border(
          left: BorderSide(color: accent.withOpacity(.38), width: 2),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: accent.withOpacity(.76)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(.46),
                fontSize: 8.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _withdrawButton({bool expanded = false}) {
    final completed = _completed;
    final backgroundColor = completed
        ? _themeGreen.withOpacity(.16)
        : Colors.white.withOpacity(.035);
    final foregroundColor = completed
        ? _themeGreen.withOpacity(.95)
        : Colors.white.withOpacity(.62);
    final button = Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: _showWithdrawDialog,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: completed
                  ? _themeGreen.withOpacity(.32)
                  : Colors.white.withOpacity(.09),
              width: .6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.exit_to_app_rounded,
                  size: 14,
                  color: foregroundColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '撤离',
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 9.4,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: completed ? '目标已完成，结束探索并结算' : '提前结束探索并结算',
      child: expanded ? SizedBox(width: double.infinity, child: button) : button,
    );
  }

  Widget _buildGoalBar({required bool compact}) {
    final bonus = _withdrawBonus();
    final remoteGoal = stringValue(
      widget.controller.surroundingsData['goal'],
      '调查当前场景',
    );

    final title = _remote
        ? (_completed ? '探索完成' : remoteGoal)
        : (_completed ? '目标完成' : '想办法摘到椰子');

    final subtitle = _remote
        ? (_completed
            ? '当前区域已处理完毕'
            : _availableCraftResult != null
                ? '材料已齐 · 可以制作'
                : '走近区域自动探索，发现后调查目标')
        : (_completed
            ? (bonus > 0 ? '当前撤离奖励 ×$bonus' : '当前撤离奖励已耗尽')
            : _hasHook
                ? '椰钩已完成 · 寻找椰树'
                : _availableCraftResult != null
                    ? '材料已齐 · 可以制作'
                    : '自由走动，收集并组合材料');

    return SizedBox(
      height: compact ? 46 : 48,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.92),
                    fontSize: compact ? 11.2 : 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.34),
                    fontSize: compact ? 8.1 : 8.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              '发现 $_foundCount',
              style: TextStyle(
                color: Colors.white.withOpacity(.30),
                fontSize: 8.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(width: 10),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.035),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(.07), width: .6),
            ),
            child: Text(
              '自由探索',
              style: TextStyle(
                color: Colors.white.withOpacity(.58),
                fontSize: 8.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPanel() => _buildWalkStage();

  Widget _buildMessagePanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _completed
            ? _themeGreen.withOpacity(.055)
            : Colors.white.withOpacity(.032),
        border: Border.all(
          color: _completed
              ? _themeGreen.withOpacity(.30)
              : Colors.white.withOpacity(.075),
          width: .7,
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(.73),
            fontSize: 9.6,
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBagPanel({bool fill = false}) {
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.022),
        border: Border.all(color: Colors.white.withOpacity(.065), width: .7),
      ),
      child: _bag.isEmpty
          ? Center(
              child: Text(
                '还没有搜刮到物品',
                style: TextStyle(
                  color: Colors.white.withOpacity(.24),
                  fontSize: 9,
                ),
              ),
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _bag.entries
                    .map((entry) => _inventoryChip(entry.key, entry.value))
                    .toList(),
              ),
            ),
    );

    final action = _buildContextActionBar();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '本轮收获',
              style: TextStyle(
                color: Colors.white.withOpacity(.84),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '${_bag.values.fold<int>(0, (sum, value) => sum + value)} 件',
              style: TextStyle(
                color: Colors.white.withOpacity(.26),
                fontSize: 8.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: action ??
              Container(
                width: double.infinity,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.014),
                  border: Border.all(
                    color: Colors.white.withOpacity(.035),
                    width: .7,
                  ),
                ),
                child: Text(
                  '继续探索，关键操作会在这里出现。',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.20),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
        ),
        const SizedBox(height: 8),
        if (fill) Expanded(child: body) else SizedBox(height: 82, child: body),
      ],
    );
  }

  Widget _buildWideBody() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
          child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildGoalBar(compact: false),
                const SizedBox(height: 12),
                Expanded(child: _buildMapPanel()),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 276,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildMessagePanel(),
                const SizedBox(height: 14),
                Expanded(child: _buildBagPanel(fill: true)),
                const SizedBox(height: 10),
                Text(
                  _remote
                      ? '提示 · 靠近危险目标可进入战斗，材料齐全后自动出现制作入口'
                      : '提示 · 微红代表危险，材料齐全后自动出现制作入口',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.22),
                    fontSize: 7.9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _withdrawButton(),
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBody() {
    final action = _buildContextActionBar();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _buildMapPanel()),
          const SizedBox(height: 7),
          _buildMessagePanel(),
          if (action != null) ...<Widget>[
            const SizedBox(height: 7),
            SizedBox(height: 48, child: action),
          ],
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.022),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white.withOpacity(.055), width: .6),
                  ),
                  child: Text(
                    _bag.isEmpty
                        ? '本轮收获 · 暂无'
                        : '本轮收获 · ${_bag.values.fold<int>(0, (sum, value) => sum + value)} 件',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.46),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              _withdrawButton(),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // 主页底部常驻版本：不再套独立页面的毛玻璃、标题栏和背包面板，
      // 只保留清晰场景与实际走路交互。
      return Material(
        color: Colors.transparent,
        // 不再画顶部白色分割线，让底部场景更像正文背景自然延伸。
        child: _buildWalkStage(),
      );
    }

    return Material(
      color: NovelPalette.background.withOpacity(.72),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x12000000),
                      Color(0x28101718),
                      Color(0x52080B0D),
                    ],
                    stops: <double>[0, .48, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 54,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _remote
                                        ? '探索 · ${widget.controller.locationTitle.trim().isEmpty ? '当前场景' : widget.controller.locationTitle.trim()}'
                                        : '探索 · 海滩边缘',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.95),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _completed
                                        ? '现场调查完成'
                                        : (widget.developerPreview
                                            ? '走路探索测试 · 可上传背景与主角立绘'
                                            : '自由走动，走到哪里就探索到哪里'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.38),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.developerPreview) ...<Widget>[
                              Tooltip(
                                message: '选择场景背景图',
                                child: IconButton(
                                  onPressed: () => unawaited(
                                    _pickWalkPreviewImage(portrait: false),
                                  ),
                                  icon: Icon(
                                    Icons.image_outlined,
                                    size: 17,
                                    color: Colors.white.withOpacity(.52),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: '选择主角立绘',
                                child: IconButton(
                                  onPressed: () => unawaited(
                                    _pickWalkPreviewImage(portrait: true),
                                  ),
                                  icon: Icon(
                                    Icons.person_outline_rounded,
                                    size: 17,
                                    color: Colors.white.withOpacity(.52),
                                  ),
                                ),
                              ),
                            ],
                            if (!_remote)
                              Tooltip(
                                message: '生成新地图',
                                child: IconButton(
                                  onPressed: _reset,
                                  icon: Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                    color: Colors.white.withOpacity(.46),
                                  ),
                                ),
                              ),
                            Container(
                              height: 28,
                              padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(.065),
                                  width: .5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Image.asset(
                                    'assets/images/xing.webp',
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_scoreOverride ?? widget.controller.score.total}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(.78),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (widget.onClose != null)
                              Tooltip(
                                message: '关闭',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(21),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      color: Colors.black.withOpacity(0.08),
                                      child: IconButton(
                                        onPressed: widget.onClose,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 20,
                                          color: Colors.white,
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
                    Container(height: .5, color: Colors.white.withOpacity(.055)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760 &&
                              constraints.maxHeight >= 500;
                          return wide ? _buildWideBody() : _buildCompactBody();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 独立的格状组件，加入 Q 弹逻辑
class _FogTileWidget extends StatefulWidget {
  const _FogTileWidget({
    required this.index,
    required this.tile,
    required this.revealed,
    required this.searched,
    required this.frontier,
    required this.hasHook,
    required this.remote,
    required this.isRemoteRecipeInput,
    required this.nearbyInterest,
    required this.nearbyDanger,
    required this.isStartIndex,
    required this.onTap,
  });

  final int index;
  final _FogTileDef tile;
  final bool revealed;
  final bool searched;
  final bool frontier;
  final bool hasHook;
  final bool remote;
  final bool isRemoteRecipeInput;
  final int nearbyInterest;
  final int nearbyDanger;
  final bool isStartIndex;
  final VoidCallback onTap;

  @override
  State<_FogTileWidget> createState() => _FogTileWidgetState();
}

class _FogTileWidgetState extends State<_FogTileWidget> {
  bool _isPressed = false;

  Color _tileBorderColor() {
    if (!widget.revealed) {
      return widget.frontier
          ? Colors.white.withOpacity(.25)
          : Colors.white.withOpacity(.055);
    }
    if (widget.searched) return Colors.white.withOpacity(.055);
    if (widget.tile.kind == _FogTileKind.hazard ||
        widget.tile.kind == _FogTileKind.normalEnemy ||
        widget.tile.kind == _FogTileKind.eliteEnemy) {
      return const Color(0xFFD96F6F).withOpacity(.46);
    }
    if (widget.tile.kind == _FogTileKind.cache) {
      return const Color(0xFFD8BF7A).withOpacity(.62);
    }
    if (widget.tile.kind == _FogTileKind.coconutTree && widget.hasHook) {
      return _themeGreen.withOpacity(.86);
    }
    if (widget.tile.kind == _FogTileKind.scavenge ||
        widget.tile.kind == _FogTileKind.genericItem ||
        widget.tile.kind == _FogTileKind.branch ||
        widget.tile.kind == _FogTileKind.stone ||
        widget.tile.kind == _FogTileKind.vine ||
        widget.tile.kind == _FogTileKind.bottle) {
      return _themeGreen.withOpacity(.40);
    }
    return Colors.white.withOpacity(.10);
  }

  IconData _tileIcon() {
    switch (widget.tile.kind) {
      case _FogTileKind.genericItem:
        return Icons.category_outlined;
      case _FogTileKind.normalEnemy:
        return Icons.pets_outlined;
      case _FogTileKind.eliteEnemy:
        return Icons.local_fire_department_outlined;
      case _FogTileKind.branch:
        return Icons.park_outlined;
      case _FogTileKind.stone:
        return Icons.landscape_outlined;
      case _FogTileKind.vine:
        return Icons.link_rounded;
      case _FogTileKind.coconutTree:
        return Icons.park_rounded;
      case _FogTileKind.bottle:
        return Icons.local_drink_outlined;
      case _FogTileKind.scavenge:
        return Icons.inventory_2_outlined;
      case _FogTileKind.cache:
        return Icons.star_border_rounded;
      case _FogTileKind.hazard:
        return Icons.warning_amber_rounded;
      case _FogTileKind.empty:
        return Icons.circle_outlined;
    }
  }

  Color _qualityColor(int quality) {
    if (quality >= 9) return const Color(0xFFD8BF7A).withOpacity(.96);
    if (quality >= 7) return const Color(0xFFC58AF9).withOpacity(.94);
    if (quality >= 5) return const Color(0xFF74A8F7).withOpacity(.92);
    if (quality >= 3) return _themeGreen.withOpacity(.90);
    return Colors.white.withOpacity(.50);
  }

  @override
  Widget build(BuildContext context) {
    Color background = Colors.white.withOpacity(.014);
    if (!widget.revealed && widget.frontier) background = Colors.white.withOpacity(.052);
    if (widget.revealed) background = Colors.white.withOpacity(.046);
    if (widget.searched) background = Colors.white.withOpacity(.020);
    final isEnemy = widget.tile.kind == _FogTileKind.normalEnemy || widget.tile.kind == _FogTileKind.eliteEnemy;
    
    if (widget.revealed && (widget.tile.kind == _FogTileKind.hazard || isEnemy)) {
      background = const Color(0xFFD96F6F).withOpacity(.045);
    }
    if (widget.revealed && widget.tile.kind == _FogTileKind.cache && !widget.searched) {
      background = const Color(0xFFD8BF7A).withOpacity(.045);
    }
    if (widget.revealed && widget.tile.kind == _FogTileKind.coconutTree && widget.hasHook && !widget.searched) {
      background = _themeGreen.withOpacity(.075);
    }

    Widget content;
    if (!widget.revealed) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: widget.frontier ? 5 : 3,
            height: widget.frontier ? 5 : 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(widget.frontier ? .72 : .12),
              shape: BoxShape.circle,
            ),
          ),
          if (widget.frontier) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              '探索',
              style: TextStyle(
                color: Colors.white.withOpacity(.42),
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    } else if (widget.isStartIndex) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '起点',
            style: TextStyle(
              color: Colors.white.withOpacity(.92),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '海滩',
            style: TextStyle(
              color: Colors.white.withOpacity(.36),
              fontSize: 7.5,
            ),
          ),
        ],
      );
    } else if (widget.tile.kind == _FogTileKind.empty) {
      content = Center(
        child: widget.nearbyInterest == 0 && widget.nearbyDanger == 0
            ? Text(
                '·',
                style: TextStyle(
                  color: Colors.white.withOpacity(.20),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (widget.nearbyInterest > 0) ...<Widget>[
                      Icon(
                        Icons.diamond_outlined,
                        size: 10,
                        color: Colors.white.withOpacity(.68),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.nearbyInterest}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.78),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (widget.nearbyInterest > 0 && widget.nearbyDanger > 0)
                      const SizedBox(width: 6),
                    if (widget.nearbyDanger > 0) ...<Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 10,
                        color: const Color(0xFFD96F6F).withOpacity(.78),
                      ),
                      const SizedBox(width: 1),
                      Text(
                        '${widget.nearbyDanger}',
                        style: TextStyle(
                          color: const Color(0xFFD96F6F).withOpacity(.82),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      );
    } else {
      final actionable = !widget.searched &&
          widget.tile.kind != _FogTileKind.hazard &&
          (widget.tile.kind != _FogTileKind.coconutTree || widget.hasHook);
      final isHazard = widget.tile.kind == _FogTileKind.hazard;
      final isDanger = isHazard || isEnemy;
      final isRare = widget.tile.kind == _FogTileKind.cache ||
          widget.tile.kind == _FogTileKind.eliteEnemy ||
          widget.tile.rare;
      final iconColor = isDanger
          ? const Color(0xFFD96F6F).withOpacity(.88)
          : isRare
              ? const Color(0xFFD8BF7A).withOpacity(.92)
              : actionable && widget.remote
                  ? _qualityColor(widget.tile.quality)
                  : actionable
                      ? _themeGreen.withOpacity(.86)
                      : Colors.white.withOpacity(.44);
                      
      late final String statusText;
      if (widget.searched) {
        statusText = '已处理';
      } else if (isHazard) {
        statusText = '危险';
      } else if (widget.tile.kind == _FogTileKind.eliteEnemy) {
        statusText = '高级 · Q${widget.tile.quality}';
      } else if (widget.tile.kind == _FogTileKind.normalEnemy) {
        statusText = '普通 · Q${widget.tile.quality}';
      } else if (widget.tile.kind == _FogTileKind.coconutTree && !widget.hasHook) {
        statusText = '需工具';
      } else if (widget.tile.kind == _FogTileKind.scavenge ||
          widget.tile.kind == _FogTileKind.cache) {
        statusText = '搜刮';
      } else if (widget.remote && widget.isRemoteRecipeInput) {
        statusText = '合成材料 · Q${widget.tile.quality}';
      } else if (actionable) {
        statusText = '拾取 · Q${widget.tile.quality}';
      } else {
        statusText = '';
      }

      content = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 4, 3, 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(_tileIcon(), size: 12.5, color: iconColor),
                const SizedBox(height: 2),
                Text(
                  widget.tile.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDanger && !widget.searched
                        ? const Color(0xFFD96F6F).withOpacity(.88)
                        : Colors.white.withOpacity(widget.searched ? .28 : .90),
                    fontSize: 7.8,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (statusText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDanger
                          ? const Color(0xFFD96F6F).withOpacity(.66)
                          : isRare
                              ? const Color(0xFFD8BF7A).withOpacity(.86)
                              : actionable
                                  ? _themeGreen.withOpacity(.80)
                                  : Colors.white.withOpacity(.32),
                      fontSize: 6.4,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.tile.rare && !widget.searched)
            Positioned(
              top: 2,
              right: 2,
              child: Icon(
                Icons.star_rounded,
                size: 7,
                color: const Color(0xFFD8BF7A).withOpacity(.92),
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.88 : 1.0,
          duration: Duration(milliseconds: _isPressed ? 150 : 600),
          curve: _isPressed ? Curves.easeOutCubic : Curves.elasticOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              border: Border.all(
                color: _tileBorderColor(),
                width: widget.frontier ||
                        widget.tile.kind == _FogTileKind.cache ||
                        widget.tile.kind == _FogTileKind.hazard ||
                        isEnemy ||
                        (widget.tile.kind == _FogTileKind.coconutTree && widget.hasHook)
                    ? .9
                    : .6,
              ),
              boxShadow: widget.revealed &&
                      !widget.searched &&
                      (widget.tile.kind == _FogTileKind.cache ||
                          widget.tile.kind == _FogTileKind.eliteEnemy ||
                          (widget.tile.kind == _FogTileKind.coconutTree && widget.hasHook))
                  ? <BoxShadow>[
                      BoxShadow(
                        color: widget.tile.kind == _FogTileKind.cache
                            ? const Color(0xFFD8BF7A).withOpacity(.08)
                            : _themeGreen.withOpacity(.09),
                        blurRadius: 10,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}


class _SurroundPickupRewardToast extends StatefulWidget {
  const _SurroundPickupRewardToast({
    required this.text,
    required this.onCompleted,
    this.assetPath = '',
    this.assetPaths = const <String>[],
  });

  final String text;
  final VoidCallback onCompleted;
  final String assetPath;
  final List<String> assetPaths;

  @override
  State<_SurroundPickupRewardToast> createState() =>
      _SurroundPickupRewardToastState();
}

class _SurroundPickupRewardToastState extends State<_SurroundPickupRewardToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _offsetY;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    );

    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 57,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(_controller);

    _offsetY = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 30, end: 0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 34,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: -7)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 41,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -7, end: -22)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(_controller);

    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: .96, end: 1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 28,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 72,
      ),
    ]).animate(_controller);

    _controller.forward().whenComplete(widget.onCompleted);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, _offsetY.value),
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            );
          },
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.assetPath.isNotEmpty || widget.assetPaths.isNotEmpty) ...<Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final asset in <String>{
                        if (widget.assetPath.isNotEmpty) widget.assetPath,
                        ...widget.assetPaths.where((path) => path.isNotEmpty),
                      })
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Image.asset(
                            asset,
                            width: 38,
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      inherit: false,
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .16,
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                      shadows: <Shadow>[
                        Shadow(
                          color: Color(0xB3000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                        Shadow(
                          color: Color(0x52000000),
                          blurRadius: 16,
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
    );
  }
}

class _SurroundingsHeader extends StatelessWidget {
  const _SurroundingsHeader({
    required this.title,
    this.onClose,
  });

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;

    return SizedBox(
      height: compact ? 52 : 56,
      child: Padding(
        padding: EdgeInsets.only(
          left: compact ? 15 : 18,
          right: compact ? 9 : 11,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.94),
                  fontSize: compact ? 15.5 : 16.5,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .08,
                ),
              ),
            ),
            if (onClose != null)
              Tooltip(
                message: '关闭',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.black.withOpacity(0.15),
                      child: IconButton(
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
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

enum _SurroundTutorialVisual { explore, merge, collect, arrange }

class _SurroundTutorialStep extends StatelessWidget {
  const _SurroundTutorialStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
    required this.visual,
    this.last = false,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;
  final _SurroundTutorialVisual visual;
  final bool last;

  Widget _node(
    String label, {
    bool green = false,
    bool mergeReady = false,
    bool plus = false,
    double width = 82,
  }) {
    final bgColor = green
        ? _themeGreen.withOpacity(0.15)
        : mergeReady
            ? _themeGreen.withOpacity(0.1)
            : Colors.white.withOpacity(0.055);
    final borderColor = green
        ? _themeGreen.withOpacity(0.9)
        : mergeReady
            ? _themeGreen.withOpacity(0.5)
            : Colors.white.withOpacity(0.12);
    final textColor = green ? _themeGreen : Colors.white.withOpacity(0.85);

    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: width,
          height: 30,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: borderColor,
              width: mergeReady ? 1.25 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (plus) ...<Widget>[
                const SizedBox(width: 4),
                const Text(
                  '+',
                  style: TextStyle(
                    color: _themeGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _visual() {
    switch (visual) {
      case _SurroundTutorialVisual.explore:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _node('环境细节', plus: true, width: 92),
            const SizedBox(width: 10),
            Icon(Icons.touch_app_outlined, size: 18, color: Colors.white.withOpacity(0.3)),
          ],
        );
      case _SurroundTutorialVisual.merge:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _node('长条材料', width: 76),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white.withOpacity(0.3)),
            ),
            _node('锋利碎片', mergeReady: true, width: 76),
          ],
        );
      case _SurroundTutorialVisual.collect:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _node('尖木棍', green: true, width: 82),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white.withOpacity(0.3)),
            ),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.1),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.white.withOpacity(.15)),
              ),
              child: Icon(Icons.inventory_2_outlined, size: 16, color: Colors.white.withOpacity(0.7)),
            ),
          ],
        );
      case _SurroundTutorialVisual.arrange:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Transform.translate(offset: const Offset(0, 5), child: _node('物品 A', width: 64)),
            const SizedBox(width: 6),
            const Icon(Icons.center_focus_weak_rounded, size: 19, color: _themeGreen),
            const SizedBox(width: 6),
            Transform.translate(offset: const Offset(0, -5), child: _node('物品 B', width: 64)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04), // 极轻微的提亮
          borderRadius: BorderRadius.zero,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 25,
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: _themeGreen,
                      fontSize: 9.4,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                ),
                Icon(icon, size: 14, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.035),
                borderRadius: BorderRadius.zero,
              ),
              child: _visual(),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10.2,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurroundStage extends StatefulWidget {
  const _SurroundStage({
    required this.defs,
    required this.visible,
    required this.positions,
    required this.parentOf,
    required this.isExplorable,
    required this.isExhausted,
    required this.isDraggable,
    required this.activeId,
    required this.draggingId,
    required this.mergeTargetId,
    required this.revealing,
    required this.collecting,
    required this.onResetLayout,
    required this.onTutorial,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Map<String, _SurroundNodeDef> defs;
  final Set<String> visible;
  final Map<String, Offset> positions;
  final String? Function(String id) parentOf;
  final bool Function(String id) isExplorable;
  final bool Function(String id) isExhausted;
  final bool Function(String id) isDraggable;
  final String activeId;
  final String? draggingId;
  final String? mergeTargetId;
  final Set<String> revealing;
  final Set<String> collecting;
  final VoidCallback onResetLayout;
  final VoidCallback onTutorial;
  final Future<void> Function(String id) onTap;
  final void Function(String id) onDragStart;
  final void Function(String id, DragUpdateDetails details, Size size)
      onDragUpdate;
  final void Function(String id) onDragEnd;

  @override
  State<_SurroundStage> createState() => _SurroundStageState();
}

class _SurroundStageState extends State<_SurroundStage> {
  final TransformationController _viewController = TransformationController();

  Size _lastViewportSize = Size.zero;
  Size _lastCanvasSize = Size.zero;
  bool _didInitialFit = false;
  bool _fitScheduled = false;
  bool _userTransformed = false;
  bool _needsRefit = true;
  bool _nodePointerActive = false;

  @override
  void didUpdateWidget(covariant _SurroundStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibleChanged = widget.visible.length != oldWidget.visible.length ||
        !widget.visible.containsAll(oldWidget.visible) ||
        !oldWidget.visible.containsAll(widget.visible);
    if (visibleChanged && !_userTransformed) {
      _needsRefit = true;
    }
  }

  @override
  void dispose() {
    _viewController.dispose();
    super.dispose();
  }

  Size _canvasSizeFor(Size viewportSize) {
    return Size(
      math.max(viewportSize.width * 1.34, 760.0),
      math.max(viewportSize.height * 1.28, 520.0),
    );
  }

  Rect _visibleBounds(Size canvasSize) {
    if (widget.visible.isEmpty) {
      return Offset.zero & canvasSize;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final id in widget.visible) {
      final def = widget.defs[id];
      if (def == null) continue;
      final p = widget.positions[id] ?? def.position;
      final center = Offset(p.dx * canvasSize.width, p.dy * canvasSize.height);
      final emphasized =
          def.collectible || def.type == _SurroundNodeType.encounter;
      final halfWidth = emphasized ? 78.0 : 70.0;
      final halfHeight = emphasized ? 30.0 : 24.0;
      minX = math.min(minX, center.dx - halfWidth);
      minY = math.min(minY, center.dy - halfHeight);
      maxX = math.max(maxX, center.dx + halfWidth);
      maxY = math.max(maxY, center.dy + halfHeight);
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return Offset.zero & canvasSize;
    }

    const padding = 54.0;
    return Rect.fromLTRB(
      (minX - padding).clamp(0.0, canvasSize.width),
      (minY - padding).clamp(0.0, canvasSize.height),
      (maxX + padding).clamp(0.0, canvasSize.width),
      (maxY + padding).clamp(0.0, canvasSize.height),
    );
  }

  void _scheduleFit(Size viewportSize, Size canvasSize, {bool force = false}) {
    _lastViewportSize = viewportSize;
    _lastCanvasSize = canvasSize;

    if (!force && _didInitialFit && !_needsRefit) return;
    if (_fitScheduled) return;
    _fitScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (!mounted) return;
      if (!force && _userTransformed) return;
      _fitToVisible(viewportSize, canvasSize);
    });
  }

  void _fitToVisible(Size viewportSize, Size canvasSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;

    final bounds = _visibleBounds(canvasSize);
    final safeWidth = math.max(bounds.width, 1.0);
    final safeHeight = math.max(bounds.height, 1.0);

    final scale = math.min(
      viewportSize.width / safeWidth,
      viewportSize.height / safeHeight,
    ).clamp(0.38, 1.12).toDouble();

    final tx = viewportSize.width / 2 - bounds.center.dx * scale;
    final ty = viewportSize.height / 2 - bounds.center.dy * scale;

    _viewController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);

    _didInitialFit = true;
    _needsRefit = false;
  }

  void _resetLayoutAndView() {
    widget.onResetLayout();
    _userTransformed = false;
    _needsRefit = true;
    if (_lastViewportSize != Size.zero && _lastCanvasSize != Size.zero) {
      _scheduleFit(_lastViewportSize, _lastCanvasSize, force: true);
    }
  }

  void _setNodePointerActive(bool active) {
    if (_nodePointerActive == active || !mounted) return;
    setState(() => _nodePointerActive = active);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final canvasSize = _canvasSizeFor(viewportSize);

        final sizeChanged = viewportSize != _lastViewportSize ||
            canvasSize != _lastCanvasSize;
        _lastViewportSize = viewportSize;
        _lastCanvasSize = canvasSize;
        if (!_didInitialFit || _needsRefit || (sizeChanged && !_userTransformed)) {
          _scheduleFit(viewportSize, canvasSize);
        }

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              InteractiveViewer(
                transformationController: _viewController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(260),
                minScale: .38,
                maxScale: 2.4,
                panEnabled: !_nodePointerActive,
                scaleEnabled: true,
                trackpadScrollCausesScale: true,
                clipBehavior: Clip.none,
                onInteractionStart: (_) {
                  _userTransformed = true;
                },
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SurroundLinePainter(
                            positions: widget.positions,
                            visible: widget.visible,
                            parentOf: widget.parentOf,
                          ),
                        ),
                      ),
                      for (final id in widget.visible)
                        if (widget.defs[id] != null)
                          _positionedNode(
                            context,
                            canvasSize,
                            id,
                            widget.defs[id]!,
                          ),
                      if (widget.draggingId != null &&
                          widget.mergeTargetId != null)
                        _mergeHint(
                          canvasSize,
                          widget.draggingId!,
                          widget.mergeTargetId!,
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                bottom: 12,
                child: IgnorePointer(
                  child: Text(
                    '拖动画布 · 双指 / 滚轮缩放',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.30),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 10,
                child: _SurroundStageStatus(
                  onResetLayout: _resetLayoutAndView,
                  onTutorial: widget.onTutorial,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedNode(
    BuildContext context,
    Size size,
    String id,
    _SurroundNodeDef def,
  ) {
    final p = widget.positions[id] ?? def.position;
    final compact = size.width < 560;
    final width = math
        .min(compact ? 112.0 : 132.0, math.max(88.0, size.width * .19))
        .toDouble();
    final height = def.collectible || def.type == _SurroundNodeType.encounter
        ? (compact ? 43.0 : 46.0)
        : (compact ? 34.0 : 37.0);
    final center = Offset(p.dx * size.width, p.dy * size.height);
    final left = (center.dx - width / 2)
        .clamp(2.0, math.max(2.0, size.width - width - 2));
    final top = (center.dy - height / 2)
        .clamp(2.0, math.max(2.0, size.height - height - 2));
    final mergeReady = id == widget.mergeTargetId ||
        (id == widget.draggingId && widget.mergeTargetId != null);

    return Positioned(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width,
      height: height,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.revealing.contains(id) ? .72 : 1,
        curve: Curves.easeOut,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: widget.revealing.contains(id)
              ? .985
              : (id == widget.draggingId ? 1.015 : 1),
          curve: Curves.easeOut,
          child: _SurroundNodeButton(
            def: def,
            active: widget.activeId == id,
            explorable: widget.isExplorable(id),
            exhausted: widget.isExhausted(id),
            draggable: widget.isDraggable(id),
            dragging: widget.draggingId == id,
            mergeReady: mergeReady,
            collecting: widget.collecting.contains(id),
            onTap: () => widget.onTap(id),
            onPointerDown: () => _setNodePointerActive(true),
            onPointerUp: () => _setNodePointerActive(false),
            onPanStart:
                widget.isDraggable(id) ? (_) => widget.onDragStart(id) : null,
            onPanUpdate: widget.isDraggable(id)
                ? (details) => widget.onDragUpdate(id, details, size)
                : null,
            onPanEnd:
                widget.isDraggable(id) ? (_) => widget.onDragEnd(id) : null,
            onPanCancel:
                widget.isDraggable(id) ? () => widget.onDragEnd(id) : null,
          ),
        ),
      ),
    );
  }

  Widget _mergeHint(Size size, String a, String b) {
    final pa = widget.positions[a];
    final pb = widget.positions[b];
    if (pa == null || pb == null) return const SizedBox.shrink();
    final midpoint = Offset(
      (pa.dx + pb.dx) * size.width / 2,
      (pa.dy + pb.dy) * size.height / 2,
    );
    const width = 70.0;
    const height = 23.0;
    return Positioned(
      left: (midpoint.dx - width / 2)
          .clamp(4.0, math.max(4.0, size.width - width - 4))
          .toDouble(),
      top: (midpoint.dy - 34)
          .clamp(4.0, math.max(4.0, size.height - height - 4))
          .toDouble(),
      width: width,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _themeGreen.withOpacity(0.16),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: _themeGreen.withOpacity(0.45)),
          ),
          child: const Center(
            child: Text(
              '松开组合',
              style: TextStyle(
                color: _themeGreen,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurroundStageStatus extends StatelessWidget {
  const _SurroundStageStatus({
    required this.onResetLayout,
    required this.onTutorial,
  });

  final VoidCallback onResetLayout;
  final VoidCallback onTutorial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 1, bottom: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: '归位节点',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onResetLayout,
                borderRadius: BorderRadius.zero,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.center_focus_weak_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.58),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: '玩法教程',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTutorial,
                borderRadius: BorderRadius.zero,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.58),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurroundNodeButton extends StatefulWidget {
  const _SurroundNodeButton({
    required this.def,
    required this.active,
    required this.explorable,
    required this.exhausted,
    required this.draggable,
    required this.dragging,
    required this.mergeReady,
    required this.collecting,
    required this.onTap,
    this.onPointerDown,
    this.onPointerUp,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  final _SurroundNodeDef def;
  final bool active;
  final bool explorable;
  final bool exhausted;
  final bool draggable;
  final bool dragging;
  final bool mergeReady;
  final bool collecting;
  final VoidCallback onTap;
  final VoidCallback? onPointerDown;
  final VoidCallback? onPointerUp;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  State<_SurroundNodeButton> createState() => _SurroundNodeButtonState();
}

class _SurroundNodeButtonState extends State<_SurroundNodeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false; // 触控 Q弹 核心状态

  bool get _shouldPulse =>
      widget.def.collectible ||
      widget.def.type == _SurroundNodeType.encounter ||
      widget.mergeReady;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _SurroundNodeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.def.collectible != widget.def.collectible ||
        oldWidget.def.type != widget.def.type ||
        oldWidget.mergeReady != widget.mergeReady) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final collectible = def.collectible;
    final encounter = def.type == _SurroundNodeType.encounter;
    final encounterQualityColor = _surroundQualityColor(def.quality);

    final pulse = Curves.easeInOut.transform(_pulseController.value);

    Color bgColor = Colors.white.withOpacity(0.055);
    Color borderColor = Colors.white.withOpacity(0.08);
    Color textColor = Colors.white.withOpacity(0.85);
    List<BoxShadow> glow = const <BoxShadow>[];

    if (widget.exhausted) {
      bgColor = Colors.white.withOpacity(0.025);
      textColor = Colors.white.withOpacity(0.3);
      borderColor = Colors.transparent;
    }

    if (widget.active && !collectible && !widget.mergeReady) {
      bgColor = Colors.white.withOpacity(0.1);
      borderColor = const Color(0xFF8BD7A2).withOpacity(0.8);
      textColor = Colors.white;
    }

    if (widget.mergeReady && !collectible) {
      bgColor = const Color(0xFF8BD7A2).withOpacity(0.08 + 0.05 * pulse);
      borderColor = const Color(0xFF8BD7A2).withOpacity(0.4 + 0.2 * pulse);
    }

    if (collectible) {
      bgColor = Colors.white.withOpacity(0.075);
      textColor = Colors.white.withOpacity(0.94);
      borderColor = const Color(0xFF8BD7A2).withOpacity(0.88);
      glow = [
        BoxShadow(
          color: const Color(0xFF8BD7A2).withOpacity(0.10 + 0.08 * pulse),
          blurRadius: 14,
          spreadRadius: 0.6,
        ),
      ];
    }

    if (encounter) {
      bgColor = const Color(0xFFB44747).withOpacity(0.10 + 0.03 * pulse);
      borderColor = encounterQualityColor.withOpacity(0.72 + 0.16 * pulse);
      textColor = Colors.white;
      glow = <BoxShadow>[
        BoxShadow(
          color: encounterQualityColor.withOpacity(0.08 + 0.06 * pulse),
          blurRadius: 15,
        ),
      ];
    }

    final selectedScale = widget.active && !collectible && !widget.mergeReady ? 1.022 : 1.0;
    final pulseScale = collectible || encounter
        ? 1 + .009 * pulse
        : widget.mergeReady
            ? 1 + .013 * pulse
            : 1.0;

    // 加入按下时的缩小倍率
    final targetScale = pulseScale * selectedScale * (_isPressed ? 0.88 : 1.0);

    return Semantics(
      button: true,
      label: def.label,
      hint: collectible
          ? '点击拾取并放入背包'
          : encounter
              ? '点击进入战斗'
              : null,
      child: MouseRegion(
        cursor: widget.draggable
            ? SystemMouseCursors.grab
            : SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            setState(() => _isPressed = true);
            widget.onPointerDown?.call();
          },
          onPointerUp: (_) {
            setState(() => _isPressed = false);
            widget.onPointerUp?.call();
          },
          onPointerCancel: (_) {
            setState(() => _isPressed = false);
            widget.onPointerUp?.call();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.dragging ? null : widget.onTap,
            // 修复点：直接使用父级传下来的参数，无需再次判断
            onPanStart: widget.onPanStart,
            onPanUpdate: widget.onPanUpdate,
            onPanEnd: widget.onPanEnd,
            onPanCancel: widget.onPanCancel,
            child: AnimatedScale(
              scale: targetScale,
              duration: Duration(milliseconds: _isPressed ? 150 : 600),
              curve: _isPressed ? Curves.easeOutCubic : Curves.elasticOut,
              child: ClipRect(
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: borderColor,
                      width: 0.8,
                    ),
                    boxShadow: glow,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: collectible ? 7 : 10,
                    vertical: collectible ? 4 : 0,
                  ),
                  child: collectible
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 18,
                                    height: 18,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8BD7A2).withOpacity(0.14),
                                      border: Border.all(
                                        color: const Color(0xFF8BD7A2).withOpacity(0.34),
                                        width: .7,
                                      ),
                                    ),
                                    child: widget.collecting
                                        ? const SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.4,
                                              color: Color(0xFF8BD7A2),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.inventory_2_outlined,
                                            size: 11.5,
                                            color: Color(0xFF8BD7A2),
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      def.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 10.6,
                                        height: 1.05,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8BD7A2).withOpacity(0.10 + 0.04 * pulse),
                                      border: Border.all(
                                        color: const Color(0xFF8BD7A2).withOpacity(0.34 + 0.12 * pulse),
                                        width: .7,
                                      ),
                                    ),
                                    child: const Text(
                                      '可拾取',
                                      style: TextStyle(
                                        color: Color(0xFF8BD7A2),
                                        fontSize: 7.8,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.collecting
                                      ? '正在放入背包…'
                                      : '点击后放入背包',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.62),
                                    fontSize: 8.3,
                                    height: 1,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              if (encounter) ...<Widget>[
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      def.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 10.8,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .2,
                                      ),
                                    ),
                                    if (encounter)
                                      Text(
                                        '等级 ${def.quality} · ${def.eliteCount > 0 ? '精英敌人' : '普通敌人'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: encounterQualityColor.withOpacity(.92),
                                          fontSize: 7.8,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.explorable) ...<Widget>[
                                const SizedBox(width: 4),
                                const Text(
                                  '+',
                                  style: TextStyle(
                                    color: Color(0xFF8BD7A2),
                                    fontSize: 13,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
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

class _SurroundLinePainter extends CustomPainter {
  const _SurroundLinePainter({
    required this.positions,
    required this.visible,
    required this.parentOf,
  });

  final Map<String, Offset> positions;
  final Set<String> visible;
  final String? Function(String id) parentOf;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(.11)
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round;

    Offset px(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

    for (final id in visible) {
      final parent = parentOf(id);
      if (parent == null || !visible.contains(parent)) continue;

      final a = positions[parent];
      final b = positions[id];
      if (a == null || b == null) continue;

      canvas.drawLine(px(a), px(b), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SurroundLinePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.visible != visible ||
        oldDelegate.parentOf != parentOf;
  }
}

class _SurroundInfoPanel extends StatelessWidget {
  const _SurroundInfoPanel({
    required this.info,
    required this.labelOf,
  });

  final _SurroundInfo info;
  final String Function(String id) labelOf;

  String get _statusTitle {
    if (info.gain.isNotEmpty) return '获得物品';
    if (info.created.isNotEmpty) return '组合成功';
    if (info.title.trim().isNotEmpty) return info.title.trim();
    if (info.text.contains('正在')) return '探索中';
    if (info.text.contains('发现')) return '发现';
    if (info.text.contains('没有更多') || info.text.contains('搜索过')) {
      return '已查看';
    }
    return '提示';
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = info.consume.isNotEmpty ||
        info.keep.isNotEmpty ||
        info.created.isNotEmpty ||
        info.gain.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
            width: .8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Text(
              _statusTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 11.8,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: .08,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              info.text,
              maxLines: hasResult ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 11,
                height: 1.22,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hasResult) ...<Widget>[
              const Spacer(),
              SizedBox(
                height: 21,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: <Widget>[
                    if (info.consume.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _SurroundResultChip(
                          label: '消耗',
                          value: info.consume.map(labelOf).join('、'),
                        ),
                      ),
                    if (info.keep.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _SurroundResultChip(
                          label: '保留',
                          value: info.keep.map(labelOf).join('、'),
                        ),
                      ),
                    if (info.created.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _SurroundResultChip(
                          label: '生成',
                          value: info.created.map(labelOf).join('、'),
                        ),
                      ),
                    if (info.gain.isNotEmpty)
                      _SurroundResultChip(
                        label: '获得',
                        value: info.gain.map(labelOf).join('、'),
                        accent: true,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SurroundResultChip extends StatelessWidget {
  const _SurroundResultChip({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    if (accent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 10, height: 1.15),
            children: <InlineSpan>[
              const TextSpan(
                text: '获得 · ',
                style: TextStyle(
                  color: _themeGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 10, height: 1.15),
          children: <InlineSpan>[
            TextSpan(
              text: '$label · ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

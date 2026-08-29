part of '../novel_sheets.dart';

// 页面入口 / 对外入口：
//   - showNovelSurroundingsDeveloperPreview(...)
//   - NovelSurroundingsTab
// 其余 `_Surround...` 类型均为探索页内部节点、拖拽、合成、拾取与教程实现。[cite: 1]

// ============================================================================
// 当前场景“周围”互动页
// 从孤岛节点原型迁移：点击探索、拖拽、可组合高亮、消耗/保留/生成。[cite: 1]
// ============================================================================

Future<void> showNovelSurroundingsDeveloperPreview(
  BuildContext context,
  NovelGameController controller,
) async {
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
    this.onClose,
  });

  final NovelGameController controller;
  final bool developerPreview;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _NovelSurroundingsPage(
      controller: controller,
      developerPreview: developerPreview,
      embedded: false,
      onClose: onClose,
    );
  }
}

enum _SurroundNodeType { environment, container, item, target, product }

class _SurroundNodeDef {
  const _SurroundNodeDef({
    required this.id,
    required this.label,
    required this.type,
    required this.position,
    this.text = '',
    this.children = const <String>[],
    this.collectible = false,
  });

  final String id;
  final String label;
  final _SurroundNodeType type;
  final Offset position;
  final String text;
  final List<String> children;
  final bool collectible;
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
    this.onClose,
  });

  final NovelGameController controller;
  final bool embedded;
  final bool developerPreview;
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
  ) {
    final result = <String, Offset>{};
    final root = defs[rootId];
    if (root != null) {
      result[rootId] = const Offset(.5, .5);
      final branchIds = root.children;
      final branchPositions = _rootBranchPositions(branchIds.length);
      for (var index = 0; index < branchIds.length; index++) {
        result[branchIds[index]] = branchPositions[index];
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
      final seed = _stableNodeHash(id);
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
      parsedDefs[id] = _SurroundNodeDef(
        id: id,
        label: stringValue(node['label'], id),
        type: _nodeTypeOf(node['type']),
        position: _defaultNodePosition(index),
        text: stringValue(node['text']),
        children: children,
        collectible: boolValue(node['collectible']),
      );
    }
    final rootId = stringValue(payload['root_id']).trim();
    final layoutPositions = _graphNodePositions(rootId, parsedDefs);
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

      // 已用于合成的材料只从当前画布消失，但仍然保持“已经发现”的状态。
      // 这样父节点不会因为它变回 undiscovered 而再次把材料展开出来。
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
      setState(() {
        _collecting.remove(id);
        _info = _SurroundInfo(
          title: '已放入背包',
          text: '「$rewardName」已放入背包。',
          gain: <String>[id],
        );
      });
      _showCollectedToast(rewardName);
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

  void _showCollectedToast(String rewardName) {
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
            text: '$rewardName 已放入背包',
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
      // 预览模式直接完成合成，不再人为等待半秒。
      // consumed 只从 visible 删除，不能从 discovered 删除，否则展开节点会把它再次生成。
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
      barrierColor: Colors.black.withOpacity(.34),
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
              borderRadius: BorderRadius.zero,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.075),
                    border: Border.all(
                      color: Colors.white.withOpacity(.11),
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
                                borderRadius: BorderRadius.zero,
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: Colors.white.withOpacity(0.5),
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
                            borderRadius: BorderRadius.zero,
                            child: InkWell(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              borderRadius: BorderRadius.zero,
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
                    color: _archiveThemeGreen,
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

        return Material(
          color: widget.embedded
              ? Colors.transparent
              : Colors.black.withOpacity(0.24),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final compact = viewport.maxWidth < 620;
                final horizontalInset = compact ? 12.0 : 28.0;
                final verticalInset = compact ? 14.0 : 28.0;
                final maxWindowWidth = math.max(
                  0.0,
                  viewport.maxWidth - horizontalInset * 2,
                );
                final maxWindowHeight = math.max(
                  0.0,
                  viewport.maxHeight - verticalInset * 2,
                );
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
                      borderRadius: BorderRadius.zero,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.075),
                            borderRadius: BorderRadius.zero,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                              width: 1,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withOpacity(0.20),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
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
        );
      },
    );
  }
}

class _SurroundPickupRewardToast extends StatefulWidget {
  const _SurroundPickupRewardToast({
    required this.text,
    required this.onCompleted,
  });

  final String text;
  final VoidCallback onCompleted;

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
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.zero,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: Colors.white.withOpacity(0.62),
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
    // 教程暗黑毛玻璃风格同步
    final bgColor = green
        ? _archiveThemeGreen.withOpacity(0.15)
        : mergeReady
            ? _archiveThemeGreen.withOpacity(0.1)
            : Colors.white.withOpacity(0.055);
    final borderColor = green
        ? _archiveThemeGreen.withOpacity(0.9)
        : mergeReady
            ? _archiveThemeGreen.withOpacity(0.5)
            : Colors.white.withOpacity(0.12);
    final textColor = green ? _archiveThemeGreen : Colors.white.withOpacity(0.85);

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
                    color: _archiveThemeGreen,
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
            const Icon(Icons.center_focus_weak_rounded, size: 19, color: _archiveThemeGreen),
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
                      color: _archiveThemeGreen,
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
    // 画布比窗口大，但不要大到初始视角只剩很小的一团节点。
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
      final halfWidth = def.collectible ? 78.0 : 70.0;
      final halfHeight = def.collectible ? 30.0 : 24.0;
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
                // 只有从空白区域开始拖动时才允许平移画布。
                // 手指/鼠标按在任意节点上时，节点优先处理点击或物品拖拽。
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
    final height = def.collectible
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
            color: _archiveThemeGreen.withOpacity(0.16),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: _archiveThemeGreen.withOpacity(0.45)),
          ),
          child: const Center(
            child: Text(
              '松开组合',
              style: TextStyle(
                color: _archiveThemeGreen,
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

  bool get _shouldPulse => widget.def.collectible || widget.mergeReady;

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

    final pulse = Curves.easeInOut.transform(_pulseController.value);

    // 核心样式变量：与抽屉统一为浅白毛玻璃 + 细线
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
      // 选中状态：微亮白底，极细绿色高亮线
      bgColor = Colors.white.withOpacity(0.1); 
      borderColor = _archiveThemeGreen.withOpacity(0.8);
      textColor = Colors.white;
    }

    if (widget.mergeReady && !collectible) {
      // 组合状态：暗黑绿色呼吸
      bgColor = _archiveThemeGreen.withOpacity(0.08 + 0.05 * pulse);
      borderColor = _archiveThemeGreen.withOpacity(0.4 + 0.2 * pulse);
    }

    if (collectible) {
      // 拾取状态：不要整块纯绿，维持玻璃底，只用绿色边框/徽标/轻呼吸光提示可领取
      bgColor = Colors.white.withOpacity(0.075);
      textColor = Colors.white.withOpacity(0.94);
      borderColor = _archiveThemeGreen.withOpacity(0.88);
      glow = [
        BoxShadow(
          color: _archiveThemeGreen.withOpacity(0.10 + 0.08 * pulse),
          blurRadius: 14,
          spreadRadius: 0.6,
        ),
      ];
    }

    final selectedScale = widget.active && !collectible && !widget.mergeReady ? 1.022 : 1.0;
    final pulseScale = collectible
        ? 1 + .009 * pulse
        : widget.mergeReady
            ? 1 + .013 * pulse
            : 1.0;

    return Semantics(
      button: true,
      label: def.label,
      hint: collectible ? '点击拾取并放入背包' : null,
      child: MouseRegion(
        cursor: widget.draggable
            ? SystemMouseCursors.grab
            : SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.onPointerDown?.call(),
          onPointerUp: (_) => widget.onPointerUp?.call(),
          onPointerCancel: (_) => widget.onPointerUp?.call(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.dragging ? null : widget.onTap,
            onPanStart: widget.onPanStart,
            onPanUpdate: widget.onPanUpdate,
            onPanEnd: widget.onPanEnd,
            onPanCancel: widget.onPanCancel,
            child: Transform.scale(
              scale: pulseScale,
              child: AnimatedScale(
                scale: selectedScale,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
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
                                      color: _archiveThemeGreen.withOpacity(0.14),
                                      border: Border.all(
                                        color: _archiveThemeGreen.withOpacity(0.34),
                                        width: .7,
                                      ),
                                    ),
                                    child: widget.collecting
                                        ? SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.4,
                                              color: _archiveThemeGreen,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.inventory_2_outlined,
                                            size: 11.5,
                                            color: _archiveThemeGreen,
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
                                      color: _archiveThemeGreen.withOpacity(0.10 + 0.04 * pulse),
                                      border: Border.all(
                                        color: _archiveThemeGreen.withOpacity(0.34 + 0.12 * pulse),
                                        width: .7,
                                      ),
                                    ),
                                    child: const Text(
                                      '可拾取',
                                      style: TextStyle(
                                        color: _archiveThemeGreen,
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
                              Flexible(
                                child: Text(
                                  def.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor, // 统一使用暗黑色系变量
                                    fontSize: 10.8,
                                    height: 1.1,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .2,
                                  ),
                                ),
                              ),
                              if (widget.explorable) ...<Widget>[
                                const SizedBox(width: 4),
                                const Text(
                                  '+',
                                  style: TextStyle(
                                    color: _archiveThemeGreen,
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
    // 与抽屉一致的浅白细线，避免抢过节点本身
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
                  color: _archiveThemeGreen,
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
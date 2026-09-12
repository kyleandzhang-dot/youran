part of '../novel_sheets.dart';

/// ScenePlan v4 预览页：
/// - 一张 background 作为整场景连续地面
/// - scene_objects 作为少量关键静态资产
/// - 2.5D 等距投影只影响显示，不改变逻辑坐标/碰撞 footprint
/// - 点击可行走地面做寻路预览，长按对象查看资产信息
class NovelExplorationPage extends StatefulWidget {
  const NovelExplorationPage({
    super.key,
    required this.backend,
    this.sessionId,
    this.initialSceneName = '斗破苍穹 乌坦城萧家坊市',
    this.onEntityTap,
  });

  final NovelBackend backend;
  final String? sessionId;
  final String initialSceneName;
  final ValueChanged<JsonMap>? onEntityTap;

  @override
  State<NovelExplorationPage> createState() => _NovelExplorationPageState();
}

class _NovelExplorationPageState extends State<NovelExplorationPage> {
  late final TextEditingController _nameController;
  JsonMap? _scenePlan;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialSceneName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.backend.previewSceneLayout(
        name: name,
        sessionId: widget.sessionId,
      );
      final plan = _sceneMap(response['scene_plan'] ?? response);
      if (plan.isEmpty) {
        throw const NovelBackendException('后端没有返回 scene_plan');
      }
      if (_sceneMap(plan['background']).isEmpty) {
        throw const NovelBackendException('scene_plan.background 为空');
      }
      if (!mounted) return;
      setState(() => _scenePlan = plan);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is NovelBackendException ? error.message : error.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleEntityTap(JsonMap entity) {
    final callback = widget.onEntityTap;
    if (callback != null) {
      callback(entity);
      return;
    }
    _showEntitySheet(entity);
  }

  Future<void> _showEntitySheet(JsonMap entity) async {
    if (!mounted) return;
    final movement = _sceneString(entity['movement']);
    final renderMode = _sceneString(entity['render_mode']);
    final interaction = _sceneString(entity['interaction']);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _sceneString(entity['name'], '场景对象'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${_sceneString(entity['kind'], 'entity')} · '
                '${_sceneString(entity['category'])} · '
                'x=${_sceneNum(entity['x']).toStringAsFixed(1)} · '
                'y=${_sceneNum(entity['y']).toStringAsFixed(1)} · '
                '${_sceneNum(entity['width'], 1).toStringAsFixed(1)}×'
                '${_sceneNum(entity['height'], 1).toStringAsFixed(1)} 格',
              ),
              if (renderMode.isNotEmpty || movement.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '渲染：${renderMode.isEmpty ? '默认' : renderMode} · '
                  '移动：${movement.isEmpty ? '默认' : movement} · '
                  '静态资产：${entity['static'] == true ? '是' : '否'}',
                ),
              ],
              if (_sceneString(entity['purpose']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(_sceneString(entity['purpose'])),
              ],
              if (interaction.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text('交互：$interaction'),
              ],
              if (_sceneString(entity['image_prompt']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                SelectableText(
                  '图片提示词：${_sceneString(entity['image_prompt'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBackgroundSheet(JsonMap background) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _sceneString(background['name'], '场景背景'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (_sceneString(background['style_prompt']).isNotEmpty)
                SelectableText('统一风格：${_sceneString(background['style_prompt'])}'),
              if (_sceneString(background['image_prompt']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                SelectableText('背景提示词：${_sceneString(background['image_prompt'])}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2.5D 场景蓝图')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _generate(),
                      decoration: const InputDecoration(
                        labelText: '场景名称',
                        hintText: '例如：乌坦城萧家坊市 / 萧家后山 / 魔兽山脉营地',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _loading ? null : _generate,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_loading ? '生成中' : '生成'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            Expanded(
              child: _scenePlan == null
                  ? const Center(child: Text('生成：1 张背景 + 少量关键静态资产'))
                  : _ScenePlanCanvas(
                      scenePlan: _scenePlan!,
                      onEntityTap: _handleEntityTap,
                      onBackgroundTap: _showBackgroundSheet,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenePlanCanvas extends StatefulWidget {
  const _ScenePlanCanvas({
    required this.scenePlan,
    required this.onEntityTap,
    required this.onBackgroundTap,
  });

  final JsonMap scenePlan;
  final ValueChanged<JsonMap> onEntityTap;
  final ValueChanged<JsonMap> onBackgroundTap;

  @override
  State<_ScenePlanCanvas> createState() => _ScenePlanCanvasState();
}

class _ScenePlanCanvasState extends State<_ScenePlanCanvas> {
  Offset _player = Offset.zero;
  List<math.Point<int>> _previewPath = const <math.Point<int>>[];
  String _moveHint = '点击地面移动 · 长按资产查看';

  @override
  void initState() {
    super.initState();
    _resetPlayer();
  }

  @override
  void didUpdateWidget(covariant _ScenePlanCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sceneString(oldWidget.scenePlan['scene_id']) !=
        _sceneString(widget.scenePlan['scene_id'])) {
      _resetPlayer();
    }
  }

  void _resetPlayer() {
    final grid = _sceneMap(widget.scenePlan['grid']);
    final gridWidth = _sceneInt(grid['width'], 48).clamp(1, 200).toInt();
    final gridHeight = _sceneInt(grid['height'], 48).clamp(1, 200).toInt();
    final entrances = _sceneList(widget.scenePlan['entrances'])
        .map(_sceneMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    var spawn = entrances.isEmpty
        ? Offset(1, gridHeight / 2)
        : Offset(
            _sceneNum(entrances.first['x']),
            _sceneNum(entrances.first['y']),
          );
    spawn = _nudgeInside(spawn, gridWidth, gridHeight);
    spawn = _nearestWalkable(spawn, gridWidth, gridHeight);
    _player = spawn;
    _previewPath = const <math.Point<int>>[];
    _moveHint = '入口出生 · 点击地面移动 · 长按资产查看';
  }

  Offset _nudgeInside(Offset point, int width, int height) {
    var x = point.dx;
    var y = point.dy;
    if (x <= .5) x = 1.5;
    if (x >= width - .5) x = width - 1.5;
    if (y <= .5) y = 1.5;
    if (y >= height - .5) y = height - 1.5;
    return Offset(
      x.clamp(.5, width - .5).toDouble(),
      y.clamp(.5, height - .5).toDouble(),
    );
  }

  Offset _nearestWalkable(Offset point, int width, int height) {
    final baseX = point.dx.floor().clamp(0, width - 1).toInt();
    final baseY = point.dy.floor().clamp(0, height - 1).toInt();
    for (var radius = 0; radius <= 8; radius++) {
      for (var y = baseY - radius; y <= baseY + radius; y++) {
        for (var x = baseX - radius; x <= baseX + radius; x++) {
          if (x < 0 || y < 0 || x >= width || y >= height) continue;
          final p = Offset(x + .5, y + .5);
          if (_isWalkable(p)) return p;
        }
      }
    }
    return Offset(baseX + .5, baseY + .5);
  }

  List<JsonMap> get _objects => _sceneList(widget.scenePlan['scene_objects'])
      .map(_sceneMap)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  bool _contains(JsonMap object, Offset point) {
    final x = _sceneNum(object['x']);
    final y = _sceneNum(object['y']);
    final width = math.max(1.0, _sceneNum(object['width'], 1));
    final height = math.max(1.0, _sceneNum(object['height'], 1));
    return point.dx >= x &&
        point.dx < x + width &&
        point.dy >= y &&
        point.dy < y + height;
  }

  bool _isWalkable(Offset point) {
    final covering = _objects.where((item) => _contains(item, point)).toList();
    // walkable overlay 优先：桥/擂台可以覆盖河流等 blocked 区域。
    if (covering.any((item) => _sceneString(item['movement']) == 'walkable')) {
      return true;
    }
    return !covering.any((item) {
      final movement = _sceneString(item['movement']);
      return movement == 'blocked' || movement == 'conditional';
    });
  }

  List<math.Point<int>> _findPath(
    math.Point<int> start,
    math.Point<int> goal,
    int width,
    int height,
  ) {
    bool valid(math.Point<int> p) =>
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height;
    bool walkable(math.Point<int> p) =>
        _isWalkable(Offset(p.x + .5, p.y + .5));

    if (!valid(goal) || !walkable(goal)) return const <math.Point<int>>[];
    final queue = <math.Point<int>>[start];
    var head = 0;
    final cameFrom = <math.Point<int>, math.Point<int>?>{start: null};
    const directions = <math.Point<int>>[
      math.Point<int>(1, 0),
      math.Point<int>(-1, 0),
      math.Point<int>(0, 1),
      math.Point<int>(0, -1),
    ];

    while (head < queue.length) {
      final current = queue[head++];
      if (current == goal) break;
      for (final d in directions) {
        final next = math.Point<int>(current.x + d.x, current.y + d.y);
        if (!valid(next) || !walkable(next) || cameFrom.containsKey(next)) continue;
        cameFrom[next] = current;
        queue.add(next);
      }
    }

    if (!cameFrom.containsKey(goal)) return const <math.Point<int>>[];
    final path = <math.Point<int>>[];
    math.Point<int>? cursor = goal;
    while (cursor != null) {
      path.add(cursor);
      cursor = cameFrom[cursor];
    }
    return path.reversed.toList(growable: false);
  }

  void _handleGroundTap(Offset localPosition, _IsoMetrics metrics) {
    final grid = _sceneMap(widget.scenePlan['grid']);
    final width = _sceneInt(grid['width'], 48).clamp(1, 200);
    final height = _sceneInt(grid['height'], 48).clamp(1, 200);
    final logical = metrics.unproject(localPosition);
    if (logical.dx < 0 ||
        logical.dy < 0 ||
        logical.dx >= width ||
        logical.dy >= height) {
      return;
    }

    final goal = math.Point<int>(logical.dx.floor(), logical.dy.floor());
    final start = math.Point<int>(
      _player.dx.floor().clamp(0, width - 1).toInt(),
      _player.dy.floor().clamp(0, height - 1).toInt(),
    );
    final path = _findPath(start, goal, width, height);
    if (path.isEmpty) {
      setState(() {
        _previewPath = const <math.Point<int>>[];
        _moveHint = '目标不可到达（被静态资产 footprint 阻挡）';
      });
      return;
    }

    setState(() {
      _previewPath = path;
      _player = Offset(goal.x + .5, goal.y + .5);
      _moveHint = '寻路 ${math.max(0, path.length - 1)} 格 · 长按资产查看';
    });
  }

  void _handleLongPress(Offset localPosition, _IsoMetrics metrics) {
    final logical = metrics.unproject(localPosition);
    final object = _hitSceneObject(_objects, logical);
    if (object != null) {
      widget.onEntityTap(<String, dynamic>{...object, 'kind': 'scene_object'});
      return;
    }

    final characters = _sceneList(widget.scenePlan['characters'])
        .map(_sceneMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final character = _hitPointEntity(characters, logical, radius: 1.2);
    if (character != null) {
      widget.onEntityTap(<String, dynamic>{...character, 'kind': 'character'});
      return;
    }

    widget.onBackgroundTap(_sceneMap(widget.scenePlan['background']));
  }

  @override
  Widget build(BuildContext context) {
    final grid = _sceneMap(widget.scenePlan['grid']);
    final gridWidth = _sceneInt(grid['width'], 48).clamp(1, 200).toInt();
    final gridHeight = _sceneInt(grid['height'], 48).clamp(1, 200).toInt();
    final objects = _objects;
    final characters = _sceneList(widget.scenePlan['characters'])
        .map(_sceneMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final entrances = _sceneList(widget.scenePlan['entrances'])
        .map(_sceneMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final metrics = _IsoMetrics.forGrid(gridWidth, gridHeight);
    final background = _sceneMap(widget.scenePlan['background']);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_sceneString(widget.scenePlan['name'], '场景')} · '
                  '$gridWidth×$gridHeight · 关键资产 ${objects.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onBackgroundTap(background),
                icon: const Icon(Icons.landscape_outlined, size: 18),
                label: const Text('背景'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _moveHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: InteractiveViewer(
              minScale: .25,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(500),
              constrained: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _handleGroundTap(details.localPosition, metrics),
                onLongPressStart: (details) =>
                    _handleLongPress(details.localPosition, metrics),
                child: SizedBox(
                  width: metrics.canvasSize.width,
                  height: metrics.canvasSize.height,
                  child: CustomPaint(
                    painter: _ScenePlanPainter(
                      scenePlan: widget.scenePlan,
                      objects: objects,
                      characters: characters,
                      entrances: entrances,
                      player: _player,
                      previewPath: _previewPath,
                      metrics: metrics,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IsoMetrics {
  const _IsoMetrics({
    required this.tileWidth,
    required this.tileHeight,
    required this.origin,
    required this.canvasSize,
  });

  final double tileWidth;
  final double tileHeight;
  final Offset origin;
  final Size canvasSize;

  factory _IsoMetrics.forGrid(int gridWidth, int gridHeight) {
    const tileWidth = 34.0;
    const tileHeight = 17.0;
    const sideMargin = 120.0;
    const topMargin = 170.0;
    const bottomMargin = 110.0;
    final groundWidth = (gridWidth + gridHeight) * tileWidth / 2;
    final groundHeight = (gridWidth + gridHeight) * tileHeight / 2;
    return _IsoMetrics(
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      origin: Offset(sideMargin + gridHeight * tileWidth / 2, topMargin),
      canvasSize: Size(
        groundWidth + sideMargin * 2,
        groundHeight + topMargin + bottomMargin,
      ),
    );
  }

  Offset project(double x, double y, [double z = 0]) {
    return Offset(
      origin.dx + (x - y) * tileWidth / 2,
      origin.dy + (x + y) * tileHeight / 2 - z * tileHeight,
    );
  }

  Offset unproject(Offset point) {
    final dx = (point.dx - origin.dx) / (tileWidth / 2);
    final dy = (point.dy - origin.dy) / (tileHeight / 2);
    return Offset((dx + dy) / 2, (dy - dx) / 2);
  }
}

class _ScenePlanPainter extends CustomPainter {
  _ScenePlanPainter({
    required this.scenePlan,
    required this.objects,
    required this.characters,
    required this.entrances,
    required this.player,
    required this.previewPath,
    required this.metrics,
  });

  final JsonMap scenePlan;
  final List<JsonMap> objects;
  final List<JsonMap> characters;
  final List<JsonMap> entrances;
  final Offset player;
  final List<math.Point<int>> previewPath;
  final _IsoMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEE9DD));
    _drawGround(canvas);
    _drawPath(canvas);
    _drawObjects(canvas);
    _drawEntrances(canvas);
    _drawCharacters(canvas);
    _drawPlayer(canvas);
  }

  void _drawGround(Canvas canvas) {
    final grid = _sceneMap(scenePlan['grid']);
    final width = _sceneInt(grid['width'], 48);
    final height = _sceneInt(grid['height'], 48);
    final ground = Path()
      ..moveTo(metrics.project(0, 0).dx, metrics.project(0, 0).dy)
      ..lineTo(metrics.project(width.toDouble(), 0).dx, metrics.project(width.toDouble(), 0).dy)
      ..lineTo(metrics.project(width.toDouble(), height.toDouble()).dx,
          metrics.project(width.toDouble(), height.toDouble()).dy)
      ..lineTo(metrics.project(0, height.toDouble()).dx, metrics.project(0, height.toDouble()).dy)
      ..close();
    canvas.drawPath(ground, Paint()..color = const Color(0xFFD8D0B9));
    canvas.drawPath(
      ground,
      Paint()
        ..color = const Color(0xFF8D846E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final gridPaint = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = .7;
    for (var x = 0; x <= width; x++) {
      canvas.drawLine(
        metrics.project(x.toDouble(), 0),
        metrics.project(x.toDouble(), height.toDouble()),
        gridPaint,
      );
    }
    for (var y = 0; y <= height; y++) {
      canvas.drawLine(
        metrics.project(0, y.toDouble()),
        metrics.project(width.toDouble(), y.toDouble()),
        gridPaint,
      );
    }

    final background = _sceneMap(scenePlan['background']);
    _label(
      canvas,
      _sceneString(background['name'], '整张背景地形'),
      metrics.project(width / 2, height / 2),
      13,
    );
  }

  void _drawPath(Canvas canvas) {
    if (previewPath.length < 2) return;
    final path = Path();
    for (var i = 0; i < previewPath.length; i++) {
      final p = previewPath[i];
      final screen = metrics.project(p.x + .5, p.y + .5, .03);
      if (i == 0) {
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xAA1565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawObjects(Canvas canvas) {
    final sorted = [...objects]
      ..sort((a, b) {
        final ad = _sceneNum(a['x']) + _sceneNum(a['y']) +
            _sceneNum(a['width']) + _sceneNum(a['height']);
        final bd = _sceneNum(b['x']) + _sceneNum(b['y']) +
            _sceneNum(b['width']) + _sceneNum(b['height']);
        return ad.compareTo(bd);
      });

    for (final object in sorted) {
      final x = _sceneNum(object['x']);
      final y = _sceneNum(object['y']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final height = math.max(1.0, _sceneNum(object['height'], 1));
      final renderMode = _sceneString(object['render_mode'], 'sprite');
      final movement = _sceneString(object['movement'], 'blocked');
      final visualHeight = renderMode == 'flat_overlay'
          ? 0.0
          : math.max(.4, _sceneNum(object['visual_height'], 2));

      final p00 = metrics.project(x, y);
      final p10 = metrics.project(x + width, y);
      final p11 = metrics.project(x + width, y + height);
      final p01 = metrics.project(x, y + height);
      final footprint = Path()
        ..moveTo(p00.dx, p00.dy)
        ..lineTo(p10.dx, p10.dy)
        ..lineTo(p11.dx, p11.dy)
        ..lineTo(p01.dx, p01.dy)
        ..close();

      if (renderMode == 'flat_overlay') {
        canvas.drawPath(
          footprint,
          Paint()..color = _flatColor(movement),
        );
        canvas.drawPath(
          footprint,
          Paint()
            ..color = const Color(0xAA37474F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        _label(
          canvas,
          _sceneString(object['name'], '关键资产'),
          metrics.project(x + width / 2, y + height / 2, .08),
          10,
        );
        continue;
      }

      final t00 = metrics.project(x, y, visualHeight);
      final t10 = metrics.project(x + width, y, visualHeight);
      final t11 = metrics.project(x + width, y + height, visualHeight);
      final t01 = metrics.project(x, y + height, visualHeight);

      final rightFace = Path()
        ..moveTo(p10.dx, p10.dy)
        ..lineTo(p11.dx, p11.dy)
        ..lineTo(t11.dx, t11.dy)
        ..lineTo(t10.dx, t10.dy)
        ..close();
      final leftFace = Path()
        ..moveTo(p11.dx, p11.dy)
        ..lineTo(p01.dx, p01.dy)
        ..lineTo(t01.dx, t01.dy)
        ..lineTo(t11.dx, t11.dy)
        ..close();
      final topFace = Path()
        ..moveTo(t00.dx, t00.dy)
        ..lineTo(t10.dx, t10.dy)
        ..lineTo(t11.dx, t11.dy)
        ..lineTo(t01.dx, t01.dy)
        ..close();

      canvas.drawPath(footprint, Paint()..color = const Color(0x22000000));
      canvas.drawPath(rightFace, Paint()..color = const Color(0xFF96704F));
      canvas.drawPath(leftFace, Paint()..color = const Color(0xFFB68A62));
      canvas.drawPath(topFace, Paint()..color = _topColor(movement));
      canvas.drawPath(
        topFace,
        Paint()
          ..color = const Color(0xAA4E342E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      _label(
        canvas,
        _sceneString(object['name'], '关键资产'),
        metrics.project(x + width / 2, y + height / 2, visualHeight + .08),
        10,
      );
    }
  }

  Color _topColor(String movement) {
    switch (movement) {
      case 'walkable':
        return const Color(0xFFD9B36C);
      case 'conditional':
        return const Color(0xFFB8A7D9);
      default:
        return const Color(0xFFC98D55);
    }
  }

  Color _flatColor(String movement) {
    switch (movement) {
      case 'walkable':
        return const Color(0x99D7C47C);
      case 'conditional':
        return const Color(0x998E78B7);
      default:
        return const Color(0x9973A7C2);
    }
  }

  void _drawEntrances(Canvas canvas) {
    for (final entrance in entrances) {
      final p = metrics.project(
        _sceneNum(entrance['x']),
        _sceneNum(entrance['y']),
        .15,
      );
      canvas.drawCircle(p, 7, Paint()..color = const Color(0xFF1565C0));
      _label(canvas, _sceneString(entrance['name'], '入口'), p + const Offset(0, -17), 9);
    }
  }

  void _drawCharacters(Canvas canvas) {
    for (final character in characters) {
      final p = metrics.project(
        _sceneNum(character['x']),
        _sceneNum(character['y']),
        .15,
      );
      canvas.drawCircle(p, 7, Paint()..color = const Color(0xFFC62828));
      canvas.drawLine(
        p + const Offset(0, -2),
        p + const Offset(0, -18),
        Paint()
          ..color = const Color(0xFF7F0000)
          ..strokeWidth = 3,
      );
      _label(canvas, _sceneString(character['name'], 'NPC'), p + const Offset(0, -28), 9);
    }
  }

  void _drawPlayer(Canvas canvas) {
    final p = metrics.project(player.dx, player.dy, .18);
    canvas.drawCircle(p, 8, Paint()..color = const Color(0xFF0D47A1));
    canvas.drawCircle(
      p,
      11,
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _label(canvas, '主角', p + const Offset(0, -22), 10);
  }

  void _label(Canvas canvas, String text, Offset center, double fontSize) {
    if (text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF1F1F1F),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          backgroundColor: const Color(0xDDFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 170);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePlanPainter oldDelegate) => true;
}

JsonMap? _hitSceneObject(List<JsonMap> objects, Offset logical) {
  final sorted = [...objects]
    ..sort((a, b) {
      final ad = _sceneNum(a['x']) + _sceneNum(a['y']);
      final bd = _sceneNum(b['x']) + _sceneNum(b['y']);
      return bd.compareTo(ad);
    });
  for (final object in sorted) {
    final x = _sceneNum(object['x']);
    final y = _sceneNum(object['y']);
    final width = math.max(1.0, _sceneNum(object['width'], 1));
    final height = math.max(1.0, _sceneNum(object['height'], 1));
    if (logical.dx >= x &&
        logical.dx < x + width &&
        logical.dy >= y &&
        logical.dy < y + height) {
      return object;
    }
  }
  return null;
}

JsonMap? _hitPointEntity(
  List<JsonMap> entities,
  Offset logical, {
  double radius = 1,
}) {
  JsonMap? best;
  var bestDistance = double.infinity;
  for (final entity in entities) {
    final dx = logical.dx - _sceneNum(entity['x']);
    final dy = logical.dy - _sceneNum(entity['y']);
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= radius && distance < bestDistance) {
      best = entity;
      bestDistance = distance;
    }
  }
  return best;
}

JsonMap _sceneMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<dynamic> _sceneList(dynamic value) =>
    value is List ? value : const <dynamic>[];

double _sceneNum(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _sceneInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _sceneString(dynamic value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

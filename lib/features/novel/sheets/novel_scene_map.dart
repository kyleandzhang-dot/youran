part of '../novel_sheets.dart';

// ============================================================================
// 有机拼接板块世界地图
// 正式入口：showNovelSceneMapSheet(...)
// 开发者入口：showNovelSceneMapDeveloperPreview(...)
// Tab入口：NovelWorldMapTab(...)
// ============================================================================

const List<_WorldMapPreviewScene> _developerWorldMapScenes =
    <_WorldMapPreviewScene>[
  _WorldMapPreviewScene(
    id: 'preview-yunlan',
    name: '云岚宗',
    imageUrl: 'assets/images/world_map/yunlan_sect_tile.webp',
  ),
  _WorldMapPreviewScene(
    id: 'preview-school',
    name: '日本校园',
    imageUrl: 'assets/images/world_map/japanese_school_tile.webp',
  ),
  _WorldMapPreviewScene(
    id: 'preview-island',
    name: '海滩海岸',
    imageUrl: 'assets/images/world_map/island_beach_tile.webp',
  ),
  _WorldMapPreviewScene(
    id: 'preview-castle',
    name: '剑与魔法城堡',
    imageUrl: 'assets/images/world_map/fantasy_castle_tile.webp',
  ),
];

class NovelWorldMapTab extends StatelessWidget {
  const NovelWorldMapTab({
    super.key,
    required this.controller,
    this.onMoveStarted,
  });
  
  final NovelGameController controller;
  final VoidCallback? onMoveStarted;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(controller.refreshSceneMap(force: false));
    });
    return _NovelWorldMapPage(
      controller: controller,
      developerPreview: false,
      embedded: true, 
      onMoveStarted: onMoveStarted,
    );
  }
}

Future<void> showNovelSceneMapSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('world-region-map:${controller.sessionId}', () async {
    unawaited(controller.refreshSceneMap(force: true));
    await _pushWorldMapPage(
      context,
      controller: controller,
      developerPreview: false,
    );
  });
}

Future<void> showNovelSceneMapDeveloperPreview(
  BuildContext context,
  NovelGameController controller,
) async {
  await _pushWorldMapPage(
    context,
    controller: controller,
    developerPreview: true,
  );
}

Future<void> _pushWorldMapPage(
  BuildContext context, {
  required NovelGameController controller,
  required bool developerPreview,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withOpacity(.75), // 加深遮罩以凸显板块
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 210),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _NovelWorldMapPage(
        controller: controller,
        developerPreview: developerPreview,
        embedded: false,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class _WorldMapPreviewScene {
  const _WorldMapPreviewScene({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final String imageUrl;
}

class _WorldMapEntry {
  const _WorldMapEntry({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.unlocked,
    this.current = false,
    this.node,
  });

  final String id;
  final String name;
  final String imageUrl;
  final bool unlocked;
  final bool current;
  final NovelSceneMapNode? node;

  bool get showsImage => imageUrl.trim().isNotEmpty;
}

// ----------------------------------------------------------------------------
// 核心：空间分割 (Space Partitioning / Voronoi) 生成紧密咬合的地形碎片
// ----------------------------------------------------------------------------
class _WorldMapPlateGeometry {
  const _WorldMapPlateGeometry({
    required this.bounds,
    required this.points,
  });

  final Rect bounds;
  final List<Offset> points;
}

class _WorldMapOrganicLayout {
  const _WorldMapOrganicLayout({
    required this.size,
    required this.contentBounds,
    required this.plates,
  });

  final Size size;
  final Rect contentBounds;
  final List<_WorldMapPlateGeometry> plates;
}

/// 在正六边形晶格上，从原点开始"紧凑生长"，选出 [count] 个站位点，再做轻微抖动。
/// 每一步都选 "与已选点相邻 + 离当前质心最近" 的晶格点，所以无论 count 多大都是一团，
/// 不会拉成一条线；同一个 seed 下，count 增加时前面的点位置不变（新增区域只是"长出来"）。
List<Offset> _packedTerrainSites(
  int count,
  double tileWidth,
  double tileHeight,
  math.Random rng,
) {
  if (count <= 0) return const <Offset>[];

  final sx = tileWidth * .86; // 横向邻居间距
  final sy = tileHeight * .74; // 行间距
  final half = math.sqrt(3) / 2;

  // 正则六边形晶格（相邻点距离恒为 1）
  const radius = 8;
  final lattice = <Offset>[
    for (var r = -radius; r <= radius; r++)
      for (var q = -radius; q <= radius; q++) Offset(q + r / 2, r * half),
  ];

  final chosen = <Offset>[Offset.zero];
  while (chosen.length < count) {
    var cx = 0.0, cy = 0.0;
    for (final c in chosen) {
      cx += c.dx;
      cy += c.dy;
    }
    final centroid = Offset(cx / chosen.length, cy / chosen.length);

    Offset? best;
    var bestScore = double.infinity;
    for (final p in lattice) {
      if (chosen.any((c) => (c - p).distance < .01)) continue; // 已选
      if (!chosen.any((c) => (c - p).distance <= 1.05)) continue; // 必须相邻
      final score = (p - centroid).distance + rng.nextDouble() * .18;
      if (score < bestScore) {
        best = p;
        bestScore = score;
      }
    }
    if (best == null) break;
    chosen.add(best);
  }

  // 拉伸到真实尺寸 + 抖动（抖动幅度 ±15%，保证邻居距离不会小于 ~0.7 个间距）
  return <Offset>[
    for (final p in chosen)
      Offset(
        p.dx * sx + (rng.nextDouble() - .5) * sx * .30,
        p.dy * (sy / half) + (rng.nextDouble() - .5) * sy * .30,
      ),
  ];
}

/// Sutherland–Hodgman：只保留 (x - linePoint)·normal >= 0 的一侧。
List<Offset> _clipPolygonByHalfPlane(
  List<Offset> poly,
  Offset linePoint,
  Offset normal,
) {
  final result = <Offset>[];
  if (poly.isEmpty) return result;

  double side(Offset p) =>
      (p.dx - linePoint.dx) * normal.dx + (p.dy - linePoint.dy) * normal.dy;

  for (var i = 0; i < poly.length; i++) {
    final current = poly[i];
    final prev = poly[(i - 1 + poly.length) % poly.length];
    final dc = side(current);
    final dp = side(prev);
    final currentInside = dc >= 0;
    final prevInside = dp >= 0;

    if (currentInside != prevInside) {
      final t = dp / (dp - dc); // 一定不会除 0：两侧符号不同
      result.add(Offset.lerp(prev, current, t)!);
    }
    if (currentInside) result.add(current);
  }
  return result;
}

/// Chaikin 切角：让尖角变成圆润的"碎石角"。
List<Offset> _chaikin(
  List<Offset> poly, {
  int iterations = 2,
  double ratio = .25,
}) {
  var current = poly;
  for (var it = 0; it < iterations; it++) {
    final next = <Offset>[];
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = current[(i + 1) % current.length];
      next.add(Offset.lerp(a, b, ratio)!);
      next.add(Offset.lerp(a, b, 1 - ratio)!);
    }
    current = next;
  }
  return current;
}

/// 把过长的边切成 <= step 的小段（变形前必须加密，否则长直边只有两个端点会被扭，中间还是直的）。
List<Offset> _densify(List<Offset> poly, double step) {
  final out = <Offset>[];
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final n = math.max(1, ((b - a).distance / step).ceil());
    for (var k = 0; k < n; k++) {
      out.add(Offset.lerp(a, b, k / n)!);
    }
  }
  return out;
}

/// 位移场里的一道正弦波：沿 [axis] 方向传播，把点沿 [push] 方向推 amplitude * sin(...)。
class _WarpWave {
  const _WarpWave({
    required this.axis,
    required this.push,
    required this.frequency,
    required this.amplitude,
    required this.phase,
  });

  final Offset axis; // 传播方向（单位向量）
  final Offset push; // 位移方向（单位向量）
  final double frequency; // 2π / 波长
  final double amplitude;
  final double phase;
}

/// 位移场 D(p) = Σ 各波位移。每道波的 Lipschitz 常数 = amplitude * frequency，
/// 总和必须 < 1，p -> p + D(p) 才是双射（不会折叠、不会让两块板互相穿过去）。
/// 下面的参数总和约 0.70，留了足够余量。
List<_WarpWave> _buildWarpWaves(math.Random rng, double tileWidth) {
  // [波长(占 tileWidth 的比例), 振幅(占 tileWidth 的比例)]
  const specs = <List<double>>[
    <double>[.75, .030], // 大起伏：决定整体"歪不歪"
    <double>[.42, .013], // 中起伏：边缘的波浪感
    <double>[.26, .005], // 小起伏：细碎的岩石感
    <double>[.14, .003], // 微起伏：边界上的小锯齿
  ];
  final waves = <_WarpWave>[];
  var lipschitz = 0.0;
  for (final spec in specs) {
    final a = rng.nextDouble() * math.pi * 2;
    final b = rng.nextDouble() * math.pi * 2;
    final frequency = math.pi * 2 / (spec[0] * tileWidth);
    final amplitude = spec[1] * tileWidth;
    lipschitz += frequency * amplitude;
    waves.add(_WarpWave(
      axis: Offset(math.cos(a), math.sin(a)),
      push: Offset(math.cos(b), math.sin(b)),
      frequency: frequency,
      amplitude: amplitude,
      phase: rng.nextDouble() * math.pi * 2,
    ));
  }
  assert(lipschitz < .9, '位移场太强，板块可能重叠：$lipschitz');
  return waves;
}

Offset _warpPoint(Offset p, List<_WarpWave> waves) {
  var x = p.dx, y = p.dy;
  for (final w in waves) {
    final s = w.amplitude *
        math.sin(w.frequency * (w.axis.dx * p.dx + w.axis.dy * p.dy) + w.phase);
    x += w.push.dx * s;
    y += w.push.dy * s;
  }
  return Offset(x, y);
}

_WorldMapOrganicLayout _buildOrganicMapLayout({
  required int count,
  required int seed,
  required bool desktop,
}) {
  final tileWidth = desktop ? 340.0 : 238.0;
  final tileHeight = desktop ? 300.0 : 216.0;
  final padding = desktop ? 360.0 : 250.0;

  if (count <= 0) {
    return const _WorldMapOrganicLayout(
      size: Size.zero,
      contentBounds: Rect.zero,
      plates: <_WorldMapPlateGeometry>[],
    );
  }

  final rng = math.Random(seed);
  final sites = _packedTerrainSites(count, tileWidth, tileHeight, rng);
  final sx = tileWidth * .86;
  final sy = tileHeight * .74;
  final gap = tileWidth * .034; // 板块之间的缝宽（世界坐标）。想更宽/更窄改这里。
  // 加权 Voronoi（power diagram）：每块板有自己的"体量"，边界向体量小的一边偏移，
  // 板块大小就不再千篇一律。仍然是凸多边形分割，互不重叠。
  final weights = <double>[
    for (var i = 0; i < sites.length; i++)
      (math.Random(seed + i * 104729).nextDouble() * 2 - 1) *
          (sx * .36) *
          (sx * .36),
  ];
  final waves = _buildWarpWaves(math.Random(seed + 12345), tileWidth);

  // ---- 第一遍：算出每块板在"世界坐标"下的最终多边形 ----
  final worldPolys = <List<Offset>>[];
  for (var i = 0; i < sites.length; i++) {
    final site = sites[i];
    final r = math.Random(seed + i * 7919);
    // 1) 外圈轮廓（海岸线）：领地半径要 > 六边形单元外接圆（≈.58 个间距），
    //    否则板块填不满自己的单元，就会像"漂在水上的鹅卵石"。
    //    叠加从低频到高频 6 档谐波：既有大起伏，也有碎裂的小缺口。
    //    内部邻接处会被中垂线裁掉，所以这些起伏只体现在最外圈。
    const harmonics = <List<double>>[
      <double>[2, .07],
      <double>[3, .06],
      <double>[5, .05],
      <double>[7, .045],
      <double>[9, .035],
      <double>[13, .025],
    ];
    final phases = <double>[
      for (var h = 0; h < harmonics.length; h++) r.nextDouble() * math.pi * 2,
    ];
    const blobSteps = 64;
    final blob = <Offset>[
      for (var k = 0; k < blobSteps; k++)
        () {
          final t = math.pi * 2 * k / blobSteps;
          var f = 1.0;
          for (var h = 0; h < harmonics.length; h++) {
            f += harmonics[h][1] * math.sin(harmonics[h][0] * t + phases[h]);
          }
          return Offset(
            site.dx + math.cos(t) * sx * .92 * f,
            site.dy + math.sin(t) * sy * .92 * 1.08 * f,
          );
        }(),
    ];

    // 2) 与每个邻居的中垂线做半平面裁切；中垂线向自己这边平移 gap/2 → 缝宽恒定
    var cell = blob;
    for (var j = 0; j < sites.length; j++) {
      if (i == j) continue;
      final delta = site - sites[j];
      final dist = delta.distance;
      if (dist < 1e-6) continue;
      final normal = delta / dist; // 指向自己
      // 边界离邻居 e 处（无权重时 e = dist/2），再向自己这边让出 gap/2 作为缝
      final e = (dist * dist + weights[j] - weights[i]) / (2 * dist);
      final linePoint = sites[j] + normal * (e + gap / 2);
      cell = _clipPolygonByHalfPlane(cell, linePoint, normal);
      if (cell.isEmpty) break;
    }
    if (cell.length < 3) cell = blob; // 兜底：保证 plates 与 entries 下标一一对应

    // 3) 轻微切角（保留棱角，别磨成圆的）→ 加密 → 全局位移场扭曲
    cell = _chaikin(cell, iterations: 1, ratio: .07);
    cell = _densify(cell, tileWidth * .05);
    cell = <Offset>[for (final p in cell) _warpPoint(p, waves)];
    worldPolys.add(cell);
  }

  // ---- 第二遍：统一平移到正坐标（旧代码的 bug 就出在这里，必须用"最终"的全局包围盒）----
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final poly in worldPolys) {
    for (final p in poly) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
  }
  final shift = Offset(padding - minX, padding - minY);

  final plates = <_WorldMapPlateGeometry>[];
  for (final poly in worldPolys) {
    var pMinX = double.infinity, pMinY = double.infinity;
    var pMaxX = double.negativeInfinity, pMaxY = double.negativeInfinity;
    for (final p in poly) {
      pMinX = math.min(pMinX, p.dx);
      pMinY = math.min(pMinY, p.dy);
      pMaxX = math.max(pMaxX, p.dx);
      pMaxY = math.max(pMaxY, p.dy);
    }
    final worldBounds = Rect.fromLTRB(pMinX, pMinY, pMaxX, pMaxY);
    plates.add(_WorldMapPlateGeometry(
      bounds: worldBounds.shift(shift), // 所有板块共用同一个 shift
      points: <Offset>[for (final p in poly) p - worldBounds.topLeft],
    ));
  }

  final totalWidth = maxX - minX;
  final totalHeight = maxY - minY;
  return _WorldMapOrganicLayout(
    size: Size(totalWidth + padding * 2, totalHeight + padding * 2),
    contentBounds: Rect.fromLTWH(padding, padding, totalWidth, totalHeight),
    plates: plates,
  );
}

/// 闭合折线 -> 平滑曲线：取每条边的中点做曲线端点，原顶点做二次贝塞尔控制点。
/// 因为顶点已经被加密过，所以不需要再做"圆角比例"了。
Path _buildOrganicPlatePath(List<Offset> points) {
  final path = Path();
  if (points.length < 3) return path;

  Offset mid(Offset a, Offset b) => Offset.lerp(a, b, .5)!;

  final start = mid(points.last, points.first);
  path.moveTo(start.dx, start.dy);
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    final m = mid(p, points[(i + 1) % points.length]);
    path.quadraticBezierTo(p.dx, p.dy, m.dx, m.dy);
  }
  path.close();
  return path;
}

class _OrganicPlateClipper extends CustomClipper<Path> {
  const _OrganicPlateClipper(this.points);

  final List<Offset> points;

  @override
  Path getClip(Size size) => _buildOrganicPlatePath(points);

  @override
  bool shouldReclip(covariant _OrganicPlateClipper oldClipper) =>
      oldClipper.points != points;
}

class _OrganicPlateBorderPainter extends CustomPainter {
  const _OrganicPlateBorderPainter({
    required this.points,
    required this.current,
  });

  final List<Offset> points;
  final bool current;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildOrganicPlatePath(points);
    canvas.drawShadow(
      path,
      Colors.black.withOpacity(.46),
      current ? 10.0 : 7.0,
      false,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF171B22),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = current ? 1.8 : 1.0
        ..strokeJoin = StrokeJoin.round
        ..color = current
            ? const Color(0xBFE9EDF4)
            : const Color(0x302D3542),
    );
  }

  @override
  bool shouldRepaint(covariant _OrganicPlateBorderPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.current != current;

  @override
  bool hitTest(Offset position) =>
      _buildOrganicPlatePath(points).contains(position);
}
// ----------------------------------------------------------------------------

class _NovelWorldMapPage extends StatefulWidget {
  const _NovelWorldMapPage({
    required this.controller,
    required this.developerPreview,
    this.embedded = false,
    this.onMoveStarted,
  });

  final NovelGameController controller;
  final bool developerPreview;
  final bool embedded;
  final VoidCallback? onMoveStarted;

  @override
  State<_NovelWorldMapPage> createState() => _NovelWorldMapPageState();
}

class _NovelWorldMapPageState extends State<_NovelWorldMapPage>
    with TickerProviderStateMixin {
  late final int _layoutSeed;
  bool _moving = false;

  late final TransformationController _transformController;
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  bool _isCameraInitialized = false;
  bool? _lastDesktopMode;
  TapDownDetails? _doubleTapDetails;

  NovelGameController get controller => widget.controller;

  _WorldMapOrganicLayout? _layoutCache;
  String _layoutKey = '';

  _WorldMapOrganicLayout _layoutFor(int count, bool desktop) {
    final key = '$count|$desktop|$_layoutSeed';
    if (key != _layoutKey || _layoutCache == null) {
      _layoutKey = key;
      _layoutCache = _buildOrganicMapLayout(
        count: count,
        seed: _layoutSeed,
        desktop: desktop,
      );
    }
    return _layoutCache!;
  }

  // 热重载时 State 不会重建，缓存里还是旧算法算出来的布局 → 改了算法却看不到效果。
  // 每次 reassemble（热重载）都清掉缓存，并让镜头重新居中。
  @override
  void reassemble() {
    super.reassemble();
    _layoutCache = null;
    _layoutKey = '';
    _isCameraInitialized = false;
  }

  @override
  void initState() {
    super.initState();
    _layoutSeed = widget.developerPreview
        ? DateTime.now().microsecondsSinceEpoch
        : controller.sessionId.hashCode;

    _transformController = TransformationController();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformController.value = _zoomAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _zoomAnimController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    final position = _doubleTapDetails!.localPosition;
    final currentMatrix = _transformController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    final isZoomedOut = currentScale < 1.2;
    final targetScale = isZoomedOut ? 1.8 : 0.85;
    final scaleFactor = targetScale / currentScale;

    final nextMatrix = Matrix4.identity()
      ..translate(position.dx, position.dy)
      ..scale(scaleFactor)
      ..translate(-position.dx, -position.dy)
      ..multiply(currentMatrix);

    _zoomAnimation = Matrix4Tween(
      begin: currentMatrix,
      end: nextMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOutQuint,
    ));
    _zoomAnimController.forward(from: 0);
  }

  List<_WorldMapEntry> _entries(NovelSceneMapData map) {
    if (widget.developerPreview) {
      return <_WorldMapEntry>[
        for (var index = 0;
            index < _developerWorldMapScenes.length;
            index++)
          _WorldMapEntry(
            id: _developerWorldMapScenes[index].id,
            name: _developerWorldMapScenes[index].name,
            imageUrl: _developerWorldMapScenes[index].imageUrl,
            unlocked: true,
            current: index == 0,
          ),
      ];
    }

    final rawCurrent = map.currentScene;
    final knownMajorScenes = map.majorScenes.isNotEmpty
        ? map.majorScenes
        : map.targets.where((node) => node.isMajorScene).toList(growable: false);
    final parentMajor = rawCurrent.parentSceneId.isEmpty
        ? null
        : knownMajorScenes
            .where((node) => node.sceneId == rawCurrent.parentSceneId)
            .firstOrNull;
    final current = rawCurrent.isMajorScene ? rawCurrent : (parentMajor ?? rawCurrent);
    final currentName = current.name.trim().isNotEmpty
        ? current.name.trim()
        : controller.locationTitle.trim();
    final currentImage = current.imageUrl.trim();
    
    return <_WorldMapEntry>[
      _WorldMapEntry(
        id: current.sceneId.trim().isEmpty
            ? 'current-scene'
            : current.sceneId.trim(),
        name: currentName.isEmpty ? '当前位置' : currentName,
        imageUrl: currentImage,
        unlocked: true,
        current: true,
        node: current,
      ),
      for (final node in knownMajorScenes.where(
        (node) => node.sceneId != current.sceneId && node.isMajorScene,
      ))
        _WorldMapEntry(
          id: node.sceneId,
          name: node.name,
          imageUrl: node.imageUrl,
          unlocked: !node.isLocked,
          node: node,
        ),
    ];
  }

  Future<void> _onEntryTap(_WorldMapEntry entry) async {
    if (!entry.unlocked || _moving) return;
    if (widget.developerPreview) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('地图测试 · ${entry.name}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1100),
          ),
        );
      return;
    }
    if (entry.current || entry.node == null) return;

    setState(() => _moving = true);
    final accepted = await controller.requestSceneMove(entry.node!);
    if (!mounted) return;
    if (accepted) {
      setState(() => _moving = false);
      widget.onMoveStarted?.call();
      if (!widget.embedded) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() => _moving = false);
    final message = controller.sceneMoveError.trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? '当前无法前往该场景' : message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        novelDisplayMode,
      ]),
      builder: (context, _) {
        final entries = _entries(controller.sceneMap);
        final loading = !widget.developerPreview && controller.isSceneMapLoading;

        return Scaffold(
          // 背景使用深空灰暗色调
          backgroundColor: const Color(0xFF1E2128),
          body: Material(
            color: const Color(0xFF1E2128),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 深蓝灰渐变比纯黑更接近参考图的“未知世界”氛围。
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -.18),
                        radius: 1.05,
                        colors: <Color>[
                          Color(0xFF303641),
                          Color(0xFF242A33),
                          Color(0xFF171B22),
                        ],
                        stops: <double>[0, .52, 1],
                      ),
                    ),
                  ),
                 
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = controller.desktopMode;
                        if (_lastDesktopMode != isDesktop) {
                          _lastDesktopMode = isDesktop;
                          _isCameraInitialized = false;
                        }
                        
                        final mapLayout = _layoutFor(entries.length, isDesktop);
                        final canvasWidth = mapLayout.size.width;
                        final canvasHeight = mapLayout.size.height;

                        if (!_isCameraInitialized) {
                          _isCameraInitialized = true;
                          final horizontalMargin = isDesktop ? 180.0 : 36.0;
                          final verticalMargin = isDesktop ? 160.0 : 130.0;
                          final widthScale =
                              (constraints.maxWidth - horizontalMargin) /
                                  mapLayout.contentBounds.width;
                          final heightScale =
                              (constraints.maxHeight - verticalMargin) /
                                  mapLayout.contentBounds.height;
                          final initialScale = math
                              .min(widthScale, heightScale)
                              .clamp(isDesktop ? .55 : .48,
                                  isDesktop ? 1.0 : .92)
                              .toDouble();
                          
                          final dx = (constraints.maxWidth - canvasWidth * initialScale) / 2;
                          final dy = (constraints.maxHeight - canvasHeight * initialScale) / 2;
                          _transformController.value = Matrix4.identity()
                            ..translate(dx, dy)
                            ..scale(initialScale);
                        }

                        // 随机散布背景星点和“未知领域”
                        final bgRandom = math.Random(_layoutSeed + 999);
                        final unknownAreas = List.generate(
                          (entries.length * 2).clamp(4, 12).toInt(),
                          (index) => Offset(
                            bgRandom.nextDouble() * canvasWidth,
                            bgRandom.nextDouble() * canvasHeight,
                          ),
                        );
                        final starPoints = List.generate(
                          (entries.length * 7).clamp(22, 54).toInt(),
                          (index) => Offset(
                            bgRandom.nextDouble() * canvasWidth,
                            bgRandom.nextDouble() * canvasHeight,
                          ),
                        );

                        return GestureDetector(
                          onDoubleTapDown: _handleDoubleTapDown,
                          onDoubleTap: _handleDoubleTap,
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            constrained: false, 
                            clipBehavior: Clip.none,
                            minScale: 0.3,
                            maxScale: 2.5,
                            boundaryMargin: EdgeInsets.symmetric(
                              horizontal: canvasWidth * 0.5,
                              vertical: canvasHeight * 0.5,
                            ),
                            child: SizedBox(
                              width: canvasWidth,
                              height: canvasHeight,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  for (var index = 0;
                                      index < starPoints.length;
                                      index++)
                                    Positioned(
                                      left: starPoints[index].dx,
                                      top: starPoints[index].dy,
                                      child: Container(
                                        width: index % 5 == 0 ? 4 : 2,
                                        height: index % 5 == 0 ? 4 : 2,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withOpacity(
                                            index % 5 == 0 ? .56 : .24,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 绘制零星的“未知领域”文字
                                  for (final pos in unknownAreas)
                                    Positioned(
                                      left: pos.dx,
                                      top: pos.dy,
                                      child: Text(
                                        '未知领域',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.12),
                                          fontSize: 14,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),

                                  // 统一分割得到的地块会共享边缘，只留一条自然暗缝。
                                  for (var index = 0;
                                      index < entries.length;
                                      index++)
                                    Positioned(
                                      left: mapLayout.plates[index].bounds.left,
                                      top: mapLayout.plates[index].bounds.top,
                                      width: mapLayout.plates[index].bounds.width,
                                      height: mapLayout.plates[index].bounds.height,
                                      child: _IrregularScenePlate(
                                        entry: entries[index],
                                        moving: _moving,
                                        points: mapLayout.plates[index].points,
                                        onTap: () => _onEntryTap(entries[index]),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _WorldMapPageHeader(
                      desktopMode: controller.desktopMode,
                      onClose: widget.embedded
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  
                  if (loading)
                    Positioned(
                      top: 16,
                      right: controller.desktopMode ? 74.0 : 32.0,
                      child: SafeArea(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
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

class _WorldMapPageHeader extends StatelessWidget {
  const _WorldMapPageHeader({
    required this.desktopMode,
    this.onClose,
  });

  final bool desktopMode;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final leftInset = desktopMode ? 46.0 : 10.0;
    final rightInset = desktopMode ? 54.0 : 12.0;
    final contentMaxWidth = desktopMode ? 1440.0 : 560.0;
    final topInset = desktopMode ? 14.0 : 4.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.only(left: leftInset, right: rightInset),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(top: topInset),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: <Widget>[
                    if (onClose != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(99),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: Color(0xFFB9C0D0),
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
  }
}

/// 文字块底边落在板块高度的这个比例处（0~1，越小越靠上）。嫌文字低/高就改这里。
const double _kPlateTextBottomFraction = .74;

class _PlateTextSlot {
  const _PlateTextSlot(this.left, this.width, this.bottom);

  final double left; // 文字块左边（相对板块外接矩形）
  final double width; // 文字块宽度
  final double bottom; // 文字块底边离外接矩形底边的距离
}

/// 水平线 y 与多边形相交的最左/最右 x（dx=最左，dy=最右）；不相交返回 null。
Offset? _horizontalSpanAt(List<Offset> pts, double y) {
  var lo = double.infinity, hi = double.negativeInfinity;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    if ((a.dy <= y && b.dy > y) || (b.dy <= y && a.dy > y)) {
      final x = a.dx + (y - a.dy) / (b.dy - a.dy) * (b.dx - a.dx);
      lo = math.min(lo, x);
      hi = math.max(hi, x);
    }
  }
  return lo.isFinite && hi.isFinite ? Offset(lo, hi) : null;
}

/// 在不规则板块内为文字找位置：沿文字块占用的高度取几条水平线，
/// 用它们的"公共宽度"作为文字宽度并居中，这样文字永远落在板块形状里，不会被边缘切掉。
/// points 是相对板块外接矩形左上角的坐标（最小值为 0）。
_PlateTextSlot _plateTextSlot(List<Offset> points) {
  var w = 0.0, h = 0.0;
  for (final p in points) {
    w = math.max(w, p.dx);
    h = math.max(h, p.dy);
  }
  if (points.length < 3 || w <= 0 || h <= 0) {
    return const _PlateTextSlot(20, 120, 24);
  }

  final bottomY = h * _kPlateTextBottomFraction;
  double? left, right;
  for (var s = 0; s <= 4; s++) {
    final span = _horizontalSpanAt(points, bottomY - s * 16.0); // 覆盖约 64px 高的文字块
    if (span == null) continue;
    left = left == null ? span.dx : math.max(left, span.dx);
    right = right == null ? span.dy : math.min(right, span.dy);
  }
  final l = left ?? 0.0;
  final r = right ?? w;
  final centerX = (l + r) / 2;
  final width = math.max(90.0, r - l - 24.0); // 左右各留 12px
  return _PlateTextSlot(
    (centerX - width / 2).clamp(0.0, math.max(0.0, w - width)).toDouble(),
    width,
    h - bottomY,
  );
}

class _IrregularScenePlate extends StatefulWidget {
  const _IrregularScenePlate({
    required this.entry,
    required this.moving,
    required this.points,
    required this.onTap,
  });

  final _WorldMapEntry entry;
  final bool moving;
  final List<Offset> points;
  final VoidCallback onTap;

  @override
  State<_IrregularScenePlate> createState() => _IrregularScenePlateState();
}

class _IrregularScenePlateState extends State<_IrregularScenePlate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false;

  List<Offset>? _slotPoints;
  _PlateTextSlot? _slot;

  _PlateTextSlot get _textSlot {
    if (_slot == null || !identical(_slotPoints, widget.points)) {
      _slotPoints = widget.points;
      _slot = _plateTextSlot(widget.points);
    }
    return _slot!;
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.entry.current) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _IrregularScenePlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.current && !oldWidget.entry.current) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.entry.current && oldWidget.entry.current) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final disabled = !entry.unlocked;

    return Semantics(
      button: true,
      label: entry.current ? '${entry.name}，当前位置' : entry.name,
      child: MouseRegion(
        cursor: widget.moving || disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTapDown: widget.moving || disabled
              ? null
              : (_) => setState(() => _isPressed = true),
          onTapUp: widget.moving || disabled
              ? null
              : (_) => setState(() => _isPressed = false),
          onTapCancel: widget.moving || disabled
              ? null
              : () => setState(() => _isPressed = false),
          onTap: widget.moving || disabled ? null : widget.onTap,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: disabled ? .35 : 1,
            child: AnimatedScale(
              duration: Duration(milliseconds: _isPressed ? 120 : 500),
              curve: _isPressed ? Curves.easeOutCubic : Curves.easeOutBack,
              scale: _isPressed || widget.moving ? 0.96 : 1.0,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: <Widget>[
                  // 不规则裁切的图片本体
                  Positioned.fill(
                    child: ClipPath(
                      clipper: _OrganicPlateClipper(widget.points),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          const ColoredBox(color: Color(0xFF23252A)),
                          _WorldSceneImage(source: entry.imageUrl),
                          
                          // 底部黑灰色渐变遮罩，以便文字清晰可见
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.transparent,
                                  Color(0x40000000),
                                  Color(0xCC000000),
                                  Color(0xF2000000),
                                ],
                                stops: <double>[0.3, 0.5, 0.75, 1.0],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 自然暗缝、轻投影和当前位置高亮。
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OrganicPlateBorderPainter(
                        points: widget.points,
                        current: entry.current,
                      ),
                    ),
                  ),

                  if (disabled)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment(0, -.3),
                          child: Icon(
                            Icons.lock,
                            size: 28,
                            color: Color(0x99FFFFFF),
                          ),
                        ),
                      ),
                    ),

                  // 悬浮在板块上的文字信息区
                  Positioned(
                    left: _textSlot.left,
                    width: _textSlot.width,
                    bottom: _textSlot.bottom,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.name.isEmpty ? '未知板块' : entry.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: entry.current
                                  ? const Color(0xFFFFFFFF)
                                  : const Color(0xFFE0E0E0),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.8),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          // 仅在当前位置时显示提示文字，非当前位置移除“探索 · 剧情 · 场景”
                          if (entry.current) ...[
                            const SizedBox(height: 6),
                            const Text(
                              '当前所在区域',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFF2F0E8),
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
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
  }
}

class _WorldSceneImage extends StatelessWidget {
  const _WorldSceneImage({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final clean = source.trim();
    final fallback = Container(
      color: Colors.transparent,
    );
    if (clean.isEmpty) return fallback;
    
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      // 在这里如果你的项目中有 CdnUtil 等工具，可以包裹一下 clean 变量转为低分辨率 webp URL
      return Image.network(
        clean,
        fit: BoxFit.cover,
        // 将 filterQuality 降为 medium，避免在缩放平移矩阵时消耗过多显存
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    
    return Image.asset(
      clean,
      fit: BoxFit.cover,
      // 本地资源同样下调采样质量
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
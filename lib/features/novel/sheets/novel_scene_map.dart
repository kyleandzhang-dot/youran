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
// 核心：独立地形碎片生成与紧密排布。
// 每块场景都有自己的凹口、尖角和半岛凸起，避免变成规则卡片或胶囊。
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

List<Offset> _packedTerrainSites(
  int count,
  double tileWidth,
  double tileHeight,
) {
  if (count <= 1) return const <Offset>[Offset.zero];
  if (count == 2) {
    return <Offset>[
      Offset(-tileWidth * .45, tileHeight * .10),
      Offset(tileWidth * .45, -tileHeight * .10),
    ];
  }
  if (count == 3) {
    return <Offset>[
      Offset(0, -tileHeight * .43),
      Offset(-tileWidth * .43, tileHeight * .38),
      Offset(tileWidth * .43, tileHeight * .38),
    ];
  }
  if (count == 4) {
    return <Offset>[
      Offset(-tileWidth * .40, -tileHeight * .39),
      Offset(tileWidth * .43, -tileHeight * .46),
      Offset(-tileWidth * .47, tileHeight * .43),
      Offset(tileWidth * .39, tileHeight * .41),
    ];
  }

  final columns = math.max(2, math.sqrt(count * 1.18).ceil());
  final rows = (count / columns).ceil();
  final sites = <Offset>[];
  for (var row = 0; row < rows; row++) {
    final rowCount = math.min(columns, count - sites.length);
    final stagger = row.isOdd ? tileWidth * .22 : -tileWidth * .05;
    for (var column = 0; column < rowCount; column++) {
      sites.add(Offset(
        (column - (rowCount - 1) / 2) * tileWidth * .86 + stagger,
        (row - (rows - 1) / 2) * tileHeight * .80,
      ));
    }
  }
  sites.sort((a, b) => a.distanceSquared.compareTo(b.distanceSquared));
  return sites;
}

List<Offset> _buildTerrainOutline({
  required Offset center,
  required double width,
  required double height,
  required int seed,
}) {
  final random = math.Random(seed);
  final pointCount = 15 + random.nextInt(4);
  final phase = -math.pi / 2 + (random.nextDouble() - .5) * .18;
  final notchA = random.nextInt(pointCount);
  var notchB = (notchA + pointCount ~/ 2 + random.nextInt(3) - 1) % pointCount;
  if (notchB < 0) notchB += pointCount;
  final peninsula = (notchA + 3 + random.nextInt(4)) % pointCount;
  final points = <Offset>[];

  for (var index = 0; index < pointCount; index++) {
    final angle = phase + index * math.pi * 2 / pointCount;
    var radius = .84 + random.nextDouble() * .19;
    if (index == notchA || index == notchB) radius *= .60;
    if (index == (notchA + 1) % pointCount ||
        index == (notchB + pointCount - 1) % pointCount) {
      radius *= .78;
    }
    if (index == peninsula) radius *= 1.10;

    // 不同频率的波动叠加，让轮廓更像海岸线而不是规则多边形。
    final coastWave = 1 +
        math.sin(angle * 3 + seed * .013) * .055 +
        math.cos(angle * 5 - seed * .007) * .035;
    points.add(center + Offset(
      math.cos(angle) * width * .5 * radius * coastWave,
      math.sin(angle) * height * .5 * radius * coastWave,
    ));
  }
  return points;
}

_WorldMapOrganicLayout _buildOrganicMapLayout({
  required int count,
  required int seed,
  required bool desktop,
}) {
  final tileWidth = desktop ? 340.0 : 238.0;
  final tileHeight = desktop ? 300.0 : 216.0;
  final padding = desktop ? 360.0 : 250.0;
  final sites = _packedTerrainSites(count, tileWidth, tileHeight);
  final rawCells = <List<Offset>>[];
  for (var index = 0; index < sites.length; index++) {
    final shapeRandom = math.Random(seed + index * 7919);
    rawCells.add(_buildTerrainOutline(
      center: sites[index],
      width: tileWidth * (.90 + shapeRandom.nextDouble() * .18),
      height: tileHeight * (.90 + shapeRandom.nextDouble() * .18),
      seed: seed + index * 3571,
    ));
  }

  var minX = rawCells.first.first.dx;
  var maxX = rawCells.first.first.dx;
  var minY = rawCells.first.first.dy;
  var maxY = rawCells.first.first.dy;
  for (final cell in rawCells) {
    for (final point in cell) {
      minX = math.min(minX, point.dx).toDouble();
      maxX = math.max(maxX, point.dx).toDouble();
      minY = math.min(minY, point.dy).toDouble();
      maxY = math.max(maxY, point.dy).toDouble();
    }
  }

  final plates = <_WorldMapPlateGeometry>[];
  for (final cell in rawCells) {
    var cellMinX = cell.first.dx;
    var cellMaxX = cell.first.dx;
    var cellMinY = cell.first.dy;
    var cellMaxY = cell.first.dy;
    for (final point in cell.skip(1)) {
      cellMinX = math.min(cellMinX, point.dx).toDouble();
      cellMaxX = math.max(cellMaxX, point.dx).toDouble();
      cellMinY = math.min(cellMinY, point.dy).toDouble();
      cellMaxY = math.max(cellMaxY, point.dy).toDouble();
    }
    final worldBounds = Rect.fromLTRB(cellMinX, cellMinY, cellMaxX, cellMaxY);
    final positionedBounds =
        worldBounds.shift(Offset(padding - minX, padding - minY));
    plates.add(_WorldMapPlateGeometry(
      bounds: positionedBounds,
      points: <Offset>[
        for (final point in cell) point - worldBounds.topLeft,
      ],
    ));
  }

  return _WorldMapOrganicLayout(
    size: Size(maxX - minX + padding * 2, maxY - minY + padding * 2),
    contentBounds: Rect.fromLTWH(
      padding,
      padding,
      maxX - minX,
      maxY - minY,
    ),
    plates: plates,
  );
}

Path _buildOrganicPlatePath(List<Offset> points) {
  final path = Path();
  if (points.length < 3) return path;
  const cornerRatio = .035;

  Offset toward(Offset from, Offset to) => Offset.lerp(from, to, cornerRatio)!;

  final first = toward(points.first, points[1]);
  path.moveTo(first.dx, first.dy);
  for (var index = 1; index <= points.length; index++) {
    final corner = points[index % points.length];
    final previous = points[(index - 1) % points.length];
    final next = points[(index + 1) % points.length];
    final beforeCorner = toward(corner, previous);
    final afterCorner = toward(corner, next);
    path.lineTo(beforeCorner.dx, beforeCorner.dy);
    path.quadraticBezierTo(
      corner.dx,
      corner.dy,
      afterCorner.dx,
      afterCorner.dy,
    );
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
                        
                        final mapLayout = _buildOrganicMapLayout(
                          count: entries.length,
                          seed: _layoutSeed,
                          desktop: isDesktop,
                        );
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
                                stops: <double>[0.3, 0.6, 0.85, 1.0],
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
                        child: Center(
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
                    left: 20,
                    right: 20,
                    bottom: 24,
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
                          const SizedBox(height: 6),
                          // 模拟参考图下方的标签文字
                          Text(
                            entry.current ? '当前所在区域' : '探索 · 剧情 · 场景',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: entry.current
                                  ? const Color(0xFFF2F0E8)
                                  : const Color(0xFF9E9E9E),
                              fontSize: 12,
                              letterSpacing: 1.0,
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
      return Image.network(
        clean,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return Image.asset(
      clean,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

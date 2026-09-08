part of '../novel_sheets.dart';

// ============================================================================
// 方形世界板块地图
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

// 供主页底部导航栏调用的内嵌 Tab 入口
class NovelWorldMapTab extends StatelessWidget {
  const NovelWorldMapTab({super.key, required this.controller});
  
  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(controller.refreshSceneMap(force: false));
    });
    return _NovelWorldMapPage(
      controller: controller,
      developerPreview: false,
      embedded: true, // 标记为内嵌模式
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
      barrierColor: Colors.black.withOpacity(.58),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 210),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _NovelWorldMapPage(
        controller: controller,
        developerPreview: developerPreview,
        embedded: false, // 弹窗模式
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
            scale: Tween<double>(begin: .985, end: 1).animate(curved),
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

  bool get showsImage => unlocked && imageUrl.trim().isNotEmpty;
}

class _NovelWorldMapPage extends StatefulWidget {
  const _NovelWorldMapPage({
    required this.controller,
    required this.developerPreview,
    this.embedded = false,
  });

  final NovelGameController controller;
  final bool developerPreview;
  final bool embedded;

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
    final targetScale = isZoomedOut ? 2.0 : 0.85;
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

    final current = map.currentScene;
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
      for (final node in map.targets)
        _WorldMapEntry(
          id: node.sceneId,
          name: node.name,
          imageUrl: node.imageUrl,
          unlocked: node.isUnlocked && node.imageUrl.trim().isNotEmpty,
          node: node,
        ),
    ];
  }

  List<int> _slotOrder(int count) {
    const slotCount = 20;
    final slots = List<int>.generate(slotCount, (index) => index)
      ..shuffle(math.Random(_layoutSeed));
    if (count > 0) {
      slots.remove(12);
      slots.insert(0, 12);
    }
    return slots
        .take(count.clamp(0, slotCount).toInt())
        .toList(growable: false);
  }

  Future<void> _onEntryTap(_WorldMapEntry entry) async {
    if (!entry.showsImage || _moving) return;
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
    if (entry.current || entry.node == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('你当前就在这里'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1000),
          ),
        );
      return;
    }

    setState(() => _moving = true);
    final accepted = await controller.requestSceneMove(entry.node!);
    if (!mounted) return;
    if (accepted) {
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
          // 适配深邃蓝主题底色
          backgroundColor: const Color(0xFF070B15),
          body: Material(
            color: const Color(0xFF070B15),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 深蓝渐变背光
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -.08),
                        radius: 1.1,
                        colors: <Color>[
                          Color(0xFF111A2C), // 对应背包页 Soft Ink
                          Color(0xFF0B111F),
                          Color(0xFF070B15), // 对应背包页 Base Ink
                        ],
                        stops: <double>[0, .58, 1],
                      ),
                    ),
                  ),
                 
                  Positioned(
                    left: controller.desktopMode ? 46.0 : 10.0,
                    right: controller.desktopMode ? 54.0 : 12.0,
                    top: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 地图模式只认共享 desktopMode，不再根据窗口宽度自动切换。
                        final isDesktop = controller.desktopMode;
                        final compact = !isDesktop;

                        // 玩家切换手机 / 电脑模式时，重新按新尺寸居中一次地图。
                        if (_lastDesktopMode != isDesktop) {
                          _lastDesktopMode = isDesktop;
                          _isCameraInitialized = false;
                        }
                        const columns = 5;
                        const rows = 4;
                        const slotCount = columns * rows;
                        
                        // 电脑端使用更大的瓦片尺寸，手机端保持紧凑
                        final tileWidth = isDesktop ? 260.0 : 176.0;
                        final tileHeight = tileWidth * .58;
                        final seam = compact ? 3.0 : 4.0;
                        final stepX = (tileWidth + seam) * .5;
                        final stepY = (tileHeight + seam) * .5;
                        
                        // 电脑端增加拖拽留白区域
                        final canvasPadding = isDesktop ? 180.0 : 60.0;
                        final slots = _slotOrder(entries.length);

                        const centerSlot = 12;
                        final cx = centerSlot % columns;
                        final cy = centerSlot ~/ columns;

                        double rawLeft(int slot) {
                          final x = slot % columns;
                          final y = slot ~/ columns;
                          return (x - y) * stepX;
                        }

                        double rawTop(int slot) {
                          final x = slot % columns;
                          final y = slot ~/ columns;
                          return (x + y) * stepY;
                        }

                        final allSlots = List<int>.generate(slotCount, (index) => index);
                        final minLeft = allSlots.map(rawLeft).reduce((a, b) => math.min(a, b));
                        final maxLeft = allSlots.map(rawLeft).reduce((a, b) => math.max(a, b));
                        final minTop = allSlots.map(rawTop).reduce((a, b) => math.min(a, b));
                        final maxTop = allSlots.map(rawTop).reduce((a, b) => math.max(a, b));
                        
                        final canvasWidth = maxLeft - minLeft + tileWidth + canvasPadding * 2;
                        final canvasHeight = maxTop - minTop + tileHeight + canvasPadding * 2;

                        if (!_isCameraInitialized) {
                          _isCameraInitialized = true;
                          double initialScale;
                          final sceneCount = entries.length;
                          
                          // 电脑端本身屏幕较大，不需要过分放大
                          if (isDesktop) {
                            initialScale = sceneCount <= 4 ? 1.15 : 0.85;
                          } else {
                            if (sceneCount <= 1) {
                              initialScale = 1.35;
                            } else if (sceneCount <= 3) {
                              initialScale = 1.1;
                            } else if (sceneCount <= 6) {
                              initialScale = 0.9;
                            } else {
                              initialScale = 0.75;
                            }
                          }
                          
                          final dx = (constraints.maxWidth - canvasWidth * initialScale) / 2;
                          final dy = (constraints.maxHeight - canvasHeight * initialScale) / 2;
                          _transformController.value = Matrix4.identity()
                            ..translate(dx, dy)
                            ..scale(initialScale);
                        }

                        return GestureDetector(
                          onDoubleTapDown: _handleDoubleTapDown,
                          onDoubleTap: _handleDoubleTap,
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            constrained: false, 
                            clipBehavior: Clip.none,
                            minScale: 0.45,
                            maxScale: 2.8,
                            boundaryMargin: EdgeInsets.symmetric(
                              horizontal: canvasWidth * 0.4,
                              vertical: canvasHeight * 0.4,
                            ),
                            child: SizedBox(
                              width: canvasWidth,
                              height: canvasHeight,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  for (final slot in allSlots) ...[
                                    Builder(builder: (context) {
                                      final x = slot % columns;
                                      final y = slot ~/ columns;
                                      final dist = (cx - x).abs() + (cy - y).abs();
                                      final fogOpacity = math.max(0.0, 1.0 - (dist * 0.15));
                                      
                                      if (fogOpacity <= 0) return const SizedBox();
                                      
                                      return Positioned(
                                        left: canvasPadding + rawLeft(slot) - minLeft,
                                        top: canvasPadding + rawTop(slot) - minTop,
                                        width: tileWidth,
                                        height: tileHeight,
                                        child: _WorldEmptyDiamondTile(
                                          opacity: fogOpacity,
                                        ),
                                      );
                                    }),
                                  ],
                                  for (var index = 0;
                                      index < entries.length &&
                                          index < slots.length;
                                      index++)
                                    Positioned(
                                      left: canvasPadding +
                                          rawLeft(slots[index]) -
                                          minLeft,
                                      top: canvasPadding +
                                          rawTop(slots[index]) -
                                          minTop,
                                      width: tileWidth,
                                      height: tileHeight,
                                      child: _WorldSceneTile(
                                        entry: entries[index],
                                        moving: _moving,
                                        onTap: () =>
                                            _onEntryTap(entries[index]),
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

                  // 标题和角色 / 背包使用同一套最大宽度、左右边距和字号；
                  // 地图画布本身仍保持全屏可拖动，不被标题容器限制。
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
                            // 替换为深邃蓝强调色
                            color: Color(0xFF506FEF),
                          ),
                        ),
                      ),
                    ),

                  SafeArea(
                    // 根据设备模式微调底部边距：电脑模式底栏若不同则保留适度边距，手机由于底栏占用固定提供 88px
                    minimum: EdgeInsets.fromLTRB(
                      controller.desktopMode ? 46.0 : 10.0,
                      10,
                      controller.desktopMode ? 54.0 : 12.0,
                      widget.embedded ? (controller.desktopMode ? 72 : 88) : 13,
                    ),
                    child: const Align(
                      alignment: Alignment.bottomCenter,
                      child: _WorldMapGestureHint(),
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
          padding: EdgeInsets.only(
            left: leftInset,
            right: rightInset,
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(top: topInset),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '地图',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFF2F0E8),
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

class _WorldMapGlassPanel extends StatelessWidget {
  const _WorldMapGlassPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? const Color(0xD9090E1A),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(.12),
              width: .75,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WorldSceneTile extends StatefulWidget {
  const _WorldSceneTile({
    required this.entry,
    required this.moving,
    required this.onTap,
  });

  final _WorldMapEntry entry;
  final bool moving;
  final VoidCallback onTap;

  @override
  State<_WorldSceneTile> createState() => _WorldSceneTileState();
}

class _WorldSceneTileState extends State<_WorldSceneTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.entry.current) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _WorldSceneTile oldWidget) {
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
    if (!entry.showsImage) return const _LockedWorldSceneTile();

    return Semantics(
      button: true,
      label: entry.current ? '${entry.name}，当前位置' : entry.name,
      child: MouseRegion(
        cursor: widget.moving
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: widget.moving ? null : (_) => setState(() => _isPressed = true),
          onTapUp: widget.moving ? null : (_) => setState(() => _isPressed = false),
          onTapCancel: widget.moving ? null : () => setState(() => _isPressed = false),
          onTap: widget.moving ? null : widget.onTap,
          child: AnimatedScale(
            duration: Duration(milliseconds: _isPressed ? 150 : 600),
            curve: _isPressed ? Curves.easeOutCubic : Curves.elasticOut,
            scale: _isPressed || widget.moving ? 0.88 : 1.0,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: <Widget>[
                if (entry.current)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _GlowDiamondPainter(
                            glowOpacity: 0.12 + 0.28 * _pulseController.value,
                          ),
                        );
                      },
                    ),
                  ),

                Positioned.fill(
                  child: ClipPath(
                    clipper: const _WorldDiamondClipper(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        const ColoredBox(color: Color(0x33000000)),
                        _WorldSceneImage(source: entry.imageUrl),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                // 适配深蓝基调的阴影遮罩
                                Color(0x26070B15),
                                Color(0x52070B15),
                                Color(0xD9070B15),
                              ],
                              stops: <double>[0, .60, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WorldDiamondBorderPainter(
                      current: entry.current,
                    ),
                  ),
                ),

                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Center(
                      child: _WorldMapGlassPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        // 边框蓝色
                        borderColor: entry.current
                            ? const Color(0x99506FEF)
                            : Colors.white.withOpacity(.10),
                        // 玻璃蓝底色
                        backgroundColor: entry.current
                            ? const Color(0xE6111A2C)
                            : const Color(0xD9090E1A),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (entry.current) ...<Widget>[
                              const Icon(
                                Icons.my_location_rounded,
                                size: 11,
                                // 当前位置图标使用点缀金
                                color: Color(0xFFC9B778),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                entry.name.isEmpty ? '未知地带' : entry.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  // 活跃文字偏亮白，普通文字用浅蓝灰
                                  color: entry.current
                                      ? const Color(0xFFF2F0E8)
                                      : const Color(0xFFB9C0D0),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
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
      alignment: Alignment.center,
      child: Icon(
        Icons.landscape_outlined,
        size: 23,
        color: Colors.white.withOpacity(.20),
      ),
    );
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

Path _worldDiamondPath(Size size) {
  return Path()
    ..moveTo(size.width * .5, 0)
    ..lineTo(size.width, size.height * .5)
    ..lineTo(size.width * .5, size.height)
    ..lineTo(0, size.height * .5)
    ..close();
}

class _WorldDiamondClipper extends CustomClipper<Path> {
  const _WorldDiamondClipper();

  @override
  Path getClip(Size size) => _worldDiamondPath(size);

  @override
  bool shouldReclip(covariant _WorldDiamondClipper oldClipper) => false;
}

class _GlowDiamondPainter extends CustomPainter {
  const _GlowDiamondPainter({required this.glowOpacity});

  final double glowOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _worldDiamondPath(size);
    canvas.drawPath(
      path,
      Paint()
        // 发光替换为主题蓝
        ..color = const Color(0xFF506FEF).withOpacity(glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  @override
  bool shouldRepaint(covariant _GlowDiamondPainter oldDelegate) =>
      oldDelegate.glowOpacity != glowOpacity;
}

class _WorldDiamondBorderPainter extends CustomPainter {
  const _WorldDiamondBorderPainter({required this.current});

  final bool current;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _worldDiamondPath(size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = current ? 1.7 : .9
        ..strokeJoin = StrokeJoin.round
        // 高亮边框替换为主题蓝
        ..color = current
            ? const Color(0xB8506FEF)
            : const Color(0x2EFFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _WorldDiamondBorderPainter oldDelegate) =>
      oldDelegate.current != current;
}

class _WorldEmptyDiamondTile extends StatelessWidget {
  const _WorldEmptyDiamondTile({required this.opacity});
  
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WorldEmptyDiamondPainter(opacity: opacity),
      child: const SizedBox.expand(),
    );
  }
}

class _WorldEmptyDiamondPainter extends CustomPainter {
  const _WorldEmptyDiamondPainter({required this.opacity});
  
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    
    final path = _worldDiamondPath(size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        // 迷雾空白块配合蓝色系微调偏向深邃蓝紫
        ..color = const Color(0xFF0F1524).withOpacity(0.62 * opacity),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withOpacity(0.075 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _WorldEmptyDiamondPainter oldDelegate) => 
      oldDelegate.opacity != opacity;
}

class _LockedWorldSceneTile extends StatelessWidget {
  const _LockedWorldSceneTile();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _WorldMapGestureHint extends StatelessWidget {
  const _WorldMapGestureHint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.pan_tool_alt_outlined,
              size: 12,
              color: Colors.white.withOpacity(.36),
            ),
            const SizedBox(width: 6),
            Text(
              '双指缩放 · 双击聚焦点',
              style: TextStyle(
                color: Colors.white.withOpacity(.36),
                fontSize: 9.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
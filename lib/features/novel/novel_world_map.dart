import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'novel_game_controller.dart';

const Color _mapPaper = Color(0xFFF4F5F2);
const Color _mapAccent = Color(0xFF6FD35F);
const Color _mapInk = Color(0xFF0F172A);

/// 打开原生大世界地图。
///
/// 当前后端只返回「当前位置 + 一跳相邻场景」，因此地图只绘制玩家已经知道的
/// 世界，不读取完整 scene_graph，也不会提前暴露隐藏地点。
Future<void> showNovelWorldMapPage(
  BuildContext context,
  NovelGameController controller, {
  String currentBackgroundUrl = '',
}) async {
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) =>
          NovelWorldMapPage(
        controller: controller,
        currentBackgroundUrl: currentBackgroundUrl,
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

class NovelWorldMapPage extends StatefulWidget {
  const NovelWorldMapPage({
    super.key,
    required this.controller,
    this.currentBackgroundUrl = '',
  });

  final NovelGameController controller;
  final String currentBackgroundUrl;

  @override
  State<NovelWorldMapPage> createState() => _NovelWorldMapPageState();
}

class _NovelWorldMapPageState extends State<NovelWorldMapPage> {
  static const Size _worldSize = Size(1480, 1020);

  final TransformationController _transform = TransformationController();
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ui.Image? _currentImage;
  Size _lastViewport = Size.zero;
  bool _didFitMap = false;

  NovelGameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(controller.refreshSceneMap(force: true));
    _loadCurrentImage(widget.currentBackgroundUrl);
  }

  @override
  void didUpdateWidget(covariant NovelWorldMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentBackgroundUrl != widget.currentBackgroundUrl) {
      _loadCurrentImage(widget.currentBackgroundUrl);
    }
  }

  void _loadCurrentImage(String raw) {
    _removeImageListener();
    _currentImage = null;
    final value = raw.trim();
    if (value.isEmpty) return;

    final ImageProvider provider =
        value.startsWith('http://') || value.startsWith('https://')
            ? NetworkImage(value)
            : AssetImage(value);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted) return;
        setState(() => _currentImage = info.image);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) return;
        setState(() => _currentImage = null);
      },
    );
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  void _fitMap(Size viewport) {
    if (viewport.isEmpty || (_didFitMap && viewport == _lastViewport)) return;
    _lastViewport = viewport;
    _didFitMap = true;
    final scale = math.min(
      viewport.width / _worldSize.width,
      viewport.height / _worldSize.height,
    );
    final fitted = (scale * .96).clamp(.1, 1.0).toDouble();
    final dx = (viewport.width - _worldSize.width * fitted) / 2;
    final dy = (viewport.height - _worldSize.height * fitted) / 2;
    _transform.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(fitted);
  }

  Future<void> _moveTo(NovelSceneMapNode target) async {
    if (!controller.canMoveToScene(target)) {
      final message = target.reason.trim().isNotEmpty
          ? target.reason.trim()
          : controller.sceneMoveDisabledReason;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? '当前无法前往该地点' : message),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final accepted = await controller.requestSceneMove(target);
    if (!mounted) return;
    if (accepted) {
      Navigator.of(context).pop();
      return;
    }
    final message = controller.sceneMoveError.trim();
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final snapshot = _NovelWorldMapSnapshot.fromController(controller);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Colors.black),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = constraints.biggest;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fitMap(viewport);
                    });
                    return InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      minScale: .12,
                      maxScale: 3.4,
                      boundaryMargin: const EdgeInsets.all(260),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: _worldSize,
                          painter: _NovelWorldMapPainter(
                            snapshot: snapshot,
                            currentImage: _currentImage,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const IgnorePointer(child: _WorldMapVignette()),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: <Widget>[
                    _WorldMapHeader(
                      title: snapshot.worldTitle,
                      loading: controller.isSceneMapLoading,
                      onClose: () => Navigator.of(context).pop(),
                      onRefresh: () =>
                          unawaited(controller.refreshSceneMap(force: true)),
                    ),
                    const Spacer(),
                    if (controller.sceneMapError.trim().isNotEmpty)
                      _WorldMapNotice(text: controller.sceneMapError.trim()),
                    if (snapshot.targets.isNotEmpty)
                      _WorldMapDestinations(
                        targets: snapshot.targets,
                        submitting: controller.isSceneMoveSubmitting,
                        canMove: controller.canRequestSceneMove,
                        onMove: _moveTo,
                      )
                    else
                      const _WorldMapNotice(
                        text: '继续探索剧情，新的道路会在迷雾中逐步显现',
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '拖动查看世界 · 双指缩放',
                      style: TextStyle(
                        color: _mapPaper.withOpacity(.34),
                        fontSize: 9.5,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NovelWorldMapSnapshot {
  const _NovelWorldMapSnapshot({
    required this.worldTitle,
    required this.regions,
    required this.localNodes,
    required this.targets,
  });

  final String worldTitle;
  final List<_NovelWorldMapRegion> regions;
  final List<NovelSceneMapNode> localNodes;
  final List<NovelSceneMapNode> targets;

  factory _NovelWorldMapSnapshot.fromController(
    NovelGameController controller,
  ) {
    final map = controller.sceneMap;
    final current = map.currentScene;
    final rawSubtitle = controller.locationSubtitle.trim();
    final timeLabel = controller.world.timeDescription.trim();
    final worldTitle = rawSubtitle.isNotEmpty && rawSubtitle != timeLabel
        ? rawSubtitle.split(' · ').first
        : (current.name.trim().isNotEmpty
            ? current.name.trim()
            : controller.locationTitle.trim());
    final currentRegionKey = current.regionId.trim().isNotEmpty
        ? current.regionId.trim()
        : 'current-world';

    final crossRegion = <String, NovelSceneMapNode>{};
    final localNodes = <NovelSceneMapNode>[];
    for (final target in map.targets) {
      final regionKey = target.regionId.trim();
      if (regionKey.isNotEmpty && regionKey != currentRegionKey) {
        crossRegion.putIfAbsent(regionKey, () => target);
      } else {
        localNodes.add(target);
      }
    }

    final regions = <_NovelWorldMapRegion>[
      _NovelWorldMapRegion(
        id: currentRegionKey,
        name: worldTitle.isEmpty ? '当前世界' : worldTitle,
        subtitle: current.name.trim(),
        current: true,
      ),
      ...crossRegion.entries.take(4).map(
            (entry) => _NovelWorldMapRegion(
              id: entry.key,
              name: entry.value.name.trim().isNotEmpty
                  ? entry.value.name.trim()
                  : _prettyIdentifier(entry.key),
              subtitle: entry.value.exitName.trim(),
              current: false,
            ),
          ),
    ];

    return _NovelWorldMapSnapshot(
      worldTitle: worldTitle.isEmpty ? '大世界地图' : worldTitle,
      regions: regions,
      localNodes: localNodes,
      targets: map.targets,
    );
  }
}

class _NovelWorldMapRegion {
  const _NovelWorldMapRegion({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.current,
  });

  final String id;
  final String name;
  final String subtitle;
  final bool current;
}

String _prettyIdentifier(String value) {
  return value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

class _NovelWorldMapPainter extends CustomPainter {
  _NovelWorldMapPainter({required this.snapshot, required this.currentImage});

  final _NovelWorldMapSnapshot snapshot;
  final ui.Image? currentImage;

  static const List<Rect> _layouts = <Rect>[
    Rect.fromLTWH(390, 70, 700, 470),
    Rect.fromLTWH(70, 430, 650, 500),
    Rect.fromLTWH(760, 430, 650, 500),
    Rect.fromLTWH(16, 90, 430, 330),
    Rect.fromLTWH(1034, 90, 430, 330),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final paths = <Path>[];
    for (var i = 0; i < snapshot.regions.length && i < _layouts.length; i++) {
      paths.add(_organicPath(_layouts[i], i));
    }

    for (var i = 1; i < paths.length; i++) {
      _drawConnection(canvas, _layouts[0].center, _layouts[i].center, i);
    }

    for (var i = 0; i < paths.length; i++) {
      _drawRegion(canvas, paths[i], _layouts[i], snapshot.regions[i], i);
    }

    if (paths.isNotEmpty) {
      _drawLocalNodes(canvas, paths.first, _layouts.first);
      _drawCurrentMarker(canvas, _layouts.first.center);
    }
  }

  Path _organicPath(Rect r, int index) {
    final wobble = index.isEven ? 1.0 : -1.0;
    return Path()
      ..moveTo(r.left + r.width * .12, r.top + r.height * .18)
      ..cubicTo(
        r.left + r.width * .25,
        r.top + r.height * (.01 + .025 * wobble),
        r.left + r.width * .45,
        r.top + r.height * .08,
        r.left + r.width * .58,
        r.top + r.height * .07,
      )
      ..cubicTo(
        r.left + r.width * .78,
        r.top + r.height * .02,
        r.left + r.width * .94,
        r.top + r.height * .13,
        r.left + r.width * .92,
        r.top + r.height * .29,
      )
      ..cubicTo(
        r.right + r.width * .01,
        r.top + r.height * .48,
        r.left + r.width * .88,
        r.top + r.height * .62,
        r.left + r.width * .91,
        r.top + r.height * .76,
      )
      ..cubicTo(
        r.left + r.width * .85,
        r.bottom - r.height * .04,
        r.left + r.width * .62,
        r.bottom - r.height * .08,
        r.left + r.width * .50,
        r.bottom - r.height * .04,
      )
      ..cubicTo(
        r.left + r.width * .30,
        r.bottom + r.height * .01,
        r.left + r.width * .08,
        r.bottom - r.height * .10,
        r.left + r.width * .07,
        r.top + r.height * .72,
      )
      ..cubicTo(
        r.left - r.width * .01,
        r.top + r.height * .54,
        r.left + r.width * .07,
        r.top + r.height * .38,
        r.left + r.width * .12,
        r.top + r.height * .18,
      )
      ..close();
  }

  void _drawConnection(Canvas canvas, Offset from, Offset to, int index) {
    final line = Paint()
      ..color = _mapAccent.withOpacity(.15)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(from.dx, from.dy + 120)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2 + (index.isEven ? 28 : -28),
        (from.dy + to.dy) / 2,
        to.dx,
        to.dy - 110,
      );
    canvas.drawPath(path, line);

    final fog = Paint()
      ..color = Colors.black.withOpacity(.72)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38);
    for (var i = 1; i <= 4; i++) {
      final t = i / 5;
      final center = Offset.lerp(from, to, t)!;
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 150 + i * 11,
          height: 78 + i * 5,
        ),
        fog,
      );
    }
  }

  void _drawRegion(
    Canvas canvas,
    Path path,
    Rect rect,
    _NovelWorldMapRegion region,
    int index,
  ) {
    canvas.save();
    canvas.clipPath(path);
    if (region.current && currentImage != null) {
      paintImage(
        canvas: canvas,
        rect: rect.inflate(16),
        image: currentImage!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        opacity: .68,
      );
      canvas.drawRect(
        rect.inflate(20),
        Paint()..color = const Color(0xFF102019).withOpacity(.28),
      );
    } else {
      final base = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: region.current
              ? const <Color>[Color(0xFF26352C), Color(0xFF111815)]
              : const <Color>[Color(0xFF20282B), Color(0xFF0C1112)],
        ).createShader(rect);
      canvas.drawRect(rect.inflate(18), base);
      _drawContours(canvas, rect, index);
    }

    final edgeFog = Paint()
      ..shader = RadialGradient(
        radius: .72,
        colors: <Color>[
          Colors.transparent,
          Colors.black.withOpacity(region.current ? .18 : .48),
          Colors.black.withOpacity(.94),
        ],
        stops: const <double>[0, .66, 1],
      ).createShader(rect);
    canvas.drawRect(rect.inflate(8), edgeFog);
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = region.current ? 2.2 : 1.2
        ..color = _mapAccent.withOpacity(region.current ? .38 : .16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    _drawRegionLabel(canvas, rect, region);
  }

  void _drawContours(Canvas canvas, Rect rect, int seed) {
    final random = math.Random(seed * 997 + 31);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _mapPaper.withOpacity(.075);
    for (var i = 0; i < 10; i++) {
      final center = Offset(
        rect.left + rect.width * (.18 + random.nextDouble() * .64),
        rect.top + rect.height * (.18 + random.nextDouble() * .64),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 110 + random.nextDouble() * 210,
          height: 34 + random.nextDouble() * 72,
        ),
        paint,
      );
    }
  }

  void _drawRegionLabel(
    Canvas canvas,
    Rect rect,
    _NovelWorldMapRegion region,
  ) {
    final title = TextPainter(
      text: TextSpan(
        text: region.name,
        style: TextStyle(
          color: _mapPaper.withOpacity(region.current ? .94 : .60),
          fontSize: region.current ? 25 : 18,
          fontWeight: FontWeight.w500,
          letterSpacing: 3,
          shadows: const <Shadow>[
            Shadow(color: Colors.black, blurRadius: 12),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width * .70);
    title.paint(
      canvas,
      Offset(rect.center.dx - title.width / 2, rect.center.dy - title.height / 2),
    );

    final subtitleValue = region.subtitle.trim();
    if (subtitleValue.isEmpty || subtitleValue == region.name) return;
    final subtitle = TextPainter(
      text: TextSpan(
        text: subtitleValue,
        style: TextStyle(
          color: _mapPaper.withOpacity(.35),
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width * .62);
    subtitle.paint(
      canvas,
      Offset(
        rect.center.dx - subtitle.width / 2,
        rect.center.dy + title.height / 2 + 9,
      ),
    );
  }

  void _drawLocalNodes(Canvas canvas, Path regionPath, Rect rect) {
    for (var i = 0; i < snapshot.localNodes.length; i++) {
      final node = snapshot.localNodes[i];
      final hash = (node.sceneId.isEmpty ? node.name : node.sceneId).hashCode;
      final random = math.Random(hash);
      var point = Offset(
        rect.left + rect.width * (.20 + random.nextDouble() * .60),
        rect.top + rect.height * (.22 + random.nextDouble() * .56),
      );
      if (!regionPath.contains(point)) point = rect.center;

      final locked = node.isLocked;
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = locked
              ? _mapPaper.withOpacity(.20)
              : _mapAccent.withOpacity(.90),
      );
      canvas.drawCircle(
        point,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _mapPaper.withOpacity(locked ? .12 : .30),
      );

      final label = TextPainter(
        text: TextSpan(
          text: node.name,
          style: TextStyle(
            color: _mapPaper.withOpacity(locked ? .34 : .68),
            fontSize: 10,
            shadows: const <Shadow>[
              Shadow(color: Colors.black, blurRadius: 8),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 150);
      label.paint(canvas, point + const Offset(12, -6));
    }
  }

  void _drawCurrentMarker(Canvas canvas, Offset center) {
    final point = center + const Offset(0, 86);
    canvas.drawCircle(
      point,
      22,
      Paint()
        ..color = _mapAccent.withOpacity(.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(point, 8, Paint()..color = _mapAccent);
    canvas.drawCircle(
      point,
      14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _mapPaper.withOpacity(.70),
    );
  }

  @override
  bool shouldRepaint(covariant _NovelWorldMapPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.currentImage != currentImage;
  }
}

class _WorldMapVignette extends StatelessWidget {
  const _WorldMapVignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: .82,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withOpacity(.12),
            Colors.black.withOpacity(.86),
          ],
          stops: const <double>[0, .68, 1],
        ),
      ),
    );
  }
}

class _WorldMapHeader extends StatelessWidget {
  const _WorldMapHeader({
    required this.title,
    required this.loading,
    required this.onClose,
    required this.onRefresh,
  });

  final String title;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _WorldMapRoundButton(icon: Icons.close_rounded, onTap: onClose),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '大世界地图',
                style: TextStyle(
                  color: _mapPaper.withOpacity(.45),
                  fontSize: 9,
                  letterSpacing: 2.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _mapPaper,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        _WorldMapRoundButton(
          icon: loading ? null : Icons.refresh_rounded,
          loading: loading,
          onTap: loading ? null : onRefresh,
        ),
      ],
    );
  }
}

class _WorldMapRoundButton extends StatelessWidget {
  const _WorldMapRoundButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _mapInk.withOpacity(.68),
            border: Border.all(color: _mapPaper.withOpacity(.16)),
          ),
          child: loading
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.3,
                    color: _mapPaper.withOpacity(.78),
                  ),
                )
              : Icon(icon, color: _mapPaper.withOpacity(.86), size: 20),
        ),
      ),
    );
  }
}

class _WorldMapDestinations extends StatelessWidget {
  const _WorldMapDestinations({
    required this.targets,
    required this.submitting,
    required this.canMove,
    required this.onMove,
  });

  final List<NovelSceneMapNode> targets;
  final bool submitting;
  final bool canMove;
  final ValueChanged<NovelSceneMapNode> onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            _mapInk.withOpacity(.78),
            _mapInk.withOpacity(.78),
            Colors.transparent,
          ],
          stops: const <double>[0, .08, .92, 1],
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        itemCount: targets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final target = targets[index];
          final enabled = canMove && !target.isLocked && !submitting;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? () => onMove(target) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 128, maxWidth: 210),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(enabled ? .055 : .025),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _mapPaper.withOpacity(enabled ? .18 : .08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      target.isLocked
                          ? Icons.lock_outline_rounded
                          : target.isRisky
                              ? Icons.warning_amber_rounded
                              : Icons.route_outlined,
                      color: target.isRisky
                          ? const Color(0xFFE2C27A)
                          : _mapPaper.withOpacity(enabled ? .70 : .28),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        target.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _mapPaper.withOpacity(enabled ? .82 : .34),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorldMapNotice extends StatelessWidget {
  const _WorldMapNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            _mapInk.withOpacity(.72),
            Colors.transparent,
          ],
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _mapPaper.withOpacity(.48),
          fontSize: 10.5,
          height: 1.45,
        ),
      ),
    );
  }
}

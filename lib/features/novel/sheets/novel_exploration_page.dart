part of '../novel_sheets.dart';

/// 正式自由探索页：
/// - 输入场景名称后创建 scene-assets 后台任务；
/// - 使用后端生成的 1 张 1536x864 完整横版场景图；
/// - Flutter 以放大的跟随相机显示舞台，不会一次把整张地图缩到屏幕里；
/// - 主角左右/上下移动时相机同步平移，向上走才逐步看到场景顶部；
/// - 移动端虚拟摇杆 + 桌面 WASD/方向键连续移动，碰撞行为对齐 HTML；
/// - 主角优先使用当前会话已有 portrait_url，不在本页重复生成角色。
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
  JsonMap? _assetPackage;
  _LoadedSceneImages? _images;
  bool _loading = false;
  String? _error;
  String _statusText = '';
  String? _activeTaskId;
  int _generationSerial = 0;
  bool _showFootprints = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialSceneName);
  }

  @override
  void dispose() {
    _generationSerial++;
    _nameController.dispose();
    _images?.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _loading) return;

    final serial = ++_generationSerial;
    setState(() {
      _loading = true;
      _error = null;
      _statusText = '正在创建场景资产任务…';
      _activeTaskId = null;
    });

    try {
      final created = await widget.backend.createSceneAssetTask(
        name: name,
        sessionId: widget.sessionId,
      );
      if (!mounted || serial != _generationSerial) return;

      final taskId = _sceneString(created['task_id']);
      if (taskId.isEmpty) {
        throw const NovelBackendException('后端没有返回场景资产 task_id');
      }
      final playerAsset = _sceneMap(created['player_asset']);
      _activeTaskId = taskId;

      for (var attempt = 0; attempt < 320; attempt++) {
        if (!mounted || serial != _generationSerial) return;

        final result = await widget.backend.fetchSceneAssetTaskResult(taskId);
        if (!mounted || serial != _generationSerial) return;

        final status = _sceneString(result['status']).toLowerCase();
        final message = _sceneString(result['message'], '场景资产生成中');
        final progress = _sceneInt(result['progress']).clamp(0, 100).toInt();
        setState(() => _statusText = '$message · $progress%');

        if (status == 'failed') {
          throw NovelBackendException(
            _sceneString(result['error'], '场景资产生成失败'),
          );
        }
        if (status == 'cancelled') {
          throw const NovelBackendException('场景资产生成已取消');
        }
        if (status == 'completed') {
          final package = _sceneMap(result['asset_package']);
          if (package.isEmpty) {
            throw const NovelBackendException('场景资产任务完成但 asset_package 为空');
          }

          // Image Service 只有在 Cloudflare Worker 已把 Fal 图片流式落到 R2 后
          // 才会把任务标记 completed；Flutter 这里只消费最终 R2 URL。
          final loaded = await _loadSceneImages(package, playerAsset);
          if (!mounted || serial != _generationSerial) {
            loaded.dispose();
            return;
          }

          final previous = _images;
          final objectCount = _sceneList(package['objects']).length;
          setState(() {
            _assetPackage = package;
            _images = loaded;
            _statusText = '生成完成 · $objectCount 个交互热点';
            _error = null;
          });
          previous?.dispose();
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }

      throw const NovelBackendException('场景资产生成等待超时，请重试');
    } catch (error) {
      if (!mounted || serial != _generationSerial) return;
      setState(() {
        _error = error is NovelBackendException ? error.message : error.toString();
      });
    } finally {
      if (mounted && serial == _generationSerial) {
        setState(() {
          _loading = false;
          _activeTaskId = null;
        });
      }
    }
  }

  Future<void> _cancelGeneration() async {
    final taskId = _activeTaskId;
    if (!_loading) return;
    _generationSerial++;
    setState(() {
      _loading = false;
      _activeTaskId = null;
      _statusText = '已取消';
      _error = null;
    });
    if (taskId == null || taskId.isEmpty) return;
    try {
      await widget.backend.cancelSceneAssetTask(taskId);
    } catch (_) {
      // 页面已经停止消费结果；后端取消失败不覆盖用户当前页面状态。
    }
  }

  Future<_LoadedSceneImages> _loadSceneImages(
    JsonMap package,
    JsonMap playerAsset,
  ) async {
    final floor = _sceneMap(package['floor']);
    final sheet = _sceneMap(package['sprite_sheet']);
    final floorUrl = _sceneString(floor['url']);
    final atlasUrl = _sceneString(sheet['url']);
    final sheetMode = _sceneString(sheet['mode']).toLowerCase();
    final objectCount = _sceneList(package['objects']).length;
    final spriteEntries = _sceneList(package['sprites'])
        .map(_sceneMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    if (floorUrl.isEmpty) {
      throw const NovelBackendException('场景资产缺少 floor.url');
    }

    // Legacy compatibility only. New scene assets may return either a keyed
    // building strip or a classic sprite sheet.
    final spriteUrls = List<String>.filled(objectCount, '');
    for (final sprite in spriteEntries) {
      final index = _sceneInt(sprite['sprite_index'], -1);
      if (index < 0 || index >= spriteUrls.length) continue;
      spriteUrls[index] = _sceneString(sprite['url']);
    }
    final hasIndividualSprites = objectCount > 0 &&
        spriteUrls.length == objectCount &&
        spriteUrls.every((url) => url.isNotEmpty);


    final playerUrl = _sceneString(
      playerAsset['portrait_url'],
      _sceneString(playerAsset['avatar_url']),
    );

    dynamic floorImage;
    dynamic atlasImage;
    dynamic stripImage;
    dynamic playerImage;
    final spriteImages = <dynamic>[];
    try {
      if (hasIndividualSprites) {
        final values = await Future.wait<dynamic>(<Future<dynamic>>[
          _loadUiImage(floorUrl),
          ...spriteUrls.map(_loadUiImage),
          if (playerUrl.isNotEmpty) _loadUiImage(playerUrl) else Future<dynamic>.value(null),
        ]);
        floorImage = values.first;
        spriteImages.addAll(values.sublist(1, 1 + objectCount));
        playerImage = values.last;

        final spriteRects = <Rect>[];
        for (final image in spriteImages) {
          final rects = await _extractOpaqueSpriteRects(image, 1, 1);
          spriteRects.add(rects.first);
        }
        return _LoadedSceneImages(
          floor: floorImage,
          atlas: null,
          strip: null,
          sprites: spriteImages,
          player: playerImage,
          spriteRects: spriteRects,
        );
      }

      final floorRenderMode = _sceneString(floor['render_mode']).toLowerCase();
      final sourceSheetMode = _sceneString(
        floor['source_sheet_mode'],
        _sceneString(_sceneMap(floor['stage'])['source_sheet_mode']),
      ).toLowerCase();
      final metadataOnlyHotspots =
          floorRenderMode == 'full_scene_plate' ||
          sourceSheetMode == 'full_scene_composite' ||
          sheetMode == 'disabled' ||
          (atlasUrl.isEmpty && !hasIndividualSprites);

      if (metadataOnlyHotspots) {
        final values = await Future.wait<dynamic>(<Future<dynamic>>[
          _loadUiImage(floorUrl),
          if (playerUrl.isNotEmpty) _loadUiImage(playerUrl) else Future<dynamic>.value(null),
        ]);
        floorImage = values[0];
        playerImage = values[1];

        return _LoadedSceneImages(
          floor: floorImage,
          atlas: null,
          strip: null,
          sprites: const <dynamic>[],
          player: playerImage,
          spriteRects: const <Rect>[],
        );
      }

      if (sheetMode == 'strip') {
        final values = await Future.wait<dynamic>(<Future<dynamic>>[
          _loadUiImage(floorUrl),
          if (atlasUrl.isNotEmpty)
            _loadPreparedAtlas(atlasUrl, sheet, 1, 1)
          else
            Future<dynamic>.value(null),
          if (playerUrl.isNotEmpty) _loadUiImage(playerUrl) else Future<dynamic>.value(null),
        ]);
        floorImage = values[0];
        final preparedStrip = values[1] as _PreparedSceneAtlas?;
        stripImage = preparedStrip?.image;
        playerImage = values[2];

        return _LoadedSceneImages(
          floor: floorImage,
          atlas: null,
          strip: stripImage,
          sprites: const <dynamic>[],
          player: playerImage,
          spriteRects: const <Rect>[],
        );
      }

      final cols = _sceneInt(sheet['cols'], 3).clamp(1, 12).toInt();
      final rows = _sceneInt(sheet['rows'], 3).clamp(1, 12).toInt();

      final values = await Future.wait<dynamic>(<Future<dynamic>>[
        _loadUiImage(floorUrl),
        if (atlasUrl.isNotEmpty)
          _loadPreparedAtlas(atlasUrl, sheet, cols, rows)
        else
          Future<dynamic>.value(null),
        if (playerUrl.isNotEmpty) _loadUiImage(playerUrl) else Future<dynamic>.value(null),
      ]);
      floorImage = values[0];
      final preparedAtlas = values[1] as _PreparedSceneAtlas?;
      atlasImage = preparedAtlas?.image;
      playerImage = values[2];

      return _LoadedSceneImages(
        floor: floorImage,
        atlas: atlasImage,
        strip: null,
        sprites: const <dynamic>[],
        player: playerImage,
        spriteRects: preparedAtlas?.spriteRects ?? const <Rect>[],
      );
    } catch (_) {
      _disposeUiImage(floorImage);
      _disposeUiImage(atlasImage);
      _disposeUiImage(stripImage);
      for (final image in spriteImages) {
        _disposeUiImage(image);
      }
      _disposeUiImage(playerImage);
      rethrow;
    }
  }

  Future<dynamic> _loadUiImage(String url) async {
    final file = await DefaultCacheManager().getSingleFile(url);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw NovelBackendException('图片为空：$url');
    }
    final codec = await instantiateImageCodec(Uint8List.fromList(bytes));
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<_PreparedSceneAtlas> _loadPreparedAtlas(
    String url,
    JsonMap sheet,
    int cols,
    int rows,
  ) async {
    // The Worker only mirrors the untouched provider atlas into R2.
    // All sampled-key work below is client-only and never uploads a processed file.
    final source = await _loadUiImage(url);
    final keySpec = _SceneSampledKeySpec.fromSheet(sheet);

    if (!keySpec.enabled) {
      final rects = await _extractOpaqueSpriteRects(source, cols, rows);
      return _PreparedSceneAtlas(image: source, spriteRects: rects);
    }

    try {
      final width = source.width as int;
      final height = source.height as int;
      final raw = await source.toByteData(format: ImageByteFormat.rawRgba);
      if (raw == null) {
        throw const NovelBackendException('无法读取摆件图集像素，客户端自动抠底失败');
      }

      final expectedBytes = width * height * 4;
      if (raw.lengthInBytes != expectedBytes) {
        throw NovelBackendException(
          '摆件图集像素格式异常：期望 $expectedBytes 字节，实际 ${raw.lengthInBytes} 字节',
        );
      }

      // Keep this as a byte list. Never reinterpret it as Uint32List and then
      // use byte offsets; that was the source of the previous 4x RangeError.
      final rgba = Uint8List.fromList(
        raw.buffer.asUint8List(raw.offsetInBytes, expectedBytes),
      );

      _applyConnectedKeyFloodFill(
        rgba,
        width,
        height,
        cols,
        rows,
        keySpec,
      );

      final spriteRects = _extractOpaqueRectsFromRgba(
        rgba,
        width,
        height,
        cols,
        rows,
      );

      // PixelFormat.rgba8888 expects premultiplied alpha. The provider atlas is
      // opaque, so its RGB starts effectively straight; after changing alpha we
      // premultiply once before creating the in-memory Flutter image.
      _premultiplyRgbaInPlace(rgba);
      final keyedImage = await _decodePremultipliedRgba(rgba, width, height);
      return _PreparedSceneAtlas(
        image: keyedImage,
        spriteRects: spriteRects,
      );
    } finally {
      source.dispose();
    }
  }

  void _applyConnectedKeyFloodFill(
    Uint8List rgba,
    int imageWidth,
    int imageHeight,
    int cols,
    int rows,
    _SceneSampledKeySpec spec,
  ) {
    final hardTolerance = spec.tolerance.clamp(1.0, 255.0).toDouble();
    final softTolerance = spec.softTolerance
        .clamp(hardTolerance + 1.0, 441.0)
        .toDouble();
    final hardSq = hardTolerance * hardTolerance;
    final softSq = softTolerance * softTolerance;
    final visited = Uint8List(imageWidth * imageHeight);

    double distanceSqAt(int pixelIndex, _SceneRgb key) {
      final p = pixelIndex * 4;
      final dr = rgba[p] - key.r;
      final dg = rgba[p + 1] - key.g;
      final db = rgba[p + 2] - key.b;
      return (dr * dr + dg * dg + db * db).toDouble();
    }

    for (var index = 0; index < cols * rows; index++) {
      final cell = _pixelCell(index, imageWidth, imageHeight, cols, rows);
      final key = spec.adaptiveBorderKey
          ? _estimateDominantBorderKey(rgba, imageWidth, cell, spec.keyColor)
          : _sampleCellKeyColor(rgba, imageWidth, cell);
      final capacity = math.max(1, (cell.right - cell.left) * (cell.bottom - cell.top));
      final queue = Int32List(capacity);
      var head = 0;
      var tail = 0;

      void pushHardBackground(int x, int y) {
        if (x < cell.left || x >= cell.right || y < cell.top || y >= cell.bottom) {
          return;
        }
        final pixelIndex = y * imageWidth + x;
        if (visited[pixelIndex] != 0) return;
        final p = pixelIndex * 4;
        if (rgba[p + 3] == 0) {
          visited[pixelIndex] = 1;
          return;
        }
        if (distanceSqAt(pixelIndex, key) > hardSq) return;
        visited[pixelIndex] = 1;
        if (tail < queue.length) queue[tail++] = pixelIndex;
      }

      void softenNeighbor(int x, int y) {
        if (x < cell.left || x >= cell.right || y < cell.top || y >= cell.bottom) {
          return;
        }
        final pixelIndex = y * imageWidth + x;
        final p = pixelIndex * 4;
        if (rgba[p + 3] == 0) return;
        final distanceSq = distanceSqAt(pixelIndex, key);
        if (distanceSq <= hardSq || distanceSq > softSq) return;
        final distance = math.sqrt(distanceSq);
        final t = ((distance - hardTolerance) / (softTolerance - hardTolerance))
            .clamp(0.0, 1.0)
            .toDouble();
        final nextAlpha = (rgba[p + 3] * t).round().clamp(0, 255).toInt();
        if (nextAlpha < rgba[p + 3]) rgba[p + 3] = nextAlpha;
      }

      // Seed only true background pixels from the outside edge. The generated
      // chroma is not always literal #FF00FF, so the key is learned from the
      // dominant border color first. Soft fringe pixels never become flood-fill
      // traversal nodes, which prevents a pink/red shop detail from opening a path
      // into the building interior.
      for (var x = cell.left; x < cell.right; x++) {
        pushHardBackground(x, cell.top);
        pushHardBackground(x, cell.bottom - 1);
      }
      for (var y = cell.top + 1; y < cell.bottom - 1; y++) {
        pushHardBackground(cell.left, y);
        pushHardBackground(cell.right - 1, y);
      }

      while (head < tail) {
        final pixelIndex = queue[head++];
        final p = pixelIndex * 4;
        rgba[p + 3] = 0;

        final x = pixelIndex % imageWidth;
        final y = pixelIndex ~/ imageWidth;

        // Traverse only hard-key pixels.
        pushHardBackground(x - 1, y);
        pushHardBackground(x + 1, y);
        pushHardBackground(x, y - 1);
        pushHardBackground(x, y + 1);

        // One-pixel soft fringe cleanup, but do not traverse through it.
        softenNeighbor(x - 1, y);
        softenNeighbor(x + 1, y);
        softenNeighbor(x, y - 1);
        softenNeighbor(x, y + 1);
      }

      // Game-asset style edge cleanup: remove the chroma-contaminated outer shell,
      // replace magenta spill with nearby building color, then feather only 2 px.
      // This stays inside the current client-side pipeline; no extra image request.
      _cleanupFloodFilledCellEdge(
        rgba,
        imageWidth,
        cell,
        key,
        hardTolerance,
        softTolerance,
      );
    }

    if (!spec.defringe) return;

    // Clean only the semi-transparent edge created by the flood fill. Solid pixels
    // inside the building are never recolored or removed.
    final source = Uint8List.fromList(rgba);
    const neighbors = <List<int>>[
      <int>[-1, 0],
      <int>[1, 0],
      <int>[0, -1],
      <int>[0, 1],
      <int>[-1, -1],
      <int>[1, -1],
      <int>[-1, 1],
      <int>[1, 1],
    ];

    for (var y = 0; y < imageHeight; y++) {
      for (var x = 0; x < imageWidth; x++) {
        final p = (y * imageWidth + x) * 4;
        final alpha = source[p + 3];
        if (alpha == 0 || alpha >= 250) continue;

        var rr = 0;
        var gg = 0;
        var bb = 0;
        var count = 0;
        for (final delta in neighbors) {
          final nx = x + delta[0];
          final ny = y + delta[1];
          if (nx < 0 || nx >= imageWidth || ny < 0 || ny >= imageHeight) continue;
          final np = (ny * imageWidth + nx) * 4;
          if (source[np + 3] <= 220) continue;
          rr += source[np];
          gg += source[np + 1];
          bb += source[np + 2];
          count++;
        }
        if (count == 0) continue;
        rgba[p] = (rr / count).round().clamp(0, 255).toInt();
        rgba[p + 1] = (gg / count).round().clamp(0, 255).toInt();
        rgba[p + 2] = (bb / count).round().clamp(0, 255).toInt();
      }
    }
  }

  void _cleanupFloodFilledCellEdge(
    Uint8List rgba,
    int imageWidth,
    _ScenePixelCell cell,
    _SceneRgb key,
    double hardTolerance,
    double softTolerance,
  ) {
    const transparentCutoff = 8;
    const maxEdgeRadius = 6;
    const referenceRadius = 9;
    const solidReferenceAlpha = 232;

    final cellWidth = math.max(1, cell.right - cell.left);
    final cellHeight = math.max(1, cell.bottom - cell.top);
    final localPixelCount = cellWidth * cellHeight;
    final hardSq = hardTolerance * hardTolerance;
    final softSq = softTolerance * softTolerance;

    bool inside(int x, int y) =>
        x >= cell.left && x < cell.right && y >= cell.top && y < cell.bottom;

    int localIndex(int x, int y) =>
        (y - cell.top) * cellWidth + (x - cell.left);

    double keyDistanceSq(Uint8List data, int x, int y) {
      final p = (y * imageWidth + x) * 4;
      final dr = data[p] - key.r;
      final dg = data[p + 1] - key.g;
      final db = data[p + 2] - key.b;
      return (dr * dr + dg * dg + db * db).toDouble();
    }

    // Freeze the flood-filled result before decontamination. The edge-distance map
    // is calculated from this alpha mask so later RGB/alpha changes cannot move the
    // silhouette while we are still processing it.
    final source = Uint8List.fromList(rgba);

    // Build a compact 1..6 px distance-to-transparent field. Cleanup is intentionally
    // stronger on the outer 2 px, then falls off quickly toward the facade interior.
    final edgeDistance = Uint8List(localPixelCount);
    edgeDistance.fillRange(0, edgeDistance.length, 255);
    final queue = Int32List(localPixelCount);
    var head = 0;
    var tail = 0;

    bool isTransparentAt(int x, int y) {
      if (!inside(x, y)) return true;
      final p = (y * imageWidth + x) * 4;
      return source[p + 3] <= transparentCutoff;
    }

    for (var y = cell.top; y < cell.bottom; y++) {
      for (var x = cell.left; x < cell.right; x++) {
        final p = (y * imageWidth + x) * 4;
        if (source[p + 3] <= transparentCutoff) continue;
        if (isTransparentAt(x - 1, y) ||
            isTransparentAt(x + 1, y) ||
            isTransparentAt(x, y - 1) ||
            isTransparentAt(x, y + 1)) {
          final li = localIndex(x, y);
          edgeDistance[li] = 1;
          queue[tail++] = li;
        }
      }
    }

    const neighbor4 = <List<int>>[
      <int>[-1, 0],
      <int>[1, 0],
      <int>[0, -1],
      <int>[0, 1],
    ];

    while (head < tail) {
      final li = queue[head++];
      final distance = edgeDistance[li];
      if (distance >= maxEdgeRadius) continue;
      final lx = li % cellWidth;
      final ly = li ~/ cellWidth;
      final x = cell.left + lx;
      final y = cell.top + ly;
      for (final delta in neighbor4) {
        final nx = x + delta[0];
        final ny = y + delta[1];
        if (!inside(nx, ny)) continue;
        final np = (ny * imageWidth + nx) * 4;
        if (source[np + 3] <= transparentCutoff) continue;
        final nli = localIndex(nx, ny);
        if (edgeDistance[nli] != 255) continue;
        edgeDistance[nli] = distance + 1;
        queue[tail++] = nli;
      }
    }

    // Decontaminate opaque AND semi-transparent edge pixels. For each 1..6 px edge
    // pixel, estimate a nearby clean facade color, then solve the simple compositing
    // model O = a*F + (1-a)*K. If the observed RGB lies close to the line between
    // the learned key color K and local facade color F, it is chroma contamination.
    // This catches the red/magenta outline even when the source pixel alpha is 255.
    for (var y = cell.top; y < cell.bottom; y++) {
      for (var x = cell.left; x < cell.right; x++) {
        final li = localIndex(x, y);
        final edge = edgeDistance[li];
        if (edge == 0 || edge == 255 || edge > maxEdgeRadius) continue;

        final p = (y * imageWidth + x) * 4;
        final alpha = source[p + 3];
        if (alpha <= transparentCutoff) continue;

        var rr = 0.0;
        var gg = 0.0;
        var bb = 0.0;
        var weightSum = 0.0;

        for (var dy = -referenceRadius; dy <= referenceRadius; dy++) {
          for (var dx = -referenceRadius; dx <= referenceRadius; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            final ny = y + dy;
            if (!inside(nx, ny)) continue;
            final nli = localIndex(nx, ny);
            final neighborEdge = edgeDistance[nli];
            // Prefer pixels farther inside the facade than the pixel being cleaned.
            if (neighborEdge != 255 && neighborEdge <= edge + 1) continue;
            final np = (ny * imageWidth + nx) * 4;
            if (source[np + 3] < solidReferenceAlpha) continue;
            if (keyDistanceSq(source, nx, ny) <= softSq) continue;

            final d2 = (dx * dx + dy * dy).toDouble();
            var weight = 1.0 / math.max(1.0, d2);
            if (neighborEdge == 255 || neighborEdge >= maxEdgeRadius) {
              weight *= 1.35;
            }
            rr += source[np] * weight;
            gg += source[np + 1] * weight;
            bb += source[np + 2] * weight;
            weightSum += weight;
          }
        }
        if (weightSum <= 0.0) continue;

        final fr = rr / weightSum;
        final fg = gg / weightSum;
        final fb = bb / weightSum;
        final vr = fr - key.r;
        final vg = fg - key.g;
        final vb = fb - key.b;
        final denom = vr * vr + vg * vg + vb * vb;
        if (denom < 36.0) continue;

        final or = source[p].toDouble();
        final og = source[p + 1].toDouble();
        final ob = source[p + 2].toDouble();
        final wr = or - key.r;
        final wg = og - key.g;
        final wb = ob - key.b;
        final coverage = ((wr * vr + wg * vg + wb * vb) / denom)
            .clamp(0.0, 1.0)
            .toDouble();

        final predR = key.r + vr * coverage;
        final predG = key.g + vg * coverage;
        final predB = key.b + vb * coverage;
        final residual = math.sqrt(
          math.pow(or - predR, 2) +
              math.pow(og - predG, 2) +
              math.pow(ob - predB, 2),
        );

        // True painted red/purple detail generally does not lie on the local
        // key-to-facade mixing line, so a residual gate protects those details.
        final residualLimit = 42.0 + edge * 6.0;
        final keyLike = keyDistanceSq(source, x, y) <= softSq * 2.25;
        final forceOuterEdge = edge <= 2;
        if (!forceOuterEdge && !keyLike &&
            (coverage >= .998 || residual > residualLimit)) {
          continue;
        }
        if (forceOuterEdge) {
          if (!keyLike && residual > residualLimit * 2.20) continue;
        } else if (residual > residualLimit * 1.65) {
          continue;
        }

        final residualConfidence =
            (1.0 - residual / (residualLimit * 1.80)).clamp(0.0, 1.0).toDouble();
        final edgeStrength = edge == 1
            ? 1.0
            : edge == 2
                ? .90
                : edge == 3
                    ? .72
                    : edge == 4
                        ? .50
                        : edge == 5
                            ? .32
                            : .18;
        final contamination =
            ((1.0 - coverage) * residualConfidence * edgeStrength)
                .clamp(0.0, 1.0)
                .toDouble();
        if (contamination < .025 && !keyLike) continue;

        // Reverse the estimated key-color mix. Blend the recovered value toward the
        // local facade reference to avoid noisy overshoot on watercolor/painted art.
        final safeCoverage = coverage.clamp(.16, 1.0).toDouble();
        double recover(double observed, double keyChannel, double localChannel) {
          final unkeyed =
              (observed - (1.0 - safeCoverage) * keyChannel) / safeCoverage;
          final clamped = unkeyed.clamp(0.0, 255.0).toDouble();
          return clamped * .68 + localChannel * .32;
        }

        final recoveredR = recover(or, key.r.toDouble(), fr);
        final recoveredG = recover(og, key.g.toDouble(), fg);
        final recoveredB = recover(ob, key.b.toDouble(), fb);
        final minimumEdgeStrength = edge == 1
            ? .88
            : edge == 2
                ? .68
                : edge == 3
                    ? .38
                    : 0.0;
        final colorStrength = math.max(
          minimumEdgeStrength,
          math.max(
            keyLike ? .78 : 0.0,
            (contamination * 3.4).clamp(0.0, 1.0).toDouble(),
          ),
        );
        rgba[p] = (or + (recoveredR - or) * colorStrength)
            .round()
            .clamp(0, 255)
            .toInt();
        rgba[p + 1] = (og + (recoveredG - og) * colorStrength)
            .round()
            .clamp(0, 255)
            .toInt();
        rgba[p + 2] = (ob + (recoveredB - ob) * colorStrength)
            .round()
            .clamp(0, 255)
            .toInt();

        // Opaque anti-aliased source pixels are common in AI output. Reconstruct a
        // useful coverage alpha instead of leaving the decontaminated pixel fully
        // opaque. The falloff is strongest only on the outer 1-2 px silhouette.
        final alphaFalloff = edge == 1
            ? 1.25
            : edge == 2
                ? .98
                : edge == 3
                    ? .72
                    : edge == 4
                        ? .48
                        : edge == 5
                            ? .28
                            : .14;
        final alphaLoss =
            (contamination * alphaFalloff).clamp(0.0, .92).toDouble();
        final alphaFactor = (1.0 - alphaLoss).clamp(.0, 1.0).toDouble();
        final nextAlpha = (alpha * alphaFactor).round().clamp(0, 255).toInt();
        if (nextAlpha < rgba[p + 3]) rgba[p + 3] = nextAlpha;
      }
    }

    // Stronger selective 2-ring trim. Test key-likeness against the original
    // flood-filled source, before RGB decontamination hides the chroma evidence.
    final decontaminated = Uint8List.fromList(rgba);
    for (var y = cell.top; y < cell.bottom; y++) {
      for (var x = cell.left; x < cell.right; x++) {
        final li = localIndex(x, y);
        final edge = edgeDistance[li];
        if (edge != 1 && edge != 2) continue;
        final p = (y * imageWidth + x) * 4;
        final alpha = decontaminated[p + 3];
        if (alpha <= transparentCutoff) {
          rgba[p + 3] = 0;
          continue;
        }
        final originalDistance = keyDistanceSq(source, x, y);
        final veryKeyLike = originalDistance <=
            (edge == 1 ? softSq * 2.40 : softSq * 1.70);
        if (edge == 1 && veryKeyLike) {
          rgba[p + 3] = 0;
        } else if (edge == 2 && veryKeyLike && alpha < 240) {
          rgba[p + 3] = 0;
        }
      }
    }

    // Strong 3-ring feather. It stays local to the extracted silhouette; there is
    // no global blur, but the visible magenta/red halo is suppressed much harder.
    for (var y = cell.top; y < cell.bottom; y++) {
      for (var x = cell.left; x < cell.right; x++) {
        final edge = edgeDistance[localIndex(x, y)];
        if (edge < 1 || edge > 3) continue;
        final p = (y * imageWidth + x) * 4;
        final alpha = rgba[p + 3];
        if (alpha <= transparentCutoff) {
          rgba[p + 3] = 0;
          continue;
        }
        final cap = edge == 1
            ? 88
            : edge == 2
                ? 168
                : 226;
        if (alpha > cap) rgba[p + 3] = cap;
      }
    }
  }

  _SceneRgb _estimateDominantBorderKey(
    Uint8List rgba,
    int imageWidth,
    _ScenePixelCell cell,
    _SceneRgb hint,
  ) {
    final cellWidth = math.max(1, cell.right - cell.left);
    final cellHeight = math.max(1, cell.bottom - cell.top);
    final band = math.max(4, math.min(18, math.min(cellWidth, cellHeight) ~/ 28));
    final stride = math.max(1, math.min(4, math.min(cellWidth, cellHeight) ~/ 180));
    final counts = <int, int>{};
    final sums = <int, List<int>>{};

    void sample(int x, int y) {
      final p = (y * imageWidth + x) * 4;
      if (rgba[p + 3] == 0) return;
      final r = rgba[p];
      final g = rgba[p + 1];
      final b = rgba[p + 2];

      // Quantize to 16-level RGB bins. Generated chroma backgrounds tend to be
      // locally very consistent even when the model misses the exact requested hex.
      final bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      counts[bucket] = (counts[bucket] ?? 0) + 1;
      final acc = sums.putIfAbsent(bucket, () => <int>[0, 0, 0, 0]);
      acc[0] += r;
      acc[1] += g;
      acc[2] += b;
      acc[3] += 1;
    }

    for (var y = cell.top; y < math.min(cell.bottom, cell.top + band); y += stride) {
      for (var x = cell.left; x < cell.right; x += stride) sample(x, y);
    }
    for (var y = math.max(cell.top, cell.bottom - band); y < cell.bottom; y += stride) {
      for (var x = cell.left; x < cell.right; x += stride) sample(x, y);
    }
    for (var x = cell.left; x < math.min(cell.right, cell.left + band); x += stride) {
      for (var y = cell.top + band; y < cell.bottom - band; y += stride) sample(x, y);
    }
    for (var x = math.max(cell.left, cell.right - band); x < cell.right; x += stride) {
      for (var y = cell.top + band; y < cell.bottom - band; y += stride) sample(x, y);
    }

    if (counts.isEmpty) return hint;

    var bestBucket = counts.keys.first;
    var bestScore = -1.0;
    for (final entry in counts.entries) {
      final acc = sums[entry.key]!;
      final n = math.max(1, acc[3]);
      final r = acc[0] / n;
      final g = acc[1] / n;
      final b = acc[2] / n;
      final hintDistance = math.sqrt(
        math.pow(r - hint.r, 2) + math.pow(g - hint.g, 2) + math.pow(b - hint.b, 2),
      );
      // Dominance matters most, but the requested magenta hint breaks ties away
      // from dark roof/wall colors if a building touches one edge.
      final score = entry.value * 1.0 - hintDistance * .12;
      if (score > bestScore) {
        bestScore = score;
        bestBucket = entry.key;
      }
    }

    final acc = sums[bestBucket]!;
    final n = math.max(1, acc[3]);
    return _SceneRgb(
      (acc[0] / n).round().clamp(0, 255).toInt(),
      (acc[1] / n).round().clamp(0, 255).toInt(),
      (acc[2] / n).round().clamp(0, 255).toInt(),
    );
  }

  _SceneRgb _sampleCellKeyColor(
    Uint8List rgba,
    int imageWidth,
    _ScenePixelCell cell,
  ) {
    final x0 = math.min(cell.right - 1, cell.left + 2);
    final x1 = math.max(cell.left, cell.right - 3);
    final y0 = math.min(cell.bottom - 1, cell.top + 2);
    final y1 = math.max(cell.top, cell.bottom - 3);
    final xm = ((cell.left + cell.right - 1) / 2).floor();
    final ym = ((cell.top + cell.bottom - 1) / 2).floor();
    final points = <List<int>>[
      <int>[x0, y0],
      <int>[x1, y0],
      <int>[x0, y1],
      <int>[x1, y1],
      <int>[xm, y0],
      <int>[xm, y1],
      <int>[x0, ym],
      <int>[x1, ym],
    ];

    var rr = 0;
    var gg = 0;
    var bb = 0;
    var count = 0;
    for (final point in points) {
      final p = (point[1] * imageWidth + point[0]) * 4;
      if (rgba[p + 3] == 0) continue;
      rr += rgba[p];
      gg += rgba[p + 1];
      bb += rgba[p + 2];
      count++;
    }
    if (count == 0) return const _SceneRgb(255, 255, 255);
    return _SceneRgb(
      (rr / count).round().clamp(0, 255).toInt(),
      (gg / count).round().clamp(0, 255).toInt(),
      (bb / count).round().clamp(0, 255).toInt(),
    );
  }

  List<Rect> _extractOpaqueRectsFromRgba(
    Uint8List rgba,
    int imageWidth,
    int imageHeight,
    int cols,
    int rows,
  ) {
    final result = <Rect>[];
    for (var index = 0; index < cols * rows; index++) {
      final cell = _pixelCell(index, imageWidth, imageHeight, cols, rows);
      var minX = cell.right;
      var minY = cell.bottom;
      var maxX = cell.left - 1;
      var maxY = cell.top - 1;

      for (var y = cell.top; y < cell.bottom; y++) {
        for (var x = cell.left; x < cell.right; x++) {
          final alpha = rgba[(y * imageWidth + x) * 4 + 3];
          if (alpha <= 12) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }

      if (maxX < minX || maxY < minY) {
        result.add(Rect.fromLTRB(
          cell.left.toDouble(),
          cell.top.toDouble(),
          cell.right.toDouble(),
          cell.bottom.toDouble(),
        ));
        continue;
      }

      const padding = 2;
      result.add(Rect.fromLTRB(
        math.max(cell.left, minX - padding).toDouble(),
        math.max(cell.top, minY - padding).toDouble(),
        math.min(cell.right, maxX + padding + 1).toDouble(),
        math.min(cell.bottom, maxY + padding + 1).toDouble(),
      ));
    }
    return result;
  }

  _ScenePixelCell _pixelCell(
    int index,
    int width,
    int height,
    int cols,
    int rows,
  ) {
    final row = index ~/ cols;
    final col = index % cols;
    final left = (col * width / cols).round();
    final right = ((col + 1) * width / cols).round();
    final top = (row * height / rows).round();
    final bottom = ((row + 1) * height / rows).round();
    return _ScenePixelCell(left, top, right, bottom);
  }

  void _premultiplyRgbaInPlace(Uint8List rgba) {
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final alpha = rgba[i + 3];
      if (alpha == 255) continue;
      if (alpha == 0) {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        continue;
      }
      rgba[i] = ((rgba[i] * alpha + 127) ~/ 255).clamp(0, 255).toInt();
      rgba[i + 1] = ((rgba[i + 1] * alpha + 127) ~/ 255).clamp(0, 255).toInt();
      rgba[i + 2] = ((rgba[i + 2] * alpha + 127) ~/ 255).clamp(0, 255).toInt();
    }
  }

  Future<dynamic> _decodePremultipliedRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<dynamic>();
    decodeImageFromPixels(
      rgba,
      width,
      height,
      PixelFormat.rgba8888,
      (image) => completer.complete(image),
      rowBytes: width * 4,
    );
    return completer.future;
  }

  Future<List<Rect>> _extractOpaqueSpriteRects(
    dynamic atlas,
    int cols,
    int rows,
  ) async {
    final width = atlas.width as int;
    final height = atlas.height as int;
    final byteData = await atlas.toByteData(format: ImageByteFormat.rawRgba);
    if (byteData == null) {
      return List<Rect>.generate(
        cols * rows,
        (index) => _atlasCellRect(index, width, height, cols, rows),
        growable: false,
      );
    }

    final expectedBytes = width * height * 4;
    if (byteData.lengthInBytes < expectedBytes) {
      return List<Rect>.generate(
        cols * rows,
        (index) => _atlasCellRect(index, width, height, cols, rows),
        growable: false,
      );
    }

    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      expectedBytes,
    );
    final result = <Rect>[];
    for (var index = 0; index < cols * rows; index++) {
      final cell = _atlasCellRect(index, width, height, cols, rows);
      final left = cell.left.round();
      final top = cell.top.round();
      final right = cell.right.round();
      final bottom = cell.bottom.round();
      var minX = right;
      var minY = bottom;
      var maxX = left - 1;
      var maxY = top - 1;

      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final alphaIndex = (y * width + x) * 4 + 3;
          if (rgba[alphaIndex] <= 12) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }

      if (maxX < minX || maxY < minY) {
        result.add(cell);
        continue;
      }
      const padding = 2;
      result.add(Rect.fromLTRB(
        math.max(left, minX - padding).toDouble(),
        math.max(top, minY - padding).toDouble(),
        math.min(right, maxX + padding + 1).toDouble(),
        math.min(bottom, maxY + padding + 1).toDouble(),
      ));
    }
    return result;
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
    final movement = _sceneString(entity['movement'], 'blocked');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _sceneString(entity['name'], '场景对象'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'sprite ${_sceneInt(entity['sprite_index'])} · '
                '${_sceneInt(entity['width'], 1)}×${_sceneInt(entity['height'], 1)} 格 · '
                '${_sceneString(entity['facing'], 'S')} · $movement',
              ),
              const SizedBox(height: 6),
              Text(
                '坐标 x=${_sceneInt(entity['x'])}, y=${_sceneInt(entity['y'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSceneSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '探索设置',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameController,
                  enabled: !_loading,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (_loading) return;
                    Navigator.of(sheetContext).pop();
                    _generate();
                  },
                  decoration: const InputDecoration(
                    labelText: '场景名称',
                    hintText: '例如：萧家卧房 / 魔兽山脉营地 / 乌坦城坊市',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示碰撞 / 可移动区域'),
                  subtitle: const Text('调试角色、障碍与底部可移动范围'),
                  value: _showFootprints,
                  onChanged: (value) {
                    setState(() => _showFootprints = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 4),
                if (_statusText.isNotEmpty) ...<Widget>[
                  Text(_statusText, style: Theme.of(sheetContext).textTheme.bodySmall),
                  const SizedBox(height: 8),
                ],
                if (_error != null) ...<Widget>[
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_loading)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _cancelGeneration();
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('取消生成'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _generate();
                    },
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(_assetPackage == null ? '生成场景' : '重新生成'),
                  ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final package = _assetPackage;
    final images = _images;
    final hasScene = package != null && images != null;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (hasScene)
            _SceneAssetCanvas(
              assetPackage: package!,
              floorImage: images!.floor,
              atlasImage: images.atlas,
              stripImage: images.strip,
              spriteImages: images.sprites,
              playerImage: images.player,
              spriteRects: images.spriteRects,
              showFootprints: _showFootprints,
              onEntityTap: _handleEntityTap,
            )
          else
            ColoredBox(
              color: const Color(0xFF111315),
              child: Center(
                child: _loading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('正在生成场景…'),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _error ?? '点击右上角设置生成探索场景',
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),
          SafeArea(
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 12,
                  top: 8,
                  child: _GlassSceneButton(
                    tooltip: '返回',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 8,
                  child: _GlassSceneButton(
                    tooltip: '探索设置',
                    icon: _loading ? Icons.hourglass_top_rounded : Icons.settings_rounded,
                    onPressed: _openSceneSettings,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSceneButton extends StatelessWidget {
  const _GlassSceneButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x990C0E10),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _PreparedSceneAtlas {
  const _PreparedSceneAtlas({
    required this.image,
    required this.spriteRects,
  });

  final dynamic image;
  final List<Rect> spriteRects;
}

class _SceneSampledKeySpec {
  const _SceneSampledKeySpec({
    required this.enabled,
    required this.adaptiveBorderKey,
    required this.keyColor,
    required this.tolerance,
    required this.softTolerance,
    required this.defringe,
  });

  final bool enabled;
  final bool adaptiveBorderKey;
  final _SceneRgb keyColor;
  final double tolerance;
  final double softTolerance;
  final bool defringe;

  factory _SceneSampledKeySpec.fromSheet(JsonMap sheet) {
    final mode = _sceneString(sheet['background_mode']).toLowerCase();
    final sheetMode = _sceneString(sheet['mode']).toLowerCase();
    final keying = _sceneMap(sheet['keying']);
    final keyMode = _sceneString(keying['mode'], 'auto').toLowerCase();
    final newAdaptive =
        mode == 'border_flood_key' && keyMode == 'adaptive_border_flood';
    final legacyFixed = mode == 'fixed_flood_key' && keyMode == 'flood_fill';
    final legacySampled = mode == 'sampled_key';
    // Building strips always use adaptive border learning, including packages
    // generated by the immediately previous fixed-#FF00FF version. This means an
    // already-paid strip does not need to be regenerated just because Krea returned
    // pink instead of the literal requested hex.
    final adaptiveBorderKey = newAdaptive || (sheetMode == 'strip' && legacyFixed);
    final rawTolerance = _sceneNum(
      keying['tolerance'],
      adaptiveBorderKey ? 48 : 52,
    ).clamp(1, 255).toDouble();
    final tolerance = adaptiveBorderKey ? math.max(48.0, rawTolerance) : rawTolerance;
    final rawSoftTolerance = _sceneNum(
      keying['soft_tolerance'],
      adaptiveBorderKey ? 78 : tolerance * 1.35,
    ).clamp(tolerance + 1, 441).toDouble();
    final softTolerance = adaptiveBorderKey
        ? math.max(78.0, rawSoftTolerance)
        : rawSoftTolerance;
    return _SceneSampledKeySpec(
      enabled: adaptiveBorderKey || legacyFixed || legacySampled,
      adaptiveBorderKey: adaptiveBorderKey,
      keyColor: _parseSceneKeyColor(
        _sceneString(
          keying['key_color_hint'],
          _sceneString(keying['key_color'], '#FF00FF'),
        ),
      ),
      tolerance: tolerance,
      softTolerance: softTolerance,
      defringe: keying['defringe'] != false,
    );
  }
}

_SceneRgb _parseSceneKeyColor(String value) {
  final raw = value.trim().replaceFirst('#', '');
  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(raw)) {
    return _SceneRgb(
      int.parse(raw.substring(0, 2), radix: 16),
      int.parse(raw.substring(2, 4), radix: 16),
      int.parse(raw.substring(4, 6), radix: 16),
    );
  }
  return const _SceneRgb(255, 0, 255);
}

class _ScenePixelCell {
  const _ScenePixelCell(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;
}

class _SceneRgb {
  const _SceneRgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

class _LoadedSceneImages {
  _LoadedSceneImages({
    required this.floor,
    required this.atlas,
    required this.strip,
    required this.sprites,
    required this.player,
    required this.spriteRects,
  });

  final dynamic floor;
  final dynamic atlas;
  final dynamic strip;
  final List<dynamic> sprites;
  final dynamic player;
  final List<Rect> spriteRects;

  void dispose() {
    _disposeUiImage(floor);
    _disposeUiImage(atlas);
    _disposeUiImage(strip);
    for (final image in sprites) {
      _disposeUiImage(image);
    }
    _disposeUiImage(player);
  }
}

void _disposeUiImage(dynamic image) {
  if (image == null) return;
  try {
    image.dispose();
  } catch (_) {}
}

Rect _atlasCellRect(int index, int width, int height, int cols, int rows) {
  final row = index ~/ cols;
  final col = index % cols;
  final x0 = (col * width / cols).round();
  final x1 = ((col + 1) * width / cols).round();
  final y0 = (row * height / rows).round();
  final y1 = ((row + 1) * height / rows).round();
  return Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());
}

class _SceneAssetCanvas extends StatefulWidget {
  const _SceneAssetCanvas({
    required this.assetPackage,
    required this.floorImage,
    required this.atlasImage,
    required this.stripImage,
    required this.spriteImages,
    required this.playerImage,
    required this.spriteRects,
    required this.showFootprints,
    required this.onEntityTap,
  });

  final JsonMap assetPackage;
  final dynamic floorImage;
  final dynamic atlasImage;
  final dynamic stripImage;
  final List<dynamic> spriteImages;
  final dynamic playerImage;
  final List<Rect> spriteRects;
  final bool showFootprints;
  final ValueChanged<JsonMap> onEntityTap;

  @override
  State<_SceneAssetCanvas> createState() => _SceneAssetCanvasState();
}

class _SceneAssetCanvasState extends State<_SceneAssetCanvas> {
  static const double _playerRadius = .28;
  static const double _maxMoveSpeedPx = 180.0;

  Offset _player = Offset.zero;
  String _facing = 'S';
  String _moveHint = '左下摇杆移动 · WASD / 方向键移动 · 长按物件查看';
  double _walkPhase = 0.0;

  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  Offset _joystickIntent = Offset.zero;
  bool _joystickActive = false;
  Offset _velocityPx = Offset.zero;
  Timer? _motionTimer;
  DateTime? _lastMotionAt;

  @override
  void initState() {
    super.initState();
    _resetPlayer();
  }

  @override
  void didUpdateWidget(covariant _SceneAssetCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sceneString(oldWidget.assetPackage['scene_id']) !=
        _sceneString(widget.assetPackage['scene_id'])) {
      _resetPlayer();
    }
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    super.dispose();
  }

  JsonMap get _grid => _sceneMap(widget.assetPackage['grid']);

  List<JsonMap> get _objects => _sceneList(widget.assetPackage['objects'])
      .map(_sceneMap)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  int get _gridWidth => _sceneInt(_grid['width'], 32).clamp(1, 200).toInt();
  int get _gridHeight => _sceneInt(_grid['height'], 32).clamp(1, 200).toInt();

  void _resetPlayer() {
    _motionTimer?.cancel();
    _motionTimer = null;
    _lastMotionAt = null;
    _velocityPx = Offset.zero;
    _joystickIntent = Offset.zero;
    _joystickActive = false;
    _pressedKeys.clear();

    final spawn = _sceneMap(widget.assetPackage['player_spawn']);
    final x = _sceneNum(spawn['x'], _gridWidth / 2).floor();
    final y = _sceneNum(spawn['y'], _gridHeight / 2).floor();
    _facing = _normalizeFacing(_sceneString(spawn['facing'], 'S'));
    _player = _nearestWalkable(Offset(x + .5, y + .5));
    _moveHint = '出生点就绪 · 左下摇杆 / WASD / 方向键移动';
    _walkPhase = 0.0;
  }

  Offset _nearestWalkable(Offset point) {
    if (_canStand(point)) return point;
    for (var radius = 1; radius <= math.max(_gridWidth, _gridHeight); radius++) {
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx.abs() != radius && dy.abs() != radius) continue;
          final candidate = Offset(
            (point.dx.floor() + dx + .5),
            (point.dy.floor() + dy + .5),
          );
          if (_canStand(candidate)) return candidate;
        }
      }
    }
    return Offset(_gridWidth / 2, _gridHeight / 2);
  }

  bool _canStand(Offset point) {
    if (point.dx - _playerRadius < 0 ||
        point.dy - _playerRadius < 0 ||
        point.dx + _playerRadius > _gridWidth ||
        point.dy + _playerRadius > _gridHeight) {
      return false;
    }

    // Buildings are interaction zones only in strip mode; they never block movement.
    // Explicit walkable overlays also do not block the player.
    for (final object in _objects) {
      if (_sceneString(object['category']).toLowerCase() == 'building') continue;
      if (_sceneString(object['movement']).toLowerCase() != 'walkable') continue;
      final x = _sceneNum(object['x']);
      final y = _sceneNum(object['y']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final height = math.max(1.0, _sceneNum(object['height'], 1));
      if (point.dx - _playerRadius >= x &&
          point.dx + _playerRadius <= x + width &&
          point.dy - _playerRadius >= y &&
          point.dy + _playerRadius <= y + height) {
        return true;
      }
    }

    for (final object in _objects) {
      if (_sceneString(object['category']).toLowerCase() == 'building') continue;
      final movement = _sceneString(object['movement'], 'blocked').toLowerCase();
      if (movement == 'walkable') continue;
      if (movement != 'blocked' && movement != 'conditional') continue;
      final x = _sceneNum(object['x']);
      final y = _sceneNum(object['y']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final height = math.max(1.0, _sceneNum(object['height'], 1));
      final closestX = point.dx.clamp(x, x + width).toDouble();
      final closestY = point.dy.clamp(y, y + height).toDouble();
      final dx = point.dx - closestX;
      final dy = point.dy - closestY;
      if (dx * dx + dy * dy < _playerRadius * _playerRadius) return false;
    }
    return true;
  }

  Offset _axisAdvance(Offset start, double targetValue, bool xAxis) {
    final direct = xAxis
        ? Offset(targetValue, start.dy)
        : Offset(start.dx, targetValue);
    if (_canStand(direct)) return direct;
    if (!_canStand(start)) return start;

    final startValue = xAxis ? start.dx : start.dy;
    var lo = 0.0;
    var hi = 1.0;
    var best = start;
    for (var i = 0; i < 18; i++) {
      final t = (lo + hi) / 2;
      final value = startValue + (targetValue - startValue) * t;
      final candidate = xAxis ? Offset(value, start.dy) : Offset(start.dx, value);
      if (_canStand(candidate)) {
        lo = t;
        best = candidate;
      } else {
        hi = t;
      }
    }
    return best;
  }

  Offset _movePlayerTarget(Offset start, Offset target) {
    if (_canStand(target)) return target;

    Offset tryOrder(bool xFirst) {
      var p = start;
      if (xFirst) {
        p = _axisAdvance(p, target.dx, true);
        p = _axisAdvance(p, target.dy, false);
      } else {
        p = _axisAdvance(p, target.dy, false);
        p = _axisAdvance(p, target.dx, true);
      }
      return p;
    }

    final a = tryOrder(true);
    final b = tryOrder(false);
    return (a - target).distanceSquared <= (b - target).distanceSquared ? a : b;
  }

  Offset _normalized(Offset value) {
    final length = value.distance;
    if (length <= .0001) return Offset.zero;
    if (length <= 1) return value;
    return Offset(value.dx / length, value.dy / length);
  }

  bool _isMoveKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.keyW ||
      key == LogicalKeyboardKey.keyA ||
      key == LogicalKeyboardKey.keyS ||
      key == LogicalKeyboardKey.keyD ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  Offset _keyboardIntent() {
    var x = 0.0;
    var y = 0.0;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp)) y -= 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown)) y += 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) x -= 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD) ||
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight)) x += 1;
    return _normalized(Offset(x, y));
  }

  Offset _combinedMoveIntent() {
    final keyboard = _keyboardIntent();
    if (keyboard != Offset.zero) return keyboard;
    if (!_joystickActive) return Offset.zero;
    return _normalized(_joystickIntent);
  }

  void _ensureMotionLoop() {
    if (_motionTimer != null) return;
    _lastMotionAt = DateTime.now();
    _motionTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _motionTick());
  }

  void _stopMotionImmediately({bool repaint = true}) {
    final needsRepaint = _velocityPx != Offset.zero || _walkPhase != 0;
    _velocityPx = Offset.zero;
    _motionTimer?.cancel();
    _motionTimer = null;
    _lastMotionAt = null;
    if (repaint && needsRepaint && mounted) {
      setState(() {
        _walkPhase = 0;
        _moveHint = '左下摇杆移动 · WASD / 方向键移动 · 长按物件查看';
      });
    }
  }

  void _setJoystickActive(bool active) {
    _joystickActive = active;
    if (!active) {
      _joystickIntent = Offset.zero;
      if (_keyboardIntent() == Offset.zero) {
        _stopMotionImmediately();
      }
    }
  }

  void _setJoystickIntent(Offset value) {
    if (!_joystickActive) {
      _joystickIntent = Offset.zero;
      return;
    }
    _joystickIntent = _normalized(value);
    if (_joystickIntent.distance <= .03) {
      _joystickIntent = Offset.zero;
      if (_keyboardIntent() == Offset.zero) {
        _stopMotionImmediately();
      }
      return;
    }
    _ensureMotionLoop();
  }

  void _clearKeyboardMovement() {
    if (_pressedKeys.isEmpty) return;
    _pressedKeys.clear();
    if (!_joystickActive || _joystickIntent.distance <= .03) {
      _stopMotionImmediately();
    }
  }

  _IsoMetrics _sceneMetrics() => _IsoMetrics.forScene(
        _gridWidth,
        _gridHeight,
        _sceneMap(widget.assetPackage['floor']),
      );

  void _motionTick() {
    if (!mounted) {
      _motionTimer?.cancel();
      _motionTimer = null;
      return;
    }

    // Do not trust a stale joystick vector. Continuous movement is permitted only
    // while a pointer is actively held on the joystick or a movement key is down.
    if (_keyboardIntent() == Offset.zero && !_joystickActive) {
      _joystickIntent = Offset.zero;
      _stopMotionImmediately();
      return;
    }

    final now = DateTime.now();
    final last = _lastMotionAt ?? now;
    _lastMotionAt = now;
    final dt = math.min(.035, math.max(.001, now.difference(last).inMicroseconds / 1000000));

    var intent = _combinedMoveIntent();
    final hasInput = intent.distance > .03;
    intent = _normalized(intent);

    // Hard input movement only: no acceleration, no deceleration and no coasting.
    // Releasing joystick/keyboard means zero movement immediately.
    if (!hasInput) {
      _stopMotionImmediately();
      return;
    }

    var vx = intent.dx * _maxMoveSpeedPx;
    var vy = intent.dy * _maxMoveSpeedPx;

    var nextPlayer = _player;
    var travelledPx = 0.0;
    final totalDelta = Offset(vx * dt, vy * dt);
    final steps = math.max(1, (totalDelta.distance / 7).ceil());
    final step = Offset(totalDelta.dx / steps, totalDelta.dy / steps);
    final metrics = _sceneMetrics();

    for (var i = 0; i < steps; i++) {
      final before = metrics.project(nextPlayer.dx, nextPlayer.dy);
      final logicalTarget = metrics.unproject(before + step);
      final moved = _movePlayerTarget(nextPlayer, logicalTarget);
      final after = metrics.project(moved.dx, moved.dy);
      final actual = after - before;
      travelledPx += actual.distance;

      // Same behavior as the HTML: when one component is blocked, damp only that
      // component and keep the other so the player naturally slides along furniture.
      if (step.dx.abs() > .2 && actual.dx.abs() < step.dx.abs() * .28) vx *= .35;
      if (step.dy.abs() > .2 && actual.dy.abs() < step.dy.abs() * .28) vy *= .35;
      nextPlayer = moved;
    }

    final movedDistance = (nextPlayer - _player).distance;
    var nextFacing = _facing;
    if (hasInput) {
      if (intent.dx.abs() > .08) {
        nextFacing = intent.dx < 0 ? 'W' : 'E';
      } else if (intent.dy.abs() > .08) {
        nextFacing = intent.dy < 0 ? 'N' : 'S';
      }
    }

    if (movedDistance > .0001 || _velocityPx.dx != vx || _velocityPx.dy != vy) {
      setState(() {
        _player = nextPlayer;
        _velocityPx = Offset(vx, vy);
        _facing = nextFacing;
        if (movedDistance > .001 && travelledPx > .05) {
          // About 1.2-1.4 gentle vertical cycles/sec at normal top speed.
          _walkPhase = (_walkPhase + travelledPx * .045) % (math.pi * 2);
        }
        _moveHint = '摇杆 / WASD 连续移动 · 松开立即停止';
      });
    } else {
      _velocityPx = Offset(vx, vy);
    }

  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (!_isMoveKey(key)) return KeyEventResult.ignored;

    if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
      if (_combinedMoveIntent().distance <= .03) {
        _stopMotionImmediately();
      } else {
        _ensureMotionLoop();
      }
    } else if (event is KeyDownEvent) {
      _pressedKeys.add(key);
      _ensureMotionLoop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  JsonMap? _nearbyBuilding() {
    JsonMap? nearest;
    var bestScore = double.infinity;

    // The building row touches logical y=0. Only reveal a name when the player
    // is genuinely close to the rear edge, not from the middle of the street.
    if (_player.dy > 7.0) return null;

    for (final object in _objects) {
      if (_sceneString(object['category']).toLowerCase() != 'building') continue;
      if (object['interactive'] == false) continue;

      final x = _sceneNum(object['x']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final radius = _sceneNum(object['interaction_radius_tiles'], 2.0)
          .clamp(.5, 5.0)
          .toDouble();

      final horizontalGap = _player.dx < x
          ? x - _player.dx
          : _player.dx > x + width
              ? _player.dx - (x + width)
              : 0.0;
      if (horizontalGap > radius) continue;

      final score = _player.dy + horizontalGap * 2.0;
      if (score < bestScore) {
        bestScore = score;
        nearest = object;
      }
    }
    return nearest;
  }

  void _handleLongPress(Offset localPosition, _IsoMetrics metrics) {
    final logical = metrics.unproject(localPosition);
    final object = _hitSceneObject(_objects, logical);
    if (object != null) {
      widget.onEntityTap(<String, dynamic>{...object, 'kind': 'scene_object'});
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _sceneMetrics();
    final objects = _objects;
    final floorSpec = _sceneMap(widget.assetPackage['floor']);
    final nearbyBuilding = _nearbyBuilding();
    final nearbyBuildingName = nearbyBuilding == null
        ? ''
        : _sceneString(
            nearbyBuilding['display_name'],
            _sceneString(nearbyBuilding['name']),
          );

    return ColoredBox(
      color: const Color(0xFF111315),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Focus(
              autofocus: true,
              onFocusChange: (hasFocus) {
                if (!hasFocus) _clearKeyboardMovement();
              },
              onKeyEvent: _handleKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final world = metrics.canvasSize;

                  // Follow camera: only part of the 1536x864 world is visible.
                  // Bottom spawn starts with the upper scene hidden; walking upward
                  // physically moves the camera upward and reveals the scene top.
                  final coverScale = math.max(
                    viewport.width / world.width,
                    viewport.height / world.height,
                  );
                  final cameraScale = coverScale * 1.34;

                  final playerOnWorld = metrics.project(_player.dx, _player.dy);
                  final scaledWidth = world.width * cameraScale;
                  final scaledHeight = world.height * cameraScale;
                  final desiredX = viewport.width * .50 -
                      playerOnWorld.dx * cameraScale;
                  final desiredY = viewport.height * .94 -
                      playerOnWorld.dy * cameraScale;

                  double clampCameraAxis(
                    double desired,
                    double scaledExtent,
                    double viewportExtent,
                  ) {
                    if (scaledExtent <= viewportExtent) {
                      return (viewportExtent - scaledExtent) / 2;
                    }
                    return desired
                        .clamp(viewportExtent - scaledExtent, 0.0)
                        .toDouble();
                  }

                  final cameraOffset = Offset(
                    clampCameraAxis(desiredX, scaledWidth, viewport.width),
                    clampCameraAxis(desiredY, scaledHeight, viewport.height),
                  );

                  return ClipRect(
                    child: Transform.translate(
                      offset: cameraOffset,
                      child: Transform.scale(
                        scale: cameraScale,
                        alignment: Alignment.topLeft,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart: (details) => _handleLongPress(
                            details.localPosition,
                            metrics,
                          ),
                          child: SizedBox(
                            width: world.width,
                            height: world.height,
                            child: CustomPaint(
                              painter: _SceneAssetPainter(
                                gridWidth: _gridWidth,
                                gridHeight: _gridHeight,
                                objects: objects,
                                floorImage: widget.floorImage,
                                floorSpec: floorSpec,
                                atlasImage: widget.atlasImage,
                                stripImage: widget.stripImage,
                                spriteImages: widget.spriteImages,
                                playerImage: widget.playerImage,
                                spriteRects: widget.spriteRects,
                                player: _player,
                                facing: _facing,
                                metrics: metrics,
                                showFootprints: widget.showFootprints,
                                walkPhase: _walkPhase,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (nearbyBuildingName.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 34 + MediaQuery.paddingOf(context).bottom,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xB814171A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x55FFFFFF)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        nearbyBuildingName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 18,
            bottom: 18 + MediaQuery.paddingOf(context).bottom,
            child: _ExplorationJoystick(
              onChanged: _setJoystickIntent,
              onActiveChanged: _setJoystickActive,
            ),
          ),
        ],
      ),
    );
  }

}

class _ExplorationJoystick extends StatefulWidget {
  const _ExplorationJoystick({
    required this.onChanged,
    required this.onActiveChanged,
  });

  final ValueChanged<Offset> onChanged;
  final ValueChanged<bool> onActiveChanged;

  @override
  State<_ExplorationJoystick> createState() => _ExplorationJoystickState();
}

class _ExplorationJoystickState extends State<_ExplorationJoystick> {
  static const double _size = 116;
  static const double _travelRadius = 38;
  Offset _value = Offset.zero;
  int? _activePointer;

  void _activate(int pointer) {
    _activePointer = pointer;
    widget.onActiveChanged(true);
  }

  void _update(Offset localPosition) {
    const center = Offset(_size / 2, _size / 2);
    final delta = localPosition - center;
    final distance = delta.distance;
    final clamped = distance <= _travelRadius || distance == 0
        ? delta
        : Offset(
            delta.dx / distance * _travelRadius,
            delta.dy / distance * _travelRadius,
          );
    final value = Offset(
      clamped.dx / _travelRadius,
      clamped.dy / _travelRadius,
    );
    if (mounted) setState(() => _value = value);
    widget.onChanged(value);
  }

  void _release([int? pointer]) {
    if (pointer != null && _activePointer != null && pointer != _activePointer) return;
    _activePointer = null;
    if (mounted && _value != Offset.zero) {
      setState(() => _value = Offset.zero);
    } else {
      _value = Offset.zero;
    }
    // Always send both signals. Never skip a release just because the local knob
    // already looks centered; the parent may still have a stale non-zero vector.
    widget.onChanged(Offset.zero);
    widget.onActiveChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _activate(event.pointer),
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _update(details.localPosition),
        onPanUpdate: (details) => _update(details.localPosition),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: CustomPaint(
          size: const Size.square(_size),
          painter: _ExplorationJoystickPainter(_value),
        ),
      ),
    );
  }
}

class _ExplorationJoystickPainter extends CustomPainter {
  const _ExplorationJoystickPainter(this.value);

  final Offset value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * .43;
    const travel = 38.0;
    final knobCenter = center + Offset(value.dx * travel, value.dy * travel);

    canvas.drawCircle(center, baseRadius, Paint()..color = const Color(0x661A1D20));
    canvas.drawCircle(
      center,
      baseRadius,
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(knobCenter, 23, Paint()..color = const Color(0xCCF2F2F2));
    canvas.drawCircle(
      knobCenter,
      23,
      Paint()
        ..color = const Color(0xAA111315)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _ExplorationJoystickPainter oldDelegate) =>
      oldDelegate.value != value;
}

class _IsoMetrics {
  const _IsoMetrics({
    required this.tileWidth,
    required this.tileHeight,
    required this.origin,
    required this.canvasSize,
    required this.groundWidth,
    required this.groundHeight,
    required this.gridWidth,
    required this.gridHeight,
    required this.sideScroll,
    required this.walkRect,
  });

  final double tileWidth;
  final double tileHeight;
  final Offset origin;
  final Size canvasSize;
  final double groundWidth;
  final double groundHeight;
  final int gridWidth;
  final int gridHeight;
  final bool sideScroll;
  final Rect walkRect;

  factory _IsoMetrics.forScene(
    int gridWidth,
    int gridHeight,
    JsonMap floorSpec,
  ) {
    final mode = _sceneString(floorSpec['mode']).toLowerCase();
    if (mode == 'side_scroll_backdrop') {
      final stage = _sceneMap(floorSpec['stage']);
      final designWidth = _sceneNum(stage['design_width'], 1536)
          .clamp(640.0, 4096.0)
          .toDouble();
      final designHeight = _sceneNum(stage['design_height'], 864)
          .clamp(360.0, 2160.0)
          .toDouble();
      // Current side-scroll tuning: the walk band is the bottom ~25% and spans
      // the full width. Keep this client-side floor so older asset packages also
      // immediately use the lower layout without requiring paid regeneration.
      const left = 0.0;
      const right = 1.0;
      const top = .75;
      const bottom = 1.0;
      final walkRect = Rect.fromLTRB(
        designWidth * left,
        designHeight * top,
        designWidth * right,
        designHeight * bottom,
      );
      return _IsoMetrics(
        tileWidth: walkRect.width / math.max(1, gridWidth),
        tileHeight: walkRect.height / math.max(1, gridHeight),
        origin: walkRect.topLeft,
        canvasSize: Size(designWidth, designHeight),
        groundWidth: walkRect.width,
        groundHeight: walkRect.height,
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        sideScroll: true,
        walkRect: walkRect,
      );
    }
    return _IsoMetrics.forGrid(gridWidth, gridHeight);
  }

  factory _IsoMetrics.forGrid(int gridWidth, int gridHeight) {
    const tileWidth = 34.0;
    const tileHeight = 17.0;
    const sideMargin = 150.0;
    const topMargin = 230.0;
    const bottomMargin = 150.0;
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
      groundWidth: groundWidth,
      groundHeight: groundHeight,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      sideScroll: false,
      walkRect: Rect.zero,
    );
  }

  Offset project(double x, double y, [double z = 0]) {
    if (sideScroll) {
      final safeGridWidth = math.max(1, gridWidth).toDouble();
      final safeGridHeight = math.max(1, gridHeight).toDouble();
      return Offset(
        walkRect.left + x / safeGridWidth * walkRect.width,
        walkRect.top + y / safeGridHeight * walkRect.height - z * tileWidth,
      );
    }
    return Offset(
      origin.dx + (x - y) * tileWidth / 2,
      origin.dy + (x + y) * tileHeight / 2 - z * tileHeight,
    );
  }

  Offset unproject(Offset point) {
    if (sideScroll) {
      final x = (point.dx - walkRect.left) / walkRect.width * gridWidth;
      final y = (point.dy - walkRect.top) / walkRect.height * gridHeight;
      return Offset(x, y);
    }
    final dx = (point.dx - origin.dx) / (tileWidth / 2);
    final dy = (point.dy - origin.dy) / (tileHeight / 2);
    return Offset((dx + dy) / 2, (dy - dx) / 2);
  }
}
class _SceneAssetPainter extends CustomPainter {
  _SceneAssetPainter({
    required this.gridWidth,
    required this.gridHeight,
    required this.objects,
    required this.floorImage,
    required this.floorSpec,
    required this.atlasImage,
    required this.stripImage,
    required this.spriteImages,
    required this.playerImage,
    required this.spriteRects,
    required this.player,
    required this.facing,
    required this.metrics,
    required this.showFootprints,
    required this.walkPhase,
  });

  final int gridWidth;
  final int gridHeight;
  final List<JsonMap> objects;
  final dynamic floorImage;
  final JsonMap floorSpec;
  final dynamic atlasImage;
  final dynamic stripImage;
  final List<dynamic> spriteImages;
  final dynamic playerImage;
  final List<Rect> spriteRects;
  final Offset player;
  final String facing;
  final _IsoMetrics metrics;
  final bool showFootprints;
  final double walkPhase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111315));
    final floorMode = _sceneString(floorSpec['mode'], 'material_texture').toLowerCase();
    if (floorMode == 'side_scroll_backdrop') {
      _drawSideScrollBackdrop(canvas);
    } else if (floorMode == 'room_surface_atlas') {
      _drawRoomSurfaceAtlas(canvas);
    } else if (floorMode == 'room_shell') {
      // Legacy compatibility for the first room-shell experiment.
      _drawRoomShell(canvas);
    } else {
      // Backward compatibility for older asset packages that still contain a
      // flat top-down material texture.
      _drawGround(canvas);
    }
    if (showFootprints) _drawFootprints(canvas);
    _drawDepthSortedEntities(canvas);
  }

  Path _groundPath() {
    return Path()
      ..moveTo(metrics.project(0, 0).dx, metrics.project(0, 0).dy)
      ..lineTo(metrics.project(gridWidth.toDouble(), 0).dx,
          metrics.project(gridWidth.toDouble(), 0).dy)
      ..lineTo(metrics.project(gridWidth.toDouble(), gridHeight.toDouble()).dx,
          metrics.project(gridWidth.toDouble(), gridHeight.toDouble()).dy)
      ..lineTo(metrics.project(0, gridHeight.toDouble()).dx,
          metrics.project(0, gridHeight.toDouble()).dy)
      ..close();
  }

  void _drawSideScrollBackdrop(Canvas canvas) {
    final fullRect = Rect.fromLTWH(
      0,
      0,
      metrics.canvasSize.width,
      metrics.canvasSize.height,
    );
    final stage = _sceneMap(floorSpec['stage']);
    final sourceSheetMode = _sceneString(
      stage['source_sheet_mode'],
      _sceneString(floorSpec['source_sheet_mode']),
    ).toLowerCase();
    final usesStackedSourceSheet =
        sourceSheetMode == 'stacked_background_ground';
    final usesFullSceneComposite =
        sourceSheetMode == 'full_scene_composite' ||
        _sceneString(floorSpec['render_mode']).toLowerCase() == 'full_scene_plate';

    if (floorImage == null) {
      canvas.drawRect(fullRect, Paint()..color = const Color(0xFF20262C));
    } else if (usesStackedSourceSheet) {
      // New packages contain one paid source image with two deterministic panels:
      // top 75% = scenic background, bottom 25% = matching ground material.
      // Crop them independently so gameplay geometry never depends on whether the
      // image model happened to draw a straight roadside inside a finished scene.
      final imageWidth = (floorImage.width as int).toDouble();
      final imageHeight = (floorImage.height as int).toDouble();
      final backgroundTop = _sceneNum(
        stage['source_background_top_ratio'],
        0.0,
      ).clamp(0.0, 1.0).toDouble();
      final backgroundBottom = _sceneNum(
        stage['source_background_bottom_ratio'],
        .75,
      ).clamp(backgroundTop, 1.0).toDouble();
      final groundTop = _sceneNum(
        stage['source_ground_top_ratio'],
        .75,
      ).clamp(0.0, 1.0).toDouble();
      final groundBottom = _sceneNum(
        stage['source_ground_bottom_ratio'],
        1.0,
      ).clamp(groundTop, 1.0).toDouble();

      final backgroundSource = Rect.fromLTRB(
        0,
        imageHeight * backgroundTop,
        imageWidth,
        imageHeight * backgroundBottom,
      );
      final groundSource = Rect.fromLTRB(
        0,
        imageHeight * groundTop,
        imageWidth,
        imageHeight * groundBottom,
      );
      final backgroundDest = Rect.fromLTRB(
        fullRect.left,
        fullRect.top,
        fullRect.right,
        metrics.walkRect.top,
      );
      final groundDest = Rect.fromLTRB(
        fullRect.left,
        metrics.walkRect.top,
        fullRect.right,
        metrics.walkRect.bottom,
      );
      final imagePaint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        floorImage,
        backgroundSource,
        backgroundDest,
        imagePaint,
      );
      canvas.drawImageRect(
        floorImage,
        groundSource,
        groundDest,
        imagePaint,
      );
    } else if (usesFullSceneComposite) {
      // Full-scene mode: the generator already painted background + ground +
      // scene-defining modules into one coherent gameplay plate. Do not cover
      // the lower band with programmatic ground again.
      final sourceRect = Rect.fromLTWH(
        0,
        0,
        (floorImage.width as int).toDouble(),
        (floorImage.height as int).toDouble(),
      );
      canvas.drawImageRect(
        floorImage,
        sourceRect,
        fullRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      // Legacy packages were generated as one finished backdrop. Preserve their
      // existing behavior and cover the lower gameplay band programmatically.
      final sourceRect = Rect.fromLTWH(
        0,
        0,
        (floorImage.width as int).toDouble(),
        (floorImage.height as int).toDouble(),
      );
      canvas.drawImageRect(
        floorImage,
        sourceRect,
        fullRect,
        Paint()..filterQuality = FilterQuality.high,
      );
      final groundMaterial = _sceneString(
        floorSpec['ground_material'],
        _sceneString(floorSpec['material'], 'stone paving'),
      );
      _drawProgrammaticGround(canvas, metrics.walkRect, groundMaterial);
    }

    _drawMidgroundStrip(canvas, fullRect);

    if (showFootprints) {
      canvas.drawRect(
        metrics.walkRect,
        Paint()
          ..color = const Color(0x18FFFFFF)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        metrics.walkRect,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  void _drawMidgroundStrip(Canvas canvas, Rect fullRect) {
    if (stripImage == null) return;
    final stage = _sceneMap(floorSpec['stage']);
    final heightRatio = _sceneNum(stage['midground_strip_height_ratio'], 512 / 864)
        .clamp(.10, .80)
        .toDouble();
    final baselineRatio = math.max(
      .75,
      _sceneNum(stage['midground_strip_baseline_ratio'], .75),
    ).clamp(.20, .95).toDouble();
    final topRatio = _sceneNum(
      stage['midground_strip_top_ratio'],
      baselineRatio - heightRatio,
    ).clamp(0.0, baselineRatio).toDouble();
    final destHeight = fullRect.height * heightRatio;
    final seamOverlapPx = (fullRect.height * .0025).clamp(1.0, 3.0).toDouble();
    final baselineY = fullRect.height * baselineRatio;
    final destBottom = (baselineY + seamOverlapPx)
        .clamp(destHeight * .35, fullRect.height)
        .toDouble();
    final dest = Rect.fromLTWH(
      0,
      math.max(0.0, destBottom - destHeight),
      fullRect.width,
      destHeight,
    );

    // LLM strips sometimes carry a 1-3 px dark baseline at the very bottom edge.
    // Trim it away, then sink the strip by a tiny overlap so the module bases blend
    // into the walkable ground instead of reading as a hard black seam.
    final sourceWidth = (stripImage.width as int).toDouble();
    final sourceHeight = (stripImage.height as int).toDouble();
    final sourceTopRatio = _sceneNum(
      stage['midground_strip_source_top_ratio'],
      0.0,
    ).clamp(0.0, .95).toDouble();
    final sourceBottomRatio = _sceneNum(
      stage['midground_strip_source_bottom_ratio'],
      1.0,
    ).clamp(sourceTopRatio + .01, 1.0).toDouble();
    final sourceTop = sourceHeight * sourceTopRatio;
    final sourceBottom = sourceHeight * sourceBottomRatio;
    final activeSourceHeight = math.max(1.0, sourceBottom - sourceTop).toDouble();
    final trimBottomPx = math.min(3.0, activeSourceHeight * .012).toDouble();
    final source = Rect.fromLTWH(
      0,
      sourceTop,
      sourceWidth,
      math.max(1.0, activeSourceHeight - trimBottomPx),
    );

    canvas.drawImageRect(
      stripImage,
      source,
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _drawProgrammaticGround(Canvas canvas, Rect rect, String material) {
    if (rect.isEmpty) return;
    final lower = material.toLowerCase();

    final isWood = lower.contains('wood') || lower.contains('timber') ||
        lower.contains('plank') || lower.contains('board');
    final isGrass = lower.contains('grass') || lower.contains('moss') ||
        lower.contains('meadow');
    final isSand = lower.contains('sand') || lower.contains('desert') ||
        lower.contains('dune');
    final isSnow = lower.contains('snow') || lower.contains('ice') ||
        lower.contains('frost');
    final isMud = lower.contains('mud') || lower.contains('muddy') ||
        lower.contains('marsh');
    final isDirt = lower.contains('earth') || lower.contains('dirt') ||
        lower.contains('soil') || lower.contains('dust');
    final isBrick = lower.contains('brick') || lower.contains('terracotta') ||
        lower.contains('tile');
    final isAsh = lower.contains('ash') || lower.contains('charcoal') ||
        lower.contains('volcanic');
    final isRock = lower.contains('rock') || lower.contains('slate') ||
        lower.contains('cliff');
    final isWet = lower.contains('wet') || lower.contains('rain') ||
        lower.contains('damp') || lower.contains('puddle');

    Color top;
    Color bottom;
    Color seam;
    if (isWood) {
      top = const Color(0xFF765E47);
      bottom = const Color(0xFF49392E);
      seam = const Color(0x6631231B);
    } else if (isGrass) {
      top = const Color(0xFF657457);
      bottom = const Color(0xFF43503B);
      seam = const Color(0x66374531);
    } else if (isSand) {
      top = const Color(0xFFC7AD7D);
      bottom = const Color(0xFF947B58);
      seam = const Color(0x665D4C37);
    } else if (isSnow) {
      top = const Color(0xFFDDE4E5);
      bottom = const Color(0xFFABB9BE);
      seam = const Color(0x554F626B);
    } else if (isMud) {
      top = const Color(0xFF685541);
      bottom = const Color(0xFF41362D);
      seam = const Color(0x66342822);
    } else if (isDirt) {
      top = const Color(0xFF89735A);
      bottom = const Color(0xFF594A3B);
      seam = const Color(0x6642342A);
    } else if (isBrick) {
      top = const Color(0xFF8C6757);
      bottom = const Color(0xFF624A40);
      seam = const Color(0x66513A32);
    } else if (isAsh) {
      top = const Color(0xFF77736C);
      bottom = const Color(0xFF4C4A46);
      seam = const Color(0x6652524D);
    } else if (isRock) {
      top = const Color(0xFF77736B);
      bottom = const Color(0xFF514F4B);
      seam = const Color(0x66504D48);
    } else if (isWet) {
      top = const Color(0xFF666B69);
      bottom = const Color(0xFF454A48);
      seam = const Color(0x66505351);
    } else {
      // Default stone / paving family. The planner already supplies the ground
      // material phrase, so this fallback is only for older packages.
      top = const Color(0xFF85847C);
      bottom = const Color(0xFF595B57);
      seam = const Color(0x66505250);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, bottom],
        ).createShader(rect),
    );

    // A straight seam is the gameplay contract. It is always horizontal even if
    // the generated backdrop contains a diagonal road, stairs, or perspective path.
    final seamBand = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      math.min(14.0, rect.height * .08),
    );
    canvas.drawRect(
      seamBand,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            seam.withOpacity(.62),
            seam.withOpacity(.08),
          ],
        ).createShader(seamBand),
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Paint()
        ..color = seam.withOpacity(.78)
        ..strokeWidth = 1.4,
    );

    if (isWood) {
      final line = Paint()
        ..color = seam
        ..strokeWidth = 1.0;
      const rows = 10;
      for (var row = 0; row <= rows; row++) {
        final y = rect.top + rect.height * row / rows;
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
      }
      const cols = 18;
      for (var col = 0; col <= cols; col++) {
        final x = rect.left + rect.width * col / cols;
        canvas.drawLine(
          Offset(x, rect.top),
          Offset(x, rect.bottom),
          Paint()
            ..color = seam.withOpacity(.48)
            ..strokeWidth = .7,
        );
      }
      for (var i = 0; i < 32; i++) {
        final fx = ((i * 37) % 101) / 101.0;
        final fy = ((i * 61) % 97) / 97.0;
        final y = rect.top + fy * rect.height;
        final x = rect.left + fx * rect.width;
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(rect.right, x + 24 + (i % 5) * 6), y),
          Paint()
            ..color = const Color(0x1AFFFFFF)
            ..strokeWidth = .8,
        );
      }
      return;
    }

    if (isBrick) {
      final line = Paint()
        ..color = seam
        ..strokeWidth = .9;
      const rows = 8;
      for (var row = 0; row <= rows; row++) {
        final y = rect.top + rect.height * row / rows;
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
        if (row == rows) continue;
        final nextY = rect.top + rect.height * (row + 1) / rows;
        const brickWidth = 104.0;
        final shift = row.isOdd ? brickWidth * .5 : 0.0;
        for (double x = rect.left - shift; x < rect.right; x += brickWidth) {
          canvas.drawLine(Offset(x, y), Offset(x, nextY), line);
        }
      }
      return;
    }

    if (isDirt || isMud || isSand || isGrass || isAsh || isSnow) {
      final speck = Paint()..color = seam.withOpacity(isSnow ? .28 : .52);
      for (var i = 0; i < 118; i++) {
        final fx = ((i * 47) % 131) / 131.0;
        final fy = ((i * 73) % 127) / 127.0;
        final p = Offset(rect.left + fx * rect.width, rect.top + fy * rect.height);
        final radius = isSnow ? .55 + (i % 2) * .35 : .65 + (i % 4) * .28;
        canvas.drawCircle(p, radius, speck);
      }

      if (isGrass) {
        final blade = Paint()
          ..color = const Color(0x4436432E)
          ..strokeWidth = .8;
        for (var i = 0; i < 54; i++) {
          final fx = ((i * 29) % 109) / 109.0;
          final fy = ((i * 67) % 103) / 103.0;
          final x = rect.left + fx * rect.width;
          final y = rect.top + fy * rect.height;
          canvas.drawLine(Offset(x, y), Offset(x + (i.isOdd ? 2 : -2), y - 4), blade);
        }
      }

      if (isMud) {
        final puddle = Paint()..color = const Color(0x223B4442);
        for (var i = 0; i < 7; i++) {
          final cx = rect.left + rect.width * (((i * 31) % 89) / 89.0);
          final cy = rect.top + rect.height * (.28 + (((i * 53) % 61) / 61.0) * .62);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: 42 + (i % 3) * 18,
              height: 7 + (i % 2) * 3,
            ),
            puddle,
          );
        }
      }
      return;
    }

    // Stone / rock / wet paving: straight horizontal rows with staggered joints.
    // The top road edge remains horizontal; only the material pattern changes.
    final line = Paint()
      ..color = seam
      ..strokeWidth = .9;
    const rows = 7;
    for (var row = 0; row <= rows; row++) {
      final y = rect.top + rect.height * row / rows;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
      if (row == rows) continue;
      final nextY = rect.top + rect.height * (row + 1) / rows;
      final cellWidth = isRock ? 142.0 : 116.0 + (row % 3) * 13.0;
      final shift = row.isOdd ? cellWidth * .45 : 0.0;
      for (double x = rect.left - shift; x < rect.right; x += cellWidth) {
        canvas.drawLine(Offset(x, y), Offset(x, nextY), line);
      }
    }

    if (isWet) {
      final sheen = Paint()..color = const Color(0x1FFFFFFF);
      for (var i = 0; i < 10; i++) {
        final x = rect.left + rect.width * (((i * 41) % 97) / 97.0);
        final y = rect.top + rect.height * (.22 + (((i * 59) % 71) / 71.0) * .70);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, y),
            width: 34 + (i % 4) * 16,
            height: 4 + (i % 2) * 2,
          ),
          sheen,
        );
      }
    }
  }

  void _drawPanelToParallelogram(
    Canvas canvas,
    dynamic image,
    Rect source,
    Offset p0,
    Offset p1,
    Offset p3,
  ) {
    if (source.width <= 0 || source.height <= 0) return;
    final a = (p1.dx - p0.dx) / source.width;
    final b = (p1.dy - p0.dy) / source.width;
    final c = (p3.dx - p0.dx) / source.height;
    final d = (p3.dy - p0.dy) / source.height;
    final matrix = Float64List.fromList(<double>[
      a, b, 0, 0,
      c, d, 0, 0,
      0, 0, 1, 0,
      p0.dx, p0.dy, 0, 1,
    ]);
    canvas.save();
    canvas.transform(matrix);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, source.width, source.height),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  void _drawRoomSurfaceAtlas(Canvas canvas) {
    final ground = _groundPath();
    if (floorImage == null) {
      canvas.drawPath(ground, Paint()..color = const Color(0xFF4A4740));
      return;
    }

    final surface = _sceneMap(floorSpec['surface_atlas']);
    final cols = _sceneInt(surface['cols'], 3).clamp(1, 8).toInt();
    final rows = _sceneInt(surface['rows'], 1).clamp(1, 8).toInt();
    final floorCell = _sceneInt(surface['floor_cell'], 0).clamp(0, cols * rows - 1).toInt();
    final leftCell = _sceneInt(surface['back_left_wall_cell'], 1).clamp(0, cols * rows - 1).toInt();
    final rightCell = _sceneInt(surface['back_right_wall_cell'], 2).clamp(0, cols * rows - 1).toInt();
    final wallHeight = _sceneNum(surface['wall_height_px'], 190)
        .clamp(80.0, metrics.origin.dy - 12.0)
        .toDouble();

    final imageWidth = (floorImage.width as int);
    final imageHeight = (floorImage.height as int);
    Rect cellRect(int index) => _atlasCellRect(index, imageWidth, imageHeight, cols, rows);

    final top = metrics.project(0, 0);
    final right = metrics.project(gridWidth.toDouble(), 0);
    final left = metrics.project(0, gridHeight.toDouble());
    final topUp = top - Offset(0, wallHeight);
    final rightUp = right - Offset(0, wallHeight);
    final leftUp = left - Offset(0, wallHeight);

    // Geometry is program-owned. The wall base edges are exactly the same two
    // rear edges of the logical 32x32 ground diamond used by collision.
    _drawPanelToParallelogram(
      canvas, floorImage, cellRect(leftCell), topUp, leftUp, top,
    );
    _drawPanelToParallelogram(
      canvas, floorImage, cellRect(rightCell), topUp, rightUp, top,
    );
    _drawPanelToParallelogram(
      canvas, floorImage, cellRect(floorCell), top, right, left,
    );

    // A subtle structural seam makes the generated materials read as one room
    // without changing the collision geometry.
    final seam = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawLine(top, left, seam);
    canvas.drawLine(top, right, seam);
    canvas.drawLine(topUp, leftUp, seam);
    canvas.drawLine(topUp, rightUp, seam);
    canvas.drawLine(topUp, top, seam);

    if (showFootprints) {
      canvas.drawPath(
        ground,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawRoomShell(Canvas canvas) {
    final ground = _groundPath();
    if (floorImage == null) {
      // Keep the logical floor usable even if the room-shell image is absent.
      canvas.drawPath(ground, Paint()..color = const Color(0xFF4A4740));
      return;
    }

    final sourceWidth = (floorImage.width as int).toDouble();
    final sourceHeight = (floorImage.height as int).toDouble();
    final destination = Offset.zero & metrics.canvasSize;

    // Legacy room_shell assets were already rendered in the final 2.5D camera.
    // New assets use room_surface_atlas instead so visual floor edges are owned
    // by the same programmatic geometry as collision.
    canvas.drawImageRect(
      floorImage,
      Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );

    // The collision/debug floor is still the programmatic 32x32 diamond.
    // Show its boundary only in debug mode so the room-shell art stays clean.
    if (showFootprints) {
      canvas.drawPath(
        ground,
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawGround(Canvas canvas) {
    final ground = _groundPath();
    if (floorImage == null) {
      canvas.drawPath(ground, Paint()..color = const Color(0xFF4A4740));
    } else {
      final sourceWidth = (floorImage.width as int).toDouble();
      final sourceHeight = (floorImage.height as int).toDouble();
      final top = metrics.project(0, 0);
      final xEnd = metrics.project(gridWidth.toDouble(), 0);
      final yEnd = metrics.project(0, gridHeight.toDouble());
      final a = (xEnd.dx - top.dx) / sourceWidth;
      final b = (xEnd.dy - top.dy) / sourceWidth;
      final c = (yEnd.dx - top.dx) / sourceHeight;
      final d = (yEnd.dy - top.dy) / sourceHeight;
      final matrix = Float64List.fromList(<double>[
        a, b, 0, 0,
        c, d, 0, 0,
        0, 0, 1, 0,
        top.dx, top.dy, 0, 1,
      ]);
      canvas.save();
      canvas.clipPath(ground);
      canvas.transform(matrix);
      canvas.drawImageRect(
        floorImage,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }
    canvas.drawPath(
      ground,
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawFootprints(Canvas canvas) {
    for (final object in objects) {
      if (_sceneString(object['movement']).toLowerCase() == 'decor') continue;
      final x = _sceneNum(object['x']);
      final y = _sceneNum(object['y']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final height = math.max(1.0, _sceneNum(object['height'], 1));
      final movement = _sceneString(object['movement'], 'blocked');
      final path = Path()
        ..moveTo(metrics.project(x, y).dx, metrics.project(x, y).dy)
        ..lineTo(metrics.project(x + width, y).dx, metrics.project(x + width, y).dy)
        ..lineTo(metrics.project(x + width, y + height).dx,
            metrics.project(x + width, y + height).dy)
        ..lineTo(metrics.project(x, y + height).dx,
            metrics.project(x, y + height).dy)
        ..close();
      final color = movement == 'walkable'
          ? const Color(0x4439C779)
          : movement == 'conditional'
              ? const Color(0x44A474D8)
              : const Color(0x44FF665F);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }

    final p = metrics.project(player.dx, player.dy, .02);
    canvas.drawCircle(
      p,
      metrics.tileWidth * .18,
      Paint()
        ..color = const Color(0xAA66FFAA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }


  void _drawDepthSortedEntities(Canvas canvas) {
    final entries = <Map<String, dynamic>>[];
    for (final object in objects) {
      final x = _sceneNum(object['x']);
      final y = _sceneNum(object['y']);
      final width = math.max(1.0, _sceneNum(object['width'], 1));
      final height = math.max(1.0, _sceneNum(object['height'], 1));
      final isBuilding = _sceneString(object['category']).toLowerCase() == 'building';
      if (isBuilding && stripImage != null) {
        // In strip mode, buildings are rendered once as a continuous keyed band.
        // Keep their footprints interactive, but do not draw duplicate per-object sprites.
        continue;
      }
      final stage = _sceneMap(floorSpec['stage']);
      final buildingBaseline = metrics.canvasSize.height *
          _sceneNum(stage['building_baseline_ratio'], .665).clamp(.50, .82).toDouble();
      entries.add(<String, dynamic>{
        'kind': 'object',
        'object': object,
        // Runtime buildings are a rear visual layer. The logical interaction box may
        // extend above y=0, but depth is pinned to the seam so the player stays in front.
        'depth': isBuilding
            ? buildingBaseline - 1
            : metrics.project(x + width / 2, y + height / 2).dy,
      });
    }
    entries.add(<String, dynamic>{
      'kind': 'player',
      'depth': metrics.project(player.dx, player.dy).dy,
    });
    entries.sort((a, b) => _sceneNum(a['depth']).compareTo(_sceneNum(b['depth'])));

    for (final entry in entries) {
      if (entry['kind'] == 'player') {
        _drawPlayer(canvas);
      } else {
        _drawObject(canvas, _sceneMap(entry['object']));
      }
    }
  }

  void _drawObject(Canvas canvas, JsonMap object) {
    final category = _sceneString(object['category']).toLowerCase();
    final isBuilding = category == 'building';
    if (isBuilding && stripImage != null) return;

    final index = _sceneInt(object['sprite_index'], -1);
    if (index < 0 || index >= spriteRects.length) return;

    dynamic image;
    if (index < spriteImages.length && spriteImages[index] != null) {
      image = spriteImages[index];
    } else if (atlasImage != null) {
      image = atlasImage;
    } else {
      return;
    }

    final source = spriteRects[index];
    if (source.width <= 0 || source.height <= 0) return;

    final x = _sceneNum(object['x']);
    final y = _sceneNum(object['y']);
    final width = math.max(1.0, _sceneNum(object['width'], 1));
    final height = math.max(1.0, _sceneNum(object['height'], 1));
    final stage = _sceneMap(floorSpec['stage']);
    final buildingBaseline = metrics.canvasSize.height *
        _sceneNum(stage['building_baseline_ratio'], .665).clamp(.50, .82).toDouble();
    // Buildings are independent sprites. Their base is pinned slightly BELOW the
    // backdrop/ground seam so they visually sit on the floor without consuming the
    // whole playable area. Their logical box is interaction-only and non-blocking.
    final contact = isBuilding
        ? Offset(metrics.project(x + width / 2, 0).dx, buildingBaseline)
        : metrics.project(x + width / 2, y + height / 2, .02);

    // Visual world scale is independent from collision footprint. A 3x3 atlas
    // generator tends to fill every cell, so cropped pixel bounds are not a
    // reliable measure of real-world size. New packages provide a deterministic
    // visual width from Python; old packages fall back to footprint-derived size.
    final fallbackWidthTiles = isBuilding
        ? width * 1.12
        : ((width + height) * .46).clamp(.80, 5.20).toDouble();
    final visualWidthTiles = _sceneNum(
      object['visual_width_tiles'],
      fallbackWidthTiles,
    ).clamp(.42, isBuilding ? 5.60 : 3.60).toDouble();
    final visualMaxHeightTiles = _sceneNum(
      object['visual_max_height_tiles'],
      isBuilding ? 8.80 : 6.20,
    ).clamp(1.20, isBuilding ? 9.60 : 7.00).toDouble();

    var drawWidth = visualWidthTiles * metrics.tileWidth;
    var drawHeight = drawWidth * source.height / source.width;

    // Tall/narrow Krea crops (umbrella stands, sign poles, IV stands, etc.) can
    // still become visually gigantic. Cap their screen height while preserving
    // aspect ratio, without touching collision or interaction geometry.
    final maxDrawHeight = visualMaxHeightTiles * metrics.tileWidth;
    if (drawHeight > maxDrawHeight && drawHeight > 0) {
      final shrink = maxDrawHeight / drawHeight;
      drawWidth *= shrink;
      drawHeight = maxDrawHeight;
    }

    final destination = Rect.fromLTWH(
      contact.dx - drawWidth * .5,
      contact.dy - drawHeight * (isBuilding ? .98 : .90),
      drawWidth,
      drawHeight,
    );

    // Buildings already form the rear boundary; avoid a floating oval shadow under
    // every facade. Loose objects keep the soft contact shadow.
    final shadowWidth = (drawWidth * .56)
        .clamp(metrics.tileWidth * 1.2, metrics.tileWidth * 6.4)
        .toDouble();
    final shadowHeight = (metrics.tileHeight * (.42 + (width + height) * .025))
        .clamp(metrics.tileHeight * .42, metrics.tileHeight * 1.25)
        .toDouble();
    final shadowRect = Rect.fromCenter(
      center: Offset(contact.dx, contact.dy + metrics.tileHeight * .06),
      width: shadowWidth,
      height: shadowHeight,
    );
    if (!isBuilding) {
      canvas.drawOval(
        shadowRect,
        Paint()
          ..color = const Color(0x46000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
    }

    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  void _drawPlayer(Canvas canvas) {
    final p = metrics.project(player.dx, player.dy, .03);
    // Smooth one-cycle bob instead of the old frame-by-frame odd/even jitter.
    final bob = -(1 - math.cos(walkPhase)) * .75;

    final playerShadowWidth = (metrics.tileWidth * .92).clamp(22.0, 46.0).toDouble();
    final playerShadowHeight = (metrics.tileHeight * .42).clamp(7.0, 16.0).toDouble();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(p.dx, p.dy + metrics.tileHeight * .07),
        width: playerShadowWidth,
        height: playerShadowHeight,
      ),
      Paint()
        ..color = const Color(0x52000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
    );

    if (playerImage != null) {
      final sourceWidth = (playerImage.width as int).toDouble();
      final sourceHeight = (playerImage.height as int).toDouble();
      // Character portrait is intentionally 20% smaller than the previous build.
      final playerDisplayScale = metrics.sideScroll ? 1.40 : 1.20;
      final drawWidth = (metrics.groundWidth * .052 * playerDisplayScale)
          .clamp(58.0, metrics.sideScroll ? 126.0 : 106.0)
          .toDouble();
      final drawHeight = drawWidth * sourceHeight / sourceWidth;
      final faceSign = facing == 'W' ? -1.0 : 1.0;
      canvas.save();
      canvas.translate(p.dx, p.dy + bob);
      canvas.scale(faceSign, 1);
      canvas.drawImageRect(
        playerImage,
        Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
        Rect.fromLTWH(-drawWidth / 2, -drawHeight * .93, drawWidth, drawHeight),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      return;
    }

    canvas.save();
    canvas.translate(p.dx, p.dy + bob);
    canvas.drawCircle(
      const Offset(0, -34),
      8,
      Paint()..color = const Color(0xFFE9D7B9),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-7, -27, 14, 22),
      Paint()..color = const Color(0xFF7F9AAA),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SceneAssetPainter oldDelegate) => true;
}

JsonMap? _hitSceneObject(List<JsonMap> objects, Offset logical) {
  final sorted = [...objects]
    ..sort((a, b) {
      final ad = _sceneNum(a['x']) + _sceneNum(a['y']);
      final bd = _sceneNum(b['x']) + _sceneNum(b['y']);
      return bd.compareTo(ad);
    });
  for (final object in sorted) {
    if (object['interactive'] == false) continue;
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

String _normalizeFacing(String value) {
  final facing = value.trim().toUpperCase();
  return const <String>{'N', 'E', 'S', 'W'}.contains(facing) ? facing : 'S';
}

String _facingFromDelta(double dx, double dy, String fallback) {
  if (dx.abs() > dy.abs()) return dx < 0 ? 'W' : 'E';
  if (dy.abs() > 0) return dy < 0 ? 'N' : 'S';
  return fallback;
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game_shell.dart';
import '../novel/novel_image_provider.dart';
import 'cinema_api.dart';
import 'cinema_playback_controller.dart';
import 'cinema_shot_stage.dart';

const _playerAccent = Color(0xFF76B900);

class CinemaPlayerPage extends StatefulWidget {
  const CinemaPlayerPage({
    super.key,
    required this.workId,
    this.chapterId,
    this.api,
    this.playback,
  });
  final int workId;
  final int? chapterId;
  final CinemaApi? api;
  final CinemaPlaybackController? playback;

  @override
  State<CinemaPlayerPage> createState() => _CinemaPlayerPageState();
}

class _CinemaPlayerPageState extends State<CinemaPlayerPage>
    with WidgetsBindingObserver {
  static const _displayChannel = MethodChannel('youran/cinema_display');
  static Object? _systemUiOwner;
  final _systemUiToken = Object();
  late final _api = widget.api ?? CinemaApi();
  late final _playback =
      widget.playback ??
      CinemaPlaybackController(
        resolveAudio: (item) {
          final id = int.tryParse('${item['id']}');
          if (id == null) throw StateError('缺少台词条目 ID');
          return _api.itemAudio(id);
        },
      );
  List<Map<String, dynamic>> _chapters = [];
  String _title = '电影放映';
  int? _chapterId;
  int _loadVersion = 0;
  int? _scrubIndex;
  bool _resumeAfterScrub = false;
  bool _loading = true;
  bool _allowAutoPlay = true;
  bool _controlsVisible = true;
  bool _wasPlaying = false;
  bool _wasPreparing = false;
  bool _fullscreen = true;
  bool _systemUiRestored = false;
  bool _chapterPickerOpen = false;
  bool _drawerOpen = false;
  Timer? _hideControlsTimer;
  Timer? _assetPollTimer;
  Timer? _progressTimer;
  int? _refreshingAssetVersion;
  int _lastObservedIndex = -1;
  Future<void> _progressQueue = Future<void>.value();
  final _warmedImages = <String>{};
  String _imageError = '';
  String _error = '';

  bool get _supportsSystemFullscreen =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _prepareDisplay() async {
    if (!_supportsSystemFullscreen) return;
    // 小说模式可能锁定竖屏；电影随设备旋转，画面始终铺满当前屏幕。
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    if (mounted) await _applyFullscreen();
  }

  Future<void> _applyFullscreen() async {
    if (!_supportsSystemFullscreen) return;
    _systemUiOwner = _systemUiToken;
    _systemUiRestored = false;
    await _setSystemFullscreen(_fullscreen);
  }

  Future<void> _setSystemFullscreen(bool enabled) async {
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        // API 35/36 使用原生 Insets 隐藏系统栏，保持 edge-to-edge 布局。
        await _displayChannel.invokeMethod<void>('setFullscreen', {
          'enabled': enabled,
        });
      } on MissingPluginException {
        // 热更新旧安装包时仍保留 Flutter 的全屏处理。
      }
    }
  }

  Future<void> _restoreSystemUi() async {
    if (_systemUiRestored || !identical(_systemUiOwner, _systemUiToken)) return;
    _systemUiRestored = true;
    _systemUiOwner = null;
    await _setSystemFullscreen(false);
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_loading ||
        _playback.isPreparing ||
        !_playback.isPlaying ||
        _chapterPickerOpen ||
        _drawerOpen) {
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playback.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    if (!mounted) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _onPlaybackChanged() {
    if (!_playback.isPlaying || _playback.isPreparing) {
      _hideControlsTimer?.cancel();
      if (mounted && !_controlsVisible) setState(() => _controlsVisible = true);
    } else if (!_wasPlaying || _wasPreparing) {
      _scheduleHideControls();
    }
    _wasPlaying = _playback.isPlaying;
    _wasPreparing = _playback.isPreparing;
    if (!_loading && _chapterId != null && _playback.items.isNotEmpty) {
      _warmImages();
      if (_lastObservedIndex != _playback.index) {
        _lastObservedIndex = _playback.index;
        _progressTimer?.cancel();
        _progressTimer = Timer(const Duration(milliseconds: 250), () {
          unawaited(_saveCurrentProgress());
        });
        unawaited(_refreshAssets(_loadVersion, updateWindow: true));
      }
    }
  }

  int get _backendIndex =>
      int.tryParse('${_playback.current['item_index']}') ?? _playback.index;

  Future<void> _saveCurrentProgress({bool force = false}) {
    _progressTimer?.cancel();
    final chapterId = _chapterId;
    if (chapterId == null || _playback.items.isEmpty) {
      return Future<void>.value();
    }
    final index = _backendIndex;
    final version = _loadVersion;
    _progressQueue = _progressQueue.then((_) async {
      if (!force && (!mounted || version != _loadVersion)) return;
      try {
        await _api.saveProgress(
          widget.workId,
          chapterId: chapterId,
          itemIndex: index,
        );
      } catch (e) {
        debugPrint('Cinema progress save failed: $e');
      }
    });
    return _progressQueue;
  }

  void _startAssetPolling(int version) {
    _assetPollTimer?.cancel();
    _assetPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshAssets(version));
    });
  }

  Future<void> _refreshAssets(int version, {bool updateWindow = false}) async {
    final chapterId = _chapterId;
    if (!mounted ||
        version != _loadVersion ||
        chapterId == null ||
        _refreshingAssetVersion == version) {
      return;
    }
    _refreshingAssetVersion = version;
    try {
      final data = await _api.playback(
        chapterId,
        itemIndex: updateWindow ? _backendIndex : null,
      );
      if (!mounted || version != _loadVersion || chapterId != _chapterId) {
        return;
      }
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _playback.updateAssets(items);
      if (_playback.currentImageUrl.isNotEmpty && _imageError.isNotEmpty) {
        setState(() => _imageError = '');
      }
    } catch (e) {
      debugPrint('Cinema image refresh failed: $e');
    } finally {
      if (_refreshingAssetVersion == version) _refreshingAssetVersion = null;
    }
  }

  void _warmImages() {
    if (!mounted) return;
    for (final url in _playback.imageUrlsAhead()) {
      if (!_warmedImages.add(url)) continue;
      unawaited(
        precacheImage(
          NovelImageProvider.network(url),
          context,
          onError: (error, stack) {
            _warmedImages.remove(url);
          },
        ),
      );
    }
  }

  Future<void> _retryImages() async {
    final chapterId = _chapterId;
    final version = _loadVersion;
    if (chapterId == null) return;
    setState(() => _imageError = '');
    try {
      await _api.prepareAssets(chapterId, itemIndex: _backendIndex);
      await _refreshAssets(version);
    } catch (e) {
      if (mounted && version == _loadVersion) {
        setState(() => _imageError = '画面准备失败，可点击重试');
      }
    }
  }

  Future<void> _togglePlayback() async {
    await _playback.toggle();
    unawaited(_saveCurrentProgress());
    _showControls();
  }

  String get _chapterTitle {
    for (final chapter in _chapters) {
      if (int.parse('${chapter['id']}') == _chapterId) {
        return chapter['title']?.toString() ?? '未命名章节';
      }
    }
    return '';
  }

  int get _chapterIndex => _chapters.indexWhere(
    (chapter) => int.parse('${chapter['id']}') == _chapterId,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.addListener(_onPlaybackChanged);
    unawaited(_prepareDisplay());
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pausePlayback();
    if (state == AppLifecycleState.resumed) {
      unawaited(_applyFullscreen());
      if (_chapterId != null) _startAssetPolling(_loadVersion);
    } else {
      _assetPollTimer?.cancel();
    }
  }

  void _pausePlayback() {
    _allowAutoPlay = false;
    unawaited(_playback.pause());
    unawaited(_saveCurrentProgress());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getWork(widget.workId);
      final work = data['work'] is Map ? data['work'] as Map : data;
      final chapters =
          (data['chapters'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => (int.tryParse('${e['id']}') ?? 0) > 0)
              .toList()
            ..sort((a, b) {
              final order = (int.tryParse('${a['sort_order']}') ?? 0).compareTo(
                int.tryParse('${b['sort_order']}') ?? 0,
              );
              return order != 0
                  ? order
                  : int.parse('${a['id']}').compareTo(int.parse('${b['id']}'));
            });
      if (!mounted) return;
      setState(() {
        _title = work['title']?.toString() ?? '电影放映';
        _chapters = chapters;
      });
      if (chapters.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final requested = chapters.where(
        (e) => int.parse('${e['id']}') == widget.chapterId,
      );
      var chapterId = int.parse(
        '${(requested.isEmpty ? chapters.first : requested.first)['id']}',
      );
      var initialIndex = 0;
      try {
        final progress = await _api.progress(widget.workId);
        final savedChapter = int.tryParse('${progress['chapter_id']}');
        if (widget.chapterId == null &&
            chapters.any(
              (chapter) => chapter['id'].toString() == '$savedChapter',
            )) {
          chapterId = savedChapter!;
        }
        if (chapterId == savedChapter) {
          initialIndex = int.tryParse('${progress['item_index']}') ?? 0;
        }
      } catch (e) {
        debugPrint('Cinema progress load failed: $e');
      }
      if (!mounted) return;
      await _loadChapter(chapterId, initialIndex: initialIndex);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载作品失败：$e';
      });
    }
  }

  Future<void> _loadChapter(int chapterId, {int initialIndex = 0}) async {
    unawaited(_saveCurrentProgress(force: true));
    _assetPollTimer?.cancel();
    final version = ++_loadVersion;
    setState(() {
      _chapterId = chapterId;
      _loading = true;
      _error = '';
      _scrubIndex = null;
      _imageError = '';
      _lastObservedIndex = -1;
      _warmedImages.clear();
    });
    try {
      await _playback.setItems([]);
      if (!mounted || version != _loadVersion) return;
      try {
        await _api.prepareAssets(chapterId, itemIndex: initialIndex);
      } catch (e) {
        debugPrint('Cinema image preparation failed: $e');
        if (mounted && version == _loadVersion) _imageError = '画面准备失败，可点击重试';
      }
      if (!mounted || version != _loadVersion) return;
      final data = await _api.playback(chapterId, itemIndex: initialIndex);
      if (!mounted || version != _loadVersion) return;
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() => _loading = false);
      _startAssetPolling(version);
      await _playback.setItems(
        items,
        autoPlay: _allowAutoPlay,
        initialIndex: initialIndex,
      );
      if (!mounted || version != _loadVersion) return;
      _showControls();
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error = '加载章节失败：$e';
      });
    }
  }

  Future<void> _chooseChapter() async {
    _chapterPickerOpen = true;
    _hideControlsTimer?.cancel();
    await _playback.pause();
    if (!mounted) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF151719),
      barrierColor: const Color(0xA6000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Color(0x14FFFFFF)),
      ),
      constraints: const BoxConstraints(maxWidth: 640),
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height * .64).clamp(200.0, 520.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Row(
                  children: [
                    const Text(
                      '选择章节',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_chapters.length} 章',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0x0FFFFFFF)),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: _chapters.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0x08FFFFFF),
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final chapter = _chapters[index];
                    final id = int.parse('${chapter['id']}');
                    final current = id == _chapterId;
                    return Semantics(
                      selected: current,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  '${index + 1}'.padLeft(2, '0'),
                                  style: TextStyle(
                                    color: current
                                        ? _playerAccent
                                        : Colors.white38,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  chapter['title']?.toString() ?? '未命名章节',
                                  style: TextStyle(
                                    color: current
                                        ? _playerAccent
                                        : Colors.white70,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
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
              ),
            ],
          ),
        ),
      ),
    );
    _chapterPickerOpen = false;
    if (!mounted || selected == null) return;
    _allowAutoPlay = true;
    if (selected == _chapterId && _error.isEmpty) {
      await _playback.resume();
    } else {
      await _loadChapter(selected);
    }
  }

  @override
  void dispose() {
    unawaited(_saveCurrentProgress(force: true));
    WidgetsBinding.instance.removeObserver(this);
    _loadVersion++;
    _hideControlsTimer?.cancel();
    _assetPollTimer?.cancel();
    _progressTimer?.cancel();
    _playback.removeListener(_onPlaybackChanged);
    _playback.dispose();
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameShell(
      activeScenarioId: widget.workId.toString(),
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      onDrawerChanged: (isOpen) {
        _drawerOpen = isOpen;
        if (isOpen) _pausePlayback();
        if (!isOpen) _showControls();
      },
      builder: (context, openDrawer) => AnimatedBuilder(
        animation: _playback,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 450;
            final hasContent =
                !_loading && _error.isEmpty && _playback.items.isNotEmpty;
            final hasNextChapter =
                _playback.hasEnded && _chapterIndex + 1 < _chapters.length;
            final footerHeight =
                (compact ? 92.0 : 104.0) + (hasNextChapter ? 40.0 : 0);
            final safeBottom = MediaQuery.paddingOf(context).bottom;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    key: const ValueKey('cinema-stage'),
                    child: _buildBackground(),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('cinema-screen'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: const SizedBox.expand(),
                  ),
                ),
                if (hasContent) ...[
                  // 渐变只负责字幕对比度，背景仍然占满整个视口。
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 230,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xB3000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    bottom:
                        safeBottom +
                        (_controlsVisible
                            ? footerHeight + 12
                            : compact
                            ? 20
                            : 36),
                    child: _buildSubtitles(constraints, compact),
                  ),
                ],
                if (!hasContent) _buildStatus(),
                if (hasContent &&
                    (_playback.isPreparing || _playback.notice.isNotEmpty))
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 90,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x99000000),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_playback.isPreparing) ...[
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Text(
                                    _playback.isPreparing
                                        ? '正在准备语音…'
                                        : _playback.notice,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _controlsLayer(_buildHeader(openDrawer)),
                ),
                if (hasContent)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _controlsLayer(
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xB3000000)],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: _buildControls(compact),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _controlsLayer(Widget child) => IgnorePointer(
    ignoring: !_controlsVisible,
    child: ExcludeSemantics(
      excluding: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: child,
      ),
    ),
  );

  Widget _buildHeader(VoidCallback openDrawer) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.fromLTRB(8, 6, 8, 16),
        child: Row(
          children: [
            IconButton(
              tooltip: '世界菜单',
              onPressed: openDrawer,
              color: Colors.white,
              icon: const Icon(Icons.menu_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_chapterTitle.isNotEmpty)
                    Text(
                      _chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (_playback.items.isEmpty)
              _buildChapterButton(enabled: _chapters.isNotEmpty && !_loading),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    final image = _playback.imageUrl;
    if (image.isEmpty) {
      final failed =
          _imageError.isNotEmpty || _playback.imageStatus == 'failed';
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF182129), Color(0xFF050708)],
            radius: 1.2,
          ),
        ),
        child: !_loading && (_playback.isImagePending || failed)
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!failed)
                      const CircularProgressIndicator(color: _playerAccent),
                    const SizedBox(height: 12),
                    Text(
                      failed ? '画面准备失败，语音可继续播放' : '正在准备画面…',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            : null,
      );
    }
    return CinemaShotStage(
      shotId: '$_chapterId:${_playback.shotIdentity}',
      imageUrl: image,
      cameraMove: _playback.cameraMove,
      duration: _playback.shotMotionDuration,
      hasCurrentImage: _playback.currentImageUrl.isNotEmpty,
      playing: _playback.isPlaying && !_playback.isPreparing,
    );
  }

  Widget _buildSubtitles(BoxConstraints constraints, bool compact) {
    final item = _playback.current;
    final speaker = item['speaker']?.toString().trim() ?? '';
    return SafeArea(
      top: false,
      bottom: false,
      minimum: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('cinema-subtitles'),
          constraints: BoxConstraints(
            maxWidth: 1000,
            maxHeight: constraints.maxHeight * (compact ? .28 : .3),
          ),
          child: SingleChildScrollView(
            key: ValueKey('${_chapterId}_${_playback.index}'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (speaker.isNotEmpty && speaker != '旁白') ...[
                  Text(
                    speaker,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  item['text']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    shadows: const [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                      Shadow(color: Colors.black, blurRadius: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _playerAccent),
      );
    }
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error.isNotEmpty
                    ? _error
                    : _chapters.isEmpty
                    ? '这部作品还没有章节'
                    : '本章节还没有放映内容',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      _chapterId == null ? _load() : _loadChapter(_chapterId!),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChapterButton({bool enabled = true}) => Tooltip(
    message: '选择章节',
    child: TextButton(
      onPressed: enabled ? _chooseChapter : null,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white24,
        backgroundColor: const Color(0x0DFFFFFF),
        minimumSize: const Size(52, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: const BorderSide(color: Color(0x1AFFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: const Text('章节'),
    ),
  );

  Widget _buildControls(bool compact) {
    final count = _playback.items.length;
    final index = _scrubIndex ?? _playback.index;
    final status = _playback.hasEnded
        ? '本章结束'
        : _playback.isPreparing
        ? '语音准备中'
        : _playback.isPlaying
        ? '正在播放'
        : '已暂停';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: compact ? 28 : 36,
          child: Slider(
            activeColor: _playerAccent,
            inactiveColor: Colors.white24,
            min: 0,
            max: count > 1 ? (count - 1).toDouble() : 1,
            value: index.toDouble(),
            label: '第 ${index + 1} 句',
            semanticFormatterCallback: (value) =>
                '第 ${value.round() + 1} 句，共 $count 句',
            onChangeStart: count > 1
                ? (_) {
                    _hideControlsTimer?.cancel();
                    _resumeAfterScrub = _playback.isPlaying;
                    unawaited(_playback.pause());
                  }
                : null,
            onChanged: count > 1
                ? (value) => setState(() => _scrubIndex = value.round())
                : null,
            onChangeEnd: count > 1
                ? (value) {
                    setState(() => _scrubIndex = null);
                    unawaited(
                      _playback.select(
                        value.round(),
                        autoPlay: _resumeAfterScrub,
                      ),
                    );
                    _showControls();
                  }
                : null,
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: '上一句',
              color: Colors.white,
              onPressed: _playback.index > 0
                  ? () {
                      unawaited(_playback.select(_playback.index - 1));
                      _showControls();
                    }
                  : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton(
              tooltip: _playback.hasEnded
                  ? '重新播放'
                  : _playback.isPlaying
                  ? '暂停'
                  : '播放',
              onPressed: _togglePlayback,
              iconSize: 36,
              color: Colors.white,
              icon: Icon(
                _playback.hasEnded
                    ? Icons.replay_rounded
                    : _playback.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            IconButton(
              tooltip: '下一句',
              color: Colors.white,
              onPressed: _playback.index + 1 < count
                  ? () {
                      unawaited(_playback.select(_playback.index + 1));
                      _showControls();
                    }
                  : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$status · ${index + 1}/$count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            _buildChapterButton(),
            if (_imageError.isNotEmpty || _playback.imageStatus == 'failed')
              IconButton(
                tooltip: '重试画面',
                onPressed: _retryImages,
                color: Colors.white70,
                icon: const Icon(Icons.refresh_rounded),
              ),
            if (_supportsSystemFullscreen)
              IconButton(
                tooltip: _fullscreen ? '退出全屏' : '全屏',
                onPressed: () {
                  setState(() => _fullscreen = !_fullscreen);
                  unawaited(_applyFullscreen());
                  _showControls();
                },
                color: Colors.white,
                icon: Icon(
                  _fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                ),
              ),
          ],
        ),
        if (_playback.hasEnded && _chapterIndex + 1 < _chapters.length)
          SizedBox(
            height: 40,
            child: TextButton.icon(
              onPressed: () {
                _allowAutoPlay = true;
                unawaited(
                  _loadChapter(
                    int.parse('${_chapters[_chapterIndex + 1]['id']}'),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('播放下一章'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 播放后端生成的音频，只有音频完成事件才会自动切换下一段。
abstract class CinemaAudio {
  Stream<void> get completed;
  Future<void> setUrl(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

/// 下一段可以提前进入同一播放队列，字幕跟随音频实际开始的条目切换。
abstract class CinemaAudioPreloader {
  Stream<int> get currentItem;
  Future<void> setItem(int itemIndex, String url);
  Future<void> preloadItem(int itemIndex, String url);
}

class _CinemaAudioPlayer implements CinemaAudio, CinemaAudioPreloader {
  _CinemaAudioPlayer() {
    _indexSub = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _sourceItems.length) {
        _currentItem.add(_sourceItems[index]);
      }
    });
  }

  final _player = AudioPlayer(useLazyPreparation: false);
  final _sourceItems = <int>[];
  final _currentItem = StreamController<int>.broadcast(sync: true);
  late final StreamSubscription<int?> _indexSub;
  int _generation = 0;

  @override
  Stream<int> get currentItem => _currentItem.stream;

  @override
  Stream<void> get completed => _player.playerStateStream
      .where((state) => state.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> setUrl(String url) => setItem(0, url);

  @override
  Future<void> setItem(int itemIndex, String url) async {
    _generation++;
    _sourceItems
      ..clear()
      ..add(itemIndex);
    await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
  }

  @override
  Future<void> preloadItem(int itemIndex, String url) async {
    if (_sourceItems.isEmpty || _sourceItems.contains(itemIndex)) return;
    final generation = _generation;
    final slot = _sourceItems.length;
    // 先保存映射，兼容短音频在 addAudioSource 返回前就已开始播放。
    _sourceItems.add(itemIndex);
    try {
      await _player.addAudioSource(AudioSource.uri(Uri.parse(url)));
    } catch (_) {
      if (generation == _generation && _sourceItems.length > slot) {
        _sourceItems.removeAt(slot);
      }
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    _generation++;
    await _player.stop();
    _sourceItems.clear();
  }

  @override
  Future<void> dispose() async {
    await _indexSub.cancel();
    await _currentItem.close();
    await _player.dispose();
  }
}

class CinemaPlaybackController extends ChangeNotifier {
  CinemaPlaybackController({
    CinemaAudio? audio,
    Future<String> Function(Map<String, dynamic> item)? resolveAudio,
  }) : _audio = audio ?? _CinemaAudioPlayer(),
       _resolveAudio = resolveAudio {
    _completedSub = _audio.completed.listen((_) {
      if (_playing &&
          _audioReady &&
          !_preparing &&
          _completionVersion != _version) {
        _completionVersion = _version;
        unawaited(_completeCurrent(_version));
      }
    });
    final audioQueue = _audio;
    if (audioQueue is CinemaAudioPreloader) {
      _currentItemSub = (audioQueue as CinemaAudioPreloader).currentItem.listen(
        _onQueuedItem,
      );
    }
  }

  final CinemaAudio _audio;
  final Future<String> Function(Map<String, dynamic> item)? _resolveAudio;
  late final StreamSubscription<void> _completedSub;
  StreamSubscription<int>? _currentItemSub;
  Future<void> _audioQueue = Future<void>.value();
  final _audioUrls = <int, Future<String>>{};
  List<Map<String, dynamic>> _items = [];
  int _index = 0;
  int _version = 0;
  int _pauseVersion = 0;
  int? _completionVersion;
  bool _playing = false;
  bool _preparing = false;
  bool _audioReady = false;
  bool _ended = false;
  bool _disposed = false;
  String _notice = '';
  String _lastImageUrl = '';

  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  int get index => _index;
  bool get isPlaying => _playing;
  bool get isPreparing => _preparing;
  bool get hasEnded => _ended;
  bool get hasAudio => _audioReady;
  String get notice => _notice;
  Map<String, dynamic> get current =>
      _items.isEmpty ? const {} : _items[_index];

  static String assetUrl(Map<String, dynamic> item, String type) {
    // 新记录优先；pending/failed 记录不能遮住已有可播放资源。
    for (final asset
        in (item['assets'] as List? ?? []).reversed.whereType<Map>()) {
      final status = asset['status']?.toString();
      if (asset['asset_type'] == type &&
          !const {
            'pending',
            'processing',
            'failed',
            'error',
          }.contains(status)) {
        final url = asset['url']?.toString().trim() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }

  String get currentImageUrl => _imageAt(_index);
  String get imageUrl =>
      currentImageUrl.isNotEmpty ? currentImageUrl : _lastImageUrl;

  Object get shotIdentity => _shotId(current) ?? current['id'] ?? _index;

  String get cameraMove {
    final metadata = _imageHead['metadata'];
    return (_imageHead['camera_move'] ??
                (metadata is Map ? metadata['camera_move'] : null))
            ?.toString() ??
        'static';
  }

  Duration get shotMotionDuration {
    final metadata = _imageHead['metadata'];
    final explicit = metadata is Map
        ? num.tryParse('${metadata['shot_duration_seconds']}')
        : null;
    if (explicit != null && explicit.isFinite && explicit > 0) {
      return Duration(
        milliseconds: (explicit * 1000).round().clamp(1000, 60000),
      );
    }
    final shot = _shotId(current);
    final lines = shot == null
        ? [current]
        : _items.where((item) => _shotId(item) == shot);
    final characters = lines.fold<int>(
      0,
      (count, item) => count + (item['text']?.toString() ?? '').runes.length,
    );
    // Until measured audio duration is available, span the entire shot using a bounded speech estimate.
    return Duration(milliseconds: (characters * 220 + 800).clamp(6000, 30000));
  }

  String _imageAt(int index) {
    if (_items.isEmpty || index < 0 || index >= _items.length) return '';
    final direct = assetUrl(_items[index], 'image');
    if (direct.isNotEmpty) return direct;
    final shot = _shotId(_items[index]);
    if (shot == null) return '';
    // 后端只在镜头首句放画面，同镜头后续台词继续显示该画面。
    for (var i = index - 1; i >= 0 && _shotId(_items[i]) == shot; i--) {
      final image = assetUrl(_items[i], 'image');
      if (image.isNotEmpty) return image;
    }
    return '';
  }

  Map<String, dynamic> get _imageHead {
    final shot = _shotId(current);
    if (shot == null) return current;
    var index = _index;
    while (index > 0 && _shotId(_items[index - 1]) == shot) {
      index--;
    }
    return _items.isEmpty ? const {} : _items[index];
  }

  String get imageStatus {
    for (final item in [current, _imageHead]) {
      for (final asset
          in (item['assets'] as List? ?? []).reversed.whereType<Map>()) {
        if (asset['asset_type'] == 'image') {
          return asset['status']?.toString() ?? '';
        }
      }
    }
    return (_imageHead['scene_prompt']?.toString().trim() ?? '').isNotEmpty
        ? 'pending'
        : '';
  }

  bool get isImagePending =>
      const {'pending', 'processing'}.contains(imageStatus);

  /// Polling only replaces asset lists. The playing audio, index and subtitle text stay in place.
  void updateAssets(List<Map<String, dynamic>> refreshed) {
    if (_disposed || _items.isEmpty) return;
    final byId = <String, Map<String, dynamic>>{
      for (final item in refreshed)
        if (item['id'] != null) '${item['id']}': item,
    };
    var changed = false;
    _items = _items.map((item) {
      final update = byId['${item['id']}'];
      if (update == null || update['assets'] is! List) return item;
      changed = true;
      return <String, dynamic>{...item, 'assets': update['assets']};
    }).toList();
    if (changed) _notify();
  }

  List<String> imageUrlsAhead({int shots = 5}) {
    final urls = <String>{};
    Object? lastShot;
    var count = 0;
    for (var i = _index; i < _items.length; i++) {
      final shot = _shotId(_items[i]) ?? 'line:$i';
      if (shot != lastShot) {
        if (count++ > shots) break;
        lastShot = shot;
      }
      final url = _imageAt(i);
      if (url.isNotEmpty) urls.add(url);
    }
    return urls.toList();
  }

  Object? _shotId(Map<String, dynamic> item) =>
      item['shot_id'] ??
      (item['metadata'] is Map ? item['metadata']['shot_id'] : null);

  Future<void> _queue(Future<void> Function() action) {
    final operation = _audioQueue.then((_) => action());
    _audioQueue = operation.catchError((Object _) {});
    return operation;
  }

  void _notify() {
    final image = currentImageUrl;
    if (image.isNotEmpty) _lastImageUrl = image;
    if (!_disposed) notifyListeners();
  }

  Future<String> _audioFor(int index) {
    final existing = _audioUrls[index];
    if (existing != null) return existing;
    final item = _items[index];
    final request =
        Future<String>.sync(
          () => _resolveAudio == null
              ? assetUrl(item, 'audio')
              : _resolveAudio(item),
        ).then((url) {
          if (url.isEmpty) throw StateError('No audio returned');
          return url;
        });
    _audioUrls[index] = request;
    request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(_audioUrls[index], request)) _audioUrls.remove(index);
      },
    );
    return request;
  }

  Future<void> _preloadFollowing(int version, int index) async {
    final candidate = index + 1;
    if (_disposed || version != _version || candidate >= _items.length) return;
    try {
      final url = await _audioFor(candidate);
      if (_disposed || version != _version) return;
      final audioQueue = _audio;
      if (audioQueue is CinemaAudioPreloader) {
        await _queue(() async {
          if (_disposed || version != _version || !_audioReady || _preparing) {
            return;
          }
          await (audioQueue as CinemaAudioPreloader).preloadItem(
            candidate,
            url,
          );
        });
      }
    } catch (_) {
      // 前瞻失败不打断当前语音；真正读到该段时允许重新请求。
      debugPrint('Cinema next audio preload failed for item $candidate');
    }
  }

  void _onQueuedItem(int index) {
    if (_disposed ||
        !_audioReady ||
        _preparing ||
        index != _index + 1 ||
        index >= _items.length) {
      return;
    }
    // 下一段已经由同一播放器自然接播，不能再 stop/setUrl 或重复请求。
    _version++;
    _index = index;
    _ended = false;
    _notice = '';
    _notify();
    if (_playing) unawaited(_preloadFollowing(_version, _index));
  }

  Future<void> _completeCurrent(int version) async {
    // 若追加下一段与队尾完成同时发生，先让队列切换事件同步字幕。
    await _audioQueue;
    if (_disposed ||
        version != _version ||
        !_playing ||
        !_audioReady ||
        _preparing) {
      return;
    }
    _audioReady = false;
    await _advance();
  }

  Future<void> setItems(
    List<Map<String, dynamic>> items, {
    bool autoPlay = true,
    int initialIndex = 0,
  }) async {
    final pauseVersion = _pauseVersion;
    final stopping = stop();
    final version = _version;
    await stopping;
    if (_disposed || version != _version) return;
    _items = List.of(items);
    _lastImageUrl = '';
    _index = 0;
    _ended = false;
    _notice = '';
    if (_items.isEmpty) {
      _notify();
    } else {
      await select(
        initialIndex.clamp(0, _items.length - 1),
        autoPlay: autoPlay && pauseVersion == _pauseVersion,
      );
    }
  }

  Future<void> select(int index, {bool? autoPlay}) async {
    if (_disposed || index < 0 || index >= _items.length) return;
    final version = ++_version;
    _index = index;
    _playing = autoPlay ?? _playing;
    _preparing = true;
    _audioReady = false;
    _ended = false;
    _notice = '';
    _notify();
    try {
      // 立即停止旧音频，也让正在等待网络的预加载退出。
      await _audio.stop();
      if (_disposed || version != _version) return;
      // 生成请求不占用音频控制队列，等待期间仍可暂停、换章和退出。
      final audio = await _audioFor(index);
      if (_disposed || version != _version) return;
      await _queue(() async {
        if (_disposed || version != _version) return;
        final audioQueue = _audio;
        if (audioQueue is CinemaAudioPreloader) {
          await (audioQueue as CinemaAudioPreloader).setItem(index, audio);
        } else {
          await _audio.setUrl(audio);
        }
        if (!_disposed && version == _version) _audioReady = true;
      });
    } catch (_) {
      if (_disposed || version != _version) return;
      _playing = false;
      _audioUrls.remove(index);
      _notice = '语音准备失败，点击播放重试';
    }
    if (_disposed || version != _version) return;
    _preparing = false;
    if (_playing) _start();
    _notify();
  }

  void _start() {
    if (_disposed || !_playing || _preparing || _items.isEmpty) return;
    if (_audioReady) {
      final version = _version;
      // just_audio 的 play Future 在暂停/结束时才完成，不能阻塞控制队列。
      unawaited(
        _audio.play().catchError((Object _) {
          if (_disposed || version != _version) return;
          _audioReady = false;
          _playing = false;
          _audioUrls.remove(_index);
          _notice = '语音播放失败，点击播放重试';
          _notify();
        }),
      );
      unawaited(_preloadFollowing(_version, _index));
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _pauseVersion++;
    _completionVersion = null;
    _playing = false;
    _notify();
    // 暂停不排在下一段的网络预加载后面。
    await _audio.pause();
  }

  Future<void> resume() async {
    if (_disposed || _items.isEmpty || _playing) return;
    if (_ended) {
      await select(0, autoPlay: true);
      return;
    }
    if (!_audioReady && !_preparing) {
      await select(_index, autoPlay: true);
      return;
    }
    _playing = true;
    _start();
    _notify();
  }

  Future<void> toggle() => _playing ? pause() : resume();

  Future<void> _advance() async {
    if (_disposed || !_playing) return;
    if (_index + 1 < _items.length) {
      await select(_index + 1, autoPlay: true);
    } else {
      _playing = false;
      _ended = true;
      _notify();
    }
  }

  Future<void> stop() async {
    _version++;
    _audioUrls.clear();
    _playing = false;
    _preparing = false;
    _audioReady = false;
    _notify();
    if (!_disposed) await _audio.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    unawaited(_completedSub.cancel());
    unawaited(_currentItemSub?.cancel());
    // dispose 会取消底层加载，不等待可能仍在缓冲的前瞻任务。
    unawaited(_audio.dispose());
    super.dispose();
  }
}

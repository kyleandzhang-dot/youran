import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'novel_models.dart';

class NovelBgmService {
  NovelBgmService({
    AudioPlayer? player,
    AudioPlayer? weatherPlayer,
    AudioPlayer? typingPlayer,
    this.defaultVolume = 0.35,
    this.fadeDuration = const Duration(milliseconds: 1500),
    this.debounceCount = 2,
  })  : _player = player ?? AudioPlayer(),
        _weatherPlayer = weatherPlayer ?? AudioPlayer(),
        _typingPlayer = typingPlayer ?? AudioPlayer() {
    // Web 继续使用单播放器快速 restart。
    // Android / iOS 使用一个很小的播放器池轮播短音，避免必须等上一声 WAV 播完
    // 才能听到下一声，从而出现“滴——滴——滴——”的长间隔。
    _typingPlayers = kIsWeb
        ? <AudioPlayer>[_typingPlayer]
        : <AudioPlayer>[
            _typingPlayer,
            AudioPlayer(),
            AudioPlayer(),
            AudioPlayer(),
          ];
  }

  final AudioPlayer _player;
  final AudioPlayer _weatherPlayer;
  final AudioPlayer _typingPlayer;
  late final List<AudioPlayer> _typingPlayers;
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final double defaultVolume;
  final Duration fadeDuration;
  final int debounceCount;

  JsonMap _config = <String, dynamic>{};
  final Map<String, int> _debounceMap = <String, int>{};
  Timer? _fadeTimer;
  Completer<void>? _fadeCompleter;
  int _switchId = 0;
  String currentIntensity = 'low';
  String currentSceneMode = 'normal';
  bool enabled = true;
  bool isPlaying = false;

  Timer? _weatherFadeTimer;
  Completer<void>? _weatherFadeCompleter;
  int _weatherSwitchId = 0;
  String currentWeatherKey = 'none';
  bool isWeatherPlaying = false;

  static const String typingAsset = 'assets/audio/ui/typing.wav';
  static const double typingVolume = 0.46;

  // 逐字动画通常 30ms 推进一次。
  // Web 保持约 60ms 一声；原生端也压到接近这一节奏，但通过播放器池避免互相抢 seek。
  static const Duration typingThrottle = Duration(milliseconds: 60);
  static const Duration nativeTypingThrottle = Duration(milliseconds: 55);
  DateTime? _lastTypingTickAt;
  bool _typingReady = false;
  Future<void>? _typingPrepareFuture;
  bool _typingRestartInFlight = false;
  bool _typingRestartQueued = false;
  int _typingPlaybackEpoch = 0;
  int _nativeTypingCursor = 0;
  Timer? _weatherDuckRestoreTimer;

  /// 预加载流式打字音效。资源缺失时静默降级。
  Future<void> preloadTypingSfx() async {
    await _prepareTypingPlayer();
  }

  Future<void> _prepareTypingPlayer() async {
    if (_typingReady) return;
    final existing = _typingPrepareFuture;
    if (existing != null) return existing;

    final future = () async {
      try {
        await Future.wait(
          _typingPlayers.map((player) async {
            await player.setLoopMode(LoopMode.off);
            await player.setVolume(typingVolume);
            await player.setAsset(typingAsset);
          }),
        );
        _typingReady = true;
      } catch (error, stackTrace) {
        // 手机安装版若资源/解码失败，必须把真实原因打印出来，避免静默无声。
        debugPrint('novel typing sfx prepare failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        _typingReady = false;
      } finally {
        _typingPrepareFuture = null;
      }
    }();
    _typingPrepareFuture = future;
    return future;
  }

  double _currentWeatherTargetVolume() =>
      _weatherVolume(currentWeatherKey).clamp(0.0, 1.0).toDouble();

  void _duckWeatherForTyping() {
    _weatherDuckRestoreTimer?.cancel();
    if (isWeatherPlaying && _weatherPlayer.playing) {
      final ducked = (_currentWeatherTargetVolume() * 0.45)
          .clamp(0.0, 1.0)
          .toDouble();
      unawaited(_weatherPlayer.setVolume(ducked));
    }
    _weatherDuckRestoreTimer = Timer(const Duration(milliseconds: 240), () {
      if (isWeatherPlaying && _weatherPlayer.playing) {
        unawaited(_weatherPlayer.setVolume(_currentWeatherTargetVolume()));
      }
    });
  }

  /// 流式文字的短促前景音效。高频调用会自动节流。
  ///
  /// Web 使用单播放器 restart；Android / iOS 使用播放器池轮播，
  /// 让相邻打字声可以自然重叠，不再受单个 WAV 完整时长限制。
  void playTypingTick() {
    final now = DateTime.now();
    final last = _lastTypingTickAt;
    final throttle = kIsWeb ? typingThrottle : nativeTypingThrottle;
    if (last != null && now.difference(last) < throttle) return;
    _lastTypingTickAt = now;

    if (!kIsWeb) {
      unawaited(_playNativeTypingTick());
      return;
    }

    if (_typingRestartInFlight) {
      _typingRestartQueued = true;
      return;
    }
    unawaited(_playWebTypingTick());
  }

  Future<void> _playNativeTypingTick() async {
    final epoch = _typingPlaybackEpoch;
    try {
      await _prepareTypingPlayer();
      if (!_typingReady || epoch != _typingPlaybackEpoch) return;

      final player = _typingPlayers[
          _nativeTypingCursor % _typingPlayers.length];
      _nativeTypingCursor =
          (_nativeTypingCursor + 1) % _typingPlayers.length;

      _duckWeatherForTyping();
      await player.setVolume(typingVolume);
      await player.seek(Duration.zero);
      if (epoch != _typingPlaybackEpoch) return;

      unawaited(
        player.play().catchError((Object error, StackTrace stackTrace) {
          debugPrint('novel typing sfx play failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }),
      );
    } catch (error, stackTrace) {
      debugPrint('novel typing sfx native tick failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _playWebTypingTick() async {
    if (_typingRestartInFlight) {
      _typingRestartQueued = true;
      return;
    }

    _typingRestartInFlight = true;
    final epoch = _typingPlaybackEpoch;
    try {
      do {
        _typingRestartQueued = false;
        await _prepareTypingPlayer();
        if (!_typingReady || epoch != _typingPlaybackEpoch) return;

        _duckWeatherForTyping();
        await _typingPlayer.setVolume(typingVolume);
        await _typingPlayer.seek(Duration.zero);
        if (epoch != _typingPlaybackEpoch) return;

        unawaited(
          _typingPlayer.play().catchError((Object error, StackTrace stackTrace) {
            debugPrint('novel typing sfx play failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }),
        );
      } while (_typingRestartQueued && epoch == _typingPlaybackEpoch);
    } catch (error, stackTrace) {
      debugPrint('novel typing sfx restart failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _typingReady = false;
    } finally {
      _typingRestartInFlight = false;
      if (_typingRestartQueued && epoch == _typingPlaybackEpoch) {
        _typingRestartQueued = false;
        unawaited(_playWebTypingTick());
      }
    }
  }

  Future<void> stopTypingSound() async {
    _typingPlaybackEpoch += 1;
    _typingRestartQueued = false;
    _lastTypingTickAt = null;
    _nativeTypingCursor = 0;
    _weatherDuckRestoreTimer?.cancel();
    _weatherDuckRestoreTimer = null;
    await Future.wait(
      _typingPlayers.map((player) async {
        try {
          await player.stop();
        } catch (_) {}
      }),
    );
    if (isWeatherPlaying && _weatherPlayer.playing) {
      await _weatherPlayer.setVolume(_currentWeatherTargetVolume());
    }
  }

  Future<void> loadPreference() async {
    enabled = await _prefs.getBool('app_setting_bgm') ?? true;
  }

  void setConfig(JsonMap config) {
    _config = config;
  }

  String? _getUrl(String sceneMode, String intensity) {
    final mode = asJsonMap(_config[sceneMode]);
    final direct = stringValue(mode[intensity]);
    if (mode.containsKey(intensity) && direct.isEmpty) return null;
    if (direct.isNotEmpty) return direct;
    final fallback = asJsonMap(_config['default']);
    final fallbackUrl = stringValue(fallback[intensity]);
    return fallbackUrl.isEmpty ? null : fallbackUrl;
  }

  Future<void> init(String intensity, String sceneMode) async {
    currentIntensity = intensity;
    currentSceneMode = sceneMode;
    _debounceMap.clear();
    if (!enabled || sceneMode == 'silence') return;
    final url = _getUrl(sceneMode, intensity);
    if (url == null) return;
    await _playImmediately(url);
  }

  Future<void> update(String intensity, String sceneMode) async {
    if (sceneMode == 'silence') {
      currentSceneMode = 'silence';
      _debounceMap.clear();
      await fadeOut();
      return;
    }
    if (!enabled) return;
    final key = '${sceneMode}_$intensity';
    _debounceMap[key] = (_debounceMap[key] ?? 0) + 1;
    if ((_debounceMap[key] ?? 0) < debounceCount) return;
    _debounceMap.clear();
    if (currentIntensity == intensity && currentSceneMode == sceneMode) return;
    currentIntensity = intensity;
    currentSceneMode = sceneMode;
    final url = _getUrl(sceneMode, intensity);
    if (url != null) await switchTo(url);
  }

  Future<void> playUrl(
    String? url, {
    String? intensity,
    String? sceneMode,
  }) async {
    if (sceneMode == 'silence') {
      currentSceneMode = 'silence';
      await fadeOut();
      return;
    }
    if (!enabled || url == null || url.trim().isEmpty) return;
    currentIntensity = intensity ?? currentIntensity;
    currentSceneMode = sceneMode ?? currentSceneMode;
    await switchTo(url);
  }

  Future<void> _playImmediately(String url) async {
    await _player.setLoopMode(LoopMode.one);
    await _player.setVolume(defaultVolume);
    await _player.setUrl(url);
    unawaited(_player.play());
    isPlaying = true;
  }

  Future<void> switchTo(String url) async {
    final switchId = ++_switchId;
    await fadeOut();
    if (switchId != _switchId || !enabled) return;
    await _player.setLoopMode(LoopMode.one);
    await _player.setUrl(url);
    await fadeIn();
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final completer = _fadeCompleter;
    _fadeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> fadeOut([Duration? duration]) async {
    _cancelFade();
    if (!_player.playing) {
      isPlaying = false;
      return;
    }
    final total = duration ?? fadeDuration;
    final startVolume = _player.volume;
    final completer = Completer<void>();
    _fadeCompleter = completer;
    const tick = Duration(milliseconds: 50);
    final steps = (total.inMilliseconds / tick.inMilliseconds).ceil().clamp(1, 1000).toInt();
    var current = 0;
    _fadeTimer = Timer.periodic(tick, (timer) async {
      current += 1;
      final progress = current / steps;
      await _player.setVolume((startVolume * (1 - progress)).clamp(0.0, 1.0).toDouble());
      if (current >= steps) {
        timer.cancel();
        await _player.pause();
        await _player.setVolume(0);
        isPlaying = false;
        if (!completer.isCompleted) completer.complete();
        if (identical(_fadeCompleter, completer)) _fadeCompleter = null;
      }
    });
    await completer.future;
  }

  Future<void> fadeIn([Duration? duration]) async {
    _cancelFade();
    final total = duration ?? fadeDuration;
    await _player.setVolume(0);
    unawaited(_player.play());
    isPlaying = true;
    final completer = Completer<void>();
    _fadeCompleter = completer;
    const tick = Duration(milliseconds: 50);
    final steps = (total.inMilliseconds / tick.inMilliseconds).ceil().clamp(1, 1000).toInt();
    var current = 0;
    _fadeTimer = Timer.periodic(tick, (timer) async {
      current += 1;
      final progress = current / steps;
      await _player.setVolume((defaultVolume * progress).clamp(0.0, defaultVolume).toDouble());
      if (current >= steps) {
        timer.cancel();
        await _player.setVolume(defaultVolume);
        if (!completer.isCompleted) completer.complete();
        if (identical(_fadeCompleter, completer)) _fadeCompleter = null;
      }
    });
    await completer.future;
  }

  /// 保留初始化入口，但不再用真实天气播放器预载 rain.mp3。
  ///
  /// 旧实现会把 rain.mp3 固定塞进 _weatherPlayer 再 pause；之后雷暴雨也复用
  /// 同一个播放器切 source。理论上 setAsset 会替换，但 Web 端音频状态切换容易造成
  /// 旧 source 残留/听感混淆。天气资源现在只在 setWeatherAmbient 中按当前 key 加载。
  Future<void> preloadWeatherAmbient() async {
    return;
  }

  static const Map<String, String> weatherAssets = <String, String>{
    'rain': 'assets/audio/weather/rain.mp3',
    'snow': 'assets/audio/weather/snow.mp3',
    'thunderstorm': 'assets/audio/weather/thunderstorm.mp3',
  };

  double _weatherVolume(String key) {
    return switch (key) {
      'thunderstorm' => .48,
      'rain' => .40,
      'snow' => .27,
      _ => .0,
    };
  }

  void _cancelWeatherFade() {
    _weatherFadeTimer?.cancel();
    _weatherFadeTimer = null;
    final completer = _weatherFadeCompleter;
    _weatherFadeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> _fadeWeatherOut([Duration? duration]) async {
    _cancelWeatherFade();
    if (!_weatherPlayer.playing) {
      isWeatherPlaying = false;
      return;
    }

    final total = duration ?? const Duration(milliseconds: 900);
    final startVolume = _weatherPlayer.volume;
    final completer = Completer<void>();
    _weatherFadeCompleter = completer;
    const tick = Duration(milliseconds: 50);
    final steps = (total.inMilliseconds / tick.inMilliseconds)
        .ceil()
        .clamp(1, 1000)
        .toInt();
    var current = 0;

    _weatherFadeTimer = Timer.periodic(tick, (timer) async {
      current += 1;
      final progress = current / steps;
      await _weatherPlayer.setVolume(
        (startVolume * (1 - progress)).clamp(0.0, 1.0).toDouble(),
      );
      if (current >= steps) {
        timer.cancel();
        await _weatherPlayer.pause();
        await _weatherPlayer.setVolume(0);
        isWeatherPlaying = false;
        if (!completer.isCompleted) completer.complete();
        if (identical(_weatherFadeCompleter, completer)) {
          _weatherFadeCompleter = null;
        }
      }
    });
    await completer.future;
  }

  Future<void> _fadeWeatherIn(
    String key, [
    Duration? duration,
  ]) async {
    _cancelWeatherFade();
    final targetVolume = _weatherVolume(key);
    final total = duration ?? const Duration(milliseconds: 1200);
    await _weatherPlayer.setVolume(0);
    unawaited(_weatherPlayer.play());
    isWeatherPlaying = true;

    final completer = Completer<void>();
    _weatherFadeCompleter = completer;
    const tick = Duration(milliseconds: 50);
    final steps = (total.inMilliseconds / tick.inMilliseconds)
        .ceil()
        .clamp(1, 1000)
        .toInt();
    var current = 0;

    _weatherFadeTimer = Timer.periodic(tick, (timer) async {
      current += 1;
      final progress = current / steps;
      await _weatherPlayer.setVolume(
        (targetVolume * progress).clamp(0.0, targetVolume).toDouble(),
      );
      if (current >= steps) {
        timer.cancel();
        await _weatherPlayer.setVolume(targetVolume);
        if (!completer.isCompleted) completer.complete();
        if (identical(_weatherFadeCompleter, completer)) {
          _weatherFadeCompleter = null;
        }
      }
    });
    await completer.future;
  }

  /// 独立于剧情 BGM 的天气环境音。
  /// 当前测试阶段只认手动天气 key，不读取后端 world.weather。
  Future<void> setWeatherAmbient(
    String weatherKey, {
    bool effectsEnabled = true,
    bool force = false,
  }) async {
    final normalized = weatherKey.trim().toLowerCase();
    final nextKey = weatherAssets.containsKey(normalized) ? normalized : 'none';

    if (!force && currentWeatherKey == nextKey) {
      if (!effectsEnabled && isWeatherPlaying) {
        _weatherSwitchId += 1;
        await _fadeWeatherOut(const Duration(milliseconds: 700));
      }
      return;
    }

    currentWeatherKey = nextKey;
    final switchId = ++_weatherSwitchId;
    await _fadeWeatherOut(const Duration(milliseconds: 850));
    if (switchId != _weatherSwitchId) return;

    if (!effectsEnabled || nextKey == 'none') {
      return;
    }

    final asset = weatherAssets[nextKey];
    if (asset == null) return;

    try {
      // 强制释放上一种天气的 source，再加载当前天气。
      // 这样 thunderstorm 永远只会绑定 thunderstorm.mp3，不会沿用 rain.mp3。
      await _weatherPlayer.stop();
      await _weatherPlayer.setVolume(0);
      await _weatherPlayer.setLoopMode(LoopMode.one);
      await _weatherPlayer.setAsset(asset);
      if (switchId != _weatherSwitchId) return;
      await _fadeWeatherIn(nextKey);
    } catch (_) {
      // 音频文件尚未放入 assets / pubspec 未声明时不影响剧情页运行。
      await _weatherPlayer.stop();
      isWeatherPlaying = false;
    }
  }

  Future<void> stopWeatherAmbient({bool fade = true}) async {
    currentWeatherKey = 'none';
    _weatherSwitchId += 1;
    if (fade) {
      await _fadeWeatherOut(const Duration(milliseconds: 700));
    } else {
      _cancelWeatherFade();
      await _weatherPlayer.stop();
      isWeatherPlaying = false;
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    await _prefs.setBool('app_setting_bgm', value);
    if (!value) {
      _switchId += 1;
      await fadeOut(const Duration(milliseconds: 800));
      return;
    }
    final url = _getUrl(currentSceneMode, currentIntensity);
    if (url != null) await _playImmediately(url);
  }

  Future<void> stop() async {
    _switchId += 1;
    _weatherSwitchId += 1;
    _cancelFade();
    _cancelWeatherFade();
    _weatherDuckRestoreTimer?.cancel();
    _weatherDuckRestoreTimer = null;
    await _player.stop();
    await _weatherPlayer.stop();
    await stopTypingSound();
    isPlaying = false;
    isWeatherPlaying = false;
  }

  Future<void> dispose() async {
    _typingPlaybackEpoch += 1;
    _typingRestartQueued = false;
    _cancelFade();
    _cancelWeatherFade();
    _weatherDuckRestoreTimer?.cancel();
    _weatherDuckRestoreTimer = null;
    await _player.dispose();
    await _weatherPlayer.dispose();
    await Future.wait(
      _typingPlayers.map((player) => player.dispose()),
    );
  }
}

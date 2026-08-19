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
        _typingPlayer = typingPlayer ?? AudioPlayer();

  final AudioPlayer _player;
  final AudioPlayer _weatherPlayer;
  final AudioPlayer _typingPlayer;
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

  // 打字声改为一句话期间的连续低音量纹理，不再按字符反复 seek + play。
  // 旧实现高频重启播放器，在手机上容易产生音频线程抖动和不连续感。
  static const double typingVolume = 0.20;
  static const Duration typingIdleGrace = Duration(milliseconds: 110);
  static const Duration typingFadeDuration = Duration(milliseconds: 90);

  bool _typingReady = false;
  bool _typingPlaying = false;
  Future<void>? _typingPrepareFuture;
  Future<void>? _typingStartFuture;
  Timer? _typingIdleTimer;
  int _typingPlaybackEpoch = 0;
  int _typingFadeEpoch = 0;

  /// 预加载连续打字音效。资源缺失时静默降级。
  Future<void> preloadTypingSfx() async {
    await _prepareTypingPlayer();
  }

  Future<void> _prepareTypingPlayer() async {
    if (_typingReady) return;
    final existing = _typingPrepareFuture;
    if (existing != null) return existing;

    final future = () async {
      try {
        // 单播放器常驻，整段逐字显示期间只启动一次。
        await _typingPlayer.setLoopMode(LoopMode.one);
        await _typingPlayer.setVolume(0);
        await _typingPlayer.setAsset(typingAsset);
        _typingReady = true;
      } catch (error, stackTrace) {
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

  /// 保留旧接口名，调用方仍可在逐字动画每次推进时调用。
  ///
  /// 新实现不会每次播放一个 tick；第一次调用启动循环，后续调用只刷新
  /// “仍在打字”的保活时间。超过 [typingIdleGrace] 没有新字符就自动淡出。
  void playTypingTick() {
    _typingIdleTimer?.cancel();
    _cancelTypingFade(restoreVolume: true);

    _typingIdleTimer = Timer(typingIdleGrace, () {
      _typingIdleTimer = null;
      unawaited(_fadeTypingOut());
    });

    if (_typingPlaying || _typingStartFuture != null) return;
    _typingStartFuture = _startTypingLoop();
  }

  Future<void> _startTypingLoop() async {
    final epoch = _typingPlaybackEpoch;
    try {
      await _prepareTypingPlayer();
      if (!_typingReady || epoch != _typingPlaybackEpoch) return;

      await _typingPlayer.setVolume(typingVolume);
      if (epoch != _typingPlaybackEpoch) return;

      _typingPlaying = true;
      unawaited(
        _typingPlayer.play().catchError((Object error, StackTrace stackTrace) {
          debugPrint('novel typing sfx play failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _typingPlaying = false;
        }),
      );
    } catch (error, stackTrace) {
      debugPrint('novel typing sfx start failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _typingReady = false;
      _typingPlaying = false;
    } finally {
      _typingStartFuture = null;
    }
  }

  void _cancelTypingFade({bool restoreVolume = false}) {
    _typingFadeEpoch += 1;
    if (restoreVolume && _typingPlaying) {
      unawaited(_typingPlayer.setVolume(typingVolume));
    }
  }

  Future<void> _fadeTypingOut({bool explicitStop = false}) async {
    if (!_typingPlaying && _typingStartFuture == null) return;

    final fadeEpoch = ++_typingFadeEpoch;
    final playbackEpoch = _typingPlaybackEpoch;
    final startVolume = _typingPlayer.volume.clamp(0.0, typingVolume).toDouble();
    final steps = explicitStop ? 5 : 6;
    final stepDelay = Duration(
      milliseconds: (typingFadeDuration.inMilliseconds / steps).round(),
    );

    for (var i = 1; i <= steps; i += 1) {
      await Future<void>.delayed(stepDelay);
      if (fadeEpoch != _typingFadeEpoch ||
          playbackEpoch != _typingPlaybackEpoch) {
        return;
      }
      final progress = i / steps;
      await _typingPlayer.setVolume(
        (startVolume * (1 - progress)).clamp(0.0, typingVolume).toDouble(),
      );
    }

    if (fadeEpoch != _typingFadeEpoch ||
        playbackEpoch != _typingPlaybackEpoch) {
      return;
    }

    try {
      await _typingPlayer.pause();
      await _typingPlayer.setVolume(0);
    } catch (_) {}
    _typingPlaying = false;
  }

  Future<void> stopTypingSound() async {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;

    // 让尚在 await 预加载/启动的旧请求失效，避免 stop 后又突然响起来。
    _typingPlaybackEpoch += 1;
    _cancelTypingFade();

    final pendingStart = _typingStartFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {}
    }

    if (_typingPlaying) {
      await _fadeTypingOut(explicitStop: true);
    } else {
      try {
        await _typingPlayer.pause();
        await _typingPlayer.setVolume(0);
      } catch (_) {}
    }
    _typingPlaying = false;
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
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    await _player.stop();
    await _weatherPlayer.stop();
    await stopTypingSound();
    isPlaying = false;
    isWeatherPlaying = false;
  }

  Future<void> dispose() async {
    _typingPlaybackEpoch += 1;
    _typingFadeEpoch += 1;
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    _cancelFade();
    _cancelWeatherFade();
    await _player.dispose();
    await _weatherPlayer.dispose();
    await _typingPlayer.dispose();
  }
}

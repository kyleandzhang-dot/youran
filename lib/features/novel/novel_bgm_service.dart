import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'novel_models.dart';

class NovelBgmService {
  NovelBgmService({
    AudioPlayer? player,
    AudioPlayer? weatherPlayer,
    this.defaultVolume = 0.35,
    this.fadeDuration = const Duration(milliseconds: 1500),
    this.debounceCount = 2,
  })  : _player = player ?? AudioPlayer(),
        _weatherPlayer = weatherPlayer ?? AudioPlayer();

  final AudioPlayer _player;
  final AudioPlayer _weatherPlayer;
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

  static const Map<String, String> weatherAssets = <String, String>{
    'rain': 'assets/audio/weather/rain.mp3',
    'snow': 'assets/audio/weather/snow.mp3',
    'thunderstorm': 'assets/audio/weather/thunderstorm.mp3',
  };

  double _weatherVolume(String key) {
    // 天气是独立环境音轨；整体提高存在感，但雪天仍保持更克制。
    // 剧情 BGM 使用另一条 AudioPlayer，不会被这里的音量覆盖。
    return switch (key) {
      'thunderstorm' => .78,
      'rain' => .65,
      'snow' => .42,
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
    await _player.stop();
    await _weatherPlayer.stop();
    isPlaying = false;
    isWeatherPlaying = false;
  }

  Future<void> dispose() async {
    _cancelFade();
    _cancelWeatherFade();
    await _player.dispose();
    await _weatherPlayer.dispose();
  }
}

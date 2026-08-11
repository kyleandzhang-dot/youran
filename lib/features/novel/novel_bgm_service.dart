import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'novel_models.dart';

class NovelBgmService {
  NovelBgmService({
    AudioPlayer? player,
    this.defaultVolume = 0.35,
    this.fadeDuration = const Duration(milliseconds: 1500),
    this.debounceCount = 2,
  }) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
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
    _cancelFade();
    await _player.stop();
    isPlaying = false;
  }

  Future<void> dispose() async {
    _cancelFade();
    await _player.dispose();
  }
}

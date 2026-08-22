import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

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

  // 参考 Web 版 AudioContext：每个 tick 是约 25ms 的随机噪声，
  // 经 4–4.5kHz 带通滤波并快速指数衰减。
  //
  // 手机原生媒体播放器并不擅长反复重播 25ms 的独立音频；部分机型只会
  // 响一两次便停在 completed 状态。因此这里把多个 tick 预先排进一条
  // 较长的内存声轨并循环播放，文字出现时只负责“续时”，不再反复 seek。
  static const int _typingSampleRate = 44100;
  static const int _typingDurationMs = 25;
  static const int _typingSpacingMs = 90;
  static const int _typingRailTickCount = 16;
  // 手机扬声器对 4kHz 左右的瞬态很敏感；稍微压低，保留清晰度但不刺耳。
  static const double typingVolume = 0.38;
  static const Duration _typingIdleTimeout = Duration(milliseconds: 230);

  bool _typingReady = false;
  Future<void>? _typingPrepareFuture;
  Timer? _typingIdleTimer;
  bool _typingRailPlaying = false;
  int _typingPlaybackEpoch = 0;
  int _typingPulseId = 0;

  Uint8List _buildTypingRailBytes() {
    final tickSamples =
        (_typingSampleRate * _typingDurationMs / 1000).round();
    final spacingSamples =
        (_typingSampleRate * _typingSpacingMs / 1000).round();
    final pcm = Int16List(spacingSamples * _typingRailTickCount);

    for (var tick = 0; tick < _typingRailTickCount; tick++) {
      final random = math.Random(0x51F15E + tick * 7919);

      // 对应参考项目的 4000 + Math.random() * 500；每个 tick 略有变化，
      // 避免长时间播放时像完全相同的机械哔声。
      final centerHz = 4000.0 + (tick % 4) * 145.0;
      const q = 1.15;
      final w0 = 2 * math.pi * centerHz / _typingSampleRate;
      final alpha = math.sin(w0) / (2 * q);
      final a0 = 1 + alpha;
      final b0 = alpha / a0;
      const b1 = 0.0;
      final b2 = -alpha / a0;
      final a1 = (-2 * math.cos(w0)) / a0;
      final a2 = (1 - alpha) / a0;

      var x1 = 0.0;
      var x2 = 0.0;
      var y1 = 0.0;
      var y2 = 0.0;
      final offset = tick * spacingSamples;
      for (var i = 0; i < tickSamples; i++) {
        final input = random.nextDouble() * 2 - 1;
        final filtered =
            b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = input;
        y2 = y1;
        y1 = filtered;

        // 2ms 淡入去掉爆音，随后在约 20ms 内指数衰减到近乎静音。
        final progress = tickSamples <= 1 ? 1.0 : i / (tickSamples - 1);
        final attack = (i / (_typingSampleRate * .002)).clamp(0.0, 1.0);
        final decay = math.pow(0.001 / 0.15, progress).toDouble();
        final value = (filtered * attack * decay * .72).clamp(-1.0, 1.0);
        pcm[offset + i] = (value * 32767).round();
      }
    }

    // just_audio 的各原生后端需要一个可识别的内存音频容器。
    // 这里只包装运行时 PCM 字节，不存在或读取任何 wav 资源文件。
    final dataSize = pcm.lengthInBytes;
    final bytes = ByteData(44 + dataSize);

    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, _typingSampleRate, Endian.little);
    bytes.setUint32(28, _typingSampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      bytes.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// 预加载短促打字音效。资源缺失时静默降级。
  Future<void> preloadTypingSfx() async {
    await _prepareTypingPlayer();
  }

  Future<void> _prepareTypingPlayer() async {
    if (_typingReady) return;
    final existing = _typingPrepareFuture;
    if (existing != null) return existing;

    final future = () async {
      try {
        await _typingPlayer.setLoopMode(LoopMode.one);
        await _typingPlayer.setVolume(typingVolume);
        await _typingPlayer.setAudioSource(
          _MemoryTypingAudioSource(_buildTypingRailBytes()),
          preload: true,
        );
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

  /// 告知内存打字声轨“文字仍在出现”。
  ///
  /// 第一次调用启动循环声轨；后续调用只刷新空闲计时器。最后一个字符后
  /// 230ms 自动暂停，因此不会残留声音，也不会反复重启原生解码器。
  void playTypingTick() {
    if (!_typingReady) {
      // 初始化期间直接跳过当前 tick，不把字符事件排队；否则预加载完成后
      // 多个等待请求会挤在同一时刻播放，听起来像一次爆音。
      unawaited(_prepareTypingPlayer());
      return;
    }
    final pulseId = ++_typingPulseId;
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(_typingIdleTimeout, () {
      if (pulseId != _typingPulseId) return;
      unawaited(_pauseTypingRail(idlePulseId: pulseId));
    });

    if (_typingRailPlaying) return;
    _typingRailPlaying = true;
    unawaited(_startTypingRail());
  }

  Future<void> _startTypingRail() async {
    final epoch = _typingPlaybackEpoch;
    try {
      await _prepareTypingPlayer();
      if (!_typingReady || epoch != _typingPlaybackEpoch) return;

      await _typingPlayer.seek(Duration.zero);
      if (epoch != _typingPlaybackEpoch) return;
      unawaited(
        _typingPlayer.play().catchError((Object error, StackTrace stackTrace) {
          debugPrint('novel typing sfx play failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _typingRailPlaying = false;
        }),
      );
    } catch (error, stackTrace) {
      debugPrint('novel typing sfx play failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _typingRailPlaying = false;
      _typingReady = false;
    }
  }

  Future<void> _pauseTypingRail({int? idlePulseId}) async {
    if (idlePulseId != null && idlePulseId != _typingPulseId) return;
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    try {
      await _typingPlayer.pause();

      // pause 等待原生播放器响应期间可能正好又显示了新字符。新字符看到
      // _typingRailPlaying 仍为 true，不会重复启动播放器；这里恢复即可。
      if (idlePulseId != null && idlePulseId != _typingPulseId) {
        unawaited(
          _typingPlayer.play().catchError((Object error, StackTrace stackTrace) {
            debugPrint('novel typing sfx resume failed: $error');
            debugPrintStack(stackTrace: stackTrace);
            _typingRailPlaying = false;
          }),
        );
        return;
      }

      _typingRailPlaying = false;
      await _typingPlayer.seek(Duration.zero);
    } catch (_) {
      _typingRailPlaying = false;
    }
  }

  Future<void> stopTypingSound() async {
    // 让尚在 await 预加载/播放的旧请求失效，避免 stop 后又突然响起来。
    _typingPlaybackEpoch += 1;
    _typingPulseId += 1;
    await _pauseTypingRail();
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
    await _player.stop();
    await _weatherPlayer.stop();
    await stopTypingSound();
    isPlaying = false;
    isWeatherPlaying = false;
  }

  Future<void> dispose() async {
    _typingPlaybackEpoch += 1;
    _typingPulseId += 1;
    _typingIdleTimer?.cancel();
    _cancelFade();
    _cancelWeatherFade();
    await _player.dispose();
    await _weatherPlayer.dispose();
    await _typingPlayer.dispose();
  }
}

class _MemoryTypingAudioSource extends StreamAudioSource {
  _MemoryTypingAudioSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final safeStart = (start ?? 0).clamp(0, bytes.length).toInt();
    final safeEnd = (end ?? bytes.length).clamp(safeStart, bytes.length).toInt();
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      stream: Stream<List<int>>.value(
        bytes.sublist(safeStart, safeEnd),
      ),
      contentType: 'audio/wav',
    );
  }
}

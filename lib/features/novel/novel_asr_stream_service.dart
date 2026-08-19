import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'novel_socket_service.dart';

class NovelAsrStreamException implements Exception {
  const NovelAsrStreamException(this.message, {this.code = ''});
  final String message;
  final String code;

  @override
  String toString() => message;
}

/// 按住说话专用：PCM16/16k/mono 从手机边录边传到 /asr/stream。
/// 中间识别结果只缓存在内存；松手后只返回豆包最终结果，不会自动发送剧情。
class NovelAsrStreamService {
  NovelAsrStreamService({required this.socketService});

  final NovelSocketService socketService;
  final AudioRecorder _recorder = AudioRecorder();

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Completer<void>? _readyCompleter;
  Completer<String>? _finalCompleter;
  Completer<void>? _audioDoneCompleter;
  Stopwatch? _captureWatch;

  final List<Uint8List> _preReadyAudio = <Uint8List>[];
  int _preReadyBytes = 0;
  static const int _maxPreReadyBytes = 480000; // 约 15 秒 PCM，覆盖后端最坏握手预算且防止无限占内存。

  // 本地 VAD：先确认确实有人声，再允许 PCM 穿过网络闸门。
  // 16k / PCM16 / mono 下每个 stream buffer 约 100ms；连续 3 个块达到 -42dBFS
  // 才认为是有效说话，能过滤纯静音和多数稳定底噪。
  static const Duration minimumSpeechDuration = Duration(seconds: 1);
  static const double _voiceRmsThresholdDb = -42.0;
  static const int _voiceChunksRequired = 3;
  bool _voiceDetected = false;
  bool _audioGateOpen = false;
  int _consecutiveVoiceChunks = 0;
  double _maxPcmRmsDb = -160.0;

  static const Duration _gatewayConnectTimeout = Duration(seconds: 5);
  static const Duration _providerReadyTimeout = Duration(seconds: 12);
  static const Duration _finalResultTimeout = Duration(seconds: 15);

  bool _channelReady = false;
  bool _recording = false;
  bool _sessionOpen = false;
  bool _ending = false;
  bool _discardAudio = false;
  String _latestPartial = '';
  double _maxAmplitudeDb = -160.0;
  int _localAudioBytes = 0;
  bool _sawNonZeroPcm = false;
  String _inputDeviceLabel = '';

  Future<InputDevice?> _selectWebInputDevice() async {
    if (!kIsWeb) return null;
    try {
      final devices = await _recorder.listInputDevices();
      if (devices.isEmpty) {
        debugPrint('[ASR] Web 没有枚举到麦克风输入设备');
        return null;
      }

      for (final device in devices) {
        debugPrint('[ASR] input device: ${device.label} (${device.id})');
      }

      // Chrome/Windows 经常同时暴露真实麦克风、Default/Communications 别名，
      // 以及 Steam Streaming Microphone / Stereo Mix / VB-Cable 等虚拟输入。
      // 上一版“取第一个看起来不像 virtual 的设备”会误选 Steam Streaming Microphone，
      // 它在当前机器上返回全 0 PCM。因此改成评分选择：优先内置/阵列麦克风，
      // 明确排除常见回环/虚拟输入；找不到可靠实体设备时再交回系统默认。
      int scoreDevice(InputDevice device) {
        final v = device.label.toLowerCase().trim();
        if (v.isEmpty) return -10000;

        // 明确无效/虚拟输入：直接淘汰。
        if (v.contains('steam streaming') ||
            v.contains('stereo mix') ||
            v.contains('what u hear') ||
            v.contains('loopback') ||
            v.contains('vb-audio') ||
            v.contains('voicemeeter') ||
            v.contains('cable input') ||
            v.contains('cable output') ||
            v.contains('立体声混音') ||
            v.contains('扬声器')) {
          return -10000;
        }

        var score = 0;

        // 真实内置麦克风最优先。当前机器的 Senary Audio 就属于这一类。
        if (v.contains('microphone array') || v.contains('麦克风阵列')) score += 100;
        if (v.contains('array')) score += 40;
        if (v.contains('senary')) score += 35;
        if (v.contains('realtek')) score += 25;
        if (v.contains('built-in') || v.contains('internal') || v.contains('内置')) score += 20;
        if (v.contains('microphone') || v.contains('麦克风')) score += 10;

        // Default / Communications 只是别名，不优先于枚举到的实体设备。
        if (device.id == 'default' ||
            v.startsWith('default -') ||
            v.contains('默认')) {
          score -= 25;
        }
        if (device.id == 'communications' || v.contains('communications') || v.contains('通讯')) {
          score -= 35;
        }

        // 泛化的 virtual/cable 设备也降权，但不直接误伤某些用户主动安装的降噪麦克风。
        if (v.contains('virtual') || v.contains('cable')) score -= 80;

        return score;
      }

      final ranked = [...devices]
        ..sort((a, b) => scoreDevice(b).compareTo(scoreDevice(a)));
      final selected = ranked.first;
      final selectedScore = scoreDevice(selected);

      if (selectedScore <= -1000) {
        _inputDeviceLabel = '系统默认麦克风';
        debugPrint('[ASR] 没有找到可靠实体麦克风，回退系统默认输入');
        return null;
      }

      _inputDeviceLabel = selected.label.trim();
      debugPrint(
        '[ASR] selected input device: ${selected.label} (${selected.id}) score=$selectedScore',
      );
      return selected;
    } catch (error) {
      debugPrint('[ASR] 枚举麦克风失败，回退系统默认设备: $error');
      return null;
    }
  }

  bool get isSessionOpen => _sessionOpen;
  bool get isRecording => _recording;
  bool get hasDetectedVoice => _voiceDetected;
  String get latestPartial => _latestPartial;

  String _asrPath() {
    final source = socketService.path.trim();
    final normalized = source.startsWith('/') ? source : '/$source';
    final wsIndex = normalized.indexOf('/ws/');
    if (wsIndex >= 0) {
      final prefix = normalized.substring(0, wsIndex);
      return '$prefix/asr/stream';
    }
    if (normalized.endsWith('/ws')) {
      return '${normalized.substring(0, normalized.length - 3)}/asr/stream';
    }
    return '/api/v1/asr/stream';
  }

  Uri _buildUri(String token, String userId) {
    var base = socketService.baseUrl.trim();
    if (base.startsWith('http://')) {
      base = 'ws://${base.substring(7)}';
    } else if (base.startsWith('https://')) {
      base = 'wss://${base.substring(8)}';
    }
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);

    final path = _asrPath();
    final baseUri = Uri.parse(base);
    var effectivePath = path;
    // baseUrl 自己已经含 /api/v1 时，避免拼成 /api/v1/api/v1/asr/stream。
    if (baseUri.path.endsWith('/api/v1') && path.startsWith('/api/v1/')) {
      effectivePath = path.substring('/api/v1'.length);
    }
    final joined = Uri.parse('$base$effectivePath');
    return joined.replace(queryParameters: <String, String>{
      ...joined.queryParameters,
      'user_id': userId,
      'token': token,
    });
  }

  Future<void> start() async {
    if (_sessionOpen || _recording) return;
    await _resetTransport();

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const NovelAsrStreamException(
        '请允许麦克风权限后再使用语音输入。',
        code: 'MIC_PERMISSION_DENIED',
      );
    }
    final pcmSupported = await _recorder.isEncoderSupported(AudioEncoder.pcm16bits);
    if (!pcmSupported) {
      throw const NovelAsrStreamException(
        '当前设备不支持实时 PCM 录音。',
        code: 'PCM_NOT_SUPPORTED',
      );
    }

    final token = (await socketService.tokenProvider())?.trim() ?? '';
    final userId = (await socketService.userIdProvider())?.trim() ?? '';
    if (token.isEmpty || userId.isEmpty) {
      throw const NovelAsrStreamException(
        '登录状态已失效，请重新登录后再试。',
        code: 'AUTH_REQUIRED',
      );
    }

    _readyCompleter = Completer<void>();
    _finalCompleter = Completer<String>();
    // start() 现在不再等待豆包 provider ready；先挂一个错误观察器，
    // 避免上游在用户松手前失败时产生未处理 Future error。
    // 原 Future 仍可在 stopAndGetFinal() 中再次 await 并拿到同一个错误。
    unawaited(_readyCompleter!.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    unawaited(_finalCompleter!.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    _latestPartial = '';
    _maxAmplitudeDb = -160.0;
    _maxPcmRmsDb = -160.0;
    _localAudioBytes = 0;
    _sawNonZeroPcm = false;
    _voiceDetected = false;
    _audioGateOpen = false;
    _consecutiveVoiceChunks = 0;
    _inputDeviceLabel = '';
    _channelReady = false;
    _ending = false;
    _discardAudio = false;
    _sessionOpen = true;

    try {
      // Web 上不要盲信系统 default 麦克风：它可能指向虚拟/无信号设备。
      // 明确选择一个真实输入；同时先关闭浏览器 AGC/AEC/NS，保证拿到最原始的 PCM。
      final inputDevice = await _selectWebInputDevice();
      final audioStream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: inputDevice,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
          streamBufferSize: 3200, // 约 100ms PCM16 单声道。
        ),
      );
      _recording = true;
      _captureWatch = Stopwatch()..start();
      _audioDoneCompleter = Completer<void>();
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((Amplitude amplitude) {
        if (amplitude.current > _maxAmplitudeDb) {
          _maxAmplitudeDb = amplitude.current;
        }
      }, onError: (_) {});

      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          _failSession(
            NovelAsrStreamException('麦克风录音中断，请重试：$error', code: 'RECORD_ERROR'),
          );
        },
        onDone: () {
          final done = _audioDoneCompleter;
          if (done != null && !done.isCompleted) done.complete();
        },
      );

      final uri = _buildUri(token, userId);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(_gatewayConnectTimeout);

      _socketSubscription = channel.stream.listen(
        _handleSocketMessage,
        onError: (Object error, StackTrace stackTrace) {
          _failSession(
            NovelAsrStreamException('语音连接中断，请重试。', code: 'SOCKET_ERROR'),
          );
        },
        onDone: () {
          if (_sessionOpen && !(_finalCompleter?.isCompleted ?? true)) {
            _failSession(
              const NovelAsrStreamException('语音连接已断开，请重试。', code: 'SOCKET_CLOSED'),
            );
          }
        },
        cancelOnError: false,
      );

      // 这里只等待 Flutter -> 自己后端的 WebSocket 建好，不再阻塞到豆包上游 ready。
      // 录音已经开始，豆包握手期间的 PCM 会继续缓存在 _preReadyAudio。
      // 这样按下麦克风几乎立即进入录音状态；上游连接与用户说话并行进行。
    } on TimeoutException {
      await cancel();
      throw const NovelAsrStreamException('连接语音服务超时，请重试。', code: 'CONNECT_TIMEOUT');
    } catch (error) {
      if (error is NovelAsrStreamException) rethrow;
      await cancel();
      throw NovelAsrStreamException('无法启动语音输入：$error', code: 'START_FAILED');
    }
  }

  double _pcmRmsDb(Uint8List chunk) {
    if (chunk.length < 2) return -160.0;

    var samples = 0;
    var sumSquares = 0.0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      var sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample >= 0x8000) sample -= 0x10000;
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
      samples++;
    }
    if (samples == 0) return -160.0;
    final rms = math.sqrt(sumSquares / samples);
    if (rms <= 0.0000001) return -160.0;
    return 20.0 * math.log(rms) / math.ln10;
  }

  void _updateLocalVoiceActivity(Uint8List chunk) {
    final rmsDb = _pcmRmsDb(chunk);
    if (rmsDb > _maxPcmRmsDb) _maxPcmRmsDb = rmsDb;

    if (rmsDb >= _voiceRmsThresholdDb) {
      _consecutiveVoiceChunks++;
      if (_consecutiveVoiceChunks >= _voiceChunksRequired) {
        _voiceDetected = true;
      }
    } else {
      _consecutiveVoiceChunks = 0;
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    // stop() 期间仍允许 recorder 把最后几个 PCM buffer 冲出来。
    if (!_sessionOpen || _discardAudio || chunk.isEmpty) return;

    _localAudioBytes += chunk.length;
    if (!_sawNonZeroPcm) {
      _sawNonZeroPcm = chunk.any((value) => value != 0);
    }
    _updateLocalVoiceActivity(chunk);

    // 无论网络是否 ready，先在本地保存。只有同时满足：
    // 1) 检测到连续有效人声；2) 已按住至少 1 秒，才打开网络音频闸门。
    _preReadyAudio.add(Uint8List.fromList(chunk));
    _preReadyBytes += chunk.length;
    while (_preReadyBytes > _maxPreReadyBytes && _preReadyAudio.isNotEmpty) {
      final removed = _preReadyAudio.removeAt(0);
      _preReadyBytes -= removed.length;
    }

    final captureMs = _captureWatch?.elapsedMilliseconds ?? 0;
    if (!_audioGateOpen &&
        _voiceDetected &&
        captureMs >= minimumSpeechDuration.inMilliseconds) {
      _audioGateOpen = true;
      debugPrint(
        '[ASR] local VAD passed: capture=${captureMs}ms maxRms=${_maxPcmRmsDb.toStringAsFixed(1)}dBFS',
      );
    }

    if (_audioGateOpen && _channelReady && _channel != null) {
      _flushPreReadyAudio();
    }
  }

  void _flushPreReadyAudio() {
    final channel = _channel;
    if (!_channelReady || channel == null) return;
    for (final chunk in _preReadyAudio) {
      channel.sink.add(chunk);
    }
    _preReadyAudio.clear();
    _preReadyBytes = 0;
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final String text;
      if (raw is String) {
        text = raw;
      } else if (raw is List<int>) {
        text = utf8.decode(raw);
      } else {
        return;
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final type = (data['type'] ?? '').toString().toLowerCase();

      if (type == 'ready') {
        _channelReady = true;
        if (_audioGateOpen) _flushPreReadyAudio();
        final ready = _readyCompleter;
        if (ready != null && !ready.isCompleted) ready.complete();
        return;
      }
      if (type == 'partial') {
        final value = (data['text'] ?? '').toString().trim();
        if (value.isNotEmpty) _latestPartial = value;
        return;
      }
      if (type == 'final') {
        final value = (data['text'] ?? '').toString().trim();
        final completer = _finalCompleter;
        if (completer != null && !completer.isCompleted) completer.complete(value);
        return;
      }
      if (type == 'error') {
        _failSession(
          NovelAsrStreamException(
            (data['message'] ?? '语音识别失败，请重试。').toString(),
            code: (data['code'] ?? 'ASR_ERROR').toString(),
          ),
        );
      }
    } catch (_) {
      // 忽略无法识别的非业务 WS 消息。
    }
  }

  Future<String> stopAndGetFinal() async {
    if (!_sessionOpen) return '';
    if (_ending) {
      final existing = _finalCompleter;
      return existing == null ? '' : existing.future;
    }
    _ending = true;

    try {
      // 以用户松手时刻作为真实录音时长，后端可用 bytes / duration 推断浏览器实际采样率。
      final captureMs = _captureWatch?.elapsedMilliseconds ?? 0;
      _captureWatch?.stop();

      if (_recording) {
        await _recorder.stop();
        _recording = false;
      }
      // 等待 record stream 的 onDone，让 stop() 触发的最后 PCM buffer 真正进入监听器。
      final audioDone = _audioDoneCompleter;
      if (audioDone != null && !audioDone.isCompleted) {
        try {
          await audioDone.future.timeout(const Duration(milliseconds: 300));
        } catch (_) {}
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      // 双保险：短按或全程没有检测到有效人声时，绝不发送 end，
      // 更不会把本地缓存的静音 PCM 冲给识别服务。只发 cancel 关闭空会话。
      if (captureMs < minimumSpeechDuration.inMilliseconds) {
        try {
          _channel?.sink.add(jsonEncode(const <String, dynamic>{'type': 'cancel'}));
        } catch (_) {}
        throw const NovelAsrStreamException(
          '说话太短了',
          code: 'AUDIO_TOO_SHORT',
        );
      }
      if (!_voiceDetected) {
        try {
          _channel?.sink.add(jsonEncode(const <String, dynamic>{'type': 'cancel'}));
        } catch (_) {}
        throw const NovelAsrStreamException(
          '没有检测到有效说话声，请靠近麦克风再试。',
          code: 'NO_VOICE',
        );
      }

      _audioGateOpen = true;

      if (_channel == null) {
        throw const NovelAsrStreamException('语音连接已断开，请重试。', code: 'SOCKET_CLOSED');
      }

      // 用户可能在豆包握手完成前就已经松手。此时不要直接报 NOT_READY，
      // 而是等待上游 ready，再一次性冲刷握手期间缓存的 PCM。
      if (!_channelReady) {
        final ready = _readyCompleter;
        if (ready == null) {
          throw const NovelAsrStreamException('语音服务尚未连接完成，请重试。', code: 'NOT_READY');
        }
        await ready.future.timeout(_providerReadyTimeout);
        _channelReady = true;
      }

      _flushPreReadyAudio();
      debugPrint(
        '[ASR] capture summary: bytes=$_localAudioBytes nonzero=$_sawNonZeroPcm '
        'voice=$_voiceDetected maxRms=${_maxPcmRmsDb.toStringAsFixed(1)}dBFS '
        'maxDb=${_maxAmplitudeDb.toStringAsFixed(1)} device=$_inputDeviceLabel',
      );
      _channel!.sink.add(jsonEncode(<String, dynamic>{
        'type': 'end',
        'capture_ms': captureMs,
        'frontend_audio_bytes': _localAudioBytes,
        'frontend_nonzero_pcm': _sawNonZeroPcm,
        'frontend_voice_detected': _voiceDetected,
        'frontend_pcm_rms_db': _maxPcmRmsDb,
        'frontend_max_db': _maxAmplitudeDb,
        'input_device': _inputDeviceLabel,
      }));

      final completer = _finalCompleter;
      if (completer == null) return '';
      final result = await completer.future.timeout(_finalResultTimeout);
      await _resetTransport();
      return result.trim();
    } on TimeoutException {
      final fallback = _latestPartial.trim();
      await _resetTransport();
      if (fallback.isNotEmpty) return fallback;
      throw const NovelAsrStreamException('语音识别结果返回超时，请重试。', code: 'FINAL_TIMEOUT');
    } catch (_) {
      await _resetTransport();
      rethrow;
    }
  }

  Future<void> cancel() async {
    _discardAudio = true;
    _captureWatch?.stop();
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(const <String, dynamic>{'type': 'cancel'}));
      } catch (_) {}
    }
    try {
      if (_recording) await _recorder.cancel();
    } catch (_) {}
    _recording = false;
    await _resetTransport();
  }

  void _failSession(NovelAsrStreamException error) {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    final finalResult = _finalCompleter;
    if (finalResult != null && !finalResult.isCompleted) finalResult.completeError(error);
  }

  Future<void> _resetTransport() async {
    _channelReady = false;
    _sessionOpen = false;
    _ending = false;
    _discardAudio = false;
    _preReadyAudio.clear();
    _preReadyBytes = 0;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _readyCompleter = null;
    _finalCompleter = null;
    _audioDoneCompleter = null;
    _captureWatch = null;
    _maxAmplitudeDb = -160.0;
    _maxPcmRmsDb = -160.0;
    _localAudioBytes = 0;
    _sawNonZeroPcm = false;
    _voiceDetected = false;
    _audioGateOpen = false;
    _consecutiveVoiceChunks = 0;
    _inputDeviceLabel = '';
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

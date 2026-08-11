import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'novel_models.dart';

typedef SocketTokenProvider = FutureOr<String?> Function();
typedef SocketUserIdProvider = FutureOr<String?> Function();
typedef SocketKickedCallback = Future<void> Function();

/// Flutter 版私有 WebSocket。
///
/// 行为与 Vue useWSStore.js 对齐：
/// - /ws/private?user_id=...&token=...
/// - 30s ping，15s 等待 pong
/// - 普通断线指数退避重连（2/4/6/8/10s，上限 10s）
/// - kicked / closeCode=4001 时禁止重连
class NovelSocketService {
  NovelSocketService({
    required this.baseUrl,
    required this.path,
    required this.tokenProvider,
    required this.userIdProvider,
    this.onKicked,
    this.extraQuery = const <String, String>{},
  });

  final String baseUrl;
  final String path;
  final SocketTokenProvider tokenProvider;
  final SocketUserIdProvider userIdProvider;
  final SocketKickedCallback? onKicked;
  final Map<String, String> extraQuery;

  final StreamController<NovelSocketEvent> _events =
      StreamController<NovelSocketEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _pongWaitTimer;

  bool _manuallyClosed = false;
  bool _connecting = false;
  bool _kickNotified = false;
  int _attempt = 0;
  String _sessionId = '';

  Stream<NovelSocketEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Uri _buildUri(String? token, String userId) {
    var value = baseUrl.trim();
    if (value.startsWith('http://')) {
      value = 'ws://${value.substring(7)}';
    } else if (value.startsWith('https://')) {
      value = 'wss://${value.substring(8)}';
    }
    value = value.endsWith('/') ? value.substring(0, value.length - 1) : value;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$value$normalizedPath');
    return uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      ...extraQuery,
      'user_id': userId,
      if (token != null && token.trim().isNotEmpty) 'token': token.trim(),
    });
  }

  Future<void> connect(String sessionId) async {
    if (_connecting) return;
    if (_channel != null && _sessionId == sessionId) return;

    _connecting = true;
    _manuallyClosed = false;
    _kickNotified = false;
    _sessionId = sessionId;
    await _closeChannel();

    try {
      final token = await tokenProvider();
      final userId = (await userIdProvider())?.trim() ?? '';
      if (userId.isEmpty || token == null || token.trim().isEmpty) {
        throw StateError('WebSocket 连接缺少登录凭证');
      }

      final uri = _buildUri(token, userId);
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      if (_manuallyClosed || _sessionId != sessionId) {
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _attempt = 0;
      _startHeartbeat();

      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) {
          _events.add(NovelSocketEvent(
            type: 'socket_error',
            data: <String, dynamic>{'message': error.toString()},
          ));
          // 与浏览器 WebSocket 一致：onError 只记录，统一由 onDone/onClose 调度重连，
          // 避免 error + close 连续触发造成两次重连与指数次数跳增。
        },
        onDone: () {
          final code = channel.closeCode;
          _stopHeartbeat();
          if (code == 4001) {
            _manuallyClosed = true;
            _events.add(const NovelSocketEvent(
              type: 'kicked',
              data: <String, dynamic>{
                'message': '你的账号在其他设备登录，已被迫下线',
              },
            ));
            _notifyKicked();
            unawaited(_closeChannel());
            return;
          }
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (error) {
      _events.add(NovelSocketEvent(
        type: 'socket_error',
        data: <String, dynamic>{'message': error.toString()},
      ));
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      dynamic decoded;
      if (raw is String) {
        decoded = jsonDecode(raw);
      } else if (raw is List<int>) {
        decoded = jsonDecode(utf8.decode(raw));
      } else {
        decoded = raw;
      }

      final data = asJsonMap(decoded);
      final type = stringValue(data['type'] ?? data['event']);
      if (type.isEmpty) return;

      if (type == 'pong') {
        _pongWaitTimer?.cancel();
        _pongWaitTimer = null;
        return;
      }
      if (type == 'connected') return;

      if (type == 'kicked') {
        _manuallyClosed = true;
        _events.add(NovelSocketEvent(type: type, data: data));
        _notifyKicked();
        unawaited(_closeChannel());
        return;
      }

      _events.add(NovelSocketEvent(type: type, data: data));
    } catch (error) {
      _events.add(NovelSocketEvent(
        type: 'socket_parse_error',
        data: <String, dynamic>{
          'message': error.toString(),
          'raw': raw.toString(),
        },
      ));
    }
  }


  void _notifyKicked() {
    if (_kickNotified) return;
    _kickNotified = true;
    final callback = onKicked;
    if (callback != null) {
      unawaited(callback());
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final channel = _channel;
      if (channel == null) return;

      try {
        channel.sink.add(jsonEncode(const <String, dynamic>{'type': 'ping'}));
        _pongWaitTimer?.cancel();
        _pongWaitTimer = Timer(const Duration(seconds: 15), () {
          // 与 Vue 一致：pong 超时后主动断开，交给重连逻辑恢复。
          unawaited(_closeForReconnect());
        });
      } catch (_) {
        unawaited(_closeForReconnect());
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongWaitTimer?.cancel();
    _pongWaitTimer = null;
  }

  Future<void> _closeForReconnect() async {
    if (_manuallyClosed) return;
    await _closeChannel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    unawaited(_prepareReconnect());
  }

  Future<void> _prepareReconnect() async {
    await _closeChannel();
    if (_manuallyClosed || _sessionId.isEmpty) return;

    _reconnectTimer?.cancel();
    _attempt += 1;
    final seconds = (_attempt * 2).clamp(2, 10).toInt();
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_manuallyClosed && _sessionId.isNotEmpty) {
        unawaited(connect(_sessionId));
      }
    });
  }

  void send(JsonMap event) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(event));
  }

  Future<void> _closeChannel() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _sessionId = '';
    await _closeChannel();
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}

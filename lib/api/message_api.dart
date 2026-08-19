// lib/api/message_api.dart
// 对应 Vue 的 message.js。
// 注意：这里是“聊天消息”接口，不等同于 MinePage 的“系统通知/评论回复通知”。

import 'api_client.dart';

class MessageApi {
  MessageApi._();

  /// Vue: getHistory(sessionId, offset, limit)
  static Future<Map<String, dynamic>> getHistory(
    String sessionId, {
    int offset = 0,
    int limit = 50,
  }) {
    return ApiClient.instance.get(
      '/chat/history',
      queryParams: <String, dynamic>{
        'session_id': sessionId,
        'offset': offset,
        'limit': limit,
      },
    );
  }

  /// Novel：读取当前阶段目标。用于首次进入、刷新和 WebSocket 重连后的恢复。
  static Future<Map<String, dynamic>> getNovelGoal(String sessionId) {
    return ApiClient.instance.get('/novel/goal/$sessionId');
  }

  /// Vue: deleteMessage(messageId)
  static Future<void> deleteMessage(String messageId) async {
    await ApiClient.instance.delete('/messages/$messageId');
  }

  /// Vue: updateMessage(messageId, content)
  static Future<Map<String, dynamic>> updateMessage(
    String messageId,
    String content,
  ) {
    return ApiClient.instance.put(
      '/messages/$messageId',
      body: <String, dynamic>{'content': content},
    );
  }
}

// lib/api/notification_api.dart
// 对应 Vue notification.js：
// GET  /notifications
// POST /notifications/:id/read
// POST /notifications/read-all

import 'api_client.dart';

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}') ?? fallback;
}

bool _asBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

String _asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text == 'null' ? fallback : text;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return const <String, dynamic>{};
}

List<dynamic> _extractList(Map<String, dynamic> json) {
  dynamic current = json;
  for (var depth = 0; depth < 3; depth++) {
    if (current is List) return current;
    if (current is! Map) break;
    final map = _asMap(current);
    for (final key in const ['notifications', 'items', 'list', 'data']) {
      final value = map[key];
      if (value is List) return value;
    }
    current = map['data'];
  }
  return const [];
}

class NotificationActor {
  const NotificationActor({
    required this.name,
    required this.avatarUrl,
    this.userId,
  });

  final String name;
  final String avatarUrl;
  final String? userId;

  factory NotificationActor.fromJson(Map<String, dynamic> json) {
    return NotificationActor(
      name: _asString(
        json['name'] ?? json['username'] ?? json['nickname'],
        '用户',
      ),
      avatarUrl: _asString(json['avatar'] ?? json['avatar_url']),
      userId: (json['id'] ?? json['user_id'])?.toString(),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.actor,
    required this.isRead,
    required this.createdAt,
    required this.type,
    this.content,
    this.templateId,
    this.coverUrl,
    this.templateTitle,
    this.commentId,
    this.replyId,
    this.targetCommentId,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final NotificationActor actor;
  final bool isRead;
  final String createdAt;
  final String type;
  final String? content;
  final String? templateId;
  final String? coverUrl;
  final String? templateTitle;

  /// 后端如果提供这些 ID，就可以像小红书一样打开作品后定位到具体评论/回复。
  final String? commentId;
  final String? replyId;
  final String? targetCommentId;
  final Map<String, dynamic> raw;

  String? get locateCommentId {
    final candidates = [replyId, targetCommentId, commentId];
    for (final value in candidates) {
      if (value != null && value!.trim().isNotEmpty) return value;
    }
    return null;
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      actor: actor,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      type: type,
      content: content,
      templateId: templateId,
      coverUrl: coverUrl,
      templateTitle: templateTitle,
      commentId: commentId,
      replyId: replyId,
      targetCommentId: targetCommentId,
      raw: raw,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = _asMap(json['actor']);
    return AppNotification(
      id: _asString(json['id'] ?? json['notification_id']),
      actor: NotificationActor.fromJson(actor),
      isRead: _asBool(json['is_read'] ?? json['read']),
      createdAt: _asString(json['created_at'] ?? json['time']),
      type: _asString(json['type'] ?? json['action'] ?? json['event_type']),
      content: (json['content'] ?? json['comment_content'])?.toString(),
      templateId: (json['template_id'] ??
              json['scenario_id'] ??
              json['target_template_id'])
          ?.toString(),
      coverUrl: (json['cover_url'] ?? json['cover'])?.toString(),
      templateTitle: (json['template_title'] ?? json['title'] ?? json['scenario_title'])?.toString(),
      commentId: (json['comment_id'] ?? json['source_comment_id'])?.toString(),
      replyId: (json['reply_id'] ?? json['source_reply_id'])?.toString(),
      targetCommentId: json['target_comment_id']?.toString(),
      raw: json,
    );
  }
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.unreadCount,
  });

  final List<AppNotification> items;
  final int unreadCount;
}

class NotificationApi {
  NotificationApi._();

  /// Vue: getNotifications(params) -> GET /notifications
  static Future<NotificationPage> getNotifications({
    Map<String, dynamic>? params,
  }) async {
    final json = await ApiClient.instance.get(
      '/notifications',
      queryParams: params,
    );

    final items = _extractList(json)
        .whereType<Map>()
        .map((raw) => AppNotification.fromJson(_asMap(raw)))
        .toList();

    final data = _asMap(json['data']);
    final unreadCount = _asInt(
      json['unread_count'] ??
          json['unread_notifications'] ??
          data['unread_count'] ??
          data['unread_notifications'],
      items.where((item) => !item.isRead).length,
    );

    return NotificationPage(items: items, unreadCount: unreadCount);
  }

  /// Vue: markRead(id) -> POST /notifications/:id/read
  static Future<void> markRead(String id) async {
    await ApiClient.instance.post('/notifications/$id/read');
  }

  /// Vue: markAllRead() -> POST /notifications/read-all
  static Future<void> markAllRead() async {
    await ApiClient.instance.post('/notifications/read-all');
  }
}

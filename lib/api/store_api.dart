// lib/api/store_api.dart
//
// Flutter 版 Store API：按 Vue src/store.js 与详情页行为完整迁移。
// 保留全部 Vue API，并补齐详情、媒体、角色、评论/回复、点赞、fork 启动等模型。

import 'api_client.dart';

int _asInt(dynamic value, [int fallback = 0]) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? fallback;

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
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map) return _asMap(data);
  return json;
}

List<dynamic> _extractList(
  Map<String, dynamic> json, {
  List<String> keys = const ['data', 'items', 'list'],
}) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) return value;
    if (value is Map) {
      final map = _asMap(value);
      for (final nestedKey in keys) {
        final nested = map[nestedKey];
        if (nested is List) return nested;
      }
    }
  }
  return const <dynamic>[];
}

class StoreItem {
  const StoreItem({
    required this.id,
    required this.title,
    required this.mode,
    required this.coverUrl,
    required this.authorName,
    required this.avatarUrl,
    required this.likes,
    this.isLiked = false,
    this.status,
  });

  final String id;
  final String title;
  final String mode;
  final String coverUrl;
  final String authorName;
  final String avatarUrl;
  final int likes;
  final bool isLiked;
  final String? status;

  StoreItem copyWith({int? likes, bool? isLiked}) => StoreItem(
        id: id,
        title: title,
        mode: mode,
        coverUrl: coverUrl,
        authorName: authorName,
        avatarUrl: avatarUrl,
        likes: likes ?? this.likes,
        isLiked: isLiked ?? this.isLiked,
        status: status,
      );

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    final author = _asMap(json['author_info'] ?? json['user']);
    return StoreItem(
      id: _asString(json['id'] ?? json['template_id'] ?? json['scenario_id']),
      title: _asString(json['title'] ?? json['public_title'], '无题'),
      mode: _asString(json['mode'], 'chat'),
      coverUrl: _asString(
        json['cover'] ?? json['cover_url'] ?? json['image'] ?? json['image_url'],
      ),
      authorName: _asString(
        json['author'] ?? json['user_name'] ?? json['username'] ?? author['name'],
        '匿名',
      ),
      avatarUrl: _asString(
        json['avatar_url'] ??
            json['author_avatar'] ??
            json['avatar'] ??
            author['avatar_url'] ??
            author['avatar'],
      ),
      likes: _asInt(json['likes'] ?? json['like_count'] ?? json['hot']),
      isLiked: _asBool(json['is_liked'] ?? json['liked']),
      status: json['status']?.toString(),
    );
  }
}

class ScenarioMediaItem {
  const ScenarioMediaItem({required this.url, this.title, this.type = 'screenshot'});

  final String url;
  final String? title;
  final String type;

  factory ScenarioMediaItem.fromJson(Map<String, dynamic> json) {
    return ScenarioMediaItem(
      url: _asString(json['url'] ?? json['image'] ?? json['cover_url']),
      title: json['title']?.toString(),
      type: _asString(json['type'], 'screenshot'),
    );
  }
}

class ScenarioCharacter {
  const ScenarioCharacter({
    required this.name,
    this.identity,
    this.desc,
    this.avatarUrl,
  });

  final String name;
  final String? identity;
  final String? desc;

  /// Vue 优先级：poster -> portrait_url -> avatar。
  final String? avatarUrl;

  factory ScenarioCharacter.fromJson(Map<String, dynamic> json) {
    final avatar = _asString(
      json['poster'] ??
          json['portrait_url'] ??
          json['avatar'] ??
          json['avatar_url'],
    );
    return ScenarioCharacter(
      name: _asString(json['name'], '未命名角色'),
      identity: json['identity']?.toString(),
      desc: (json['desc'] ?? json['description'] ?? json['background'])?.toString(),
      avatarUrl: avatar.isEmpty ? null : avatar,
    );
  }
}

class ScenarioDetail {
  const ScenarioDetail({
    required this.id,
    required this.title,
    required this.mode,
    required this.coverUrl,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.likes,
    required this.isLiked,
    this.description = '',
    this.userId,
    this.createdAt,
    this.tags = const [],
    this.mediaItems = const [],
    this.characters = const [],
  });

  final String id;
  final String title;
  final String mode;
  final String coverUrl;
  final String authorName;
  final String authorAvatarUrl;
  final String description;
  final String? userId;
  final String? createdAt;
  final int likes;
  final bool isLiked;
  final List<String> tags;
  final List<ScenarioMediaItem> mediaItems;
  final List<ScenarioCharacter> characters;

  factory ScenarioDetail.fromJson(Map<String, dynamic> json) {
    final mediaRaw = json['media_items'];
    final characterRaw = json['characters'] ?? json['roles'];
    final tagsRaw = json['tags'] ?? json['categories'];
    final author = _asMap(json['author_info'] ?? json['user']);

    final media = mediaRaw is List
        ? mediaRaw
            .map((e) => ScenarioMediaItem.fromJson(_asMap(e)))
            .where((e) => e.url.isNotEmpty)
            .toList()
        : <ScenarioMediaItem>[];

    final characters = characterRaw is List
        ? characterRaw
            .map((e) => ScenarioCharacter.fromJson(_asMap(e)))
            .toList()
        : <ScenarioCharacter>[];

    final tags = tagsRaw is List
        ? tagsRaw
            .map((e) => e is Map ? _asString(_asMap(e)['name']) : _asString(e))
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    return ScenarioDetail(
      id: _asString(json['id'] ?? json['template_id'] ?? json['scenario_id']),
      title: _asString(json['title'] ?? json['public_title'], '无题'),
      mode: _asString(json['mode'], 'chat'),
      coverUrl: _asString(json['cover'] ?? json['cover_url']),
      authorName: _asString(
        json['author'] ?? json['user_name'] ?? json['username'] ?? author['name'],
        '匿名',
      ),
      authorAvatarUrl: _asString(
        json['avatar_url'] ??
            json['author_avatar'] ??
            json['avatar'] ??
            author['avatar_url'] ??
            author['avatar'],
      ),
      description: _asString(
        json['description'] ??
            json['public_description'] ??
            json['intro'] ??
            json['summary'],
      ),
      userId: (json['user_id'] ?? json['author_id'])?.toString(),
      createdAt: (json['created_at'] ?? json['published_at'])?.toString(),
      likes: _asInt(json['likes'] ?? json['like_count']),
      isLiked: _asBool(json['is_liked'] ?? json['liked']),
      tags: tags,
      mediaItems: media,
      characters: characters,
    );
  }
}

class LikeResult {
  const LikeResult({required this.isLiked, this.likeCount, this.message});

  final bool isLiked;
  final int? likeCount;
  final String? message;

  factory LikeResult.fromJson(Map<String, dynamic> json) {
    final data = _unwrapData(json);
    final action = (data['action'] ?? json['action'])?.toString();
    final likedRaw = data['is_liked'] ??
        data['liked'] ??
        json['is_liked'] ??
        json['liked'];
    final countRaw = data['like_count'] ??
        data['likes'] ??
        data['likes_count'] ??
        json['like_count'] ??
        json['likes'] ??
        json['likes_count'];

    return LikeResult(
      isLiked: action != null ? action == 'liked' : _asBool(likedRaw),
      likeCount: countRaw == null ? null : _asInt(countRaw),
      message: (data['message'] ?? json['message'])?.toString(),
    );
  }
}

class ScenarioComment {
  const ScenarioComment({
    required this.id,
    required this.content,
    required this.authorName,
    required this.likes,
    this.userId,
    this.authorAvatarUrl,
    this.isLiked = false,
    this.isPinned = false,
    this.parentId,
    this.createdAt,
    this.replyCount = 0,
    this.replies = const [],
    this.visibleReplyCount = 1,
  });

  final String id;
  final String content;
  final String authorName;
  final String? userId;
  final String? authorAvatarUrl;
  final int likes;
  final bool isLiked;
  final bool isPinned;
  final String? parentId;
  final String? createdAt;
  final int replyCount;
  final List<ScenarioComment> replies;
  final int visibleReplyCount;

  ScenarioComment copyWith({
    int? likes,
    bool? isLiked,
    bool? isPinned,
    List<ScenarioComment>? replies,
    int? visibleReplyCount,
  }) {
    return ScenarioComment(
      id: id,
      content: content,
      authorName: authorName,
      userId: userId,
      authorAvatarUrl: authorAvatarUrl,
      likes: likes ?? this.likes,
      isLiked: isLiked ?? this.isLiked,
      isPinned: isPinned ?? this.isPinned,
      parentId: parentId,
      createdAt: createdAt,
      replyCount: replyCount,
      replies: replies ?? this.replies,
      visibleReplyCount: visibleReplyCount ?? this.visibleReplyCount,
    );
  }

  factory ScenarioComment.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user'] ?? json['author_info']);
    return ScenarioComment(
      id: _asString(json['id'] ?? json['comment_id']),
      content: _asString(json['content']),
      authorName: _asString(
        json['author'] ??
            json['user_name'] ??
            json['username'] ??
            user['name'] ??
            user['username'],
        '匿名用户',
      ),
      userId: (json['user_id'] ?? json['author_id'] ?? user['id'])?.toString(),
      authorAvatarUrl: (json['author_avatar'] ??
              json['avatar_url'] ??
              json['avatar'] ??
              user['avatar_url'] ??
              user['avatar'])
          ?.toString(),
      likes: _asInt(json['likes'] ?? json['like_count']),
      isLiked: _asBool(json['is_liked'] ?? json['liked']),
      isPinned: _asBool(json['is_pinned']),
      parentId: json['parent_id']?.toString(),
      createdAt: (json['created_at'] ?? json['time'])?.toString(),
      replyCount: _asInt(json['reply_count']),
    );
  }
}

class ScenarioLaunchInfo {
  const ScenarioLaunchInfo({
    required this.mode,
    required this.scenarioId,
    required this.sessionId,
  });

  final String mode;
  final String scenarioId;
  final String sessionId;

  factory ScenarioLaunchInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackMode = 'chat',
  }) {
    final data = _unwrapData(json);
    return ScenarioLaunchInfo(
      mode: _asString(data['mode'], fallbackMode),
      scenarioId: _asString(
        data['scenario_id'] ?? data['instance_id'] ?? data['id'],
      ),
      sessionId: _asString(data['session_id'] ?? data['sessionId']),
    );
  }

  bool get isValid => scenarioId.isNotEmpty && sessionId.isNotEmpty;
}

class StoreApi {
  StoreApi._();

  /// 1. 获取发现页/商店列表。
  static Future<List<StoreItem>> getStoreList({
    int page = 1,
    int size = 20,
    String? query,
    String? mode,
    String? category,
    String sort = 'recommend',
  }) async {
    final json = await ApiClient.instance.post(
      '/store/list',
      body: {
        'page': page,
        'size': size,
        'sort': sort,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
        if ((category ?? mode) != null) 'category': category ?? mode,
      },
    );
    final list = _extractList(json, keys: const ['data', 'items', 'list']);
    return list.map((e) => StoreItem.fromJson(_asMap(e))).toList();
  }

  /// 搜索剧本。
  static Future<List<StoreItem>> searchScripts({
    String? query,
    String? category,
    int page = 1,
    int size = 20,
    String sort = 'recommend',
  }) async {
    final json = await ApiClient.instance.post(
      '/scripts/search',
      body: {
        if (query != null) 'query': query,
        if (category != null) 'category': category,
        'page': page,
        'size': size,
        'sort': sort,
      },
    );
    final list = _extractList(json, keys: const ['data', 'items', 'list']);
    return list.map((e) => StoreItem.fromJson(_asMap(e))).toList();
  }

  static Future<List<String>> getSearchSuggestions(String q) async {
    final json = await ApiClient.instance.get(
      '/scripts/search-suggestions',
      queryParams: {'q': q},
    );
    final list = _extractList(json, keys: const ['data', 'suggestions', 'items']);
    return list.map((e) => e.toString()).toList();
  }

  static Future<List<String>> getHotTags({int limit = 12}) async {
    final json = await ApiClient.instance.get(
      '/scripts/hot-tags',
      queryParams: {'limit': limit},
    );
    final list = _extractList(json, keys: const ['data', 'tags', 'items']);
    return list
        .map((e) => e is Map ? _asString(_asMap(e)['name']) : _asString(e))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 2. 发布剧本。
  static Future<Map<String, dynamic>> publishScenario({
    required String instanceId,
    required String publicTitle,
    String? publicDescription,
  }) {
    return ApiClient.instance.post(
      '/scenario/publish',
      body: {
        'instance_id': instanceId,
        'public_title': publicTitle,
        'public_description': publicDescription,
      },
    );
  }

  /// 3. 获取我发布的作品。
  static Future<List<StoreItem>> getMyPublishedScripts({String? status}) async {
    final json = await ApiClient.instance.get(
      '/user/my-scripts',
      queryParams: {if (status != null) 'status': status},
    );
    final list = _extractList(json, keys: const ['data', 'items', 'list']);
    return list.map((e) => StoreItem.fromJson(_asMap(e))).toList();
  }

  /// 4. 获取剧本详情。
  static Future<ScenarioDetail> getScenarioDetail(String templateId) async {
    final json = await ApiClient.instance.get('/store/scenario/$templateId');
    return ScenarioDetail.fromJson(_unwrapData(json));
  }

  /// 5. 从商场下载剧本到存档；与 Vue 一样依赖后端去重。
  static Future<ScenarioLaunchInfo> forkScenario(
    String templateId, {
    String? title,
    String? description,
    String fallbackMode = 'chat',
  }) async {
    final json = await ApiClient.instance.post(
      '/scenario/template/$templateId',
      body: {'title': title, 'description': description},
    );
    return ScenarioLaunchInfo.fromJson(json, fallbackMode: fallbackMode);
  }

  /// 6. 获取活跃游戏 session。
  static Future<Map<String, dynamic>> getActiveSession(String scenarioId) {
    return ApiClient.instance.get('/scenario/$scenarioId/info');
  }

  /// 7. 获取用户场景列表。
  static Future<Map<String, dynamic>> getUserScenarios() {
    return ApiClient.instance.get('/user/profile');
  }

  /// 删除已发布剧本。
  static Future<void> deletePublishedScenario(String templateId) async {
    await ApiClient.instance.delete('/store/scenario/$templateId');
  }

  /// 8. 获取主评论，并像 Vue 一样把每条评论的回复一并拉回。
  static Future<List<ScenarioComment>> getScenarioComments(
    String scenarioId, {
    int page = 1,
    int pageSize = 20,
    String sortBy = 'time',
    bool includeReplies = true,
  }) async {
    final json = await ApiClient.instance.get(
      '/scenarios/$scenarioId/comments',
      queryParams: {
        'page': page,
        'page_size': pageSize,
        'sort_by': sortBy,
      },
    );

    final rawList = _extractList(
      json,
      keys: const ['comments', 'data', 'items', 'list'],
    );
    final parents = rawList
        .map((e) => ScenarioComment.fromJson(_asMap(e)))
        .toList()
      ..sort(_compareCommentTime);

    if (!includeReplies) return parents;

    return Future.wait(
      parents.map((parent) async {
        if (parent.replyCount <= 0) return parent;
        try {
          final replies = await getCommentReplies(parent.id);
          return parent.copyWith(replies: replies, visibleReplyCount: 1);
        } catch (_) {
          return parent;
        }
      }),
    );
  }

  /// 9. 发送主评论或回复。Vue 成功后会整体 reloadComments，因此返回值可为空。
  static Future<ScenarioComment?> postScenarioComment(
    String scenarioId, {
    required String content,
    String? parentId,
  }) async {
    final json = await ApiClient.instance.post(
      '/scenarios/$scenarioId/comments',
      body: {'content': content, 'parent_id': parentId},
    );
    final data = _unwrapData(json);
    if (data['id'] == null && data['comment_id'] == null) return null;
    return ScenarioComment.fromJson(data);
  }

  /// 10. 获取单条评论的回复。
  static Future<List<ScenarioComment>> getCommentReplies(
    String commentId, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final json = await ApiClient.instance.get(
      '/scenarios/comments/$commentId/replies',
      queryParams: {'page': page, 'page_size': pageSize},
    );
    final list = _extractList(
      json,
      keys: const ['replies', 'comments', 'data', 'items', 'list'],
    );
    final replies = list
        .map((e) => ScenarioComment.fromJson(_asMap(e)))
        .toList()
      ..sort(_compareCommentTime);
    return replies;
  }

  /// 11. 点赞/取消点赞评论。
  static Future<LikeResult> likeScenarioComment(String commentId) async {
    final json =
        await ApiClient.instance.post('/scenarios/comments/$commentId/like');
    return LikeResult.fromJson(json);
  }

  /// 12. 删除评论。
  static Future<void> deleteScenarioComment(String commentId) async {
    await ApiClient.instance.delete('/scenarios/comments/$commentId');
  }

  /// 13. 置顶/取消置顶评论。
  static Future<bool> pinScenarioComment(
    String scenarioId,
    String commentId,
  ) async {
    final json = await ApiClient.instance
        .patch('/scenarios/$scenarioId/comments/$commentId/pin');
    final data = _unwrapData(json);
    return _asBool(data['is_pinned'] ?? json['is_pinned']);
  }

  /// 剧本点赞/取消点赞。
  static Future<LikeResult> likeScenario(String templateId) async {
    final json = await ApiClient.instance.post('/scenarios/$templateId/like');
    return LikeResult.fromJson(json);
  }

  static int _compareCommentTime(ScenarioComment a, ScenarioComment b) {
    final at = DateTime.tryParse(a.createdAt ?? '');
    final bt = DateTime.tryParse(b.createdAt ?? '');
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    return at.compareTo(bt);
  }
}

import 'package:http/http.dart' as http;

import 'api_client.dart';

class MineAnnouncement {
  const MineAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final String createdAt;
}

class MineCheckinStatus {
  const MineCheckinStatus({
    required this.checkedInToday,
    required this.days,
  });

  final bool checkedInToday;
  final List<String> days;
}

class MineCheckinResult {
  const MineCheckinResult({
    required this.reward,
    this.balance,
  });

  final int reward;
  final int? balance;
}

class MineApi {
  MineApi._();

  static final ApiClient _client = ApiClient.instance;

  static Map<String, dynamic> _data(Map<String, dynamic> response) {
    final value = response['data'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return response;
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static int _int(dynamic value, {int fallback = 0}) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static Future<Map<String, dynamic>> getProfile() async {
    return _data(await _client.get('/user/profile'));
  }

  static String profileName(Map<String, dynamic> profile) {
    return _string(
      profile['name'] ??
          profile['username'] ??
          profile['nickname'] ??
          profile['user_name'],
    );
  }

  static String profileAvatar(Map<String, dynamic> profile) {
    return _string(
      profile['avatar_url'] ??
          profile['avatar'] ??
          profile['avatarUrl'],
    );
  }

  static String profileShortId(Map<String, dynamic> profile) {
    return _string(
      profile['short_id'] ??
          profile['shortId'] ??
          profile['uid'] ??
          profile['user_id'] ??
          profile['id'],
    );
  }

  static int profileBalance(Map<String, dynamic> profile) {
    return _int(
      profile['token_balance'] ??
          profile['balance'] ??
          profile['points'],
    );
  }

  static Future<void> updateUserName(String name) async {
    await _client.put(
      '/user/name',
      body: <String, dynamic>{'name': name.trim()},
    );
  }

  /// 用户头像上传：
  /// 1. 向后端申请 R2 预签名地址；
  /// 2. 客户端直接 PUT 到 R2；
  /// 3. 将 public_url 写回 /user/avatar。
  ///
  /// 这里复用当前项目中场景/角色图片已经使用的 R2 上传链路，
  /// 不再依赖旧的 /upload/image multipart 接口。
  static Future<String> uploadAndUpdateAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.isEmpty) {
      throw const ApiException('头像文件为空');
    }

    final safeFilename =
        filename.trim().isEmpty ? 'avatar.jpg' : filename.trim();
    final contentType = _imageContentType(safeFilename);

    final signatureResponse = await _client.post(
      '/r2/get-signature',
      body: <String, dynamic>{
        'filename': safeFilename,
        'content_type': contentType,
        // 当前项目角色头像已经使用该分类，直接复用现有可用分类。
        'category': 'char/avatar',
      },
    );

    final signature = _data(signatureResponse);
    final uploadUrl = _string(signature['upload_url']);
    final publicUrl = _string(signature['public_url']);

    if (uploadUrl.isEmpty || publicUrl.isEmpty) {
      throw const ApiException('服务器未返回有效的头像上传地址');
    }

    final uploadResponse = await http.put(
      Uri.parse(uploadUrl),
      headers: <String, String>{
        'Content-Type': contentType,
      },
      body: bytes,
    );

    if (uploadResponse.statusCode < 200 ||
        uploadResponse.statusCode >= 300) {
      throw ApiException('头像上传失败（${uploadResponse.statusCode}）');
    }

    await _client.put(
      '/user/avatar',
      body: <String, dynamic>{'avatar_url': publicUrl},
    );

    return publicUrl;
  }

  static String _imageContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  static Future<MineCheckinStatus> getCheckinStatus() async {
    final data = _data(await _client.get('/user/checkin/status'));
    final rawDays = data['checkin_days_this_month'];
    final days = rawDays is List
        ? rawDays.map((item) => item.toString()).toList()
        : <String>[];

    return MineCheckinStatus(
      checkedInToday: data['checked_in_today'] == true,
      days: days,
    );
  }

  static Future<MineCheckinResult> dailyCheckin() async {
    final response = await _client.post('/user/checkin');
    final code = _int(response['code'], fallback: -1);
    final message = _string(response['message']);

    // 严格以 /user/checkin 的真实业务返回为准。
    // 后端即使使用 HTTP 200 包装 code=409/403，也不能当成签到成功。
    if (code != 200) {
      throw ApiException(message.isEmpty ? '签到失败' : message);
    }

    final data = _data(response);
    if (data['reward'] == null) {
      throw const ApiException('签到成功，但服务器未返回 reward');
    }

    return MineCheckinResult(
      reward: _int(data['reward']),
      balance: data['balance'] == null ? null : _int(data['balance']),
    );
  }

  static Future<void> redeemCode(String code) async {
    await _client.post(
      '/redeem/use',
      body: <String, dynamic>{'code': code.trim()},
    );
  }

  static Future<List<MineAnnouncement>> getAnnouncements() async {
    final response = await _client.get(
      '/announcements',
      queryParams: const <String, dynamic>{
        'page': 1,
        'page_size': 10,
      },
    );
    final data = _data(response);
    final raw = data['list'] ?? data['items'] ?? data['announcements'];
    if (raw is! List) return const <MineAnnouncement>[];

    return raw.whereType<Map>().map((item) {
      return MineAnnouncement(
        id: _string(item['id']),
        title: _string(item['title']).isEmpty ? '公告' : _string(item['title']),
        content: _string(item['content']),
        createdAt: _string(item['created_at'] ?? item['createdAt']),
      );
    }).toList();
  }

  static Future<void> submitFeedback({
    required String title,
    required String content,
  }) async {
    await _client.post(
      '/feedback',
      body: <String, dynamic>{
        'title': title.trim(),
        'content': content.trim(),
        'category': 'general',
      },
    );
  }
}

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

  static Future<String> uploadAndUpdateAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final upload = await _client.postMultipartBytes(
      '/upload/image',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      fields: const <String, String>{'category': 'avatar'},
    );

    final data = _data(upload);
    final url = _string(
      data['url'] ??
          data['image_url'] ??
          data['avatar_url'] ??
          data['file_url'] ??
          upload['url'],
    );

    if (url.isEmpty) {
      throw const ApiException('头像上传成功，但服务器没有返回图片地址');
    }

    await _client.put(
      '/user/avatar',
      body: <String, dynamic>{'avatar_url': url},
    );
    return url;
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
    final data = _data(await _client.post('/user/checkin'));
    return MineCheckinResult(
      reward: _int(data['reward'], fallback: 100),
      balance: data['balance'] == null
          ? null
          : _int(data['balance']),
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

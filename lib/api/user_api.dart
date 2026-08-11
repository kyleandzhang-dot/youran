// lib/api/user_api.dart
//
// 用户资料与首页世界接口。
// /user/profile：昵称、UID、积分等资料。
// /user/home：与 Vue HomePage 一致的“我的世界”数据源。

import 'api_client.dart';

/// 后端首页/资料接口中的一条剧本摘要。
class ScenarioSummary {
  ScenarioSummary({
    required this.id,
    required this.title,
    required this.mode,
    required this.coverUrl,
    required this.description,
  });

  final String id;
  final String title;
  final String mode;
  final String coverUrl;
  final String description;

  factory ScenarioSummary.fromJson(Map<String, dynamic> json) {
    return ScenarioSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'chat',
      coverUrl: (json['cover'] ?? json['cover_url'])?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

/// 对应 Vue api/home.js 的 GET /user/home。
/// “我的世界”列表必须从这个接口读取，不能用 /user/profile 代替。
class UserHomeData {
  UserHomeData({
    required this.activeScenarioId,
    required this.scenarios,
  });

  final String? activeScenarioId;
  final List<ScenarioSummary> scenarios;

  factory UserHomeData.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    final rawScenarios = data['scenarios'];
    final scenariosJson = rawScenarios is List ? rawScenarios : const <dynamic>[];

    final activeRaw = data['active_scenario_id'];
    final activeScenarioId =
        activeRaw == null || activeRaw.toString().trim().isEmpty
            ? null
            : activeRaw.toString();

    return UserHomeData(
      activeScenarioId: activeScenarioId,
      scenarios: scenariosJson
          .whereType<Map>()
          .map((e) => ScenarioSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class UserProfile {
  UserProfile({
    required this.userId,
    required this.shortId,
    required this.name,
    required this.avatarUrl,
    required this.tokenBalance,
    required this.scenarios,
  });

  final String userId;
  final String shortId;
  final String name;
  final String avatarUrl;
  final double tokenBalance;
  final List<ScenarioSummary> scenarios;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final scenariosJson = (data['scenarios'] as List<dynamic>? ?? []);
    return UserProfile(
      userId: data['user_id'] as String,
      shortId: (data['short_id'] as num?)?.toString() ??
          data['short_id'] as String? ??
          '',
      name: data['name'] as String? ?? '',
      avatarUrl: data['avatar_url'] as String? ?? '',
      tokenBalance: (data['token_balance'] as num?)?.toDouble() ?? 0,
      scenarios: scenariosJson
          .map((e) => ScenarioSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 对应 POST /user/set-active-scenario，返回进入世界所需的 session_id。
class ActiveScenarioResult {
  ActiveScenarioResult({required this.scenarioId, required this.sessionId});

  final String scenarioId;
  final String sessionId;

  factory ActiveScenarioResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return ActiveScenarioResult(
      scenarioId: data['scenario_id'].toString(),
      sessionId: data['session_id'].toString(),
    );
  }
}

class UserApi {
  UserApi._();

  /// 拉取账户资料：昵称、UID、积分等。
  static Future<UserProfile> getProfile() async {
    final json = await ApiClient.instance.get('/user/profile');
    return UserProfile.fromJson(json);
  }

  /// 与 Vue getUserHomeData() 完全一致：读取首页“我的世界”。
  static Future<UserHomeData> getHomeData() async {
    final json = await ApiClient.instance.get('/user/home');
    return UserHomeData.fromJson(json);
  }

  /// 与 Vue setActiveScenario() 完全一致。
  static Future<ActiveScenarioResult> setActiveScenario(
    String scenarioId,
  ) async {
    final json = await ApiClient.instance.post(
      '/user/set-active-scenario',
      body: {'scenario_id': scenarioId},
    );
    return ActiveScenarioResult.fromJson(json);
  }
}
import 'api_client.dart';

/// 剧本编辑页 API。
///
/// 接口路径严格对齐 Vue 的 scenario_detail.js：
/// - GET    /scenario/{id}/info?detailed=true
/// - PUT    /scenario/{id}/update
/// - POST   /scenario/{id}/reset        body: { keep_characters: true }
/// - DELETE /scenario/{id}
/// - POST   /scenario/{id}/bgm/config
class ScenarioEditorApi {
  ScenarioEditorApi({
    ApiClient? client,
    this.scenarioBasePath = '/scenario',
  }) : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  final String scenarioBasePath;

  String _scenarioPath(String scenarioId) => '$scenarioBasePath/$scenarioId';

  Future<Map<String, dynamic>> getScenarioDetail(String scenarioId) async {
    final response = await _client.get(
      '${_scenarioPath(scenarioId)}/info',
      queryParams: const <String, dynamic>{
        'detailed': true,
      },
    );
    return _unwrapMap(response);
  }

  Future<Map<String, dynamic>> updateScenario(
    String scenarioId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.put(
      '${_scenarioPath(scenarioId)}/update',
      body: payload,
    );
    return _unwrapMap(response);
  }

  Future<void> resetScenario(
    String scenarioId, {
    bool keepCharacters = true,
  }) async {
    await _client.post(
      '${_scenarioPath(scenarioId)}/reset',
      body: <String, dynamic>{
        'keep_characters': keepCharacters,
      },
    );
  }

  Future<void> deleteScenario(String scenarioId) async {
    await _client.delete(_scenarioPath(scenarioId));
  }

  Future<void> saveBgmConfig(
    String scenarioId,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return;
    await _client.post(
      '${_scenarioPath(scenarioId)}/bgm/config',
      body: <String, dynamic>{'items': items},
    );
  }

  static Map<String, dynamic> _unwrapMap(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return response;
  }
}

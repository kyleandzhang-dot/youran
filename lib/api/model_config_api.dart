import 'api_client.dart';

class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    required this.speed,
    required this.price,
    required this.quality,
  });

  final String id;
  final String name;
  final num speed;
  final num price;
  final num quality;

  factory ModelOption.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['meta'];
    final meta = rawMeta is Map
        ? rawMeta.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    num readNum(dynamic value) {
      if (value is num) return value;
      return num.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ModelOption(
      id: json['id']?.toString() ?? '',
      name: (json['name']?.toString().trim().isNotEmpty == true)
          ? json['name'].toString()
          : (json['id']?.toString() ?? ''),
      speed: readNum(meta['speed']),
      price: readNum(meta['price']),
      quality: readNum(meta['quality']),
    );
  }
}

class CustomApiConfig {
  const CustomApiConfig({
    this.apiKey = '',
    this.baseUrl = '',
    this.modelName = '',
  });

  final String apiKey;
  final String baseUrl;
  final String modelName;
}

class ModelConfigSnapshot {
  const ModelConfigSnapshot({
    required this.scenePreferences,
    required this.enableOwnKey,
    required this.customApi,
    required this.models,
  });

  final Map<String, String> scenePreferences;
  final bool enableOwnKey;
  final CustomApiConfig customApi;
  final List<ModelOption> models;
}

class ModelConfigApi {
  ModelConfigApi._();

  static final ApiClient _client = ApiClient.instance;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _data(Map<String, dynamic> response) {
    final raw = response['data'];
    final data = _asMap(raw);
    return data.isNotEmpty ? data : response;
  }

  static Future<ModelConfigSnapshot> getConfig() async {
    final response = await _client.get('/model-config/');
    final data = _data(response);

    final sceneRaw = _asMap(data['scene_preferences']);
    final scenePreferences = <String, String>{
      for (final entry in sceneRaw.entries)
        entry.key: entry.value?.toString() ?? '',
    };

    final apiKeys = _asMap(data['api_keys']);
    final customRaw = _asMap(apiKeys['custom']);

    final modelsRaw = data['models'];
    final models = <ModelOption>[];
    if (modelsRaw is List) {
      for (final item in modelsRaw) {
        final map = _asMap(item);
        if (map.isEmpty) continue;
        final option = ModelOption.fromJson(map);
        if (option.id.isNotEmpty) models.add(option);
      }
    }

    return ModelConfigSnapshot(
      scenePreferences: scenePreferences,
      enableOwnKey: data['enable_own_key'] == true,
      customApi: CustomApiConfig(
        apiKey: customRaw['api_key']?.toString() ?? '',
        baseUrl: customRaw['base_url']?.toString() ?? '',
        modelName: customRaw['model_name']?.toString() ?? '',
      ),
      models: models,
    );
  }

  static Future<void> updateScenePreference(
    String scene,
    String modelId,
  ) async {
    await _client.post(
      '/model-config/scene-preferences',
      body: <String, dynamic>{scene: modelId},
    );
  }

  static Future<void> toggleOwnKey(bool enable) async {
    await _client.post(
      '/model-config/toggle-own-key',
      body: <String, dynamic>{'enable': enable},
    );
  }

  static Future<bool> testConnection({
    required String apiKey,
    required String baseUrl,
    required String modelName,
  }) async {
    final response = await _client.post(
      '/model-config/test-connection',
      body: <String, dynamic>{
        'api_key': apiKey,
        'base_url': baseUrl,
        'model_name': modelName,
      },
    );

    final status = response['status']?.toString().toLowerCase().trim() ?? '';
    if (status.isNotEmpty) return status == 'success';

    final code = int.tryParse(response['code']?.toString() ?? '');
    if (code != null) return code == 200;

    final success = response['success'];
    if (success is bool) return success;

    // ApiClient 到这里已经确认 HTTP 2xx；后端未提供额外状态时视为成功。
    return true;
  }

  static Future<void> saveCustomApi({
    required String apiKey,
    required String baseUrl,
    required String modelName,
  }) async {
    await _client.post(
      '/model-config/api-keys',
      body: <String, dynamic>{
        'api_key': apiKey,
        'base_url': baseUrl,
        'model_name': modelName,
      },
    );
  }

  static Future<void> deleteCustomApi() async {
    await _client.delete('/model-config/api-keys');
  }
}

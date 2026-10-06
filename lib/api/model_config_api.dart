import 'api_client.dart';

class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    this.speed = 0,
    this.price = 0,
    this.quality = 0,
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

/// 后端下发的大模型平台预设（自带 Key 面板的平台列表，前端不再写死）。
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    this.keyHint = '',
    this.models = const <String>[],
  });

  final String id;
  final String label;
  final String baseUrl;
  final String keyHint;
  final List<String> models;

  factory ProviderPreset.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'];
    final id = json['id']?.toString() ?? '';
    final label = json['label']?.toString().trim() ?? '';
    return ProviderPreset(
      id: id,
      label: label.isNotEmpty ? label : id,
      baseUrl: json['base_url']?.toString().trim() ?? '',
      keyHint: json['key_hint']?.toString() ?? '',
      models: rawModels is List
          ? rawModels
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
          : const <String>[],
    );
  }
}

class CustomApiConfig {
  const CustomApiConfig({
    this.provider = '',
    this.apiKey = '',
    this.baseUrl = '',
    this.modelName = '',
  });

  final String provider;
  final String apiKey; // 后端返回的是脱敏值，例如 sk-****abcd
  final String baseUrl;
  final String modelName;
}

class ModelConfigSnapshot {
  const ModelConfigSnapshot({
    required this.scenePreferences,
    required this.enableOwnKey,
    required this.customApi,
    required this.models,
    this.presets = const <ProviderPreset>[],
  });

  final Map<String, String> scenePreferences;
  final bool enableOwnKey;
  final CustomApiConfig customApi;
  final List<ModelOption> models;
  final List<ProviderPreset> presets;
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

    // 自带 Key 可选的平台与推荐模型（没有 base_url 的「自定义」项面板无法使用，过滤掉）
    final presetsRaw = data['presets'];
    final presets = <ProviderPreset>[];
    if (presetsRaw is List) {
      for (final item in presetsRaw) {
        final map = _asMap(item);
        if (map.isEmpty) continue;
        final preset = ProviderPreset.fromJson(map);
        if (preset.id.isNotEmpty && preset.baseUrl.isNotEmpty) {
          presets.add(preset);
        }
      }
    }

    return ModelConfigSnapshot(
      scenePreferences: scenePreferences,
      enableOwnKey: data['enable_own_key'] == true,
      customApi: CustomApiConfig(
        provider: customRaw['provider']?.toString() ?? '',
        apiKey: customRaw['api_key']?.toString() ?? '',
        baseUrl: customRaw['base_url']?.toString() ?? '',
        modelName: customRaw['model_name']?.toString() ?? '',
      ),
      models: models,
      presets: presets,
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
    String? provider,
  }) async {
    await _client.post(
      '/model-config/api-keys',
      body: <String, dynamic>{
        'api_key': apiKey,
        'base_url': baseUrl,
        'model_name': modelName,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
  }

  /// 向平台实时拉取该 Key 可用的模型；失败或为空时返回空列表，调用方回落到 presets。
  static Future<List<String>> listProviderModels({
    required String apiKey,
    required String baseUrl,
  }) async {
    final response = await _client.post(
      '/model-config/list-models',
      body: <String, dynamic>{
        'api_key': apiKey,
        'base_url': baseUrl,
      },
    );

    final status = response['status']?.toString().toLowerCase().trim() ?? '';
    if (status != 'success') return const <String>[];

    final raw = _data(response)['models'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Future<void> deleteCustomApi() async {
    await _client.delete('/model-config/api-keys');
  }
}
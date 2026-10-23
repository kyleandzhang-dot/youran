import '../../api/api_client.dart';

class CinemaApi {
  CinemaApi({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  static const String _base = '/cinema';

  Map<String, dynamic> _data(Map<String, dynamic> value) {
    final data = value['data'];
    return data is Map ? Map<String, dynamic>.from(data) : value;
  }

  Future<Map<String, dynamic>> createWork({required String title, String description = ''}) async =>
      _data(await _client.post('$_base/works', body: {'title': title, 'description': description}));

  Future<Map<String, dynamic>> getWork(int id) async => _data(await _client.get('$_base/works/$id'));

  Future<Map<String, dynamic>> updateWork(int id, Map<String, dynamic> body) async =>
      _data(await _client.patch('$_base/works/$id', body: body));

  Future<Map<String, dynamic>> createChapter(int workId, {required String title, required String text, int sortOrder = 0}) async =>
      _data(await _client.post('$_base/works/$workId/chapters', body: {'title': title, 'source_text': text, 'sort_order': sortOrder}));

  Future<Map<String, dynamic>> updateChapter(int id, Map<String, dynamic> body) async =>
      _data(await _client.patch('$_base/chapters/$id', body: body));

  Future<void> deleteChapter(int id) => _client.delete('$_base/chapters/$id');

  Future<Map<String, dynamic>> getChapter(int id) async => _data(await _client.get('$_base/chapters/$id'));

  /// LLM 解析本章：提取角色 → 分句 → 分镜。立即返回，之后轮询 getChapter 的 processing_status。
  Future<Map<String, dynamic>> analyzeChapter(int id) async => _data(await _client.post('$_base/chapters/$id/analyze'));

  Future<Map<String, dynamic>> chapterItems(int id) async => _data(await _client.get('$_base/chapters/$id/items'));

  Future<Map<String, dynamic>> updateItem(int id, Map<String, dynamic> body) async =>
      _data(await _client.patch('$_base/items/$id', body: body));

  Future<Map<String, dynamic>> characters(int workId) async => _data(await _client.get('$_base/works/$workId/characters'));

  Future<Map<String, dynamic>> createCharacter(int workId, Map<String, dynamic> body) async =>
      _data(await _client.post('$_base/works/$workId/characters', body: body));

  Future<Map<String, dynamic>> updateCharacter(int id, Map<String, dynamic> body) async =>
      _data(await _client.patch('$_base/characters/$id', body: body));

  Future<void> deleteCharacter(int id) => _client.delete('$_base/characters/$id');

  Future<Map<String, dynamic>> prepareChapter(int id) async => _data(await _client.post('$_base/chapters/$id/prepare'));

  Future<Map<String, dynamic>> prepareAssets(int id, {Map<String, dynamic>? voice, Map<String, dynamic>? image}) async =>
      _data(await _client.post('$_base/chapters/$id/prepare-assets', body: {'voice_profile': voice ?? {}, 'image_profile': image ?? {}}));

  Future<Map<String, dynamic>> playback(int id) async => _data(await _client.get('$_base/chapters/$id/playback'));

  Future<Map<String, dynamic>> progress(int workId) async => _data(await _client.get('$_base/works/$workId/progress'));

  Future<Map<String, dynamic>> saveProgress(int workId, {int? chapterId, int itemIndex = 0, double positionSeconds = 0}) async =>
      _data(await _client.put('$_base/works/$workId/progress', body: {'chapter_id': chapterId, 'item_index': itemIndex, 'position_seconds': positionSeconds}));
}
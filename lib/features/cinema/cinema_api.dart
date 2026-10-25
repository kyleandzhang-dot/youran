import 'dart:async';

import 'package:http/http.dart' as http;

import '../../api/api_client.dart';

class CinemaApi {
  CinemaApi({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  static const String _base = '/cinema';

  Map<String, dynamic> _data(Map<String, dynamic> value) {
    final data = value['data'];
    return data is Map ? Map<String, dynamic>.from(data) : value;
  }

  Future<Map<String, dynamic>> createWork({
    required String title,
    String description = '',
  }) async => _data(
    await _client.post(
      '$_base/works',
      body: {'title': title, 'description': description},
    ),
  );

  Future<Map<String, dynamic>> getWork(int id) async =>
      _data(await _client.get('$_base/works/$id'));

  Future<Map<String, dynamic>> updateWork(
    int id,
    Map<String, dynamic> body,
  ) async => _data(await _client.patch('$_base/works/$id', body: body));

  Future<Map<String, dynamic>> createChapter(
    int workId, {
    required String title,
    required String text,
    int sortOrder = 0,
  }) async => _data(
    await _client.post(
      '$_base/works/$workId/chapters',
      body: {'title': title, 'source_text': text, 'sort_order': sortOrder},
    ),
  );

  Future<Map<String, dynamic>> updateChapter(
    int id,
    Map<String, dynamic> body,
  ) async => _data(await _client.patch('$_base/chapters/$id', body: body));

  Future<void> deleteChapter(int id) => _client.delete('$_base/chapters/$id');

  Future<Map<String, dynamic>> getChapter(int id) async =>
      _data(await _client.get('$_base/chapters/$id'));

  /// LLM 解析本章：提取角色 → 分句 → 分镜。立即返回，之后轮询 getChapter 的 processing_status。
  Future<Map<String, dynamic>> analyzeChapter(int id) async =>
      _data(await _client.post('$_base/chapters/$id/analyze'));

  Future<Map<String, dynamic>> chapterItems(int id) async =>
      _data(await _client.get('$_base/chapters/$id/items'));

  Future<Map<String, dynamic>> updateItem(
    int id,
    Map<String, dynamic> body,
  ) async => _data(await _client.patch('$_base/items/$id', body: body));

  Future<Map<String, dynamic>> characters(int workId) async =>
      _data(await _client.get('$_base/works/$workId/characters'));

  Future<Map<String, dynamic>> createCharacter(
    int workId,
    Map<String, dynamic> body,
  ) async =>
      _data(await _client.post('$_base/works/$workId/characters', body: body));

  Future<Map<String, dynamic>> updateCharacter(
    int id,
    Map<String, dynamic> body,
  ) async => _data(await _client.patch('$_base/characters/$id', body: body));

  Future<void> deleteCharacter(int id) =>
      _client.delete('$_base/characters/$id');

  Future<Map<String, dynamic>> prepareChapter(int id) async =>
      _data(await _client.post('$_base/chapters/$id/prepare'));

  Future<Map<String, dynamic>> prepareAssets(
    int id, {
    Map<String, dynamic>? voice,
    Map<String, dynamic>? image,
    int? itemIndex,
  }) async => _data(
    await _client.post(
      '$_base/chapters/$id/prepare-assets',
      queryParams: {if (itemIndex != null) 'item_index': itemIndex},
      body: {'voice_profile': voice ?? {}, 'image_profile': image ?? {}},
    ),
  );

  Future<Map<String, dynamic>> playback(int id, {int? itemIndex}) async =>
      _data(
        await _client.get(
          '$_base/chapters/$id/playback',
          queryParams: {if (itemIndex != null) 'item_index': itemIndex},
        ),
      );

  static String normalizeGender(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'male' || '男' || '男性' => 'male',
      'female' || '女' || '女性' => 'female',
      'other' || '其他' || '非二元' => 'other',
      _ => 'unknown',
    };
  }

  static String genderLabel(Object? value) => switch (normalizeGender(value)) {
    'male' => '男',
    'female' => '女',
    'other' => '其他',
    _ => '未知',
  };

  /// 台词和音色由后端按条目读取，已有音频会直接复用。
  Future<String> itemAudio(int itemId) async {
    final data = _data(await _client.post('$_base/items/$itemId/tts'));
    final asset = data['asset'];
    final url =
        (asset is Map ? asset['url'] : data['url'])?.toString().trim() ?? '';
    if (url.isEmpty) throw const ApiException('后端未返回可播放语音');
    return url;
  }

  // ───────── 角色立绘：上传 / AI 生成 ─────────
  // 与小说端共用同一套通用图片服务和 R2 直传，不依赖 /cinema 路由。

  /// 与 HttpNovelBackend 一致：data 非空取 data，否则取根对象。
  Map<String, dynamic> _payload(Map<String, dynamic> root) {
    final data = root['data'];
    return data is Map && data.isNotEmpty
        ? Map<String, dynamic>.from(data)
        : root;
  }

  /// 上传图片到 R2（先取预签名地址，再 PUT），返回公开访问 URL。
  Future<String> uploadCharacterImage({
    required List<int> bytes,
    required String filename,
    required String contentType,
    String category = 'char/portrait',
  }) async {
    if (bytes.isEmpty) throw const ApiException('上传文件为空');

    final signed = _payload(
      await _client.post(
        '/r2/get-signature',
        body: <String, dynamic>{
          'filename': filename,
          'content_type': contentType,
          'category': category,
        },
      ),
    );
    final uploadUrl = (signed['upload_url'] ?? '').toString();
    var publicUrl = (signed['public_url'] ?? '').toString();
    if (uploadUrl.isEmpty || publicUrl.isEmpty) {
      throw const ApiException('获取上传签名失败：缺少 upload_url/public_url');
    }
    if (!publicUrl.startsWith('http://') && !publicUrl.startsWith('https://')) {
      publicUrl = 'https://$publicUrl';
    }

    try {
      final res = await http
          .put(
            Uri.parse(uploadUrl),
            headers: <String, String>{'Content-Type': contentType},
            body: bytes,
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          '图片上传失败（HTTP ${res.statusCode}）',
          statusCode: res.statusCode,
        );
      }
    } on TimeoutException {
      throw const ApiException('上传超时，请检查网络后重试');
    }
    return publicUrl;
  }

  /// AI 生成角色立绘，返回立绘 URL。
  /// 只轮询普通 JSON 的 /result 接口（/image/task/{id} 是 SSE 长连接，不能用 http 轮询）。
  Future<String> generateCharacterPortrait({
    required String name,
    String gender = 'unknown',
    String appearancePrompt = '',
    String worldContext = '',
    String style = 'anime',
  }) async {
    final look = appearancePrompt.trim();
    final world = worldContext.trim();
    final description = <String>[
      '【角色视觉简报｜角色设定优先】',
      '【角色姓名】$name',
      '【性别】${genderLabel(gender)}',
      '【外貌描述】${look.isEmpty ? '未明确，请根据姓名与作品背景合理设计' : look}',
      if (world.isNotEmpty) '【作品背景】$world',
      '【美术转译要求】以上资料是事实依据，请把身份与气质一起视觉化到脸部、轮廓、服装与姿态，输出单人全身立绘。',
    ].join('\n');

    final created = _payload(
      await _client.post(
        '/image/generate',
        body: <String, dynamic>{
          'description': description,
          'style': style == 'stylized_3d' ? '3d' : style,
          'remove_bg': true,
          'auto_crop_avatar': true,
        },
      ),
    );
    final taskId = (created['task_id'] ?? created['id'] ?? '').toString();
    if (taskId.isEmpty) throw const ApiException('图片服务未返回 task_id');

    String portraitOf(Map<String, dynamic> d) =>
        (d['portrait_url'] ??
                d['portrait'] ??
                d['tachie'] ??
                d['image_url'] ??
                d['url'] ??
                '')
            .toString()
            .trim();

    var url = portraitOf(created);
    if (url.isNotEmpty) return url;

    final estimated = int.tryParse('${created['estimated_wait'] ?? ''}') ?? 60;
    final deadline = DateTime.now().add(
      Duration(seconds: (estimated + 45).clamp(60, 180).toInt()),
    );
    const failedStates = <String>{'failed', 'error', 'cancelled', 'canceled'};
    final resultPath = '/image/task/${Uri.encodeComponent(taskId)}/result';

    while (DateTime.now().isBefore(deadline)) {
      var failure = '';
      try {
        final r = _payload(
          await _client.get(resultPath).timeout(const Duration(seconds: 8)),
        );
        url = portraitOf(r);
        if (url.isNotEmpty) return url;
        final state = (r['status'] ?? r['state'] ?? r['task_status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (failedStates.contains(state)) {
          failure = (r['error'] ?? r['message'] ?? 'AI 立绘生成失败').toString();
        }
      } on ApiException catch (e) {
        // 无状态码＝网络抖动/超时，继续轮询；404＝任务刚创建尚不可见；其余错误直接抛出
        if (e.statusCode != null && e.statusCode != 404) rethrow;
      } catch (_) {
        // 临时错误不终止生成，deadline 前继续探测
      }
      if (failure.isNotEmpty) throw ApiException(failure);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    // deadline 临界点再取最后一次
    try {
      url = portraitOf(
        _payload(
          await _client.get(resultPath).timeout(const Duration(seconds: 8)),
        ),
      );
      if (url.isNotEmpty) return url;
    } catch (_) {}
    throw const ApiException('立绘生成超时，请稍后重试');
  }

  Future<Map<String, dynamic>> progress(int workId) async =>
      _data(await _client.get('$_base/works/$workId/progress'));

  Future<Map<String, dynamic>> saveProgress(
    int workId, {
    int? chapterId,
    int itemIndex = 0,
    double positionSeconds = 0,
  }) async => _data(
    await _client.put(
      '$_base/works/$workId/progress',
      body: {
        'chapter_id': chapterId,
        'item_index': itemIndex,
        'position_seconds': positionSeconds,
      },
    ),
  );
}

import 'novel_models.dart';

abstract class NovelBackend {
  Future<NovelScenario> fetchScenario(String scenarioId, {bool full = true});

  Future<NovelHistoryResult> fetchHistory(
    String sessionId, {
    bool force = false,
  });

  Stream<NovelStreamEvent> sendMessageStream(NovelSendRequest request);

  Future<void> cancelActiveStream();

  Future<void> markMessageRead(String scenarioId, String messageId);

  Future<List<NovelCharacter>> fetchCharacterStatus(String scenarioId);

  Future<JsonMap> fetchJourney(String scenarioId);

  Future<void> updateScenario(String scenarioId, JsonMap payload);

  Future<NovelModelConfig> fetchModelConfig();

  Future<void> updateNovelModel(String modelId);

  /// 创建 AI 立绘任务。Flutter 使用同一套图片服务，但用状态轮询代替浏览器 EventSource。
  Future<JsonMap> createImageTask({
    required String description,
    required String style,
    bool removeBackground = true,
    bool autoCropAvatar = true,
  });

  Future<JsonMap> fetchImageTaskStatus(String taskId);

  Future<JsonMap> fetchImageTaskResult(String taskId);

  /// 与 Vue uploadToR2() 对齐：先向 /r2/get-signature 取签名，再 PUT 到预签名地址。
  Future<String> uploadBytesToR2({
    required List<int> bytes,
    required String filename,
    required String contentType,
    String category = 'general',
  });

  /// Vue 的真实调用是 GET /novel/inventory/{sessionId}。
  /// 不要把这里误认为 scenario instance id。
  Future<NovelInventoryData> fetchInventory(String sessionId);

  Future<void> equipItem({
    required String scenarioInstanceId,
    required String itemId,
    required bool equipped,
  });

  Future<NovelGiftResult> useGift({
    required String sessionId,
    required String scenarioInstanceId,
    required String characterInstanceId,
  });

  Future<NovelBlindBoxReward> useBlindBox({
    required String sessionId,
    required String scenarioInstanceId,
  });

  Future<List<NovelShopItem>> fetchShopItems(String sessionId);

  Future<NovelScore> buyItem({
    required String sessionId,
    required String scenarioInstanceId,
    required String itemType,
    int quantity = 1,
  });

  Future<NovelHistoryResult> revertToTurn({
    required String sessionId,
    required String scenarioInstanceId,
    required int targetTurn,
  });

  Future<void> close();
}

class NovelBackendException implements Exception {
  const NovelBackendException(
    this.message, {
    this.statusCode,
    this.code = '',
    this.details,
  });

  final String message;
  final int? statusCode;
  final String code;
  final dynamic details;

  bool get isInsufficientBalance =>
      statusCode == 402 ||
      code == 'INSUFFICIENT_BALANCE' ||
      message.contains('点数不足') ||
      message.contains('余额不足');

  @override
  String toString() => message;
}

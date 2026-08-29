import 'novel_models.dart';

abstract class NovelBackend {
  Future<NovelScenario> fetchScenario(String scenarioId, {bool full = true});

  Future<NovelHistoryResult> fetchHistory(
    String sessionId, {
    bool force = false,
  });

  Stream<NovelStreamEvent> sendMessageStream(NovelSendRequest request);

  /// 获取当前位置与一跳相邻节点。后端不会返回完整世界地图或隐藏节点。
  Future<JsonMap> fetchSceneMap(String sessionId);

  /// 校验一次节点点击并返回结构化 navigation_action；本接口不直接改位置。
  Future<JsonMap> createSceneMoveIntent(
    String sessionId,
    String targetSceneId,
  );

  /// 轻量读取当前位置是否允许调查；本接口不会触发 LLM。
  Future<JsonMap> fetchSurroundingsAvailability(String sessionId);

  /// 首次打开时按当前场景生成并保存调查结构；之后直接读取存档。
  Future<JsonMap> fetchSurroundings(String sessionId);

  Future<JsonMap> investigateSurroundNode(
    String sessionId,
    String nodeId,
  );

  Future<JsonMap> combineSurroundNodes(
    String sessionId,
    String firstId,
    String secondId,
  );

  Future<JsonMap> claimSurroundReward(
    String sessionId,
    String nodeId,
  );

  /// 使用与普通聊天完全相同的 SSE 通道发送一次地图移动回合。
  Stream<NovelStreamEvent> sendNavigationMessageStream(
    NovelSendRequest request,
    JsonMap navigationAction,
  );

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

  /// 战斗退出时一次性扣除本场使用的消耗品。
  /// 默认实现便于预览/测试后端继续工作；正式 HTTP 后端必须覆写。
  Future<JsonMap> settleBattleItems({
    required String sessionId,
    required List<JsonMap> consumptions,
    required String outcome,
  }) {
    throw const NovelBackendException('当前后端不支持战斗道具结算');
  }

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

/// 可选的开发者内容识别能力。
///
/// 单独拆成接口，避免预览/测试用的 NovelBackend 实现被迫接入开发者路由；
/// 正式 HTTP 后端实现后，控制器会自动启用“输入名称获取技能/物品”。
abstract class NovelDeveloperContentBackend {
  Future<JsonMap> recognizeAndAcquireDeveloperContent({
    required String sessionId,
    required String name,
  });
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

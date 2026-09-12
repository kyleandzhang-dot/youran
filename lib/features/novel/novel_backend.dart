import 'novel_models.dart';

abstract class NovelBackend {
  Future<NovelScenario> fetchScenario(String scenarioId, {bool full = true});

  Future<NovelHistoryResult> fetchHistory(
    String sessionId, {
    bool force = false,
  });

  Stream<NovelStreamEvent> sendMessageStream(NovelSendRequest request);

  /// 按场景名称生成新版自由二维 ScenePlan。
  /// 返回只负责空间布局与实体语义，不写旧 surroundings 探索状态。
  Future<JsonMap> previewSceneLayout({
    required String name,
    String? sessionId,
    String description = '',
  });

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

  /// 点击调查中的敌人节点后，创建并冻结一场后端权威战斗。
  Future<JsonMap> startSurroundEncounter(
    String sessionId,
    String nodeId,
  ) {
    throw const NovelBackendException('当前后端不支持探索遭遇');
  }

  /// 使用与普通聊天完全相同的 SSE 通道发送一次地图移动回合。
  Stream<NovelStreamEvent> sendNavigationMessageStream(
    NovelSendRequest request,
    JsonMap navigationAction,
  );

  Future<void> cancelActiveStream();

  Future<void> markMessageRead(String scenarioId, String messageId);

  Future<List<NovelCharacter>> fetchCharacterStatus(String scenarioId);

  /// 读取当前小说存档的结缘状态。鲜花、碎片和已获得角色均由后端持久化。
  Future<JsonMap> fetchNovelCharacterRoster(String mainSessionId) {
    throw const NovelBackendException('当前后端不支持小说角色结缘');
  }

  /// 在当前小说存档中消耗鲜花结缘。count 目前只允许 1 或 10。
  Future<JsonMap> drawNovelCharacters({
    required String mainSessionId,
    required int count,
  }) {
    throw const NovelBackendException('当前后端不支持小说角色结缘');
  }

  /// 消耗角色碎片升一星。角色从 0 星开始，最高 10 星。
  Future<JsonMap> upgradeNovelCharacter({
    required String mainSessionId,
    required String characterInstanceId,
  }) {
    throw const NovelBackendException('当前后端不支持小说角色升星');
  }

  /// 读取 NPC 援战阵容与程序化技能（最多 3 人出战、每人最多 4 技能）。
  Future<JsonMap> fetchNovelCompanions(String mainSessionId) {
    throw const NovelBackendException('当前后端不支持 NPC 援战');
  }

  Future<JsonMap> updateNovelCompanionDeployment({
    required String mainSessionId,
    required String characterInstanceId,
    required bool deployed,
  }) {
    throw const NovelBackendException('当前后端不支持调整援战阵容');
  }

  Future<JsonMap> drawNovelCompanionSkill({
    required String mainSessionId,
    required String characterInstanceId,
  }) {
    throw const NovelBackendException('当前后端不支持抽取援战技能');
  }

  Future<JsonMap> renameNovelCompanionSkill({
    required String mainSessionId,
    required String characterInstanceId,
    required String skillId,
    required String name,
  }) {
    throw const NovelBackendException('当前后端不支持命名援战技能');
  }

  /// 读取小说角色页中某个已获得角色的私聊记录。
  Future<JsonMap> fetchNovelCharacterChatHistory({
    required String mainSessionId,
    required String characterInstanceId,
    int offset = 0,
    int limit = 30,
  }) {
    throw const NovelBackendException('当前后端不支持小说角色私聊');
  }

  /// 小说角色页专用 SSE。它不推进主线，也不复用主线消息列表。
  Stream<JsonMap> sendNovelCharacterChatStream({
    required String mainSessionId,
    required String characterInstanceId,
    required String message,
  }) {
    throw const NovelBackendException('当前后端不支持小说角色私聊');
  }

  Future<void> cancelNovelCharacterChatStream() async {}

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
    String battleId = '',
  }) {
    throw const NovelBackendException('当前后端不支持战斗道具结算');
  }

  Future<void> equipItem({
    required String scenarioInstanceId,
    required String itemId,
    required bool equipped,
  });

  /// 消耗 1 颗玄石尝试强化装备；成功率、保底与材料扣除均由后端权威判定。
  Future<JsonMap> enhanceEquipment({
    required String sessionId,
    required String scenarioInstanceId,
    required String itemId,
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

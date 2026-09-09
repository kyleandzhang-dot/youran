part of '../novel_sheets.dart';

// ============================================================================
// 开发者测试页
// 页面入口 / 对外入口：
//   - NovelDeveloperPreviewActions
//   - _DeveloperToolsPanel（由设置页进入）
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

class NovelDeveloperPreviewActions {
  const NovelDeveloperPreviewActions({
    required this.weatherOverride,
    required this.timeOverride,
    required this.backgroundPreviewName,
    required this.parallaxStrength,
    required this.setWeatherOverride,
    required this.setTimeOverride,
    required this.setParallaxStrength,
    required this.setBackgroundPreview,
    required this.clearBackgroundPreview,
    required this.previewCharacterSetup,
    required this.previewOpening,
    required this.previewSceneArrival,
    required this.previewStoryBrewing,
    required this.previewLoading,
    required this.previewFailure,
    required this.previewFateRevert,
    required this.previewBalance,
    required this.previewDice,
    required this.previewChoices,
    required this.previewSurroundings,
    required this.previewWorldMap,
    required this.previewBattle,
    required this.previewTimeSkip,
    required this.previewEndingIntro,
    required this.previewEnding,
    required this.previewImageTransition,
    required this.previewAffectionUp,
    required this.previewAffectionDown,
    required this.previewItemObtained,
    required this.previewScoreGain,
    required this.previewGoalRefresh,
    required this.previewGoalSuccess,
    required this.previewGoalFailure,
    required this.previewDamageLight,
    required this.previewDamage,
    required this.previewDamageCritical,
    required this.previewRecovery,
    required this.previewRisk,
    required this.previewNarrationStyles,
    this.recognizeAndAcquireContent,
    this.testGeneratedOpponent,
  });

  final NovelWeatherEffect? Function() weatherOverride;
  final NovelTimePeriod? Function() timeOverride;
  final String? Function() backgroundPreviewName;
  final double Function() parallaxStrength;
  final Future<void> Function(NovelWeatherEffect? value) setWeatherOverride;
  final void Function(NovelTimePeriod? value) setTimeOverride;
  final ValueChanged<double> setParallaxStrength;
  final void Function(Uint8List bytes, String fileName) setBackgroundPreview;
  final VoidCallback clearBackgroundPreview;

  final Future<void> Function() previewCharacterSetup;
  final Future<void> Function() previewOpening;
  final Future<void> Function() previewSceneArrival;
  final Future<void> Function() previewStoryBrewing;
  final Future<void> Function() previewLoading;
  final Future<void> Function() previewFailure;
  final Future<void> Function() previewFateRevert;
  final Future<void> Function() previewBalance;
  final Future<void> Function() previewDice;
  final Future<void> Function() previewChoices;
  final Future<void> Function() previewSurroundings;
  final Future<void> Function() previewWorldMap;
  final Future<void> Function() previewBattle;
  final Future<void> Function() previewTimeSkip;
  final Future<void> Function() previewEndingIntro;
  final Future<void> Function() previewEnding;
  final Future<void> Function() previewImageTransition;

  // 直接反馈预览：全部只作用于当前客户端，不写真实剧情状态。
  final Future<void> Function() previewAffectionUp;
  final Future<void> Function() previewAffectionDown;
  final Future<void> Function() previewItemObtained;
  final Future<void> Function() previewScoreGain;
  final Future<void> Function() previewGoalRefresh;
  final Future<void> Function() previewGoalSuccess;
  final Future<void> Function() previewGoalFailure;
  final Future<void> Function() previewDamageLight;
  final Future<void> Function() previewDamage;
  final Future<void> Function() previewDamageCritical;
  final Future<void> Function() previewRecovery;
  final Future<void> Function() previewRisk;

  // 正文（旁白层）正则标记样式预览：把 （）* 【】 [] "" 全部标记的实际渲染
  // 效果集中展示，纯本地弹窗，不产生真实剧情反馈，所以单独放在字段最后。
  final Future<void> Function() previewNarrationStyles;

  /// 开发者专用：统一识别技能、药物、武器和普通物品并写入对应状态。
  final Future<String> Function(String name)? recognizeAndAcquireContent;

  /// 开发者专用：输入对手名称和可选描述，调用后端读取当前玩家、生成对手，
  /// 随后直接进入真实战斗页。
  final Future<void> Function(String opponentName, String description)?
      testGeneratedOpponent;
}
class _DeveloperToolsPanel extends StatefulWidget {
  const _DeveloperToolsPanel({
    required this.actions,
    required this.onBack,
  });

  final NovelDeveloperPreviewActions actions;
  final VoidCallback onBack;

  @override
  State<_DeveloperToolsPanel> createState() => _DeveloperToolsPanelState();
}

class _DeveloperToolsPanelState extends State<_DeveloperToolsPanel> {
  final TextEditingController _contentNameController = TextEditingController();
  final TextEditingController _opponentNameController = TextEditingController();
  final TextEditingController _opponentDescriptionController =
      TextEditingController();
  bool _recognizingContent = false;
  bool _startingOpponentBattle = false;
  bool _pickingBackground = false;
  String _contentResult = '';
  bool _contentResultIsError = false;
  String? _expandedDeveloperSection = 'environment';

  NovelDeveloperPreviewActions get actions => widget.actions;

  @override
  void dispose() {
    _contentNameController.dispose();
    _opponentNameController.dispose();
    _opponentDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _recognizeAndAcquireContent() async {
    final submit = actions.recognizeAndAcquireContent;
    final name = _contentNameController.text.trim();
    if (submit == null || name.isEmpty || _recognizingContent) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _recognizingContent = true;
      _contentResult = '';
      _contentResultIsError = false;
    });
    try {
      final result = await submit(name);
      if (!mounted) return;
      final message = result.trim().isEmpty ? '已写入当前存档' : result.trim();
      setState(() {
        _contentResult = message;
        _contentResultIsError = message.startsWith('未识别');
        if (!_contentResultIsError) _contentNameController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contentResult = error is NovelBackendException
            ? error.message
            : '识别或写入失败，请检查后端接口与当前存档。';
        _contentResultIsError = true;
      });
    } finally {
      if (mounted) setState(() => _recognizingContent = false);
    }
  }

  Future<void> _openPreview(Future<void> Function() preview) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await preview();
  }

  Future<void> _openDepthParallaxPreview() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DepthParallaxPreviewPage(),
      ),
    );
  }

  Future<void> _testGeneratedOpponent() async {
    final submit = actions.testGeneratedOpponent;
    final name = _opponentNameController.text.trim();
    final description = _opponentDescriptionController.text.trim();
    if (submit == null || name.isEmpty || _startingOpponentBattle) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _startingOpponentBattle = true);
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await submit(name, description);
  }

  Future<void> _pickBackgroundPreview() async {
    if (_pickingBackground) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _pickingBackground = true);

    try {
      // 与项目现有探索页的图片上传逻辑保持一致。
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      if (!mounted || file == null || file.bytes == null) return;

      final bytes = file.bytes!;
      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('无法读取这张图片，请换一张 JPG / PNG / WebP')),
          );
        return;
      }

      actions.setBackgroundPreview(bytes, file.name);
      if (!mounted) return;
      // 选完立即回到剧情页，方便直接比较手机 / 电脑布局构图。
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('选择背景失败，请重新选择图片')),
        );
    } finally {
      if (mounted) setState(() => _pickingBackground = false);
    }
  }

  void _restoreStoryBackground() {
    actions.clearBackgroundPreview();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toggleDeveloperSection(String section) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _expandedDeveloperSection =
          _expandedDeveloperSection == section ? null : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentWeather = actions.weatherOverride();
    final currentTime = actions.timeOverride();
    final currentBackgroundName = actions.backgroundPreviewName();
    final currentParallaxStrength =
        actions.parallaxStrength().clamp(.15, 2.5).toDouble();
    const weatherOptions = <NovelWeatherEffect?>[
      null,
      NovelWeatherEffect.none,
      NovelWeatherEffect.cloudy,
      NovelWeatherEffect.rain,
      NovelWeatherEffect.heavyRain,
      NovelWeatherEffect.thunderstorm,
      NovelWeatherEffect.snow,
      NovelWeatherEffect.blizzard,
    ];
    const timeOptions = <NovelTimePeriod?>[
      null,
      NovelTimePeriod.morning,
      NovelTimePeriod.noon,
      NovelTimePeriod.afternoon,
      NovelTimePeriod.evening,
      NovelTimePeriod.night,
      NovelTimePeriod.midnight,
    ];

    return _SettingsDrawerScaffold(
      title: '开发者测试',
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: <Widget>[
          Text(
            '页面与反馈预览仅改变当前客户端；“识别并获取”会写入当前存档，“测试对手”只生成本场战斗。',
            style: TextStyle(
              color: AppColors.textOnDarkMuted.withOpacity(.88),
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.035),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withOpacity(.10)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _novelDrawerAccent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.wallpaper_rounded,
                    size: 18,
                    color: _novelDrawerAccent.withOpacity(.92),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '背景图快速预览',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentBackgroundName == null
                            ? '上传本地图片，立即回到剧情页查看效果'
                            : '当前：$currentBackgroundName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted.withOpacity(.80),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    onPressed: _pickingBackground ? null : _pickBackgroundPreview,
                    icon: _pickingBackground
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: AppColors.textOnDark,
                            ),
                          )
                        : const Icon(Icons.upload_rounded, size: 15),
                    label: Text(
                      currentBackgroundName == null ? '上传背景图' : '重新上传',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textOnDark,
                      side: BorderSide(color: Colors.white.withOpacity(.14)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _DeveloperFoldHeader(
            title: '生成 / 数据',
            subtitle: '识别并获取 · 测试对手',
            expanded: _expandedDeveloperSection == 'data',
            onTap: () => _toggleDeveloperSection('data'),
          ),
          if (_expandedDeveloperSection == 'data') ...<Widget>[
          if (actions.recognizeAndAcquireContent != null) ...<Widget>[
            const _DeveloperSectionTitle(
              title: '识别并获取',
              subtitle: '统一识别技能、药物、武器与普通物品，并写入对应状态',
            ),
            const SizedBox(height: 10),
            _CleanSettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _contentNameController,
                    enabled: !_recognizingContent,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _recognizeAndAcquireContent(),
                    style: const TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: '例如：八极崩、玄重尺、回气丹、纳戒',
                      hintStyle: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(.72),
                        fontSize: 11.5,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.035),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: FilledButton(
                      onPressed: _recognizingContent
                          ? null
                          : _recognizeAndAcquireContent,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF111313),
                        disabledBackgroundColor: Colors.white.withOpacity(.20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _recognizingContent
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: Color(0xFF111313),
                              ),
                            )
                          : const Text(
                              '识别并获取',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  if (_contentResult.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 9),
                    Text(
                      _contentResult,
                      style: TextStyle(
                        color: _contentResultIsError
                            ? const Color(0xFFFF8C8C)
                            : const Color(0xFFBFD7C3),
                        fontSize: 10.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          if (actions.testGeneratedOpponent != null) ...<Widget>[
            const _DeveloperSectionTitle(
              title: '测试对手',
              subtitle: '名称必填、描述可选；后端读取当前玩家后生成数值并直接进入战斗',
            ),
            const SizedBox(height: 10),
            _CleanSettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _opponentNameController,
                    enabled: !_startingOpponentBattle,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    style: const TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: '对手名称（必填）',
                      hintText: '例如：云山、雷欧奥特曼、自定义剑士',
                      labelStyle: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(.86),
                        fontSize: 11.5,
                      ),
                      hintStyle: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(.62),
                        fontSize: 11.5,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.035),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _opponentDescriptionController,
                    enabled: !_startingOpponentBattle,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 800,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      labelText: '补充描述（可选）',
                      hintText: '填写时期、境界、装备或特殊状态，例如：斗宗时期，魂殿强化前',
                      counterText: '',
                      labelStyle: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(.86),
                        fontSize: 11.5,
                      ),
                      hintStyle: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(.62),
                        fontSize: 11.5,
                      ),
                      alignLabelWithHint: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.035),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(.26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '只填知名角色名称也可以；存在多个时期或形态时，建议补充说明。',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted.withOpacity(.72),
                      fontSize: 10.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: FilledButton(
                      onPressed: _startingOpponentBattle ||
                              _opponentNameController.text.trim().isEmpty
                          ? null
                          : _testGeneratedOpponent,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEFE7DA),
                        foregroundColor: const Color(0xFF211A16),
                        disabledBackgroundColor: Colors.white.withOpacity(.20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '生成对手并进入战斗',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          ],
          const SizedBox(height: 10),
          _DeveloperFoldHeader(
            title: '环境',
            subtitle: '背景 · 天气 · 时间',
            expanded: _expandedDeveloperSection == 'environment',
            onTap: () => _toggleDeveloperSection('environment'),
          ),
          if (_expandedDeveloperSection == 'environment') ...<Widget>[
          const _DeveloperSectionTitle(
            title: '环境预览',
            subtitle: '直接观察背景、光照与天气效果',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '背景',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed:
                              _pickingBackground ? null : _pickBackgroundPreview,
                          icon: _pickingBackground
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppColors.textOnDark,
                                  ),
                                )
                              : const Icon(
                                  Icons.image_outlined,
                                  size: 17,
                                ),
                          label: Text(
                            currentBackgroundName == null
                                ? '更换背景'
                                : '重新选择背景',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textOnDark,
                            side: BorderSide(
                              color: Colors.white.withOpacity(.14),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (currentBackgroundName != null) ...<Widget>[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _restoreStoryBackground,
                        child: const Text(
                          '恢复',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
                if (currentBackgroundName != null) ...<Widget>[
                  const SizedBox(height: 7),
                  Text(
                    '当前预览：$currentBackgroundName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted.withOpacity(.78),
                      fontSize: 9.8,
                    ),
                  ),
                ],
                Divider(height: 22, color: Colors.white.withOpacity(.10)),
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '2.5D 强度',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      currentParallaxStrength.toStringAsFixed(2),
                      style: TextStyle(
                        color: _novelDrawerAccent.withOpacity(.95),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Slider(
                  value: currentParallaxStrength,
                  min: .15,
                  max: 2.5,
                  divisions: 47,
                  onChanged: (value) {
                    actions.setParallaxStrength(value);
                    if (mounted) setState(() {});
                  },
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <double>[.75, 1.0, 1.5, 2.0, 2.5].map((value) {
                    return _DeveloperChoiceChip(
                      label: value.toStringAsFixed(value == 1.0 || value == 2.0 ? 1 : 2),
                      selected: (currentParallaxStrength - value).abs() < .03,
                      onTap: () {
                        actions.setParallaxStrength(value);
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  currentBackgroundName == null
                      ? '默认 1.50。选择背景后会直接走正式剧情的 Depth + Shader；调强度后回到剧情页即可比较。'
                      : '当前本地背景正在复用正式剧情 2.5D 链路；调整后回到剧情页立即生效。',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted.withOpacity(.76),
                    fontSize: 9.6,
                    height: 1.45,
                  ),
                ),
                Divider(height: 22, color: Colors.white.withOpacity(.10)),
                _DeveloperPreviewRow(
                  title: '独立 2.5D 深度实验室',
                  subtitle: '单独查看原图 / Depth / Shader；正式剧情预览请直接用上方“更换背景”',
                  onTap: _openDepthParallaxPreview,
                ),
                Divider(height: 22, color: Colors.white.withOpacity(.10)),
                const Text(
                  '天气',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: weatherOptions.map((effect) {
                    final selected = currentWeather == effect;
                    return _DeveloperChoiceChip(
                      label: effect?.label ?? '自动',
                      selected: selected,
                      onTap: () async {
                        await actions.setWeatherOverride(effect);
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
                Divider(height: 22, color: Colors.white.withOpacity(.10)),
                const Text(
                  '时间',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: timeOptions.map((period) {
                    final selected = currentTime == period;
                    return _DeveloperChoiceChip(
                      label: period?.label ?? '自动',
                      selected: selected,
                      onTap: () {
                        actions.setTimeOverride(period);
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ],
          const SizedBox(height: 10),
          _DeveloperFoldHeader(
            title: '剧情反馈',
            subtitle: '好感 · 物品 · 积分 · 目标 · 伤势 · 风险',
            expanded: _expandedDeveloperSection == 'feedback',
            onTap: () => _toggleDeveloperSection('feedback'),
          ),
          if (_expandedDeveloperSection == 'feedback') ...<Widget>[
          const _DeveloperSectionTitle(
            title: '直接反馈预览',
            subtitle: '关闭测试抽屉后播放真实剧情页会使用的反馈效果',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _DeveloperPreviewRow(
                  title: '角色好感 +2',
                  subtitle: '当前对白角色爱心与数字原位放大；角色未出场则等出场再播放',
                  onTap: () => _openPreview(actions.previewAffectionUp),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '角色好感 -2',
                  subtitle: '当前对白角色爱心与数字原位缩放反馈，不再弹 HUD 卡片',
                  onTap: () => _openPreview(actions.previewAffectionDown),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '获得物品',
                  subtitle: '模拟获得“云岚宗令牌 ×1”，仅显示无背景纯文字提示',
                  onTap: () => _openPreview(actions.previewItemObtained),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '获得积分',
                  subtitle: '模拟 +13 积分，直接让右上角星星与数字原位放大',
                  onTap: () => _openPreview(actions.previewScoreGain),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标刷新',
                  subtitle: '临时替换顶部当前目标并播放目标更新提示',
                  onTap: () => _openPreview(actions.previewGoalRefresh),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标完成',
                  subtitle: '绿色完成动画，复用正式目标成功效果',
                  onTap: () => _openPreview(actions.previewGoalSuccess),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标失败',
                  subtitle: '红色震动失败动画，复用正式目标失败效果',
                  onTap: () => _openPreview(actions.previewGoalFailure),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '伤势屏幕 · 轻伤',
                  subtitle: '静态淡黄边缘，不启动持续呼吸动画',
                  onTap: () => _openPreview(actions.previewDamageLight),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '伤势屏幕 · 重伤',
                  subtitle: '红色边缘 + 很慢的轻微呼吸，预览约 6 秒',
                  onTap: () => _openPreview(actions.previewDamage),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '伤势屏幕 · 濒危',
                  subtitle: '紫红边缘 + 暗角 + 明显呼吸，预览约 6 秒',
                  onTap: () => _openPreview(actions.previewDamageCritical),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '伤势屏幕 · 恢复',
                  subtitle: '切回健康，确认边缘与持续动画立即停止',
                  onTap: () => _openPreview(actions.previewRecovery),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '风险 / 警戒',
                  subtitle: '测试行动失败后留下持续风险的提示',
                  onTap: () => _openPreview(actions.previewRisk),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ],
          const SizedBox(height: 10),
          _DeveloperFoldHeader(
            title: '页面 / 转场',
            subtitle: '开场 · 场景 · 判定 · 战斗 · 结局 · 背景过渡',
            expanded: _expandedDeveloperSection == 'pages',
            onTap: () => _toggleDeveloperSection('pages'),
          ),
          if (_expandedDeveloperSection == 'pages') ...<Widget>[
          const _DeveloperSectionTitle(
            title: '页面预览',
            subtitle: '关闭测试抽屉后直接展示目标页面',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _DeveloperPreviewRow(
                  title: '角色确认',
                  subtitle: '首次进入世界前的角色确认页',
                  onTap: () => _openPreview(actions.previewCharacterSetup),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '故事开场',
                  subtitle: '序章文字与背景过场',
                  onTap: () => _openPreview(actions.previewOpening),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '更换场景',
                  subtitle: '预览中央场景名，以及左上角地点与目标的淡出、恢复',
                  onTap: () => _openPreview(actions.previewSceneArrival),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '加载故事',
                  subtitle: '预览“故事正在展开”的流光动画；轻触页面即可结束',
                  onTap: () => _openPreview(actions.previewStoryBrewing),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '载入世界',
                  subtitle: '初始化中的全屏载入状态',
                  onTap: () => _openPreview(actions.previewLoading),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '载入失败',
                  subtitle: '“世界暂时无法载入”失败页面',
                  onTap: () => _openPreview(actions.previewFailure),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '命运回溯',
                  subtitle: '死亡后的回溯提示页面',
                  onTap: () => _openPreview(actions.previewFateRevert),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '余额不足',
                  subtitle: '无法继续生成剧情时的提示',
                  onTap: () => _openPreview(actions.previewBalance),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '命运判定',
                  subtitle: '骰子判定结果全屏反馈',
                  onTap: () => _openPreview(actions.previewDice),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '选择框样式',
                  subtitle: '固定展示 dialogue / action / battle 三种类型，仅预览不触发剧情',
                  onTap: () => _openPreview(actions.previewChoices),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '探索周围',
                  subtitle: '打开本地演示场景，点击绿色成品测试拾取与放入背包提示',
                  onTap: () => _openPreview(actions.previewSurroundings),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '世界地图',
                  subtitle: '四个场景填充斜角地图格；白线分隔并随机分布',
                  onTap: () => _openPreview(actions.previewWorldMap),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '回合制战斗',
                  subtitle: '预览入场转场、双立绘、技能、药水、撤离与自由行动判定',
                  onTap: () => _openPreview(actions.previewBattle),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '时间跳转',
                  subtitle: '跨日 / 跨时段的转场页面',
                  onTap: () => _openPreview(actions.previewTimeSkip),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '终章转场',
                  subtitle: '进入结局前的黑屏提示',
                  onTap: () => _openPreview(actions.previewEndingIntro),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '结局页面',
                  subtitle: '最终结局、共同记忆与命运轨迹',
                  onTap: () => _openPreview(actions.previewEnding),
                ),
                _DeveloperPreviewDivider(), // <--- 新增这根分割线
                _DeveloperPreviewRow(       // <--- 新增这个预览按钮
                  title: '背景过渡',
                  subtitle: '测试场景图片更换时的无缝淡入效果',
                  onTap: () => _openPreview(actions.previewImageTransition),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ],
          const SizedBox(height: 10),
          _DeveloperFoldHeader(
            title: '正文 / 样式',
            subtitle: '旁白正则标记渲染预览',
            expanded: _expandedDeveloperSection == 'text',
            onTap: () => _toggleDeveloperSection('text'),
          ),
          if (_expandedDeveloperSection == 'text') ...<Widget>[
          const _DeveloperSectionTitle(
            title: '正文样式',
            subtitle: '查看旁白层各种正则标记的渲染效果，不影响角色对白',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _DeveloperPreviewRow(
                  title: '正则样式预览',
                  subtitle: '（）* 【】 [] "" 全部标记效果一次看全',
                  onTap: () => _openPreview(actions.previewNarrationStyles),
                ),
              ],
            ),
          ),
          ],
        ],
      ),
    );
  }
}

class _DeveloperFoldHeader extends StatelessWidget {
  const _DeveloperFoldHeader({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = expanded
        ? _novelDrawerAccent.withOpacity(.34)
        : Colors.white.withOpacity(.085);
    final backgroundColor = expanded
        ? _novelDrawerAccent.withOpacity(.055)
        : Colors.white.withOpacity(.025);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: expanded
                            ? _novelDrawerAccent
                            : AppColors.textOnDark,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: expanded
                      ? _novelDrawerAccent
                      : AppColors.textOnDarkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeveloperSectionTitle extends StatelessWidget {
  const _DeveloperSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textOnDark,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _DeveloperChoiceChip extends StatelessWidget {
  const _DeveloperChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? _novelDrawerAccent.withOpacity(.12)
                : Colors.white.withOpacity(.025),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? _novelDrawerAccent.withOpacity(.42)
                  : Colors.white.withOpacity(.07),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _novelDrawerAccent : AppColors.textOnDarkMuted,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeveloperPreviewDivider extends StatelessWidget {
  const _DeveloperPreviewDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(.10));
  }
}

class _DeveloperPreviewRow extends StatelessWidget {
  const _DeveloperPreviewRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.textOnDarkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

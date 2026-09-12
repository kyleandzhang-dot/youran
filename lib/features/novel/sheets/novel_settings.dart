part of '../novel_sheets.dart';

// ============================================================================
// 偏好设置页
// 页面入口 / 对外入口：
//   - showNovelSettingsSheet(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

const Color _novelDrawerAccent = NovelPalette.accent;

Future<void> showNovelSettingsSheet(
  BuildContext context,
  NovelGameController controller, {
  required bool immersiveMode,
  required Future<void> Function(bool immersiveMode) onReadingModeChanged,
  bool isAdmin = false,
  NovelDeveloperPreviewActions? developerPreview,
}) async {
  final compactLandscape = NovelViewportMetrics.of(context).shortWide;
  final panel = _SettingsPanel(
    controller: controller,
    immersiveMode: immersiveMode,
    onReadingModeChanged: onReadingModeChanged,
    isAdmin: isAdmin,
    developerPreview: developerPreview,
  );

  // 竖屏沿用全局抽屉；横屏单独使用和左侧 GameDrawer 接近的窄侧栏。
  if (!compactLandscape) {
    await _showNovelEndDrawer<void>(context, child: panel);
    return;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭偏好设置',
    barrierColor: Colors.black.withOpacity(.56),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      final size = MediaQuery.sizeOf(dialogContext);
      final drawerWidth = (size.width * .40).clamp(286.0, 320.0).toDouble();
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            left: false,
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF171717).withOpacity(.96),
                  border: Border(
                    left: BorderSide(color: Colors.white.withOpacity(.055)),
                  ),
                ),
                child: panel,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _SettingsDrawerScaffold extends StatelessWidget {
  const _SettingsDrawerScaffold({
    required this.title,
    required this.child,
    this.onBack,
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    final buttonSize = compactLandscape ? 28.0 : 32.0;

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            onBack == null ? (compactLandscape ? 12 : 18) : (compactLandscape ? 8 : 12),
            compactLandscape ? 7 : 14,
            compactLandscape ? 8 : 12,
            compactLandscape ? 7 : 12,
          ),
          child: Row(
            children: <Widget>[
              if (onBack != null) ...<Widget>[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: buttonSize,
                      height: buttonSize,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: compactLandscape ? 11 : 13,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compactLandscape ? 2 : 4),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: compactLandscape ? 14.5 : 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: buttonSize,
                    height: buttonSize,
                    child: Icon(
                      Icons.close_rounded,
                      size: compactLandscape ? 15 : 18,
                      color: AppColors.textOnDarkMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withOpacity(compactLandscape ? .08 : .12),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.controller,
    required this.immersiveMode,
    required this.onReadingModeChanged,
    required this.isAdmin,
    this.developerPreview,
  });

  final NovelGameController controller;
  final bool immersiveMode;
  final Future<void> Function(bool immersiveMode) onReadingModeChanged;
  final bool isAdmin;
  final NovelDeveloperPreviewActions? developerPreview;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

enum _LandscapeSettingsSection { visual, text, engine, reading }

class _SettingsPanelState extends State<_SettingsPanel> {
  NovelGameController get controller => widget.controller;
  bool _showDeveloperTools = false;
  late bool _immersiveMode;
  _LandscapeSettingsSection _landscapeSection = _LandscapeSettingsSection.visual;

  @override
  void initState() {
    super.initState();
    _immersiveMode = widget.immersiveMode;
  }

  Future<void> _setReadingMode(bool immersiveMode) async {
    if (_immersiveMode == immersiveMode) return;
    setState(() => _immersiveMode = immersiveMode);
    await widget.onReadingModeChanged(immersiveMode);
  }

  String _modelLabel() {
    if (controller.currentNovelModel.isEmpty) return '自动选择';
    for (final model in controller.availableModels) {
      if (model.id == controller.currentNovelModel) return model.name;
    }
    return controller.currentNovelModel.split('/').last;
  }


  Widget _buildLandscapeSettings(NovelDeveloperPreviewActions? developerPreview) {
    return _SettingsDrawerScaffold(
      title: '偏好设置',
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
            child: Row(
              children: <Widget>[
                _landscapeTab('画面', Icons.palette_outlined, _LandscapeSettingsSection.visual),
                const SizedBox(width: 5),
                _landscapeTab('文字', Icons.text_fields_rounded, _LandscapeSettingsSection.text),
                const SizedBox(width: 5),
                _landscapeTab('声音', Icons.tune_rounded, _LandscapeSettingsSection.engine),
                const SizedBox(width: 5),
                _landscapeTab('阅读', Icons.auto_stories_outlined, _LandscapeSettingsSection.reading),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(.07)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _LandscapeSettingsViewport(
                key: ValueKey<_LandscapeSettingsSection>(_landscapeSection),
                child: _buildLandscapeSectionContent(developerPreview),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscapeTab(
    String label,
    IconData icon,
    _LandscapeSettingsSection section,
  ) {
    final selected = _landscapeSection == section;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _landscapeSection = section),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white.withOpacity(.045) : Colors.transparent,
              border: Border.all(
                color: selected ? Colors.white.withOpacity(.28) : Colors.transparent,
                width: .8,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 13,
                  color: selected ? Colors.white : AppColors.textOnDarkMuted,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textOnDarkMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeSectionContent(
    NovelDeveloperPreviewActions? developerPreview,
  ) {
    switch (_landscapeSection) {
      case _LandscapeSettingsSection.visual:
        return _buildLandscapeVisualSection();
      case _LandscapeSettingsSection.text:
        return _buildLandscapeTextSection();
      case _LandscapeSettingsSection.engine:
        return _buildLandscapeEngineSection();
      case _LandscapeSettingsSection.reading:
        return _buildLandscapeReadingSection(developerPreview);
    }
  }

  Widget _buildLandscapeVisualSection() {
    final settings = controller.settings;

    Widget choice({
      required String label,
      required IconData icon,
      required bool selected,
      VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withOpacity(.045)
                  : Colors.white.withOpacity(.012),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? Colors.white.withOpacity(.30)
                    : Colors.white.withOpacity(.075),
                width: selected ? .9 : .65,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 15,
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textOnDarkMuted.withOpacity(.64),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textOnDark
                          : AppColors.textOnDarkMuted.withOpacity(.76),
                      fontSize: 10.4,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_rounded
                      : (enabled
                          ? Icons.chevron_right_rounded
                          : Icons.lock_outline_rounded),
                  size: 12,
                  color: selected
                      ? Colors.white.withOpacity(.88)
                      : AppColors.textOnDarkMuted.withOpacity(.50),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget pair(Widget left, Widget right) {
      return Row(
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: 7),
          Expanded(child: right),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _CleanSettingsHeader(
          icon: Icons.palette_outlined,
          title: '画面风格',
          subtitle: '预览当前效果并选择画风',
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset(
                  'assets/images/bg-anime.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: Colors.white.withOpacity(.025),
                    child: const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: AppColors.textOnDarkMuted,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withOpacity(.08),
                        Colors.black.withOpacity(.66),
                      ],
                      stops: const <double>[0, .55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '动漫',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.34),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withOpacity(.14),
                            width: .7,
                          ),
                        ),
                        child: const Text(
                          '当前',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        pair(
          choice(
            label: '动漫',
            icon: Icons.auto_awesome_outlined,
            selected: true,
            onTap: () => settings.setArtStyle('anime'),
          ),
          choice(
            label: '3D',
            icon: Icons.view_in_ar_outlined,
            selected: false,
          ),
        ),
        const SizedBox(height: 7),
        pair(
          choice(
            label: '写实',
            icon: Icons.camera_alt_outlined,
            selected: false,
          ),
          choice(
            label: '梦幻',
            icon: Icons.blur_on_rounded,
            selected: false,
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeTextSection() {
    final settings = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _CleanSettingsHeader(
          icon: Icons.text_fields_rounded,
          title: '文字',
          subtitle: '字号、字体与显示速度',
        ),
        const SizedBox(height: 8),
        _CleanSettingsCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '字体大小',
                      style: TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${settings.fontSize.clamp(8.0, 20.0).round()}',
                      style: TextStyle(
                        color: AppColors.textOnDark.withOpacity(.88),
                        fontSize: 9.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: <Widget>[
                  const Text('A', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 9.5)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _novelDrawerAccent,
                        inactiveTrackColor: Colors.white.withOpacity(.08),
                        thumbColor: _novelDrawerAccent,
                        overlayColor: _novelDrawerAccent.withOpacity(.08),
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                      ),
                      child: Slider(
                        value: settings.fontSize.clamp(8.0, 20.0).toDouble(),
                        min: 8,
                        max: 20,
                        divisions: 12,
                        onChanged: settings.setFontSize,
                      ),
                    ),
                  ),
                  const Text('A', style: TextStyle(color: AppColors.textOnDark, fontSize: 15)),
                ],
              ),
              Divider(height: 12, color: Colors.white.withOpacity(.14)),
              Row(
                children: <Widget>[
                  Expanded(child: _CleanSettingChoice(label: '黑体', selected: settings.fontKey == 'font-hei', onTap: () => settings.setFont('font-hei'))),
                  const SizedBox(width: 4),
                  Expanded(child: _CleanSettingChoice(label: 'MiSans', fontFamily: 'NovelMiSans', selected: settings.fontKey == 'font-misans', onTap: () => settings.setFont('font-misans'))),
                  const SizedBox(width: 4),
                  Expanded(child: _CleanSettingChoice(label: '宋体', fontFamily: 'WenJinMinchoP0', selected: settings.fontKey == 'font-song', onTap: () => settings.setFont('font-song'))),
                  const SizedBox(width: 4),
                  Expanded(child: _CleanSettingChoice(label: '文楷', fontFamily: 'LXGWWenKaiGBScreen', selected: settings.fontKey == 'font-wenkai', onTap: () => settings.setFont('font-wenkai'))),
                ],
              ),
              Divider(height: 12, color: Colors.white.withOpacity(.14)),
              Row(
                children: <Widget>[
                  const Text(
                    '文字速度',
                    style: TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    settings.textSpeedLabel,
                    style: TextStyle(
                      color: AppColors.textOnDark.withOpacity(.88),
                      fontSize: 9.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: <Widget>[
                  for (final option in const <(String, String)>[
                    ('instant', '即时'),
                    ('fast', '快速'),
                    ('standard', '标准'),
                    ('slow', '慢速'),
                  ]) ...<Widget>[
                    Expanded(
                      child: _CleanSettingChoice(
                        label: option.$2,
                        selected: settings.textSpeedKey == option.$1,
                        onTap: () => settings.setTextSpeed(option.$1),
                      ),
                    ),
                    if (option.$1 != 'slow') const SizedBox(width: 4),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeEngineSection() {
    final settings = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _CleanSettingsHeader(
          icon: Icons.tune_rounded,
          title: '声音与引擎',
          subtitle: '常用开关与生成模型',
        ),
        const SizedBox(height: 8),
        _CleanSettingsCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _CleanSettingsRow(
                icon: Icons.music_note_rounded,
                title: '背景音乐',
                subtitle: controller.bgm.enabled ? '音乐播放中' : '音乐已暂停',
                trailing: Switch.adaptive(
                  value: controller.bgm.enabled,
                  activeColor: _novelDrawerAccent,
                  onChanged: (value) async {
                    await controller.bgm.setEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              Divider(height: 1, color: Colors.white.withOpacity(.14)),
              _CleanSettingsRow(
                icon: Icons.keyboard_alt_outlined,
                title: '打字音效',
                subtitle: settings.typingSoundEnabled ? '逐字播放轻微打字声' : '逐字显示保持静音',
                trailing: Switch.adaptive(
                  value: settings.typingSoundEnabled,
                  activeColor: _novelDrawerAccent,
                  onChanged: (value) async {
                    await settings.setTypingSoundEnabled(value);
                    if (!value) await controller.bgm.stopTypingSound();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              Divider(height: 1, color: Colors.white.withOpacity(.14)),
              _CleanSettingsRow(
                icon: Icons.cloud_outlined,
                title: '天气特效',
                subtitle: settings.weatherEffectsEnabled ? '天气与环境音已开启' : '天气与环境音已关闭',
                trailing: Switch.adaptive(
                  value: settings.weatherEffectsEnabled,
                  activeColor: _novelDrawerAccent,
                  onChanged: (value) async {
                    await settings.setWeatherEffectsEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              Divider(height: 1, color: Colors.white.withOpacity(.14)),
              PopupMenuButton<String>(
                tooltip: '选择模型',
                color: const Color(0xFF191B1B),
                onSelected: controller.isChangingModel ? null : (value) => controller.setNovelModel(value),
                itemBuilder: (context) => controller.availableModels
                    .map((model) => PopupMenuItem<String>(
                          value: model.id,
                          child: Text(
                            model.name,
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 10.5,
                            ),
                          ),
                        ))
                    .toList(),
                child: _CleanSettingsRow(
                  icon: Icons.hub_outlined,
                  title: '生成引擎模型',
                  subtitle: _modelLabel(),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textOnDarkMuted,
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeReadingSection(
    NovelDeveloperPreviewActions? developerPreview,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _CleanSettingsHeader(
          icon: Icons.auto_stories_outlined,
          title: '阅读模式',
          subtitle: '标准阅读或沉浸展开场景',
        ),
        const SizedBox(height: 8),
        _ReadingModeChoice(
          label: '标准',
          caption: '竖屏 · 专注阅读',
          immersive: false,
          selected: !_immersiveMode,
          compact: true,
          onTap: () => unawaited(_setReadingMode(false)),
        ),
        const SizedBox(height: 7),
        _ReadingModeChoice(
          label: '沉浸',
          caption: '横屏 · 展开场景',
          immersive: true,
          selected: _immersiveMode,
          compact: true,
          onTap: () => unawaited(_setReadingMode(true)),
        ),
        if (widget.isAdmin && developerPreview != null) ...<Widget>[
          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.white.withOpacity(.10)),
          const SizedBox(height: 7),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _showDeveloperTools = true),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.science_outlined, size: 14, color: AppColors.textOnDarkMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '开发者测试',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 15, color: AppColors.textOnDarkMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[controller, controller.settings]),
      builder: (context, _) {
        final settings = controller.settings;
        final developerPreview = widget.developerPreview;
        final compactLandscape = NovelViewportMetrics.of(context).shortWide;
        if (_showDeveloperTools &&
            widget.isAdmin &&
            developerPreview != null) {
          return _DeveloperToolsPanel(
            actions: developerPreview,
            onBack: () => setState(() => _showDeveloperTools = false),
          );
        }
        if (settings.artStyle != 'anime') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.settings.artStyle != 'anime') {
              controller.settings.setArtStyle('anime');
            }
          });
        }
        if (compactLandscape) {
          return _buildLandscapeSettings(developerPreview);
        }
        return _SettingsDrawerScaffold(
          title: '偏好设置',
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compactLandscape ? 14 : 18,
              compactLandscape ? 2 : 6,
              compactLandscape ? 14 : 18,
              compactLandscape ? 14 : 28,
            ),
            children: <Widget>[
              const _CleanSettingsHeader(
                icon: Icons.palette_outlined,
                title: '画面风格',
                subtitle: '当前暂时锁定为动漫风格，其他画风稍后开放',
              ),
              SizedBox(height: compactLandscape ? 6 : 12),
              SizedBox(
                height: compactLandscape ? 62 : 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: <Widget>[
                    _ArtStyleCard(
                      label: '动漫',
                      asset: 'assets/images/bg-anime.webp',
                      selected: true,
                      onTap: () => settings.setArtStyle('anime'),
                    ),
                    SizedBox(width: compactLandscape ? 6 : 10),
                    _ArtStyleCard(
                      label: '3D',
                      asset: 'assets/images/bg-3d.webp',
                      selected: false,
                      onTap: null,
                      lockedLabel: '暂未开放',
                    ),
                    SizedBox(width: compactLandscape ? 6 : 10),
                    _ArtStyleCard(
                      label: '写实',
                      asset: 'assets/images/bg-realistic.webp',
                      selected: false,
                      onTap: null,
                      lockedLabel: '暂未开放',
                    ),
                    SizedBox(width: compactLandscape ? 6 : 10),
                    _ArtStyleCard(
                      label: '梦幻',
                      asset: 'assets/images/bg-painterly.webp',
                      selected: false,
                      onTap: null,
                      lockedLabel: '暂未开放',
                    ),
                  ],
                ),
              ),
              SizedBox(height: compactLandscape ? 12 : 24),
              const _CleanSettingsHeader(
                icon: Icons.text_fields_rounded,
                title: '文字',
                subtitle: '只调整阅读本身，不再混入背景主题设置',
              ),
              SizedBox(height: compactLandscape ? 6 : 10),
              _CleanSettingsCard(
                padding: EdgeInsets.symmetric(vertical: compactLandscape ? 8 : 13),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '字体大小',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: compactLandscape ? 11 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${settings.fontSize.clamp(8.0, 20.0).round()}',
                          style: TextStyle(
                            color: AppColors.textOnDark.withOpacity(.88),
                            fontSize: compactLandscape ? 9.8 : 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Text('A', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: compactLandscape ? 9.5 : 11)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _novelDrawerAccent,
                              inactiveTrackColor: Colors.white.withOpacity(.08),
                              thumbColor: _novelDrawerAccent,
                              overlayColor: _novelDrawerAccent.withOpacity(.08),
                              trackHeight: 2,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: compactLandscape ? 4.5 : 5.5,
                              ),
                            ),
                            child: Slider(
                              value: settings.fontSize.clamp(8.0, 20.0).toDouble(),
                              min: 8,
                              max: 20,
                              divisions: 12,
                              onChanged: settings.setFontSize,
                            ),
                          ),
                        ),
                        Text('A', style: TextStyle(color: AppColors.textOnDark, fontSize: compactLandscape ? 15 : 18)),
                      ],
                    ),
                    Divider(height: compactLandscape ? 12 : 18, color: Colors.white.withOpacity(.14)),
                    // 四种字体属于同一级别的单选项，一行四等分展示，
                    // 避免字体设置占两行把整个设置页纵向拉长。
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _CleanSettingChoice(
                            label: '黑体',
                            selected: settings.fontKey == 'font-hei',
                            onTap: () => settings.setFont('font-hei'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CleanSettingChoice(
                            label: 'MiSans',
                            fontFamily: 'NovelMiSans',
                            selected: settings.fontKey == 'font-misans',
                            onTap: () => settings.setFont('font-misans'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CleanSettingChoice(
                            label: '宋体',
                            fontFamily: 'WenJinMinchoP0',
                            selected: settings.fontKey == 'font-song',
                            onTap: () => settings.setFont('font-song'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CleanSettingChoice(
                            label: '文楷',
                            fontFamily: 'LXGWWenKaiGBScreen',
                            selected: settings.fontKey == 'font-wenkai',
                            onTap: () => settings.setFont('font-wenkai'),
                          ),
                        ),
                      ],
                    ),
                    Divider(height: compactLandscape ? 12 : 18, color: Colors.white.withOpacity(.14)),
                    Row(
                      children: <Widget>[
                        Text(
                          '文字速度',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: compactLandscape ? 11 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          settings.textSpeedLabel,
                          style: TextStyle(
                            color: AppColors.textOnDark.withOpacity(.88),
                            fontSize: compactLandscape ? 9.8 : 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compactLandscape ? 3 : 6),
                    Row(
                      children: <Widget>[
                        for (final option in const <(String, String)>[
                          ('instant', '即时'),
                          ('fast', '快速'),
                          ('standard', '标准'),
                          ('slow', '慢速'),
                        ]) ...<Widget>[
                          Expanded(
                            child: _CleanSettingChoice(
                              label: option.$2,
                              selected: settings.textSpeedKey == option.$1,
                              onTap: () => settings.setTextSpeed(option.$1),
                            ),
                          ),
                          if (option.$1 != 'slow') const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: compactLandscape ? 12 : 24),
              const _CleanSettingsHeader(
                icon: Icons.tune_rounded,
                title: '声音与引擎',
                subtitle: '游戏过程中真正需要调整的选项',
              ),
              SizedBox(height: compactLandscape ? 6 : 10),
              _CleanSettingsCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _CleanSettingsRow(
                      icon: Icons.music_note_rounded,
                      title: '背景音乐',
                      subtitle: controller.bgm.enabled ? '音乐播放中' : '音乐已暂停',
                      trailing: Switch.adaptive(
                        value: controller.bgm.enabled,
                        activeColor: _novelDrawerAccent,
                        onChanged: (value) async {
                          await controller.bgm.setEnabled(value);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(.14)),
                    _CleanSettingsRow(
                      icon: Icons.keyboard_alt_outlined,
                      title: '打字音效',
                      subtitle: settings.typingSoundEnabled
                          ? '逐字显示时播放轻微打字声'
                          : '逐字显示保持静音',
                      trailing: Switch.adaptive(
                        value: settings.typingSoundEnabled,
                        activeColor: _novelDrawerAccent,
                        onChanged: (value) async {
                          await settings.setTypingSoundEnabled(value);
                          if (!value) {
                            await controller.bgm.stopTypingSound();
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(.14)),
                    _CleanSettingsRow(
                      icon: Icons.cloud_outlined,
                      title: '天气特效',
                      subtitle: settings.weatherEffectsEnabled
                          ? '天气画面与环境音已开启'
                          : '雨、雪、雷雨特效与环境音均已关闭',
                      trailing: Switch.adaptive(
                        value: settings.weatherEffectsEnabled,
                        activeColor: _novelDrawerAccent,
                        onChanged: (value) async {
                          await settings.setWeatherEffectsEnabled(value);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withOpacity(.14)),
                    PopupMenuButton<String>(
                      tooltip: '选择模型',
                      color: const Color(0xFF191B1B),
                      onSelected: controller.isChangingModel ? null : (value) => controller.setNovelModel(value),
                      itemBuilder: (context) => controller.availableModels
                          .map((model) => PopupMenuItem<String>(
                                value: model.id,
                                child: Text(
                                  model.name,
                                  style: TextStyle(
                                    color: AppColors.textOnDark,
                                    fontSize: compactLandscape ? 10.5 : 12.5,
                                  ),
                                ),
                              ))
                          .toList(),
                      child: _CleanSettingsRow(
                        icon: Icons.hub_outlined,
                        title: '生成引擎模型',
                        subtitle: _modelLabel(),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textOnDarkMuted,
                          size: compactLandscape ? 15 : 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compactLandscape ? 12 : 24),
              const _CleanSettingsHeader(
                icon: Icons.auto_stories_outlined,
                title: '阅读模式',
                subtitle: '标准专注阅读，沉浸展开场景',
              ),
              SizedBox(height: compactLandscape ? 6 : 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackChoices = constraints.maxWidth < 220;
                  final standard = _ReadingModeChoice(
                    label: '标准',
                    caption: '竖屏 · 专注阅读',
                    immersive: false,
                    selected: !_immersiveMode,
                    compact: compactLandscape,
                    onTap: () => unawaited(_setReadingMode(false)),
                  );
                  final immersive = _ReadingModeChoice(
                    label: '沉浸',
                    caption: '横屏 · 展开场景',
                    immersive: true,
                    selected: _immersiveMode,
                    compact: compactLandscape,
                    onTap: () => unawaited(_setReadingMode(true)),
                  );

                  if (stackChoices) {
                    return Column(
                      children: <Widget>[
                        standard,
                        SizedBox(height: compactLandscape ? 5 : 7),
                        immersive,
                      ],
                    );
                  }

                  return Row(
                    children: <Widget>[
                      Expanded(child: standard),
                      SizedBox(width: compactLandscape ? 6 : 8),
                      Expanded(child: immersive),
                    ],
                  );
                },
              ),
              if (widget.isAdmin && developerPreview != null) ...<Widget>[
                SizedBox(height: compactLandscape ? 12 : 26),
                Divider(height: 1, color: Colors.white.withOpacity(.10)),
                SizedBox(height: compactLandscape ? 6 : 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _showDeveloperTools = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: compactLandscape ? 6 : 10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.science_outlined,
                            size: compactLandscape ? 14 : 17,
                            color: AppColors.textOnDarkMuted,
                          ),
                          SizedBox(width: compactLandscape ? 7 : 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '开发者测试',
                                  style: TextStyle(
                                    color: AppColors.textOnDark,
                                    fontSize: compactLandscape ? 10.5 : 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: compactLandscape ? 2 : 3),
                                Text(
                                  '天气、时间与关键页面美术预览',
                                  style: TextStyle(
                                    color: AppColors.textOnDarkMuted,
                                    fontSize: compactLandscape ? 8.5 : 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textOnDarkMuted,
                            size: compactLandscape ? 15 : 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
class _LandscapeSettingsViewport extends StatelessWidget {
  const _LandscapeSettingsViewport({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 252),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArtStyleCard extends StatelessWidget {
  const _ArtStyleCard({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
    this.lockedLabel,
    this.fullWidth = false,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback? onTap;
  final String? lockedLabel;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    final disabled = onTap == null && !selected;
    final cardWidth = fullWidth ? double.infinity : (compactLandscape ? 82.0 : 108.0);
    final aspectRatio = fullWidth
        ? 16 / 9
        : (compactLandscape ? 82 / 58 : 108 / 82);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(fullWidth ? 9 : 0),
        child: Align(
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: cardWidth,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(fullWidth ? 9 : 0),
              border: Border.all(
                color: selected
                    ? Colors.white.withOpacity(.35)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  NovelArtwork(
                    assetCandidates: <String>[asset],
                    fit: BoxFit.contain,
                    fallbackIcon: Icons.image_outlined,
                    fallbackText: label,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          Colors.black.withOpacity(.10),
                          Colors.black.withOpacity(.72),
                        ],
                        stops: const <double>[0, .50, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: compactLandscape ? 6 : 8,
                    bottom: compactLandscape ? 4 : 7,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: disabled
                            ? Colors.white.withOpacity(.72)
                            : Colors.white,
                        fontSize: compactLandscape ? 9.6 : 11.5,
                        fontWeight: FontWeight.w700,
                        shadows: const <Shadow>[
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  if (disabled)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.32),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            margin: EdgeInsets.only(
                              top: compactLandscape ? 4 : 7,
                              right: compactLandscape ? 4 : 7,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: compactLandscape ? 5 : 6,
                              vertical: compactLandscape ? 2 : 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.42),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white.withOpacity(.10),
                              ),
                            ),
                            child: Text(
                              lockedLabel ?? '已锁定',
                              style: TextStyle(
                                color: Colors.white.withOpacity(.80),
                                fontSize: compactLandscape ? 7.8 : 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      right: compactLandscape ? 4 : 7,
                      top: compactLandscape ? 4 : 7,
                      child: Icon(
                        Icons.check_rounded,
                        size: compactLandscape ? 11 : 13,
                        color: Colors.white.withOpacity(.92),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingModeChoice extends StatelessWidget {
  const _ReadingModeChoice({
    required this.label,
    required this.caption,
    required this.immersive,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool immersive;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedBorder = Colors.white.withOpacity(.30);
    final idleBorder = Colors.white.withOpacity(.08);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: Colors.white.withOpacity(.045),
        highlightColor: Colors.white.withOpacity(.02),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: compact ? 48 : 56,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withOpacity(.050)
                : Colors.white.withOpacity(.012),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? selectedBorder : idleBorder,
              width: selected ? .9 : .65,
            ),
          ),
          child: Row(
            children: <Widget>[
              _ReadingModeGlyph(
                immersive: immersive,
                selected: selected,
                compact: compact,
              ),
              SizedBox(width: compact ? 9 : 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textOnDark
                            : AppColors.textOnDark.withOpacity(.72),
                        fontSize: compact ? 11.2 : 12.8,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: .2,
                      ),
                    ),
                    SizedBox(height: compact ? 1 : 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textOnDarkMuted.withOpacity(
                          selected ? .78 : .52,
                        ),
                        fontSize: compact ? 8.0 : 9.2,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...<Widget>[
                SizedBox(width: compact ? 5 : 7),
                Icon(
                  Icons.check_rounded,
                  size: compact ? 12 : 14,
                  color: Colors.white.withOpacity(.82),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingModeGlyph extends StatelessWidget {
  const _ReadingModeGlyph({
    required this.immersive,
    required this.selected,
    required this.compact,
  });

  final bool immersive;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = immersive ? (compact ? 25.0 : 28.0) : (compact ? 17.0 : 19.0);
    final height = immersive ? (compact ? 15.0 : 17.0) : (compact ? 24.0 : 27.0);
    final stroke = selected
        ? Colors.white.withOpacity(.86)
        : Colors.white.withOpacity(.34);

    return SizedBox(
      width: compact ? 28 : 32,
      height: compact ? 30 : 34,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(immersive ? 4 : 5),
            border: Border.all(color: stroke, width: 1),
          ),
          child: Center(
            child: Container(
              width: immersive ? 6 : 3,
              height: 1,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(.64)
                    : Colors.white.withOpacity(.22),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CleanSettingsHeader extends StatelessWidget {
  const _CleanSettingsHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(top: compactLandscape ? 0 : 1),
          child: Icon(
            icon,
            size: compactLandscape ? 13.5 : 16,
            color: AppColors.textOnDarkMuted.withOpacity(.88),
          ),
        ),
        SizedBox(width: compactLandscape ? 7 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: compactLandscape ? 11.5 : 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compactLandscape ? 2 : 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textOnDarkMuted.withOpacity(.86),
                  fontSize: compactLandscape ? 9 : 10.5,
                  height: compactLandscape ? 1.25 : 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CleanSettingsCard extends StatelessWidget {
  const _CleanSettingsCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 13),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(.12),
            width: 1,
          ),
          bottom: BorderSide(
            color: Colors.white.withOpacity(.12),
            width: 1,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _CleanSettingChoice extends StatelessWidget {
  const _CleanSettingChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fontFamily,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: compactLandscape ? 30 : 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Colors.white.withOpacity(.35)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? AppColors.textOnDark
                  : AppColors.textOnDarkMuted,
              fontFamily: fontFamily,
              fontSize: compactLandscape ? 9.8 : 11.3,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CleanSettingsRow extends StatelessWidget {
  const _CleanSettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    return SizedBox(
      height: compactLandscape ? 48 : 60,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compactLandscape ? 9 : 13,
          0,
          compactLandscape ? 7 : 10,
          0,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: compactLandscape ? 14 : 17,
              color: AppColors.textOnDarkMuted.withOpacity(.82),
            ),
            SizedBox(width: compactLandscape ? 8 : 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: compactLandscape ? 10.5 : 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: compactLandscape ? 2 : 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: compactLandscape ? 8.8 : 10.5,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compactLandscape ? 5 : 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

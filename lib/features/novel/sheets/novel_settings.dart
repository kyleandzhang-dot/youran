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
  bool isAdmin = false,
  NovelDeveloperPreviewActions? developerPreview,
}) async {
  await _showNovelEndDrawer<void>(
    context,
    child: _SettingsPanel(
      controller: controller,
      isAdmin: isAdmin,
      developerPreview: developerPreview,
    ),
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
    required this.isAdmin,
    this.developerPreview,
  });

  final NovelGameController controller;
  final bool isAdmin;
  final NovelDeveloperPreviewActions? developerPreview;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  NovelGameController get controller => widget.controller;
  bool _showDeveloperTools = false;

  String _modelLabel() {
    if (controller.currentNovelModel.isEmpty) return '自动选择';
    for (final model in controller.availableModels) {
      if (model.id == controller.currentNovelModel) return model.name;
    }
    return controller.currentNovelModel.split('/').last;
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
                          '${settings.fontSize.round()}',
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
                              value: settings.fontSize,
                              min: 12,
                              max: 24,
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
class _ArtStyleCard extends StatelessWidget {
  const _ArtStyleCard({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
    this.lockedLabel,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback? onTap;
  final String? lockedLabel;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = NovelViewportMetrics.of(context).shortWide;
    final disabled = onTap == null && !selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: compactLandscape ? 82 : 108,
          height: compactLandscape ? 58 : 82,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(
              color: selected
                  ? Colors.white.withOpacity(.35)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              NovelArtwork(
                assetCandidates: <String>[asset],
                fit: BoxFit.cover,
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
                    color: disabled ? Colors.white.withOpacity(.72) : Colors.white,
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
                          border: Border.all(color: Colors.white.withOpacity(.10)),
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

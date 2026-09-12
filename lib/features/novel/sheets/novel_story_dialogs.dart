part of '../novel_sheets.dart';

// ============================================================================
// 故事流程弹窗 / 转场页
// 页面入口 / 对外入口：
//   - showNovelCharacterSetupDialog(...)
//   - showNovelOpeningDialog(...)
//   - showNovelFateRevertDialog(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

Future<bool> showNovelCharacterSetupDialog(
  BuildContext context,
  NovelGameController controller, {
  bool previewOnly = false,
}) async {
  final host = controller.protagonist;
  final nameController = TextEditingController(text: host?.name ?? '');
  final persona = host?.persona ?? const <String, dynamic>{};
  final background = stringValue(
    persona['background'] ?? controller.scenario?.description,
    '暂无背景信息。你将从这里开始书写自己的故事。',
  );
  final age = stringValue(persona['age']);
  final gender = host?.gender.trim().isNotEmpty == true
      ? host!.gender.trim()
      : stringValue(persona['gender'], '保密');
  final appearance = stringValue(
    persona['portrait_prompt'] ?? persona['appearance'] ?? persona['identity'],
  );

  final normalizedGender = gender.trim().toLowerCase();
  final isFemale = gender.contains('女') ||
      normalizedGender == 'female' ||
      normalizedGender == 'f' ||
      normalizedGender.contains('female');
  final setupAvatarAsset = isFemale
      ? 'assets/images/female.webp'
      : 'assets/images/male.webp';

  var submitting = false;

  final started = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '确认角色',
    barrierColor: Colors.black.withOpacity(.34),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 410),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.075),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: Colors.white.withOpacity(.11),
                          width: .8,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(.16),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.055),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(.10),
                                    width: .8,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: NovelArtwork(
                                  // 首次确认角色时不使用远程头像：
                                  // 始终按剧本主角性别显示本地 male.webp / female.webp。
                                  url: '',
                                  assetCandidates: <String>[setupAvatarAsset],
                                  fit: BoxFit.cover,
                                  fallbackText: host?.name ?? '你',
                                  fallbackIcon: Icons.person_outline_rounded,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text(
                                      '确认角色',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .2,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      gender.trim().isEmpty
                                          ? '确认姓名后进入故事'
                                          : '${gender.trim()} · 确认姓名后进入故事',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.52),
                                        fontSize: 10.5,
                                        height: 1.3,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: '关闭',
                                onPressed: submitting
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(false),
                                icon: const Icon(Icons.close_rounded),
                                color: Colors.white.withOpacity(.60),
                                disabledColor: Colors.white.withOpacity(.24),
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            '姓名',
                            style: TextStyle(
                              color: Color(0x8CFFFFFF),
                              fontSize: 10.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            maxLength: 10,
                            enabled: !submitting,
                            cursorColor: _archiveThemeGreen,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: host?.name.isNotEmpty == true
                                  ? host!.name
                                  : '输入姓名',
                              hintStyle: const TextStyle(
                                color: Color(0x47FFFFFF),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(.045),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.08),
                                  width: .8,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                  color: _archiveThemeGreen.withOpacity(.72),
                                  width: .9,
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.05),
                                  width: .8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            '背景',
                            style: TextStyle(
                              color: Color(0x8CFFFFFF),
                              fontSize: 10.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 148),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.035),
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: Colors.white.withOpacity(.07),
                                width: .8,
                              ),
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                background,
                                style: const TextStyle(
                                  color: Color(0xB8FFFFFF),
                                  fontSize: 11.7,
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _archiveThemeGreen,
                                foregroundColor: NovelPalette.accentDark,
                                disabledBackgroundColor:
                                    _archiveThemeGreen.withOpacity(.45),
                                elevation: 0,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              onPressed: submitting
                                  ? null
                                  : () async {
                                      if (previewOnly) {
                                        Navigator.of(dialogContext).pop(false);
                                        return;
                                      }
                                      final name = nameController.text.trim();
                                      if (name.isEmpty) return;
                                      setDialogState(() => submitting = true);
                                      var completed = false;
                                      try {
                                        await controller.submitCharacterSetup(
                                          NovelCharacterSetupInput(
                                            name: name,
                                            gender: gender,
                                            age: int.tryParse(age),
                                            description: background,
                                            appearance: appearance,
                                          ),
                                        );
                                        if (!dialogContext.mounted) return;

                                        // 成功时 controller 会关闭角色设置并进入开场。
                                        // 只有确认状态已经切换成功才退出当前 Dialog，
                                        // 避免保存失败时错误关闭，也避免与开场 Dialog 抢 Navigator。
                                        if (!controller.showCharacterSetup &&
                                            controller.showOpening) {
                                          completed = true;
                                          Navigator.of(dialogContext).pop(true);
                                        }
                                      } finally {
                                        if (!completed && dialogContext.mounted) {
                                          setDialogState(() => submitting = false);
                                        }
                                      }
                                    },
                              child: submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: NovelPalette.accentDark,
                                      ),
                                    )
                                  : const Text(
                                      '进入故事',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .8,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .975, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  nameController.dispose();
  return started ?? false;
}

class _CharacterSetupMeta extends StatelessWidget {
  const _CharacterSetupMeta({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _archiveThemeGreen.withOpacity(.11),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _archiveAccent,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _IdentityTag extends StatelessWidget {
  const _IdentityTag({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(.065)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: NovelPalette.muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Future<bool> showNovelOpeningDialog(
  BuildContext context,
  NovelGameController controller, {
  bool previewOnly = false,
}) async {
  final openMenuRequested = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '故事开场',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 1200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _NovelOpeningExperience(
        controller: controller,
        previewOnly: previewOnly,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
        child: child,
      );
    },
  );
  return openMenuRequested ?? false;
}

class _NovelOpeningExperience extends StatefulWidget {
  const _NovelOpeningExperience({
    required this.controller,
    required this.previewOnly,
  });
  final NovelGameController controller;
  final bool previewOnly;

  @override
  State<_NovelOpeningExperience> createState() => _NovelOpeningExperienceState();
}

class _NovelOpeningExperienceState extends State<_NovelOpeningExperience>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _breatheController;
  late final Animation<double> _breathe;
  late final List<String> _paragraphs;
  int _visibleCount = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final source = widget.controller.openingText.trim().isEmpty
        ? '故事即将开始。'
        : widget.controller.openingText.trim();
    final cleanedSource = novelTextWithoutSymbolOnlyLines(source);
    _paragraphs = (cleanedSource.isEmpty ? '故事即将开始。' : cleanedSource)
        .split('\n')
        .where(novelTextHasReadableContent)
        .toList(growable: false);
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _breathe = Tween<double>(begin: .22, end: .80).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!mounted || _paragraphs.isEmpty) return;
      setState(() => _visibleCount = 1);
      _scrollToLatestParagraph(animated: false);
    });
  }

  bool get _finished =>
      _paragraphs.isNotEmpty && _visibleCount >= _paragraphs.length;

  void _scrollToLatestParagraph({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      if (target <= position.pixels + .5) return;

      if (!animated) {
        _scrollController.jumpTo(target);
        return;
      }

      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _requestWorldMenu() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(true);
  }

  void _advance() {
    if (_closing) return;
    if (!_finished) {
      setState(() => _visibleCount += 1);
      _scrollToLatestParagraph();
      return;
    }
    _closing = true;
    Navigator.of(context).pop(false);
    if (!widget.previewOnly) {
      unawaited(widget.controller.startNarrative());
    }
  }

  Widget _buildParagraphList({
    required double fontSize,
    required double lineHeight,
    required double paragraphGap,
    required double maxWidth,
  }) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(_visibleCount, (index) {
              final current = index == _visibleCount - 1;
              final targetOpacity = current ? .96 : .34;
              return TweenAnimationBuilder<double>(
                key: ValueKey<String>('opening-paragraph-$index'),
                tween: Tween<double>(begin: 0, end: targetOpacity),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  final revealProgress = targetOpacity <= 0
                      ? 1.0
                      : (value / targetOpacity)
                          .clamp(0.0, 1.0)
                          .toDouble();
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, (1 - revealProgress) * 8),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.only(bottom: paragraphGap),
                  child: Text(
                    _paragraphs[index],
                    textAlign: TextAlign.justify,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: widget.controller.settings.fontFamily,
                      fontSize: fontSize,
                      height: lineHeight,
                      letterSpacing: .7,
                      fontWeight:
                          current ? FontWeight.w500 : FontWeight.w400,
                      shadows: current
                          ? const <Shadow>[
                              Shadow(
                                color: Color(0x52000000),
                                blurRadius: 18,
                                offset: Offset(0, 4),
                              ),
                            ]
                          : const <Shadow>[],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueHint({required bool compact}) {
    if (_visibleCount <= 0) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _breathe,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _finished ? '轻触进入故事' : '轻触继续',
            style: TextStyle(
              color: Colors.white.withOpacity(.58),
              fontSize: compact ? 9.5 : 10.5,
              letterSpacing: compact ? 1.2 : 1.6,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Icon(
            Icons.chevron_right_rounded,
            size: compact ? 14 : 16,
            color: Colors.white.withOpacity(.42),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitOpening(Size size) {
    final compact = size.width < 560;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 28 : size.width * .14,
        34,
        compact ? 28 : size.width * .14,
        48,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '序章',
            style: TextStyle(
              color: NovelPalette.accent.withOpacity(.55),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const Spacer(flex: 3),
          Expanded(
            flex: 9,
            child: _buildParagraphList(
              fontSize: compact ? 15.5 : 17,
              lineHeight: 1.95,
              paragraphGap: 20,
              maxWidth: 680,
            ),
          ),
          const Spacer(flex: 1),
          Align(
            alignment: Alignment.center,
            child: _buildContinueHint(compact: false),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeOpening(Size size) {
    final short = size.height < 440;
    final veryShort = size.height < 360;
    final edge = short ? 22.0 : 36.0;
    final railWidth = veryShort ? 72.0 : (short ? 86.0 : 112.0);
    final gap = veryShort ? 14.0 : (short ? 22.0 : 34.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        edge,
        veryShort ? 12 : (short ? 16 : 26),
        edge,
        veryShort ? 10 : (short ? 14 : 22),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: railWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(height: veryShort ? 2 : 6),
                    Text(
                      '序章',
                      style: TextStyle(
                        color: NovelPalette.accent.withOpacity(.60),
                        fontSize: short ? 9 : 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: short ? 2.2 : 3.0,
                      ),
                    ),
                    SizedBox(height: short ? 8 : 12),
                    Text(
                      '故事开场',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.30),
                        fontSize: short ? 8.5 : 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .8,
                      ),
                    ),
                    const Spacer(),
                    if (!veryShort)
                      Text(
                        '${_visibleCount.clamp(0, _paragraphs.length)} / ${_paragraphs.length}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.24),
                          fontSize: 9,
                          letterSpacing: 1.0,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildParagraphList(
                          fontSize: veryShort ? 13.2 : (short ? 14.2 : 16.2),
                          lineHeight: veryShort ? 1.56 : (short ? 1.68 : 1.82),
                          paragraphGap: veryShort ? 10 : (short ? 13 : 17),
                          maxWidth: 760,
                        ),
                      ),
                    ),
                    if (_visibleCount > 0) ...<Widget>[
                      SizedBox(height: veryShort ? 4 : 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildContinueHint(compact: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final background = widget.controller.world.backgroundUrl;
    final landscape = size.width > size.height;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _requestWorldMenu();
      },
      child: Material(
        color: Colors.black,
        child: GestureDetector(
          onTap: _advance,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Opacity(
                  opacity: landscape ? .26 : .22,
                  child: NovelArtwork(
                    url: background,
                    assetCandidates: const <String>[
                      'assets/images/home_background.jpg',
                    ],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: landscape
                        ? Alignment.centerLeft
                        : Alignment.topCenter,
                    end: landscape
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    colors: landscape
                        ? const <Color>[
                            Color(0xF20A0A0A),
                            Color(0xBA080909),
                            Color(0xE6050606),
                          ]
                        : const <Color>[
                            Color(0xD9000000),
                            Color(0xA8090A0A),
                            Color(0xF2050606),
                          ],
                    stops: landscape
                        ? const <double>[0, .50, 1]
                        : const <double>[0, .48, 1],
                  ),
                ),
              ),
              SafeArea(
                child: landscape
                    ? _buildLandscapeOpening(size)
                    : _buildPortraitOpening(size),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showNovelFateRevertDialog(
  BuildContext context,
  NovelGameController controller, {
  bool previewOnly = false,
  FateRevertData? previewData,
}) async {
  final data = previewData ?? controller.fateRevert;
  // 死亡页只把苍白紫留作氛围色；真正的操作入口使用纯白，拉开层级。
  const glowColor = Color(0xFFA8A1B3);

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '意识沉沦',
    barrierColor: Colors.black.withOpacity(.82),
    transitionDuration: const Duration(milliseconds: 1050),
    pageBuilder: (dialogContext, _, __) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      // 中央仅保留一层极弱的冷色呼吸区，避免整页被紫色染满。
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -.08),
                            radius: .72,
                            colors: <Color>[
                              glowColor.withOpacity(.055),
                              Colors.transparent,
                              Colors.black.withOpacity(.16),
                            ],
                            stops: const <double>[0, .58, 1],
                          ),
                        ),
                      ),
                      Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 24 : 40,
                            vertical: compact ? 24 : 34,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.lens_blur_rounded,
                                  size: compact ? 38 : 42,
                                  color: Colors.white.withOpacity(.80),
                                  shadows: <Shadow>[
                                    Shadow(
                                      color: glowColor.withOpacity(.52),
                                      blurRadius: 26,
                                    ),
                                  ],
                                ),
                                SizedBox(height: compact ? 16 : 19),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      width: compact ? 34 : 46,
                                      height: 1,
                                      color: glowColor.withOpacity(.22),
                                    ),
                                    SizedBox(width: compact ? 11 : 14),
                                    Text(
                                      '意 识 沉 沦',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(.68),
                                        fontSize: compact ? 11 : 12,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: compact ? 4.8 : 6.0,
                                      ),
                                    ),
                                    SizedBox(width: compact ? 6 : 8),
                                    Container(
                                      width: compact ? 34 : 46,
                                      height: 1,
                                      color: glowColor.withOpacity(.22),
                                    ),
                                  ],
                                ),
                                SizedBox(height: compact ? 27 : 32),
                                Text(
                                  data.message.isEmpty
                                      ? '你的意识在无边的黑暗中逐渐涣散……'
                                      : data.message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: NovelPalette.text.withOpacity(.88),
                                    fontSize: compact ? 14.5 : 15.5,
                                    height: 1.82,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: compact ? .8 : 1.2,
                                    shadows: const <Shadow>[
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: compact ? 20 : 23),
                                Text(
                                  '死亡次数 ${data.deathCount}   /   法则损耗 ${data.scoreDeduct}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.34),
                                    fontSize: compact ? 9.8 : 10.5,
                                    letterSpacing: compact ? 1.1 : 1.5,
                                  ),
                                ),
                                SizedBox(height: compact ? 48 : 58),

                                // 唯一的高亮操作：白色实体按钮像黑暗中的出口。
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: compact ? 210 : 238,
                                    minHeight: compact ? 46 : 50,
                                  ),
                                  child: Material(
                                    color: Colors.white.withOpacity(.95),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(dialogContext).pop();
                                        if (!previewOnly) {
                                          controller.acceptFateRevert();
                                        }
                                      },
                                      splashColor: Colors.black.withOpacity(.08),
                                      highlightColor: Colors.black.withOpacity(.035),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: compact ? 26 : 32,
                                          vertical: compact ? 13 : 14,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: <Widget>[
                                            Icon(
                                              Icons.remove_red_eye_outlined,
                                              size: compact ? 15 : 16,
                                              color: Colors.black.withOpacity(.78),
                                            ),
                                            SizedBox(width: compact ? 11 : 14),
                                            Text(
                                              '睁 开 双 眼',
                                              style: TextStyle(
                                                color: Colors.black.withOpacity(.88),
                                                fontSize: compact ? 12.5 : 13.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: compact ? 3.2 : 4.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -.035),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

part of '../novel_sheets.dart';

// ============================================================================
// 故事流程弹窗 / 转场页
// 页面入口 / 对外入口：
//   - showNovelCharacterSetupDialog(...)
//   - showNovelOpeningDialog(...)
//   - showNovelFateRevertDialog(...)
//   - showDefaultNovelEnding(...)
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
    // 返回键只退出开场覆盖层，并把“打开左侧世界菜单”的意图交回游戏页。
    // 不启动正文，避免开场被中断后落到无内容页面。
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
                opacity: .22,
                child: NovelArtwork(
                  url: background,
                  assetCandidates: const <String>['assets/images/home_background.jpg'],
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xD9000000),
                    Color(0xA8090A0A),
                    Color(0xF2050606),
                  ],
                  stops: <double>[0, .48, 1],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  size.width < 560 ? 28 : size.width * .14,
                  34,
                  size.width < 560 ? 28 : size.width * .14,
                  64,
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
                    const Spacer(flex: 4),
                    Expanded(
                      flex: 8,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        // 自动跟随最新段落，同时保留手动滚动兜底。
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            // 未出现的段落不再提前占据布局高度。
                            // 每新增一段，滚动范围才真实增长，最后一段会被自动顶上来。
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
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Text(
                                    _paragraphs[index],
                                    textAlign: TextAlign.justify,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: widget.controller.settings.fontFamily,
                                      fontSize: size.width < 560 ? 15.5 : 17,
                                      height: 1.95,
                                      letterSpacing: .75,
                                      fontWeight: current ? FontWeight.w500 : FontWeight.w400,
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
                    ),
                    const Spacer(flex: 2),
                    if (_visibleCount > 0)
                      FadeTransition(
                        opacity: _breathe,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 24,
                              height: 1,
                              color: Colors.white.withOpacity(.20),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _finished ? '轻触进入故事' : '轻触继续',
                              style: TextStyle(
                                color: Colors.white.withOpacity(.58),
                                fontSize: 10.5,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 24,
                              height: 1,
                              color: Colors.white.withOpacity(.20),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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
  // 使用一种苍白、冰冷且易碎的紫色，更符合意识消散的氛围
  final glowColor = const Color(0xFFA89CB8);

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '意识沉沦',
    // 背景压得更暗一些，模拟死亡时的视觉剥夺
    barrierColor: Colors.black.withOpacity(.75),
    // 死亡的转场时间应该拉长，给人沉重感
    transitionDuration: const Duration(milliseconds: 1200),
    pageBuilder: (dialogContext, _, __) {
      return Material(
        color: Colors.transparent,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColoredBox(
              color: Colors.transparent,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // 使用模糊/消散意象的图标
                      Icon(
                        Icons.lens_blur_rounded,
                        size: 42,
                        color: Colors.white.withOpacity(.78),
                        shadows: <Shadow>[
                          Shadow(color: glowColor.withOpacity(.6), blurRadius: 24)
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(width: 48, height: 1, color: glowColor.withOpacity(.2)),
                          const SizedBox(width: 14),
                          Text(
                            '意 识 沉 沦',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.65),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 6.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 48, height: 1, color: glowColor.withOpacity(.2)),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Text(
                        data.message.isEmpty ? '你的意识在无边的黑暗中逐渐涣散……' : data.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: NovelPalette.text.withOpacity(.85),
                          fontSize: 15.5,
                          height: 1.8,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2))
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 将游戏数据（死亡次数、扣分）做弱化处理
                      Text(
                        '死亡次数 ${data.deathCount}   /   法则损耗 ${data.scoreDeduct}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.38),
                          fontSize: 10.5,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 72),
                      // 幽灵感交互按钮，去掉现代UI的实心背景和圆角
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            if (!previewOnly) {
                              controller.acceptFateRevert();
                            }
                          },
                          splashColor: glowColor.withOpacity(.15),
                          highlightColor: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.3),
                              border: Border.all(color: glowColor.withOpacity(.25), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.remove_red_eye_outlined,
                                  size: 16,
                                  color: glowColor.withOpacity(.75),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  '睁 开 双 眼',
                                  style: TextStyle(
                                    color: glowColor.withOpacity(.9),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 4.0,
                                  ),
                                ),
                              ],
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
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      // 改为缓慢浮现+轻微下坠的动画，不再使用弹簧效果
      final curvedAnimation = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

Future<void> showDefaultNovelEnding(
  BuildContext context,
  NovelGameController controller, {
  NovelEnding? endingOverride,
}) async {
  final ending = endingOverride ?? controller.ending;
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (_, animation, secondaryAnimation) => Scaffold(
        backgroundColor: NovelPalette.background,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            NovelWorldBackground(url: ending.backgroundUrl.isEmpty ? controller.world.backgroundUrl : ending.backgroundUrl),
            ColoredBox(color: Colors.black.withOpacity(.58)),
            SafeArea(
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 80, 24, 50),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(<Widget>[
                        Text(ending.code, style: const TextStyle(color: NovelPalette.accent, fontSize: 11, letterSpacing: 2)),
                        const SizedBox(height: 14),
                        Text(ending.title, style: const TextStyle(color: NovelPalette.text, fontSize: 44, height: 1.05, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 24),
                        Text(ending.text, style: const TextStyle(color: NovelPalette.text, fontSize: 15.5, height: 1.95)),
                        if (ending.milestones.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 42),
                          const Text('共同记忆', style: TextStyle(color: NovelPalette.text, fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          ...ending.milestones.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text('· $item', style: const TextStyle(color: NovelPalette.muted, height: 1.6)),
                              )),
                        ],
                        if (ending.triggeredEvents.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 34),
                          const Text('命运轨迹', style: TextStyle(color: NovelPalette.text, fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          ...ending.triggeredEvents.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text('· $item', style: const TextStyle(color: NovelPalette.muted, height: 1.6)),
                              )),
                        ],
                        const SizedBox(height: 48),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: NovelPalette.accent, foregroundColor: NovelPalette.accentDark, padding: const EdgeInsets.symmetric(vertical: 15)),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('返回世界'),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

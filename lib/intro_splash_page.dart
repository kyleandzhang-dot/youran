import 'package:flutter/material.dart';
import 'home_page.dart';
import 'services/session_manager.dart';

class IntroSplashPage extends StatefulWidget {
  final UserSession? initialSession;

  const IntroSplashPage({super.key, this.initialSession});

  @override
  State<IntroSplashPage> createState() => _IntroSplashPageState();
}

class _IntroSplashPageState extends State<IntroSplashPage> with TickerProviderStateMixin {
  // 扩展为 6 段长剧情文本
  final List<String> _paragraphs = [
    "公元2142年，霓虹闪烁的下城区。",
    "酸雨冲刷着仿生人的残骸，\n也冲刷着你昨夜支离破碎的记忆。",
    "你唯一能记起的，\n只有那个被称为「悠然」的代号...",
    "以及，\n口袋里那枚染血的筹码。",
    "迷雾深处，高耸入云的荒原塔正发出沉闷的低鸣。",
    "你抬起头，雨水滑过冰冷的脸颊，\n属于你的故事，此刻才刚刚开始。"
  ];

  int _visibleCount = 0;
  bool _isTransitioning = false;

  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      value: 1.0,
    );

    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _breathingAnimation = Tween<double>(begin: 0.1, end: 0.8).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    // 延迟显示第一段
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _visibleCount = 1);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  // 核心：新文字出现时，控制页面平滑向下滚动，将旧文字自然推上去
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleScreenClick() {
    if (_isTransitioning) return;

    if (_visibleCount < _paragraphs.length) {
      setState(() {
        _visibleCount++;
      });
      _scrollToBottom();
    } else {
      // 剧情播完，整页平滑 Fade out 离场
      setState(() {
        _isTransitioning = true;
      });

      _fadeController.reverse().then((_) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 2000),
            pageBuilder: (context, animation, secondaryAnimation) =>
                HomePage(initialSession: widget.initialSession),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleScreenClick,
        behavior: HitTestBehavior.opaque,
        child: FadeTransition(
          opacity: _fadeController,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 使用 SingleChildScrollView 配合动画控制，实现平滑上推
              Center(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const NeverScrollableScrollPhysics(), // 禁用手动滚动，保持节奏感
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 140.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_paragraphs.length, (index) {
                      final isVisible = index < _visibleCount;
                      final isPast = index < _visibleCount - 1;

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOut,
                        // 过去的段落降低到 0.25 透明度，当前段落保持 1.0 高亮
                        opacity: isVisible ? (isPast ? 0.25 : 1.0) : 0.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.translationValues(0, isVisible ? 0 : 20, 0),
                          margin: const EdgeInsets.only(bottom: 48.0),
                          child: Text(
                            _paragraphs[index],
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'serif',
                              color: Colors.white,
                              fontSize: 16.0,
                              height: 2.0,
                              letterSpacing: 2.5,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // 底部固定提示文字
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _breathingAnimation,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 500),
                    opacity: _visibleCount > 0 ? 1.0 : 0.0,
                    child: Text(
                      _visibleCount >= _paragraphs.length
                          ? '点击屏幕进入世界'
                          : '点击屏幕继续',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 6.0,
                      ),
                    ),
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
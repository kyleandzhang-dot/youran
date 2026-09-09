import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_shared.dart';
import 'api/api_client.dart';
import 'api/store_api.dart';

typedef ScenarioLaunchCallback = void Function(ScenarioLaunchInfo info);
typedef ScenarioDeletedCallback = void Function(String scenarioId);
typedef ScenarioLikeChangedCallback = void Function(
  String scenarioId,
  bool isLiked,
  int likes,
);

class DiscoverDetailWindow extends StatefulWidget {
  const DiscoverDetailWindow({
    super.key,
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.userName,
    required this.avatarUrl,
    required this.likes,
    this.isLiked = false,
    this.isLoggedIn = false,
    this.currentUserId,
    this.shareUrl,
    this.onLaunch,
    this.onDeleted, // 仅保留参数防止外部报错，本页面不再使用
    this.onLikeChanged,
    this.initialCommentId,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String userName;
  final String avatarUrl;
  final int likes;
  final bool isLiked;
  final bool isLoggedIn;
  final String? currentUserId;
  final String? shareUrl;
  final ScenarioLaunchCallback? onLaunch;
  final ScenarioDeletedCallback? onDeleted;
  final ScenarioLikeChangedCallback? onLikeChanged;
  final String? initialCommentId;

  @override
  State<DiscoverDetailWindow> createState() => _DiscoverDetailWindowState();
}

class _DiscoverDetailWindowState extends State<DiscoverDetailWindow> {
  static const Color _pageBg = Color(0xFF0A0A0A);
  static const Color _danger = Color(0xFFE0554A);

  OverlayEntry? _currentToast;

  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final PageController _mediaController = PageController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = <String, GlobalKey>{};

  Future<void> _loadCollectStatus() async {
    try {
      final collected = await StoreApi.checkCollected(widget.id);
      if (!mounted) return;
      setState(() => _isCollected = collected);
    } catch (_) {}
  }
  
  ScenarioDetail? _detail;
  List<ScenarioComment> _comments = const [];
  ScenarioComment? _replyingTo;

  late bool _isLiked;
  late int _likeCount;
  int _currentMediaIndex = 0;

  bool _isCollected = false;
  bool _collecting = false;

  bool _liking = false;
  bool _launching = false;
  bool _sendingComment = false;
  bool _hasInput = false;
  bool _commentsLoading = true;
  String? _commentsError;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likeCount = widget.likes;
    _commentController.addListener(_onCommentChanged);
    _loadAll();
    if (widget.isLoggedIn) {
      _loadCollectStatus();
    }
  }

  @override
  void dispose() {
    _currentToast?.remove(); // 加上这行
    _currentToast = null;    // 加上这行

    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    _mediaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCommentChanged() {
    final hasText = _commentController.text.trim().isNotEmpty;
    if (_hasInput != hasText && mounted) {
      setState(() => _hasInput = hasText);
    }
  }

  Future<void> _loadAll() async {
    await Future.wait<void>([
      _loadDetail(),
      _loadComments(),
    ]);
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await StoreApi.getScenarioDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLiked = detail.isLiked;
        _likeCount = detail.likes;
        if (_currentMediaIndex >= _mediaItems.length) {
          _currentMediaIndex = 0;
        }
      });
      widget.onLikeChanged?.call(widget.id, _isLiked, _likeCount);
    } catch (_) {}
  }

  

  bool get _isOwner {
    final me = widget.currentUserId;
    final owner = _detail?.userId;
    return me != null &&
        me.isNotEmpty &&
        owner != null &&
        owner.isNotEmpty &&
        me == owner;
  }

  bool _isMyComment(ScenarioComment comment) {
    final me = widget.currentUserId;
    return me != null && me.isNotEmpty && comment.userId == me;
  }

  bool _isAuthorComment(ScenarioComment comment) {
    final owner = _detail?.userId;
    return owner != null && owner.isNotEmpty && comment.userId == owner;
  }

  List<ScenarioMediaItem> get _mediaItems {
    final detailMedia = _detail?.mediaItems ?? const <ScenarioMediaItem>[];
    if (detailMedia.isNotEmpty) return detailMedia;

    final cover = (_detail?.coverUrl.isNotEmpty == true)
        ? _detail!.coverUrl
        : widget.imageUrl;
    if (cover.isEmpty) return const <ScenarioMediaItem>[];
    return [ScenarioMediaItem(url: cover, type: 'cover')];
  }

  int get _totalComments => _comments.fold<int>(
        0,
        (sum, item) => sum + 1 + item.replies.length,
      );

  GlobalKey _commentKey(String id) {
    return _commentKeys.putIfAbsent(id, () => GlobalKey());
  }

  bool _isTargetComment(String id) {
    final target = widget.initialCommentId?.trim();
    return target != null && target.isNotEmpty && target == id;
  }

  void _scrollToInitialComment() {
    if (!mounted) return;
    final target = widget.initialCommentId?.trim();
    if (target == null || target.isEmpty) return;
    final targetContext = _commentKeys[target]?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;

    // 清除可能还在显示的自带 SnackBar
    ScaffoldMessenger.of(context).clearSnackBars();

    // 移除上一个自定义 Toast（防止快速点击时重叠）
    if (_currentToast != null) {
      _currentToast!.remove();
      _currentToast = null;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    bool isRemoved = false;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        // 固定在顶部，彻底避开底部键盘收起时的闪烁跳动
        top: MediaQuery.paddingOf(context).top + 20, 
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, -15 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616).withOpacity(0.75),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isError) ...[
                          const Icon(Icons.error_outline, size: 16, color: Color(0xFFE0554A)),
                          const SizedBox(width: 8),
                        ] else ...[
                          const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          message,
                          style: TextStyle(
                            color: isError ? const Color(0xFFE0554A) : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _currentToast = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!isRemoved && _currentToast == entry && mounted) {
        isRemoved = true;
        entry.remove();
        _currentToast = null;
      }
    });
  }

  bool _requireLogin() {
    if (widget.isLoggedIn) return true;
    _toast('请先登录', isError: true);
    return false;
  }

  String _modeLabel(String? mode) {
    const map = <String, String>{
      'chat': '独聊',
      'group': '多人',
      'novel': '小说',
      'online': '联机',
      'rpg': '跑团',
    };
    return map[mode] ?? '互动';
  }

  String _formatDate(String? value, {bool withTime = false}) {
    if (value == null || value.isEmpty) return withTime ? '' : '刚刚';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final d = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '${d.year}-${two(d.month)}-${two(d.day)}';
    return withTime ? '$base ${two(d.hour)}:${two(d.minute)}' : base;
  }

  Future<void> _toggleLike() async {
    if (!_requireLogin() || _liking) return;

    final previousLiked = _isLiked;
    final previousCount = _likeCount;
    setState(() {
      _liking = true;
      _isLiked = !_isLiked;
      _likeCount = (_likeCount + (_isLiked ? 1 : -1)).clamp(0, 1 << 31).toInt();
    });
    widget.onLikeChanged?.call(widget.id, _isLiked, _likeCount);

    try {
      final result = await StoreApi.likeScenario(widget.id);
      if (!mounted) return;
      setState(() {
        _isLiked = result.isLiked;
        _likeCount = result.likeCount ?? _likeCount;
        _liking = false;
      });
      widget.onLikeChanged?.call(widget.id, _isLiked, _likeCount);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiked = previousLiked;
        _likeCount = previousCount;
        _liking = false;
      });
      widget.onLikeChanged?.call(widget.id, _isLiked, _likeCount);
      _toast('操作失败', isError: true);
    }
  }

  // 加上 quiet 参数，默认 false
  Future<void> _loadComments({bool quiet = false}) async {
    if (mounted) {
      if (!quiet) {
        // 如果不是静默刷新，才显示加载圈
        setState(() {
          _commentsLoading = true;
          _commentsError = null;
        });
      } else {
        // 静默刷新也顺便清一下错误状态
        setState(() => _commentsError = null);
      }
    }

    try {
      final comments = await StoreApi.getScenarioComments(widget.id);
      if (!mounted) return;
      final targetId = widget.initialCommentId?.trim();
      final nextComments = <ScenarioComment>[];
      for (final parent in comments) {
        var updated = parent;
        if (targetId != null && targetId.isNotEmpty) {
          final replyIndex = parent.replies.indexWhere((r) => r.id == targetId);
          if (replyIndex >= 0) {
            updated = parent.copyWith(
              visibleReplyCount: replyIndex + 1,
            );
          }
        }
        nextComments.add(updated);
      }

      setState(() {
        _comments = nextComments;
        if (!quiet) _commentsLoading = false; 
      });

      if (targetId != null && targetId.isNotEmpty && !quiet) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToInitialComment();
        });
      }
    } on ApiException catch (error, stackTrace) {
      debugPrint('load comments api failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        if (!quiet) _commentsLoading = false;
        _commentsError = '评论暂时无法加载';
      });
    } catch (error, stackTrace) {
      debugPrint('load comments failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        if (!quiet) _commentsLoading = false;
        _commentsError = '评论暂时无法加载';
      });
    }
  }

  Future<void> _toggleCollect() async {
    if (!_requireLogin() || _collecting) return;

    final previousCollected = _isCollected;
    setState(() {
      _collecting = true;
      _isCollected = !_isCollected;
    });

    try {
      if (_isCollected) {
        await StoreApi.collectScenario(widget.id);
      } else {
        await StoreApi.uncollectScenario(widget.id);
      }
      if (!mounted) return;
      setState(() => _collecting = false);
      _toast(_isCollected ? '已收藏' : '已取消收藏');
    } on ApiException catch (error, stackTrace) {
      debugPrint('collect scenario api failed: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isCollected = previousCollected;
        _collecting = false;
      });
      _toast('操作失败：${error.message}', isError: true);
    } catch (error, stackTrace) {
      debugPrint('collect scenario failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isCollected = previousCollected;
        _collecting = false;
      });
      _toast('操作失败', isError: true);
    }
  }

  void _startReply(ScenarioComment comment) {
    if (!_requireLogin()) return;
    if (_isMyComment(comment)) return;
    setState(() => _replyingTo = comment);
    _commentFocusNode.requestFocus();
  }

  void _cancelReply({bool clearInput = true}) {
    setState(() => _replyingTo = null);
    if (clearInput) _commentController.clear();
  }

  Future<void> _submitComment() async {
    if (!_requireLogin()) return;
    final content = _commentController.text.trim();
    if (content.isEmpty || _sendingComment) return;

    setState(() => _sendingComment = true);
    try {
      await StoreApi.postScenarioComment(
        widget.id,
        content: content,
        parentId: _replyingTo?.id,
      );
      if (!mounted) return;
      _commentController.clear();
      _commentFocusNode.unfocus();
      setState(() {
        _replyingTo = null;
        _sendingComment = false;
      });
      _toast('发送成功');
      
      // 改为静默刷新，不要让列表跳动
      await _loadComments(quiet: true); 
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingComment = false);
      _toast('发送失败', isError: true);
    }
  }

  Future<void> _toggleCommentLike(
    ScenarioComment comment, {
    ScenarioComment? parent,
  }) async {
    if (!_requireLogin()) return;

    final parentIndex = _comments.indexWhere(
      (c) => c.id == (parent?.id ?? comment.id),
    );
    if (parentIndex == -1) return;

    final oldParent = _comments[parentIndex];
    final oldTarget = parent == null
        ? oldParent
        : oldParent.replies.firstWhere((r) => r.id == comment.id);

    ScenarioComment optimistic(ScenarioComment item) => item.copyWith(
          isLiked: !item.isLiked,
          likes: (item.likes + (item.isLiked ? -1 : 1)).clamp(0, 1 << 31).toInt(),
        );

    setState(() {
      final next = [..._comments];
      if (parent == null) {
        next[parentIndex] = optimistic(oldParent);
      } else {
        final replies = [...oldParent.replies];
        final replyIndex = replies.indexWhere((r) => r.id == comment.id);
        if (replyIndex == -1) return;
        replies[replyIndex] = optimistic(replies[replyIndex]);
        next[parentIndex] = oldParent.copyWith(replies: replies);
      }
      _comments = next;
    });

    try {
      final result = await StoreApi.likeScenarioComment(comment.id);
      final serverLikeCount = result.likeCount;
      if (!mounted || serverLikeCount == null) return;
      setState(() {
        final next = [..._comments];
        final currentParent = next[parentIndex];
        if (parent == null) {
          next[parentIndex] = currentParent.copyWith(likes: serverLikeCount);
        } else {
          final replies = [...currentParent.replies];
          final replyIndex = replies.indexWhere((r) => r.id == comment.id);
          if (replyIndex == -1) return;
          replies[replyIndex] = replies[replyIndex].copyWith(
            likes: serverLikeCount,
          );
          next[parentIndex] = currentParent.copyWith(replies: replies);
        }
        _comments = next;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final next = [..._comments];
        if (parent == null) {
          next[parentIndex] = oldTarget;
        } else {
          final currentParent = next[parentIndex];
          final replies = [...currentParent.replies];
          final replyIndex = replies.indexWhere((r) => r.id == comment.id);
          if (replyIndex != -1) replies[replyIndex] = oldTarget;
          next[parentIndex] = currentParent.copyWith(replies: replies);
        }
        _comments = next;
      });
      _toast('操作失败', isError: true);
    }
  }

  void _expandReplies(ScenarioComment parent) {
    final index = _comments.indexWhere((c) => c.id == parent.id);
    if (index == -1) return;
    setState(() {
      final next = [..._comments];
      final current = next[index];
      next[index] = current.copyWith(
        visibleReplyCount:
            (current.visibleReplyCount + 5).clamp(1, current.replies.length).toInt(),
      );
      _comments = next;
    });
  }

  void _collapseReplies(ScenarioComment parent) {
    final index = _comments.indexWhere((c) => c.id == parent.id);
    if (index == -1) return;
    setState(() {
      final next = [..._comments];
      next[index] = next[index].copyWith(visibleReplyCount: 1);
      _comments = next;
    });
  }

  Future<void> _deleteComment(ScenarioComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), 
        ),
        title: const Text('删除评论', style: TextStyle(color: AppColors.textOnDark, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          '确定要删除这条评论吗？',
          style: TextStyle(color: AppColors.textOnDarkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: TextStyle(color: _danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await StoreApi.deleteScenarioComment(comment.id);
      if (!mounted) return;
      setState(() => _comments = _removeComment(_comments, comment.id));
      if (_replyingTo?.id == comment.id) _cancelReply();
      _toast('删除成功');
    } catch (_) {
      _toast('删除失败', isError: true);
    }
  }

  List<ScenarioComment> _removeComment(
    List<ScenarioComment> source,
    String commentId,
  ) {
    final result = <ScenarioComment>[];
    for (final item in source) {
      if (item.id == commentId) continue;
      final replies = _removeComment(item.replies, commentId);
      result.add(item.copyWith(replies: replies));
    }
    return result;
  }

  Future<void> _togglePin(ScenarioComment comment) async {
    if (!_isOwner) return;
    try {
      final pinned = await StoreApi.pinScenarioComment(widget.id, comment.id);
      if (!mounted) return;
      final index = _comments.indexWhere((c) => c.id == comment.id);
      if (index != -1) {
        setState(() {
          final next = [..._comments];
          next[index] = next[index].copyWith(isPinned: pinned);
          _comments = next;
        });
      }
      _toast(pinned ? '已置顶' : '已取消置顶');
    } catch (_) {
      _toast('操作失败', isError: true);
    }
  }

  Future<void> _playScenario() async {
    if (_launching) return;
    setState(() => _launching = true);

    try {
      final launch = await StoreApi.forkScenario(
        widget.id,
        fallbackMode: _detail?.mode ?? 'chat',
      );
      if (!mounted) return;
      if (!launch.isValid) {
        _toast('获取剧本失败，请重试', isError: true);
        return;
      }

      if (widget.onLaunch != null) {
        widget.onLaunch!(launch);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final route = launch.mode == 'online'
          ? '/online/${launch.scenarioId}'
          : '/${_routeMode(launch.mode)}/${launch.scenarioId}';
      final arguments = <String, dynamic>{
        'session_id': launch.sessionId,
        if (launch.mode == 'online') 'mode': 'create',
      };

      try {
        await Navigator.of(context, rootNavigator: true).pushNamed(
          route,
          arguments: arguments,
        );
      } catch (_) {
        _toast('剧本已加入存档，但路由尚未配置：$route', isError: true);
      }
    } on ApiException catch (e) {
      _toast(e.message, isError: true);
    } catch (_) {
      _toast('网络或服务器异常', isError: true);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  String _routeMode(String mode) {
    switch (mode) {
      case 'novel':
        return 'novel';
      case 'group':
        return 'group';
      case 'rpg':
        return 'rpg';
      case 'chat':
      default:
        return 'chat';
    }
  }

  Future<void> _copyLink() async {
    final value = widget.shareUrl?.trim().isNotEmpty == true
        ? widget.shareUrl!.trim()
        : 'scenario://${widget.id}';
    await Clipboard.setData(ClipboardData(text: value));
    _toast('链接已复制');
  }

  bool _useLandscapeLayout(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height && size.width >= 640;
  }

  bool _compactLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useLandscapeLayout(context) && size.height < 560;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.padding.bottom;
    final landscape = _useLandscapeLayout(context);
    final compactLandscape = _compactLandscape(context);

    if (landscape) {
      final leftWidth = (mediaQuery.size.width * .43)
          .clamp(compactLandscape ? 300.0 : 360.0, 620.0)
          .toDouble();
      final dockReserve =
          (_replyingTo == null ? 62.0 : 92.0) + bottomInset + safeBottom;

      return Scaffold(
        backgroundColor: _pageBg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: leftWidth,
                    child: _buildLandscapeMediaPane(),
                  ),
                  Container(
                    width: 1,
                    color: Colors.white.withOpacity(.055),
                  ),
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          bottom: dockReserve,
                          child: ListView(
                            controller: _scrollController,
                            padding: EdgeInsets.zero,
                            physics: const BouncingScrollPhysics(),
                            children: <Widget>[
                              _buildArticleInfo(),
                              _buildTags(),
                              _buildCharacters(),
                              _buildMainEnterButton(),
                              _buildCommentSection(),
                              SizedBox(height: compactLandscape ? 28 : 44),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: bottomInset,
                          child: _buildStickyBottomDock(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: mediaQuery.padding.top + (compactLandscape ? 8 : 12),
              left: compactLandscape ? 10 : 16,
              child: _buildStickyActionButton(
                LucideIcons.chevronLeft,
                () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: (_replyingTo == null ? 72 : 108) + bottomInset,
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildMediaArea(),
                _buildArticleInfo(),
                _buildTags(),
                _buildCharacters(),
                _buildMainEnterButton(),
                _buildCommentSection(),
                const SizedBox(height: 60),
              ],
            ),
          ),
          Positioned(
            top: mediaQuery.padding.top + 12,
            left: 16,
            child: _buildStickyActionButton(
              LucideIcons.chevronLeft,
              () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset,
            child: _buildStickyBottomDock(),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaArea() {
    final media = _mediaItems;
    if (media.isEmpty) {
      return AspectRatio(aspectRatio: 1, child: _errorPlaceholder());
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AspectRatio(
          aspectRatio: 1.0, 
          child: PageView.builder(
            controller: _mediaController,
            itemCount: media.length,
            onPageChanged: (index) => setState(() => _currentMediaIndex = index),
            itemBuilder: (context, index) {
              final item = media[index];
              return GestureDetector(
                onTap: () => _showImagePreview(item.url), 
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: _image(CdnUtil.resize(item.url, width: 200), fit: BoxFit.cover, opacity: 0.4),
                    ),
                    _image(CdnUtil.resize(item.url, width: 1080), fit: BoxFit.contain), 
                  ],
                ),
              );
            },
          ),
        ),
        
        Positioned(
          top: 0, left: 0, right: 0,
          height: 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _pageBg.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          height: 80, 
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    _pageBg,
                    _pageBg.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (media.length > 1)
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12), 
              ),
              child: Text(
                '${_currentMediaIndex + 1}/${media.length}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }


  Widget _buildLandscapeMediaPane() {
    final media = _mediaItems;
    if (media.isEmpty) return _errorPlaceholder();

    final compact = _compactLandscape(context);
    return ColoredBox(
      color: _pageBg,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          PageView.builder(
            controller: _mediaController,
            itemCount: media.length,
            onPageChanged: (index) => setState(() => _currentMediaIndex = index),
            itemBuilder: (context, index) {
              final item = media[index];
              return GestureDetector(
                onTap: () => _showImagePreview(item.url),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: _image(
                        CdnUtil.resize(item.url, width: 260),
                        fit: BoxFit.cover,
                        opacity: .38,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 22,
                        compact ? 8 : 18,
                        compact ? 12 : 22,
                        compact ? 8 : 18,
                      ),
                      child: _image(
                        CdnUtil.resize(item.url, width: 1080),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: compact ? 78 : 110,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      _pageBg.withOpacity(.76),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: compact ? 58 : 78,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      _pageBg.withOpacity(.92),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (media.length > 1)
            Positioned(
              bottom: compact ? 10 : 16,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 12,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.42),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentMediaIndex + 1}/${media.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 9.5 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image(String url, {BoxFit fit = BoxFit.cover, double opacity = 1.0}) {
    Widget img;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      img = Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        errorBuilder: (_, __, ___) => _errorPlaceholder(),
      );
    } else if (url.isEmpty) {
      img = _errorPlaceholder();
    } else {
      img = Image.asset(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        errorBuilder: (_, __, ___) => _errorPlaceholder(),
      );
    }

    if (opacity < 1.0) {
      return Opacity(opacity: opacity, child: img);
    }
    return img;
  }

  Widget _errorPlaceholder() {
    return Container(
      color: Colors.white.withOpacity(0.02),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.textOnDarkMuted,
        size: 40,
      ),
    );
  }

  Future<void> _showImagePreview(String url) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭图片预览',
      barrierColor: Colors.black.withOpacity(0.94),
      pageBuilder: (previewContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(120),
                    child: Center(child: _image(url, fit: BoxFit.contain)),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    onPressed: () => Navigator.pop(previewContext),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickyActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 40, 
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4), 
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.textOnDark),
          ),
        ),
      ),
    );
  }

  Widget _buildArticleInfo() {
    final compact = _compactLandscape(context);
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true ? detail!.title : widget.title;
    final author = detail?.authorName.isNotEmpty == true
        ? detail!.authorName
        : widget.userName;
    final avatar = detail?.authorAvatarUrl.isNotEmpty == true
        ? detail!.authorAvatarUrl
        : widget.avatarUrl;
    final description = detail?.description ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 10 : 16,
        compact ? 18 : 24,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: compact ? 19 : 24,
              fontWeight: FontWeight.w700,
              height: compact ? 1.2 : 1.3,
            ),
          ),
          SizedBox(height: compact ? 11 : 20),
          Row(
            children: [
              Container(
                width: compact ? 24 : 28,
                height: compact ? 24 : 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 6 : 8),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar.isEmpty
                    ? _avatarPlaceholder()
                    : _image(avatar, fit: BoxFit.cover),
              ),
              SizedBox(width: compact ? 8 : 12),
              Flexible(
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _modeLabel(detail?.mode),
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: compact ? 9.5 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if ((detail?.createdAt ?? '').isNotEmpty) ...[
            SizedBox(height: compact ? 8 : 14),
            Text(
              _formatDate(detail!.createdAt),
              style: TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: compact ? 10.5 : 12,
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            SizedBox(height: compact ? 13 : 24),
            Text(
              description,
              style: TextStyle(
                color: AppColors.textOnDark.withOpacity(0.85),
                fontSize: compact ? 13 : 15,
                height: compact ? 1.45 : 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      color: Colors.white.withOpacity(0.04),
      alignment: Alignment.center,
      child: const Icon(Icons.person, size: 14, color: AppColors.textOnDarkMuted),
    );
  }

  Widget _buildTags() {
    final compact = _compactLandscape(context);
    final tags = _detail?.tags ?? const <String>[];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 14 : 24,
        compact ? 18 : 24,
        0,
      ),
      child: Wrap(
        spacing: compact ? 6 : 10,
        runSpacing: compact ? 6 : 10,
        children: tags
            .map(
              (tag) => Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 12,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: compact ? 10.5 : 12,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCharacters() {
    final compact = _compactLandscape(context);
    final characters = _detail?.characters ?? const <ScenarioCharacter>[];
    if (characters.isEmpty) return const SizedBox.shrink();
    final avatarSize = compact ? 42.0 : 56.0;
    final cardWidth = compact ? 48.0 : 60.0;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 20 : 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
            child: Text(
              '登场角色',
              style: TextStyle(
                color: AppColors.textOnDark,
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          SizedBox(
            height: compact ? 66 : 90,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: characters.length,
              separatorBuilder: (_, __) => SizedBox(width: compact ? 10 : 16),
              itemBuilder: (context, index) {
                final char = characters[index];
                return GestureDetector(
                  onTap: () => _showCharacterPopup(char),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      children: [
                        Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(compact ? 11 : 16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (char.avatarUrl ?? '').isEmpty
                              ? const Icon(
                                  Icons.person,
                                  color: AppColors.textOnDarkMuted,
                                )
                              : _image(
                                  CdnUtil.resize(char.avatarUrl!, width: 120),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        SizedBox(height: compact ? 5 : 10),
                        Text(
                          char.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: compact ? 9.5 : 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainEnterButton() {
    final compact = _compactLandscape(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 20 : 36,
        compact ? 18 : 24,
        compact ? 18 : 32,
      ),
      child: Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          onTap: _launching ? null : _playScenario,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: compact ? 11 : 16),
            alignment: Alignment.center,
            child: _launching
                ? SizedBox(
                    width: compact ? 16 : 20,
                    height: compact ? 16 : 20,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF121212),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.play,
                        size: compact ? 15 : 18,
                        color: const Color(0xFF0A0A0A),
                      ),
                      SizedBox(width: compact ? 6 : 8),
                      Text(
                        '进入世界',
                        style: TextStyle(
                          color: const Color(0xFF0A0A0A),
                          fontSize: compact ? 13 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentSection() {
    final compact = _compactLandscape(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        compact ? 6 : 10,
        compact ? 18 : 24,
        compact ? 18 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '评论区${_totalComments > 0 ? ' ($_totalComments)' : ''}',
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: compact ? 14 : 24), 
          if (_commentsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
            )
          else if (_commentsError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: GestureDetector(
                  onTap: () => _loadComments(),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _commentsError!,
                        style: const TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '重试',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_comments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  '还没有评论，来抢个沙发吧',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            for (int i = 0; i < _comments.length; i++) ...[
              if (i > 0) const SizedBox(height: 28), 
              _buildCommentItem(_comments[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildCommentItem(
    ScenarioComment comment, {
    ScenarioComment? parent,
    bool isReply = false,
  }) {
    final avatarSize = isReply ? 26.0 : 36.0;
    final visibleCount = !isReply
        ? comment.visibleReplyCount.clamp(0, comment.replies.length).toInt()
        : 0;
    final visibleReplies = !isReply
        ? comment.replies.take(visibleCount).toList()
        : const <ScenarioComment>[];

    final isTarget = _isTargetComment(comment.id);
    
    return Container(
      key: _commentKey(comment.id),
      margin: EdgeInsets.only(left: isReply ? 46 : 0, top: isReply ? 20 : 0),
      padding: isTarget ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: isTarget
          ? BoxDecoration(
              color: Colors.white.withOpacity(0.04), 
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(avatarSize / 2), 
            ),
            clipBehavior: Clip.antiAlias,
            child: (comment.authorAvatarUrl ?? '').isEmpty
                ? _avatarPlaceholder()
                : _image(CdnUtil.resize(comment.authorAvatarUrl!, width: 100), fit: BoxFit.cover), 
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行：用户名与标签 (已移除爱心点赞)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: isReply ? 12 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_isAuthorComment(comment)) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.12), 
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '作者',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (comment.isPinned) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C58B).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '置顶',
                          style: TextStyle(
                            color: Color(0xFFE8C58B),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  comment.content,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: isReply ? 13 : 14,
                    height: 1.6, 
                  ),
                ),
                const SizedBox(height: 12),
                // 第三行：时间、回复、更多按钮、点赞(爱心移到这里)
                Row(
                  children: [
                    if ((comment.createdAt ?? '').isNotEmpty)
                      Text(
                        _formatDate(comment.createdAt, withTime: true),
                        style: const TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 11,
                        ),
                      ),
                    if (!_isMyComment(comment)) ...[
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: () => _startReply(comment),
                        child: const Text(
                          '回复',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (_isMyComment(comment) || (_isOwner && !isReply)) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => _showCommentActions(comment, isReply: isReply),
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          size: 16,
                          color: AppColors.textOnDarkMuted,
                        ),
                      ),
                    ],
                    // 用 Spacer 将点赞按钮推向最右侧
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _toggleCommentLike(comment, parent: parent),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: comment.isLiked
                                  ? const Color(0xFFE0554A)
                                  : AppColors.textOnDarkMuted,
                            ),
                            if (comment.likes > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${comment.likes}',
                                style: const TextStyle(
                                  color: AppColors.textOnDarkMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isReply && visibleReplies.isNotEmpty)
                  Column(
                    children: [
                      for (final reply in visibleReplies)
                        _buildCommentItem(
                          reply,
                          parent: comment,
                          isReply: true,
                        ),
                    ],
                  ),
                if (!isReply && comment.replies.length > visibleCount)
                  Padding(
                    padding: const EdgeInsets.only(left: 46, top: 16),
                    child: GestureDetector(
                      onTap: () => _expandReplies(comment),
                      child: Text(
                        '展开更多回复 (${comment.replies.length - visibleCount})',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (!isReply && comment.replies.length > 1 && visibleCount >= comment.replies.length)
                  Padding(
                    padding: const EdgeInsets.only(left: 46, top: 16),
                    child: GestureDetector(
                      onTap: () => _collapseReplies(comment),
                      child: const Text(
                        '收起回复',
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentActions(ScenarioComment comment, {required bool isReply}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(16), 
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isOwner && !isReply)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined, color: AppColors.textOnDark, size: 20),
                title: Text(
                  comment.isPinned ? '取消置顶' : '置顶评论',
                  style: const TextStyle(color: AppColors.textOnDark, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _togglePin(comment);
                },
              ),
            if (_isMyComment(comment))
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFE0554A), size: 20),
                title: const Text(
                  '删除评论',
                  style: TextStyle(color: Color(0xFFE0554A), fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteComment(comment);
                },
              ),
            ListTile(
              title: const Center(
                child: Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 15)),
              ),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottomDock() {
    final compact = _compactLandscape(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), 
        child: Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 20,
            compact ? 8 : 14,
            compact ? 14 : 20,
            (compact ? 8 : 14) + bottomPadding,
          ),
          decoration: BoxDecoration(
            color: _pageBg.withOpacity(0.85),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '回复 @${_replyingTo!.authorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: compact ? 10.5 : 12,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _cancelReply(clearInput: false),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 6 : 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: compact ? 36 : 42,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.06), 
                        borderRadius: BorderRadius.circular(compact ? 18 : 21), 
                      ),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: compact ? 12.5 : 14,
                        ),
                        onTapOutside: (_) {
                          if (_replyingTo != null && !_hasInput) {
                            _cancelReply(clearInput: false);
                          }
                          _commentFocusNode.unfocus();
                        },
                        decoration: InputDecoration(
                          hintText: _replyingTo == null
                              ? '说点什么...'
                              : '回复 @${_replyingTo!.authorName}',
                          hintStyle: TextStyle(
                            color: AppColors.textOnDarkMuted.withOpacity(.6),
                            fontSize: compact ? 11.5 : 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _hasInput
                        ? GestureDetector(
                            key: const ValueKey('send'),
                            onTap: _sendingComment ? null : _submitComment,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 12 : 16,
                                vertical: compact ? 8 : 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(20), 
                              ),
                              child: _sendingComment
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : Text(
                                      '发送',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: compact ? 11.5 : 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          )
                        : Row(
                            key: const ValueKey('actions'), 
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _collecting ? null : _toggleCollect,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  child: Icon(
                                    _isCollected ? Icons.star_rounded : Icons.star_border_rounded,
                                    size: compact ? 22 : 26, 
                                    color: _isCollected ? Colors.amber : AppColors.textOnDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4), 
                              GestureDetector(
                                key: const ValueKey('like'),
                                onTap: _liking ? null : _toggleLike,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isLiked ? Icons.favorite : Icons.favorite_border,
                                        size: compact ? 20 : 24,
                                        color: _isLiked
                                            ? const Color(0xFFE0554A)
                                            : AppColors.textOnDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$_likeCount',
                                        style: TextStyle(
                                          color: AppColors.textOnDark,
                                          fontSize: compact ? 12 : 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(16), 
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link_rounded, color: AppColors.textOnDark, size: 20),
              title: const Text('复制链接', style: TextStyle(color: AppColors.textOnDark, fontSize: 15)),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyLink();
              },
            ),
            const SizedBox(height: 8), 
            ListTile(
              title: const Center(
                child: Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 15)),
              ),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  void _showCharacterPopup(ScenarioCharacter character) {
    final String displayImageUrl = (character.portraitUrl != null && character.portraitUrl!.isNotEmpty)
        ? character.portraitUrl!
        : (character.avatarUrl ?? '');

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(20), 
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (displayImageUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showImagePreview(displayImageUrl);
                    },
                    child: AspectRatio(
                      aspectRatio: 1, 
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: _image(displayImageUrl, fit: BoxFit.cover, opacity: 0.4),
                          ),
                          _image(displayImageUrl, fit: BoxFit.contain),
                        ],
                      ),
                    ),
                  )
                else
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _errorPlaceholder(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(28), 
                  child: Column(
                    children: [
                      Text(
                        character.name,
                        style: const TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          (character.identity ?? '').isNotEmpty
                              ? character.identity!
                              : '神秘角色',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        (character.desc ?? '').isNotEmpty
                            ? character.desc!
                            : '暂无背景故事',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
part of '../novel_sheets.dart';

// ============================================================================
// 道具兑换 / 商城页
// 页面入口 / 对外入口：
//   - showNovelStoreSheet(...)
// ============================================================================

Future<void> showNovelStoreSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭道具兑换',
    barrierColor: Colors.black.withOpacity(.28),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      final media = MediaQuery.of(dialogContext);
      final compact = media.size.width < 600;
      final shortViewport = media.size.height < 620;
      final heightFactor = shortViewport ? .94 : (compact ? .84 : .78);

      return Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: compact ? Alignment.bottomCenter : Alignment.center,
            child: FractionallySizedBox(
              widthFactor: compact ? 1 : .88,
              heightFactor: heightFactor,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                  ),
                  child: SafeArea(
                    top: false,
                    child: _StoreSheet(controller: controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _StoreSheet extends StatefulWidget {
  const _StoreSheet({required this.controller});
  final NovelGameController controller;

  @override
  State<_StoreSheet> createState() => _StoreSheetState();
}

class _StoreSheetState extends State<_StoreSheet> {
  String busy = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchShopData();
  }

  Future<void> _fetchShopData() async {
    await widget.controller.refreshShop();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final viewportWidth = MediaQuery.of(context).size.width;
        final horizontalPadding = viewportWidth >= 600 ? 22.0 : 12.0;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Column(
                children: <Widget>[
                  _StoreHeader(
                    score: widget.controller.score.total,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF7C8B96),
                            ),
                          )
                        : widget.controller.shopItems.isEmpty
                            ? const _EmptyState(text: '暂无可兑换物品')
                            : ListView.separated(
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  12,
                                  horizontalPadding,
                                  30,
                                ),
                                itemCount: widget.controller.shopItems.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item =
                                      widget.controller.shopItems[index];
                                  final affordable =
                                      widget.controller.score.total >= item.price;
                                  return _ItemCard(
                                    iconUrl: item.imageUrl,
                                    itemType: item.itemType,
                                    fallback: _itemFallback(item.itemType),
                                    name: item.name,
                                    description: item.description,
                                    badge: '已拥有 ${item.quantity}',
                                    actionText: '${item.price}',
                                    showPointIcon: true,
                                    loading: busy == item.itemType,
                                    enabled: affordable && busy.isEmpty,
                                    onAction: () async {
                                      if (busy.isNotEmpty) return;
                                      setState(() => busy = item.itemType);
                                      try {
                                        await widget.controller.buyShopItem(item);
                                      } finally {
                                        if (mounted) setState(() => busy = '');
                                      }
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            if (widget.controller.hudEvent != null)
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey<int>(widget.controller.hudEvent!.id),
                  child: NovelHudEventOverlay(event: widget.controller.hudEvent!),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({
    required this.score,
    required this.onClose,
  });

  final int score;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '道具兑换',
                  style: TextStyle(
                    color: Color(0xFF1C2227),
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '用星块换取故事中的特殊机会',
                  style: TextStyle(
                    color: Color(0xFF7B848B),
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF3F5F3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Image.asset(
                    'assets/images/xing.webp',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$score',
                  style: const TextStyle(
                    color: Color(0xFF283038),
                    fontSize: 12.5,
                    fontFamily: 'MiSans',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.zero,
              child: const SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  Icons.close,
                  size: 19,
                  color: Color(0xFF59636B),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.iconUrl,
    required this.itemType,
    required this.fallback,
    required this.name,
    required this.description,
    required this.badge,
    required this.actionText,
    required this.loading,
    required this.enabled,
    required this.onAction,
    this.showPointIcon = false,
  });

  final String iconUrl;
  final String itemType;
  final String fallback;
  final String name;
  final String description;
  final String badge;
  final String actionText;
  final bool loading;
  final bool enabled;
  final VoidCallback onAction;
  final bool showPointIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFA),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 图标区域：纯白卡片中的浅灰图标托盘
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F3F0),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: iconUrl,
                  assetCandidates: <String>[
                    if (itemType.trim().isNotEmpty) 'assets/images/${itemType.trim()}.webp',
                  ],
                  fit: BoxFit.contain,
                  fallbackText: fallback,
                ),
              ),
              if (badge.isNotEmpty && badge != '已拥有 0')
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF626A66),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14), 
          
          // 文字区域
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF1C2227),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description.trim().isEmpty ? _itemTypeLabel(itemType) : description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF6C747B),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          // 购买按钮：只保留一个明确的主题色操作面，弱化其余结构线。
          if (actionText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: 1,
              child: Material(
                color: enabled ? NovelPalette.accent : const Color(0xFFE2E6E3),
                borderRadius: BorderRadius.zero,
                child: InkWell(
                  onTap: loading || !enabled ? null : onAction,
                  borderRadius: BorderRadius.zero,
                  splashColor: Colors.white24,
                  highlightColor: Colors.white10,
                  child: Container(
                    width: 88,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: loading
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: enabled ? NovelPalette.accentDark : const Color(0xFF7D8580),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (showPointIcon) ...<Widget>[
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: Image.asset(
                                  'assets/images/xing.webp', 
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              actionText,
                              style: TextStyle(
                                color: enabled
                                    ? NovelPalette.accentDark
                                    : const Color(0xFF858C87),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _itemTypeLabel(String type) {
    return switch (type) {
      'misc' => '普通物品',
      'consumable' => '消耗品',
      'material' => '材料',
      'quest' => '任务道具',
      'gift' => '赠礼道具',
      'skill_book' => '技能道具',
      'lucky_card' => '特殊道具',
      _ => '故事物品',
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.inventory_2_outlined, size: 32, color: Color(0xFFB2BAC0)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF7B848B),
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _itemFallback(String type) {
  return switch (type) {
    'fate_card' => '命',
    'revert_card' => '溯',
    'gift' => '绊',
    'skill_book' => '技',
    'image_card' => '幻',
    'lucky_card' => '运',
    _ => '物',
  };
}

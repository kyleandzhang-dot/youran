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
  await _showNovelSheet<void>(
    context,
    heightFactor: .78,
    child: _StoreSheet(controller: controller),
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
        return Stack(
          children: [
            _SheetScaffold(
              title: '道具兑换',
              subtitle: '用星块换取故事中的特殊机会',
              trailing: Container(
                // 顶部资产胶囊：高级深色玻璃质感
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 4), 
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.35), // 加深底色提升对比度
                  borderRadius: BorderRadius.circular(8), // 微圆角
                  border: Border.all(
                    color: Colors.white.withOpacity(.12), 
                    width: 0.5,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Image.asset(
                        'assets/images/xing.webp',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.controller.score.total}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(.96),
                        fontSize: 13.5,
                        fontFamily: 'MiSans', // 推荐使用现代无衬线字体
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              child: _loading 
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withOpacity(.4),
                      ),
                    )
                  : widget.controller.shopItems.isEmpty
                  ? const _EmptyState(text: '暂无可兑换物品')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                      itemCount: widget.controller.shopItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = widget.controller.shopItems[index];
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
  final VoidCallback onAction;
  final bool showPointIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 核心提升：为每个商品包裹一层高质感的微圆角暗卡
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.25), // 沉稳的底色，压住浮躁感
        borderRadius: BorderRadius.circular(10), // TRPG 风格偏好的硬朗微圆角
        border: Border.all(
          color: Colors.white.withOpacity(.06), // 极微弱的边缘反光
          width: 0.5,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 图标区域：增加黑底色托盘，让图片更聚焦
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.4), // 深色托盘
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(.04)),
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
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E201E),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.5),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
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
                    color: Colors.white.withOpacity(0.95),
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
                    color: Colors.white.withOpacity(0.55), // 提高描述的可读性
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          // 按钮区域：采用具有真实点击欲望的立体悬浮按钮
          if (actionText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Material(
              color: Colors.white.withOpacity(.08), // 按钮底色比卡片略亮
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: loading ? null : onAction,
                borderRadius: BorderRadius.circular(8),
                splashColor: Colors.white.withOpacity(.06),
                highlightColor: Colors.white.withOpacity(.04),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(.15), // 按钮边缘高光
                      width: 0.5,
                    ),
                  ),
                  child: loading
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5, 
                            color: Colors.white.withOpacity(.7)
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (showPointIcon) ...<Widget>[
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: Image.asset(
                                  'assets/images/xing.webp', 
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              actionText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
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
  }

  String _itemTypeLabel(String type) {
    return switch (type) {
      'misc' => '普通物品',
      'consumable' => '消耗品',
      'material' => '材料',
      'quest' => '任务道具',
      'gift' => '赠礼道具',
      'blind_box' => '福袋',
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
            Icon(Icons.inventory_2_outlined, size: 32, color: Colors.white.withOpacity(.15)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(.45),
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
    'blind_box' => '福',
    'image_card' => '幻',
    'lucky_card' => '运',
    _ => '物',
  };
}
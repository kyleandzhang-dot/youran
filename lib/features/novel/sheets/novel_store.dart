part of '../novel_sheets.dart';

// ============================================================================
// 道具兑换 / 商城页
// 页面入口 / 对外入口：
//   - showNovelStoreSheet(...)
// 其余以下划线 `_` 开头的类型/方法均为该页面内部实现或共享私有实现。
// ============================================================================

/// 旧“状态”调用保留兼容，实际统一打开背包。
Future<void> showNovelStoreSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  // 1. 去掉这里的 await controller.refreshShop(); 防止阻塞弹窗
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
  bool _loading = true; // 2. 新增加载状态

  @override
  void initState() {
    super.initState();
    // 弹窗打开后，异步拉取商品数据
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
        // 3. 在最外层包裹 Stack，用于解决 HUD 提示层级问题
        return Stack(
          children: [
            _SheetScaffold(
              title: '道具兑换',
              subtitle: '用积分换取故事中的特殊机会',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.045),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF4C542)),
                    const SizedBox(width: 5),
                    Text(
                      '${widget.controller.score.total}',
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              child: _loading 
                  // 数据加载时显示加载动画
                  ? const Center(
                      child: CircularProgressIndicator(color: NovelPalette.accent),
                    )
                  : widget.controller.shopItems.isEmpty
                  ? const _EmptyState(text: '暂无可兑换物品')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
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
            
            // 4. 将系统提示渲染在商城弹窗内部的最上层
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
    this.selected = false,
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
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 增加上下留白
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 图标区域：去掉生硬的边框，改为微圆角和极浅底色
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.04), // 浅色玻璃底
                  borderRadius: BorderRadius.circular(12), // 微圆角
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
              if (badge.isNotEmpty)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E201E),
                      borderRadius: BorderRadius.circular(6),
                      // 仅保留一点点高光边
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
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
          const SizedBox(width: 16), // 拉开图标和文字的距离
          
          // 文字区域：弱化描述，突出标题
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
                    color: Colors.white.withOpacity(0.45), // 进一步弱化描述
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          // 按钮区域：无边框，采用柔和底色和微圆角
          if (actionText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Material(
              color: Colors.white.withOpacity(0.06), // 淡淡的底色取代边框
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: loading ? null : onAction,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (showPointIcon) ...<Widget>[
                              const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF4C542)), // 让星星带点色彩
                              const SizedBox(width: 4),
                            ],
                            Text(
                              actionText,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.only(top: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 24,
              height: 1,
              color: Colors.white.withOpacity(.22),
            ),
            const SizedBox(height: 20),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(.55),
                fontSize: 12.5,
                letterSpacing: 1.2,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? label}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: NovelPalette.muted, fontSize: 11),
    filled: true,
    fillColor: Colors.white.withOpacity(.018),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: NovelPalette.accent, width: 1),
    ),
  );
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





// ============================================================================
// Light archive palette
// 人物 / 背包 / 档案 / 经历统一使用近白冷中性色。
// 强调色统一引用 NovelPalette 的抹茶绿体系，只用于选中、主操作和状态。
// ============================================================================

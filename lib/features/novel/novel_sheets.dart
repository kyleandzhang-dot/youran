import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import '../../app_shared.dart';
import 'novel_backend.dart';
import 'novel_game_controller.dart';
import 'novel_models.dart';
import 'novel_widgets.dart';

Future<T?> _showNovelSheet<T>(
  BuildContext context, {
  required Widget child,
  double heightFactor = .76,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭面板',
    barrierColor: Colors.black.withOpacity(.80),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      final media = MediaQuery.of(dialogContext);
      final maxHeight =
          (media.size.height * heightFactor).clamp(360.0, 650.0).toDouble();
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: maxHeight,
                ),
                child: _SheetFrame(child: child),
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
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}


Future<T?> _showNovelArchivePage<T>(
  BuildContext context, {
  required Widget child,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B0C0D),
          body: SafeArea(
            child: child,
          ),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
    ),
  );
}

Future<void> showNovelChoicesSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _showNovelSheet<void>(
    context,
    heightFactor: .58,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return _SheetScaffold(
          title: '命运选择',
          subtitle: controller.playerHint.isEmpty ? '每一个决定都会留下痕迹' : controller.playerHint,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            itemCount: controller.choices.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == controller.choices.length) {
                return _ActionTile(
                  icon: Icons.hourglass_empty_rounded,
                  title: '暂不行动',
                  subtitle: '让角色或环境自然推进剧情',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await controller.forceContinue();
                  },
                );
              }
              final choice = controller.choices[index];
              return _ActionTile(
                number: index + 1,
                icon: choice.isAction ? Icons.casino_outlined : Icons.arrow_outward_rounded,
                title: choice.text,
                subtitle: choice.isAction ? '该行动可能触发判定' : '',
                highlighted: choice.isAction,
                onTap: () async {
                  Navigator.of(context).pop();
                  await controller.selectChoice(choice);
                },
              );
            },
          ),
        );
      },
    ),
  );
}

Future<void> showNovelInventorySheet(
  BuildContext context,
  NovelGameController controller,
) async {
  // 先打开页面，再由页面首帧后的异步任务刷新背包。
  await _showNovelArchivePage<void>(
    context,
    child: _ArchivePageScaffold(
      title: '背包',
      child: _InventorySheet(controller: controller),
    ),
  );
}

class _InventorySheet extends StatefulWidget {
  const _InventorySheet({required this.controller});
  final NovelGameController controller;

  @override
  State<_InventorySheet> createState() => _InventorySheetState();
}

class _InventorySheetState extends State<_InventorySheet> {
  int tab = 0;
  String busy = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    // 保证路由先完成首帧，再请求数据；点击后不会卡在原页面等待网络。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshInventory();
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final data = widget.controller.inventory;
        final items = tab == 0 ? data.storyItems : data.consumables;
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: _InventoryTabBar(
                selected: tab,
                storyCount: data.storyItems.length,
                consumableCount: data.consumables.length,
                onChanged: (value) => setState(() => tab = value),
              ),
            ),
            if (loading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: NovelPalette.accent,
                  ),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(
                      text: loading
                          ? '正在整理背包…'
                          : (tab == 0 ? '故事里还没有留下物品' : '暂时没有可使用的道具'),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 22,
                          thickness: .6,
                          color: Colors.white.withOpacity(.055),
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _InventoryItemTile(
                            item: item,
                            fallback: _itemFallback(item.itemType),
                            actionText: tab == 0 ? '' : _consumableAction(item.itemType),
                            loading: busy == item.id,
                            onAction: tab == 0 ? null : () => _handleItem(item),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleItem(NovelInventoryItem item) async {
    // 故事物品只展示，不再存在“装备 / 卸下”。
    if (tab == 0 || busy.isNotEmpty) return;
    setState(() => busy = item.id);
    try {
      if (item.itemType == 'gift') {
        final npcs = widget.controller.scenario?.characters.values
                .where((character) => !character.isMain)
                .toList() ??
            <NovelCharacter>[];
        if (!mounted) return;
        final target = await _showNovelSheet<NovelCharacter>(
          context,
          heightFactor: .56,
          child: _SheetScaffold(
            title: '赠送鲜花',
            subtitle: '选择要赠送的角色',
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
              itemCount: npcs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final npc = npcs[index];
                return _CharacterCard(
                  character: npc,
                  onTap: () => Navigator.of(context).pop(npc),
                );
              },
            ),
          ),
        );
        if (target != null) await widget.controller.giveGift(target);
      } else if (item.itemType == 'blind_box') {
        final reward = await widget.controller.openBlindBox();
        if (mounted) {
          await _showNovelSheet<void>(
            context,
            heightFactor: .38,
            child: _SheetScaffold(
              title: '福袋已开启',
              subtitle: '命运给了你一份礼物',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      reward.type == 'score' ? Icons.star_rounded : Icons.redeem_outlined,
                      size: 38,
                      color: reward.type == 'score' ? const Color(0xFFF4C542) : NovelPalette.accent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reward.type == 'score'
                          ? '获得 ${reward.score} 积分'
                          : '获得 ${reward.name} ×1',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: NovelPalette.accent,
                          foregroundColor: NovelPalette.accentDark,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('收下'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      } else if (item.itemType == 'lucky_card') {
        widget.controller.toggleLuckyCard();
      }
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }
}

class _InventoryItemTile extends StatelessWidget {
  const _InventoryItemTile({
    required this.item,
    required this.fallback,
    required this.actionText,
    required this.loading,
    this.onAction,
  });

  final NovelInventoryItem item;
  final String fallback;
  final String actionText;
  final bool loading;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(.055)),
          ),
          clipBehavior: Clip.antiAlias,
          child: NovelArtwork(
            url: item.imageUrl,
            assetCandidates: <String>[
              if (item.itemType.trim().isNotEmpty)
                'assets/images/${item.itemType.trim()}.webp',
            ],
            fit: BoxFit.contain,
            fallbackText: fallback,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (item.quantity > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '×${item.quantity}',
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                item.description.trim().isEmpty
                    ? _inventoryTypeLabel(item.itemType)
                    : item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NovelPalette.muted,
                  fontSize: 10.8,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (actionText.isNotEmpty && onAction != null) ...<Widget>[
          const SizedBox(width: 12),
          TextButton(
            onPressed: loading ? null : onAction,
            style: TextButton.styleFrom(
              foregroundColor: NovelPalette.accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(48, 34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: loading
                ? const SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: NovelPalette.accent,
                    ),
                  )
                : Text(
                    actionText,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ],
    );
  }
}

String _inventoryTypeLabel(String type) {
  return switch (type) {
    'consumable' => '消耗品',
    'material' => '材料',
    'quest' => '任务物品',
    'gift' => '赠礼道具',
    'blind_box' => '福袋',
    'lucky_card' => '特殊道具',
    _ => '故事物品',
  };
}

class _InventoryTabBar extends StatelessWidget {
  const _InventoryTabBar({
    required this.selected,
    required this.storyCount,
    required this.consumableCount,
    required this.onChanged,
  });

  final int selected;
  final int storyCount;
  final int consumableCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(int index, String label, int count) {
      final active = selected == index;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(index),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: active ? NovelPalette.text : NovelPalette.muted,
                  fontSize: 13.4,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    color: active ? NovelPalette.text : NovelPalette.muted,
                    fontSize: 12.2,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        item(0, '故事物品', storyCount),
        const SizedBox(width: 24),
        item(1, '可使用', consumableCount),
      ],
    );
  }
}

Future<void> showNovelStoreSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await controller.refreshShop();
  if (!context.mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return _SheetScaffold(
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
          child: widget.controller.shopItems.isEmpty
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
        );
      },
    );
  }
}

Future<void> _pickNovelBackground(
  BuildContext context,
  NovelGameController controller,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty || !context.mounted) return;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法读取这张图片')),
    );
    return;
  }
  if (bytes.length > 2 * 1024 * 1024) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片请控制在 2MB 以内，避免本地设置过大')),
    );
    return;
  }
  final extension = (file.extension ?? 'png').toLowerCase();
  final mime = switch (extension) {
    'jpg' || 'jpeg' => 'jpeg',
    'webp' => 'webp',
    'gif' => 'gif',
    _ => 'png',
  };
  await controller.settings.setCustomBackground(
    'data:image/$mime;base64,${base64Encode(bytes)}',
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('自定义背景已应用')),
  );
}

Future<void> showNovelSettingsSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _showNovelEndDrawer<void>(
    context,
    child: _SettingsPanel(controller: controller),
  );
}

class _SettingsDrawerScaffold extends StatelessWidget {
  const _SettingsDrawerScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(4),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
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
          color: Colors.white.withOpacity(.12),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({required this.controller});
  final NovelGameController controller;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  NovelGameController get controller => widget.controller;

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
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
            children: <Widget>[
              const _CleanSettingsHeader(
                icon: Icons.palette_outlined,
                title: '画面风格',
                subtitle: '当前暂时锁定为动漫风格，其他画风稍后开放',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
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
                    const SizedBox(width: 10),
                    _ArtStyleCard(
                      label: '3D',
                      asset: 'assets/images/bg-3d.webp',
                      selected: false,
                      onTap: null,
                      lockedLabel: '暂未开放',
                    ),
                    const SizedBox(width: 10),
                    _ArtStyleCard(
                      label: '写实',
                      asset: 'assets/images/bg-realistic.webp',
                      selected: false,
                      onTap: null,
                      lockedLabel: '暂未开放',
                    ),
                    const SizedBox(width: 10),
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
              const SizedBox(height: 24),
              const _CleanSettingsHeader(
                icon: Icons.text_fields_rounded,
                title: '文字',
                subtitle: '只调整阅读本身，不再混入背景主题设置',
              ),
              const SizedBox(height: 10),
              _CleanSettingsCard(
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Text(
                          '字体大小',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${settings.fontSize.round()}',
                          style: TextStyle(
                            color: AppColors.textOnDark.withOpacity(.88),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        const Text('A', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: AppColors.accent,
                              inactiveTrackColor: Colors.white.withOpacity(.08),
                              thumbColor: AppColors.accent,
                              overlayColor: AppColors.accent.withOpacity(.08),
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
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
                        const Text('A', style: TextStyle(color: AppColors.textOnDark, fontSize: 18)),
                      ],
                    ),
                    Divider(height: 18, color: Colors.white.withOpacity(.14)),
                    Row(
                      children: <Widget>[
                        Expanded(child: _CleanSettingChoice(label: '黑体', selected: settings.fontKey == 'font-hei', onTap: () => settings.setFont('font-hei'))),
                        const SizedBox(width: 7),
                        Expanded(child: _CleanSettingChoice(label: '文楷', selected: settings.fontKey == 'font-wenkai', onTap: () => settings.setFont('font-wenkai'))),
                        const SizedBox(width: 7),
                        Expanded(child: _CleanSettingChoice(label: '宋体', selected: settings.fontKey == 'font-song', onTap: () => settings.setFont('font-song'))),
                        const SizedBox(width: 7),
                        Expanded(child: _CleanSettingChoice(label: 'MiSans', selected: settings.fontKey == 'font-misans', onTap: () => settings.setFont('font-misans'))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _CleanSettingsHeader(
                icon: Icons.tune_rounded,
                title: '声音与 AI',
                subtitle: '游戏过程中真正需要调整的选项',
              ),
              const SizedBox(height: 10),
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
                        activeColor: AppColors.accent,
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
                        activeColor: AppColors.accent,
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
                        activeColor: AppColors.accent,
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
                                child: Text(model.name, style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5)),
                              ))
                          .toList(),
                      child: _CleanSettingsRow(
                        icon: Icons.hub_outlined,
                        title: 'AI 引擎模型',
                        subtitle: _modelLabel(),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDarkMuted, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
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
    final disabled = onTap == null && !selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 108,
          height: 82,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(2),
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
                left: 8,
                bottom: 7,
                child: Text(
                  label,
                  style: TextStyle(
                    color: disabled ? Colors.white.withOpacity(.72) : Colors.white,
                    fontSize: 11.5,
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
                        margin: const EdgeInsets.only(top: 7, right: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.42),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withOpacity(.10)),
                        ),
                        child: Text(
                          lockedLabel ?? '已锁定',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.80),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Icon(
                    Icons.check_rounded,
                    size: 15,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.textOnDarkMuted.withOpacity(.88),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textOnDarkMuted.withOpacity(.86),
                  fontSize: 10.5,
                  height: 1.35,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
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
              fontSize: 11.3,
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
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 0, 10, 0),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: AppColors.textOnDarkMuted.withOpacity(.82),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textOnDarkMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
      ),
    );
  }
}

class _SettingRowHeader extends StatelessWidget {
  const _SettingRowHeader({required this.title, required this.trailing});
  final String title;
  final String trailing;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _SectionEyebrow(title)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            trailing,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: selected
                      ? AppColors.accent
                      : Colors.white.withOpacity(.11),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                'A',
                style: TextStyle(
                  color: color.computeLuminance() > .5 ? Colors.black87 : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textOnDark : AppColors.textOnDarkMuted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontChoice extends StatelessWidget {
  const _FontChoice({
    required this.char,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String char;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Column(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withOpacity(.10)
                    : Colors.white.withOpacity(.025),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? AppColors.accent.withOpacity(.48)
                      : Colors.white.withOpacity(.07),
                ),
              ),
              child: Text(
                char,
                style: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textOnDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textOnDark : AppColors.textOnDarkMuted,
                fontSize: 9.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLine extends StatelessWidget {
  const _SettingsLine({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.018),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(.065)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.accent.withOpacity(.78), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

Future<void> showNovelHostProfileSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await controller.refreshCharacterStatus();
  if (!context.mounted) return;

  final host = controller.protagonist;

  // 主角档案与右侧“偏好设置”使用同一套抽屉容器：
  // 直角、暗色透明毛玻璃、主背景只压暗、不做全屏模糊。
  await _showNovelEndDrawer<void>(
    context,
    child: _SheetScaffold(
      title: '主角档案',
      subtitle: '当前身份与故事状态',
      child: _CharacterProfileBody(
        controller: controller,
        character: host,
        fallbackName: controller.protagonistName,
        condition: controller.protagonistCondition,
        isHostProfile: true,
      ),
    ),
  );
}

Future<void> showNovelCharactersSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  // 先进入角色页，再在页面首帧后刷新实时角色状态。
  await _showNovelArchivePage<void>(
    context,
    child: _ArchivePageScaffold(
      title: '角色档案',
      child: _CharactersPanel(controller: controller),
    ),
  );
}


class _CharactersPanel extends StatefulWidget {
  const _CharactersPanel({required this.controller});
  final NovelGameController controller;

  @override
  State<_CharactersPanel> createState() => _CharactersPanelState();
}

class _CharactersPanelState extends State<_CharactersPanel> {
  int filter = 0; // 0 全部 / 1 亲密 / 2 普通
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshCharacterStatus();
    if (mounted) setState(() => loading = false);
  }

  bool _isClose(NovelCharacter c) => c.affection >= 60;

  List<NovelCharacter> _applyFilter(List<NovelCharacter> source) {
    if (filter == 1) {
      return source.where(_isClose).toList();
    }
    if (filter == 2) {
      return source.where((c) => !_isClose(c)).toList();
    }
    return source;
  }

  String _summaryOf(NovelCharacter c) {
    final status = c.status;
    final persona = c.persona;
    final values = <String>[
      stringValue(status['description']),
      stringValue(persona['description']),
      stringValue(status['background']),
      stringValue(persona['background']),
      stringValue(status['personality']),
      stringValue(persona['personality']),
    ].where((e) => e.trim().isNotEmpty).toList();
    return values.isNotEmpty ? values.first : '暂无角色描述';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final characters = widget.controller.scenario?.characters.values.toList() ?? <NovelCharacter>[];
        characters.sort((a, b) {
          if (_isClose(a) != _isClose(b)) return _isClose(a) ? -1 : 1;
          return b.affection.compareTo(a.affection);
        });

        if (characters.isEmpty) {
          return _EmptyState(text: loading ? '正在整理角色档案…' : '还没有角色资料');
        }

        final closeCount = characters.where(_isClose).length;
        final normalCount = characters.length - closeCount;
        final filtered = _applyFilter(characters);

        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: <Widget>[
                  _ArchiveTopTab(
                    label: '全部',
                    count: characters.length,
                    selected: filter == 0,
                    onTap: () => setState(() => filter = 0),
                  ),
                  const SizedBox(width: 24),
                  _ArchiveTopTab(
                    label: '亲密',
                    count: closeCount,
                    selected: filter == 1,
                    onTap: () => setState(() => filter = 1),
                  ),
                  const SizedBox(width: 24),
                  _ArchiveTopTab(
                    label: '普通',
                    count: normalCount,
                    selected: filter == 2,
                    onTap: () => setState(() => filter = 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            if (loading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: NovelPalette.accent,
                  ),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState(text: '当前筛选下暂无角色')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 110),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        return _ArchiveCharacterCard(
                          character: c,
                          summary: _summaryOf(c),
                          onTap: () => showNovelNpcProfileSheet(
                            context,
                            widget.controller,
                            c,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ArchiveTopTab extends StatelessWidget {
  const _ArchiveTopTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? NovelPalette.text : NovelPalette.muted.withOpacity(.90);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13.8,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCharacterCard extends StatelessWidget {
  const _ArchiveCharacterCard({
    required this.character,
    required this.summary,
    required this.onTap,
  });

  final NovelCharacter character;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.png';
    final relationLabel = character.isMain ? '主角' : (character.affection >= 60 ? '亲密' : '普通');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.025),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 88,
                height: 122,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.28),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: character.avatarUrl.isNotEmpty ? character.avatarUrl : character.portraitUrl,
                  assetCandidates: <String>[fallbackAsset],
                  fit: BoxFit.cover,
                  fallbackText: character.name,
                  fallbackIcon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 122,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              character.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: NovelPalette.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.open_in_full_rounded,
                            size: 16,
                            color: Colors.white.withOpacity(.84),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: NovelPalette.text.withOpacity(.76),
                            fontSize: 11.8,
                            height: 1.58,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Text(
                            '关系： ${character.affection}',
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 12.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            constraints: const BoxConstraints(minWidth: 86),
                            height: 32,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              relationLabel,
                              style: const TextStyle(
                                color: NovelPalette.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

Future<void> showNovelNpcProfileSheet(
  BuildContext context,
  NovelGameController controller,
  NovelCharacter character,
) async {
  await controller.refreshCharacterStatus();
  if (!context.mounted) return;

  var current = character;
  for (final item in controller.scenario?.characters.values ?? const <NovelCharacter>[]) {
    if ((character.id.isNotEmpty && item.id == character.id) || item.name == character.name) {
      current = item;
      break;
    }
  }
  final identity = stringValue(current.status['identity']);
  await _showNovelArchivePage<void>(
    context,
    child: _ArchivePageScaffold(
      title: current.isMain ? '主角档案' : '角色档案',
      child: _CharacterProfileBody(
        controller: controller,
        character: current,
        fallbackName: current.name,
        condition: identity,
        isHostProfile: current.isMain,
      ),
    ),
  );
}

class _CharacterProfileBody extends StatelessWidget {
  const _CharacterProfileBody({
    super.key,
    required this.controller,
    required this.character,
    required this.fallbackName,
    required this.condition,
    this.isHostProfile = false,
  });

  final NovelGameController controller;
  final NovelCharacter? character;
  final String fallbackName;
  final String condition;
  final bool isHostProfile;

  Color _conditionColor(String condition) {
    final v = condition.toLowerCase();
    if (v.contains('濒死') || v.contains('dying') || v.contains('near_death')) {
      return const Color(0xFFB18AA6);
    }
    if (v.contains('重伤') || v.contains('heavy')) {
      return const Color(0xFFE07A78);
    }
    if (v.contains('轻伤') || v.contains('light')) {
      return const Color(0xFFD4A373);
    }
    return const Color(0xFF91B79A);
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => stringValue(e))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = character;
    final status = c?.status ?? const <String, dynamic>{};
    final persona = c?.persona ?? const <String, dynamic>{};

    final name =
        c?.name.trim().isNotEmpty == true ? c!.name : fallbackName;
    final avatar = c?.avatarUrl.isNotEmpty == true
        ? c!.avatarUrl
        : c?.portraitUrl ?? '';

    final fallbackAsset = c?.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.png';

    final identity = stringValue(status['identity']);
    final level = stringValue(status['level']);
    final deathCount = intValue(status['death_count'], -1);
    final combatPower = stringValue(status['combat_power']);
    final rawCondition =
        stringValue(status['current_condition'], condition);

    final personality =
        stringValue(status['personality'] ?? persona['personality']);
    final background =
        stringValue(status['background'] ?? persona['background']);
    final description =
        stringValue(status['description'] ?? persona['description']);
    final appearance =
        stringValue(status['appearance'] ?? persona['appearance']);

    final injuries = _stringList(status['injuries']);
    final limits = _stringList(status['known_limits']);
    final conditionColor = _conditionColor(rawCondition);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
      children: <Widget>[
        // 顶部人物信息：靠留白和明暗分层，不用线框。
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Colors.white.withOpacity(.035),
              ),
              clipBehavior: Clip.antiAlias,
              child: NovelArtwork(
                url: avatar,
                assetCandidates: <String>[fallbackAsset],
                fit: BoxFit.cover,
                fallbackText: name,
                fallbackIcon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NovelPalette.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: <Widget>[
                      if (identity.isNotEmpty)
                        _ProfileMetaText(identity),
                      if (c?.gender.isNotEmpty == true)
                        _ProfileMetaText(c!.gender),
                      if (level.isNotEmpty)
                        _ProfileMetaText('境界 · $level'),
                      if (deathCount >= 0)
                        _ProfileMetaText(
                          '轮回 · $deathCount',
                          danger: deathCount > 0,
                        ),
                      if (c != null && !c.isMain)
                        _ProfileMetaText(
                          '${c.affectionLabel.isEmpty ? '好感' : c.affectionLabel} · ${c.affection}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        if (rawCondition.isNotEmpty ||
            combatPower.isNotEmpty ||
            injuries.isNotEmpty ||
            limits.isNotEmpty)
          _ProfileLineSection(
            title: '状态',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 5,
                      height: 5,
                      color: conditionColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rawCondition.isEmpty ? '状态未知' : rawCondition,
                        style: TextStyle(
                          color: conditionColor,
                          fontSize: 12.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (combatPower.isNotEmpty)
                      Text(
                        '战力 $combatPower',
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 10.8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                if (injuries.isNotEmpty || limits.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  ...injuries.map(
                    (text) => _ProfileStatusLine(
                      text: text,
                      color: const Color(0xFFC98582),
                    ),
                  ),
                  ...limits.map(
                    (text) => _ProfileStatusLine(
                      text: '限制：$text',
                      color: NovelPalette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),

        if (personality.isNotEmpty)
          _ProfileLineSection(
            title: '性格特征',
            child: _ProfileParagraph(personality),
          ),

        if (background.isNotEmpty)
          _ProfileLineSection(
            title: isHostProfile ? '身世' : '人物背景',
            child: _ProfileParagraph(background),
          ),

        if (description.isNotEmpty)
          _ProfileLineSection(
            title: isHostProfile ? '阅历' : '人物简介',
            child: _ProfileParagraph(description),
          ),

        if (appearance.isNotEmpty)
          _ProfileLineSection(
            title: '外貌设定',
            child: _ProfileParagraph(appearance),
          ),

        // 立绘单独作为详情底部的一栏：头像仍在顶部，立绘预览与生成操作放在这里。
        if (c != null) ...<Widget>[
          const SizedBox(height: 18),
          _InlineCharacterVisualEditor(
            controller: controller,
            character: c,
          ),
        ],
      ],
    );
  }
}

class _ProfileLineSection extends StatelessWidget {
  const _ProfileLineSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: NovelPalette.muted.withOpacity(.90),
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              letterSpacing: .55,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _ProfileMetaText extends StatelessWidget {
  const _ProfileMetaText(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color:
            danger ? const Color(0xFFC98582) : NovelPalette.muted,
        fontSize: 10.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ProfileStatusLine extends StatelessWidget {
  const _ProfileStatusLine({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 3,
              height: 3,
              color: color.withOpacity(.70),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11.3,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileParagraph extends StatelessWidget {
  const _ProfileParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.left,
      style: TextStyle(
        color: NovelPalette.text.withOpacity(.74),
        fontSize: 11.8,
        height: 1.72,
      ),
    );
  }
}


class _InlineCharacterVisualEditor extends StatefulWidget {
  const _InlineCharacterVisualEditor({
    required this.controller,
    required this.character,
  });

  final NovelGameController controller;
  final NovelCharacter character;

  @override
  State<_InlineCharacterVisualEditor> createState() =>
      _InlineCharacterVisualEditorState();
}

class _InlineCharacterVisualEditorState
    extends State<_InlineCharacterVisualEditor> {
  late final TextEditingController _promptController;

  late String _imageStyle;
  late String _portraitUrl;
  late String _avatarUrl;

  // 用于判断“是否真的改过”。
  // 没发生变化时，页面完全不显示保存按钮。
  late String _savedPortraitUrl;
  late String _savedAvatarUrl;

  Uint8List? _localBytes;
  String _localFilename = '';
  String _localContentType = '';

  bool _generating = false;
  bool _saving = false;
  String _errorText = '';

  bool get _hasPortrait =>
      _localBytes != null || _portraitUrl.trim().isNotEmpty;

  bool get _hasPendingChanges =>
      _localBytes != null ||
      _portraitUrl != _savedPortraitUrl ||
      _avatarUrl != _savedAvatarUrl;

  @override
  void initState() {
    super.initState();

    // 角色完整资料由 Controller 自动整理成 Character Brief。
    // 这里仅填写“本次额外形象调整”，留空也可以直接生成。
    _promptController = TextEditingController();

    _imageStyle = 'anime';

    _portraitUrl = widget.character.portraitUrl;
    _avatarUrl = widget.character.avatarUrl;

    _savedPortraitUrl = _portraitUrl;
    _savedAvatarUrl = _avatarUrl;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalImage() async {
    if (_generating || _saving) return;

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.size > 12 * 1024 * 1024) {
      setState(() {
        _errorText = '图片请控制在 12MB 以内';
      });
      return;
    }

    setState(() {
      _localBytes = file.bytes;
      _localFilename = file.name;
      _localContentType = _imageContentType(file.name);
      _errorText = '';
    });
  }

  Future<void> _generatePortrait() async {
    if (_generating || _saving) return;

    final prompt = _promptController.text.trim();

    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final result = await widget.controller.generatePortrait(
        character: widget.character,
        prompt: prompt,
        style: 'anime',
      );

      if (!mounted) return;

      // AI 生成只先进入预览状态。
      // 只有用户确认保存后，才调用 updateCharacterVisuals。
      setState(() {
        _portraitUrl = result.portraitUrl;
        _avatarUrl = result.avatarUrl;
        _localBytes = null;
        _localFilename = '';
        _localContentType = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '生成立绘失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _savePortrait() async {
    if (_generating || _saving || !_hasPendingChanges) return;

    if (!_hasPortrait) {
      setState(() {
        _errorText = '请先上传或生成一张立绘';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = '';
    });

    try {
      var finalPortrait = _portraitUrl;
      var finalAvatar = _avatarUrl;

      if (_localBytes != null) {
        finalPortrait = await widget.controller.uploadCharacterImage(
          bytes: _localBytes!,
          filename:
              _localFilename.isEmpty ? 'portrait.jpg' : _localFilename,
          contentType: _localContentType.isEmpty
              ? 'image/jpeg'
              : _localContentType,
        );

        // 当前没有独立头像时，上传的立绘同时作为头像兜底。
        if (finalAvatar.trim().isEmpty ||
            finalAvatar == widget.character.avatarUrl) {
          finalAvatar = finalPortrait;
        }
      }

      await widget.controller.updateCharacterVisuals(
        character: widget.character,
        portraitUrl: finalPortrait,
        avatarUrl: finalAvatar,
      );

      // 立绘保存属于原地编辑，不需要再额外弹“XXX 立绘已更新”状态提示。
      widget.controller.clearMessages();

      if (!mounted) return;

      setState(() {
        _portraitUrl = finalPortrait;
        _avatarUrl = finalAvatar;

        // 保存成功后更新“基准值”，保存按钮自动消失。
        _savedPortraitUrl = finalPortrait;
        _savedAvatarUrl = finalAvatar;

        _localBytes = null;
        _localFilename = '';
        _localContentType = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '保存失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildPreview() {
    if (_localBytes != null) {
      return Image.memory(
        _localBytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    if (_portraitUrl.trim().isNotEmpty) {
      return NovelArtwork(
        url: _portraitUrl,
        fit: BoxFit.contain,
        fallbackText: widget.character.name,
        fallbackIcon: Icons.person_outline_rounded,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_generating || _saving) ? null : _pickLocalImage,
        child: Center(
          child: Text(
            '暂无立绘，点击这里上传',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NovelPalette.muted.withOpacity(.78),
              fontSize: 11.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryGreen = NovelPalette.accent;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '形象设定',
            style: TextStyle(
              color: NovelPalette.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          // 上方只展示立绘，保持主角档案结构清楚。
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (_generating || _saving) ? null : _pickLocalImage,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 180,
                  height: 240,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.035),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withOpacity(.06),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _buildPreview(),
                      if (_generating)
                        ColoredBox(
                          color: Colors.black.withOpacity(.42),
                          child: const Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryGreen,
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
          if (_hasPortrait) ...<Widget>[
            const SizedBox(height: 7),
            Center(
              child: Text(
                '点击立绘可更换',
                style: TextStyle(
                  color: NovelPalette.muted.withOpacity(.62),
                  fontSize: 10.2,
                ),
              ),
            ),
          ],

          const SizedBox(height: 22),

          // 立绘下面才显示当前画风。
          Text(
            '当前画风',
            style: TextStyle(
              color: NovelPalette.muted.withOpacity(.82),
              fontSize: 10.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _VisualStyleChoice(
                label: '动漫',
                selected: true,
                onTap: (_generating || _saving)
                    ? null
                    : () => setState(() => _imageStyle = 'anime'),
              ),
              const SizedBox(width: 8),
              const _VisualStyleChoice(
                label: '3D（已锁定）',
                selected: false,
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '立绘会自动读取完整角色资料；下方只需填写本次想额外调整的方向。',
            style: TextStyle(
              color: NovelPalette.muted.withOpacity(.58),
              fontSize: 10.2,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            '额外形象要求（可选）',
            style: TextStyle(
              color: NovelPalette.muted.withOpacity(.82),
              fontSize: 10.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.028),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white.withOpacity(.055)),
            ),
            child: TextField(
              controller: _promptController,
              enabled: !_generating && !_saving,
              minLines: 3,
              maxLines: 5,
              cursorColor: primaryGreen,
              style: const TextStyle(
                color: NovelPalette.text,
                fontSize: 12,
                height: 1.5,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '留空按角色完整设定生成；例如：裙摆更轻盈、气质更清冷、仙气更强……',
                hintStyle: TextStyle(
                  color: NovelPalette.muted.withOpacity(.46),
                  fontSize: 11,
                ),
              ),
            ),
          ),

          if (_errorText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _errorText,
              style: const TextStyle(
                color: Color(0xFFE07A78),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 只用文字按钮，不再放魔法、相机、勾选等装饰图标。
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(.08),
                foregroundColor: NovelPalette.text,
                disabledBackgroundColor: Colors.white.withOpacity(.035),
                disabledForegroundColor: NovelPalette.muted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: (_generating || _saving) ? null : _generatePortrait,
              child: _generating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: NovelPalette.text,
                      ),
                    )
                  : const Text(
                      '生成立绘',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          if (_hasPendingChanges) ...<Widget>[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: primaryGreen.withOpacity(.28),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                onPressed: (_generating || _saving) ? null : _savePortrait,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        '保存立绘',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VisualStyleChoice extends StatelessWidget {
  const _VisualStyleChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !selected;
    return Material(
      color: selected
          ? Colors.white.withOpacity(.10)
          : disabled
              ? Colors.white.withOpacity(.015)
              : Colors.white.withOpacity(.025),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? NovelPalette.text
                  : disabled
                      ? NovelPalette.muted.withOpacity(.42)
                      : NovelPalette.muted,
              fontSize: 11.5,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSoftAction extends StatelessWidget {
  const _ProfileSoftAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: primary
          ? NovelPalette.accent.withOpacity(enabled ? 1 : .25)
          : Colors.white.withOpacity(enabled ? .055 : .025),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (loading)
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    color: primary
                        ? NovelPalette.accentDark
                        : NovelPalette.text,
                  ),
                )
              else
                Icon(
                  icon,
                  size: 15,
                  color: primary
                      ? NovelPalette.accentDark
                      : NovelPalette.muted,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary
                        ? NovelPalette.accentDark
                        : (enabled
                            ? NovelPalette.text
                            : NovelPalette.muted),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
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

Future<void> showNovelPortraitSheet(
  BuildContext context,
  NovelGameController controller, {
  NovelCharacter? character,
}) async {
  final target =
      character ?? controller.currentSpeakerCharacter ?? controller.protagonist;

  if (target == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前没有可编辑的角色')),
    );
    return;
  }

  // 角色完整资料由 Controller 自动整理成 Character Brief。
  // 这里仅填写“本次额外形象调整”，留空也可以直接生成。
  final promptController = TextEditingController();

  var imageStyle = 'anime';

  var portraitUrl = target.portraitUrl;
  var avatarUrl = target.avatarUrl;

  var savedPortraitUrl = portraitUrl;
  var savedAvatarUrl = avatarUrl;

  Uint8List? localBytes;
  String localFilename = '';
  String localContentType = '';

  var generating = false;
  var saving = false;
  var errorText = '';

  bool hasPortrait() =>
      localBytes != null || portraitUrl.trim().isNotEmpty;

  bool hasPendingChanges() =>
      localBytes != null ||
      portraitUrl != savedPortraitUrl ||
      avatarUrl != savedAvatarUrl;

  try {
    await _showNovelArchivePage<void>(
      context,
      child: StatefulBuilder(
        builder: (pageContext, setState) {
          Future<void> pickLocalImage() async {
            if (generating || saving) return;

            final result = await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: false,
              withData: true,
            );

            final file = result?.files.single;
            if (file == null || file.bytes == null) return;
            if (!pageContext.mounted) return;

            if (file.size > 12 * 1024 * 1024) {
              setState(() => errorText = '图片请控制在 12MB 以内');
              return;
            }

            setState(() {
              localBytes = file.bytes;
              localFilename = file.name;
              localContentType = _imageContentType(file.name);
              errorText = '';
            });
          }

          Future<void> generateImage() async {
            if (generating || saving) return;

            final prompt = promptController.text.trim();

            setState(() {
              generating = true;
              errorText = '';
            });

            try {
              final result = await controller.generatePortrait(
                character: target,
                prompt: prompt,
                style: 'anime',
              );

              if (!pageContext.mounted) return;

              setState(() {
                portraitUrl = result.portraitUrl;
                avatarUrl = result.avatarUrl;
                localBytes = null;
                localFilename = '';
                localContentType = '';
              });
            } catch (error) {
              if (!pageContext.mounted) return;
              setState(() {
                errorText = error is NovelBackendException
                    ? error.message
                    : '生成立绘失败：$error';
              });
            } finally {
              if (pageContext.mounted) {
                setState(() => generating = false);
              }
            }
          }

          Future<void> saveImage() async {
            if (generating || saving || !hasPendingChanges()) return;

            // 在异步保存开始前拿到稳定的 NavigatorState。
            // 后面不再通过可能正在 deactivate 的 BuildContext 重新查 Navigator。
            final pageNavigator = Navigator.of(pageContext);

            if (!hasPortrait()) {
              setState(() => errorText = '请先上传或生成一张立绘');
              return;
            }

            setState(() {
              saving = true;
              errorText = '';
            });

            try {
              var finalPortrait = portraitUrl;
              var finalAvatar = avatarUrl;

              if (localBytes != null) {
                finalPortrait = await controller.uploadCharacterImage(
                  bytes: localBytes!,
                  filename:
                      localFilename.isEmpty ? 'portrait.jpg' : localFilename,
                  contentType: localContentType.isEmpty
                      ? 'image/jpeg'
                      : localContentType,
                );

                if (finalAvatar.trim().isEmpty ||
                    finalAvatar == target.avatarUrl) {
                  finalAvatar = finalPortrait;
                }
              }

              await controller.updateCharacterVisuals(
                character: target,
                portraitUrl: finalPortrait,
                avatarUrl: finalAvatar,
              );

              // 快捷更换立绘成功后不需要顶部再显示“XXX 立绘已更新”。
              controller.clearMessages();

              if (!pageContext.mounted) return;

              // 先把当前页面的本地状态完整收尾，再退出路由。
              // 避免 Navigator.pop() 已经开始 deactivate 页面后，finally 又 setState，
              // 从而触发 Flutter InheritedElement 的 _dependents.isEmpty 断言。
              setState(() {
                savedPortraitUrl = finalPortrait;
                savedAvatarUrl = finalAvatar;
                portraitUrl = finalPortrait;
                avatarUrl = finalAvatar;
                localBytes = null;
                localFilename = '';
                localContentType = '';
                saving = false;
              });

              // updateCharacterVisuals 会通知剧情页重建。
              // 等本帧完成再退页；直接使用异步开始前捕获的 NavigatorState，
              // 避免在页面 deactivate 过程中重新从 context 查找 InheritedWidget。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!pageNavigator.mounted) return;
                if (pageNavigator.canPop()) pageNavigator.pop();
              });
            } catch (error) {
              if (!pageContext.mounted) return;
              setState(() {
                saving = false;
                errorText = error is NovelBackendException
                    ? error.message
                    : '保存失败：$error';
              });
            }
          }

          Widget buildPreview() {
            if (localBytes != null) {
              return Image.memory(
                localBytes!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              );
            }

            if (portraitUrl.trim().isNotEmpty) {
              return NovelArtwork(
                url: portraitUrl,
                fit: BoxFit.contain,
                fallbackText: target.name,
                fallbackIcon: Icons.person_outline_rounded,
              );
            }

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: (generating || saving) ? null : pickLocalImage,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 26,
                        color: NovelPalette.muted.withOpacity(.60),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '点击上传',
                        style: TextStyle(
                          color: NovelPalette.text.withOpacity(.82),
                          fontSize: 11.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '或在下方生成新的立绘',
                        style: TextStyle(
                          color: NovelPalette.muted.withOpacity(.58),
                          fontSize: 10.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _ArchivePageScaffold(
            title: '生成立绘',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final previewHeight = compact ? 240.0 : 280.0;

                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    8,
                    compact ? 16 : 28,
                    40,
                  ),
                  children: <Widget>[
                    // 角色信息只保留最必要的一行，避免页面像表单。
                    Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: NovelArtwork(
                              url: target.avatarUrl.isNotEmpty
                                  ? target.avatarUrl
                                  : target.portraitUrl,
                              fit: BoxFit.cover,
                              fallbackText: target.name,
                              fallbackIcon: Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            target.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          target.isMain ? '主角' : '角色',
                          style: TextStyle(
                            color: NovelPalette.muted.withOpacity(.58),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // 预览是页面主体，不再用厚重卡片或多余边框。
                    Container(
                      height: previewHeight,
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.022),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          buildPreview(),

                          if (generating)
                            ColoredBox(
                              color: Colors.black.withOpacity(.38),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.7,
                                        color: NovelPalette.text,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '正在生成…',
                                      style: TextStyle(
                                        color:
                                            NovelPalette.text.withOpacity(.86),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (hasPortrait() && !generating)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Material(
                                color: Colors.black.withOpacity(.28),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: saving ? null : pickLocalImage,
                                  customBorder: const CircleBorder(),
                                  child: SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: Icon(
                                      Icons.photo_camera_back_outlined,
                                      size: 16,
                                      color:
                                          NovelPalette.text.withOpacity(.88),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 画风使用轻量选择，不再用大块 SegmentedButton。
                    // 仅保留动漫和3D选项，去掉占空间的文字
                    Row(
                      children: <Widget>[
                        _VisualStyleChoice(
                          label: '动漫',
                          selected: true,
                          onTap: (generating || saving)
                              ? null
                              : () => setState(() => imageStyle = 'anime'),
                        ),
                        const SizedBox(width: 8),
                        const _VisualStyleChoice(
                          label: '3D（已锁定）',
                          selected: false,
                          onTap: null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '立绘会自动读取完整角色资料；下方只需填写本次想额外调整的方向。',
                      style: TextStyle(
                        color: NovelPalette.muted.withOpacity(.58),
                        fontSize: 10.2,
                      ),
                    ),

                    const SizedBox(height: 16),

      

                    Text(
                      '额外形象要求（可选）',
                      style: TextStyle(
                        color: NovelPalette.muted.withOpacity(.72),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.024),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: TextField(
                        controller: promptController,
                        enabled: !generating && !saving,
                        minLines: 3,
                        maxLines: 5,
                        cursorColor: NovelPalette.accent,
                        style: const TextStyle(
                          color: NovelPalette.text,
                          fontSize: 12.3,
                          height: 1.55,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText:
                              '留空按角色完整设定生成；例如：服装更轻盈、气质更清冷、减少华丽首饰…',
                          hintStyle: TextStyle(
                            color: NovelPalette.muted.withOpacity(.46),
                            fontSize: 11.1,
                          ),
                        ),
                      ),
                    ),

                    if (errorText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 9),
                      Text(
                        errorText,
                        style: const TextStyle(
                          color: NovelPalette.danger,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _ProfileSoftAction(
                            icon: Icons.auto_awesome_rounded,
                            label: generating ? '生成中…' : '生成立绘',
                            loading: generating,
                            onTap: (generating || saving)
                                ? null
                                : generateImage,
                          ),
                        ),
                        if (hasPendingChanges()) ...<Widget>[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ProfileSoftAction(
                              icon: Icons.check_rounded,
                              label: saving ? '保存中…' : '保存',
                              loading: saving,
                              primary: true,
                              onTap: (generating || saving)
                                  ? null
                                  : saveImage,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  } finally {
    // Navigator.push() 的 Future 在 pop 后可能先完成，而路由的 reverse transition
    // 仍在使用 TextField。立即 dispose 会造成概率性“controller disposed”红屏。
    // 当前归档页 reverseTransitionDuration 为 220ms，留出额外余量后再释放。
    await Future<void>.delayed(const Duration(milliseconds: 320));
    promptController.dispose();
  }
}

String _imageContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

Future<void> showNovelJourneySheet(
  BuildContext context,
  NovelGameController controller,
) async {
  // 经历页立即打开；真正的数据请求放到页面首帧之后。
  await _showNovelArchivePage<void>(
    context,
    child: _ArchivePageScaffold(
      title: '经历',
      child: _JourneyPanel(controller: controller),
    ),
  );
}

Future<bool> showNovelRevertDialog(
  BuildContext context,
  NovelGameController controller,
) async {
  final result = await _showNovelSheet<bool>(
    context,
    heightFactor: .40,
    child: _SheetScaffold(
      title: '轮次回溯',
      subtitle: '返回上一轮会消耗 1 个钟表',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '确认返回到上一轮回合吗？',
              style: TextStyle(
                color: NovelPalette.text,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NovelPalette.muted,
                      side: BorderSide(color: Colors.white.withOpacity(.08)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: NovelPalette.accent,
                      foregroundColor: NovelPalette.accentDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('确认回溯'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (result == true) await controller.revertPreviousTurn();
  return result ?? false;
}

Future<bool> showNovelCharacterSetupDialog(
  BuildContext context,
  NovelGameController controller,
) async {
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

  var submitting = false;

  final started = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '确认角色',
    barrierColor: Colors.black.withOpacity(.82),
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
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withOpacity(.10),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(.42),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
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
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: NovelPalette.accent.withOpacity(.28),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: NovelArtwork(
                                  url: host?.avatarUrl.isNotEmpty == true
                                      ? host!.avatarUrl
                                      : host?.portraitUrl ?? '',
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
                                      '确认你的角色',
                                      style: TextStyle(
                                        color: NovelPalette.text,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .4,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '这是你在这个世界中的身份，确认后即可进入故事。',
                                      style: TextStyle(
                                        color: NovelPalette.muted.withOpacity(.86),
                                        fontSize: 11.5,
                                        height: 1.45,
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
                                color: NovelPalette.muted,
                                disabledColor: NovelPalette.muted,
                                iconSize: 20,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              _CharacterSetupMeta(text: gender),
                              if (age.isNotEmpty)
                                _CharacterSetupMeta(text: '$age 岁'),
                              if (appearance.isNotEmpty)
                                const _CharacterSetupMeta(text: '已有形象'),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '角色姓名',
                            style: TextStyle(
                              color: NovelPalette.text,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            maxLength: 10,
                            enabled: !submitting,
                            cursorColor: NovelPalette.accent,
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: host?.name.isNotEmpty == true
                                  ? host!.name
                                  : '输入姓名',
                              hintStyle: TextStyle(
                                color: NovelPalette.muted.withOpacity(.55),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(.035),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 13,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.09),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: NovelPalette.accent.withOpacity(.62),
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.06),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '角色背景',
                            style: TextStyle(
                              color: NovelPalette.text,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 170),
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.025),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withOpacity(.07),
                              ),
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                background,
                                style: TextStyle(
                                  color: NovelPalette.text.withOpacity(.70),
                                  fontSize: 12,
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: NovelPalette.accent,
                                foregroundColor: NovelPalette.accentDark,
                                disabledBackgroundColor:
                                    NovelPalette.accent.withOpacity(.45),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onPressed: submitting
                                  ? null
                                  : () async {
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
                                        letterSpacing: .5,
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
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: NovelPalette.muted.withOpacity(.92),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
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
        borderRadius: BorderRadius.circular(5),
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

Future<void> showNovelOpeningDialog(
  BuildContext context,
  NovelGameController controller,
) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '故事开场',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 1200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _NovelOpeningExperience(controller: controller);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
        child: child,
      );
    },
  );
}

class _NovelOpeningExperience extends StatefulWidget {
  const _NovelOpeningExperience({required this.controller});
  final NovelGameController controller;

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
    _paragraphs = source
        .split(RegExp(r'\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _breathe = Tween<double>(begin: .22, end: .80).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (mounted && _paragraphs.isNotEmpty) setState(() => _visibleCount = 1);
    });
  }

  bool get _finished => _paragraphs.isNotEmpty && _visibleCount >= _paragraphs.length;

  void _advance() {
    if (_closing) return;
    if (!_finished) {
      setState(() => _visibleCount += 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= pos.pixels) return;
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 680),
          curve: Curves.easeOutCubic,
        );
      });
      return;
    }
    _closing = true;
    Navigator.of(context).pop();
    unawaited(widget.controller.startNarrative());
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
    return Material(
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
                      'PROLOGUE / 序章',
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
                        physics: const NeverScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List<Widget>.generate(_paragraphs.length, (index) {
                              final visible = index < _visibleCount;
                              final current = index == _visibleCount - 1;
                              return AnimatedOpacity(
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutCubic,
                                opacity: visible ? (current ? .96 : .34) : 0,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 900),
                                  curve: Curves.easeOutCubic,
                                  offset: visible ? Offset.zero : const Offset(0, .06),
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
    );
  }
}

Future<void> showNovelFateRevertDialog(
  BuildContext context,
  NovelGameController controller,
) async {
  final data = controller.fateRevert;
  await _showNovelSheet<void>(
    context,
    heightFactor: .48,
    child: _SheetScaffold(
      title: '命运回溯',
      subtitle: '死亡并非终点',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              data.message.isEmpty
                  ? '命运将你送回故事仍可改变之处。'
                  : data.message,
              style: const TextStyle(
                color: NovelPalette.muted,
                fontSize: 12,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.018),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withOpacity(.07)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '死亡次数  ${data.deathCount}',
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  Text(
                    '扣除 ${data.scoreDeduct}',
                    style: const TextStyle(
                      color: NovelPalette.danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 42,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NovelPalette.accent,
                  foregroundColor: NovelPalette.accentDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  controller.acceptFateRevert();
                },
                child: const Text('接受命运'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showDefaultNovelEnding(
  BuildContext context,
  NovelGameController controller,
) async {
  final ending = controller.ending;
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

/// 从右侧滑出的设置抽屉。
/// 视觉规则与左侧 GameDrawer 镜像统一：
/// - 直角
/// - 抽屉自身毛玻璃
/// - 10% 白色透明叠层
/// - 内侧一条细分隔线
/// - 抽屉外主游戏画面只压暗，不做全屏模糊
Future<T?> _showNovelEndDrawer<T>(
  BuildContext context, {
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭面板',

    // 对齐左侧 Drawer 打开后的主背景压暗感。
    // 只作用在抽屉外部，不会把主场景做毛玻璃。
    barrierColor: Colors.black.withOpacity(.78),

    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, __) {
      final media = MediaQuery.of(dialogContext);

      // 与左侧 GameDrawer 完全一致：屏幕宽度 82%，最大 300。
      final width = math.min(media.size.width * .82, 300.0);

      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: media.size.height,
          child: Material(
            color: Colors.transparent,
            child: _EndDrawerFrame(child: child),
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

      // 右侧镜像左侧抽屉：水平滑入，不缩放、不做弹窗式动画。
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _EndDrawerFrame extends StatelessWidget {
  const _EndDrawerFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 非常关键：
    // 用 ClipRect 把 BackdropFilter 严格限制在“右侧抽屉本身”的矩形范围内。
    // Chrome/Web 下如果不裁剪，BackdropFilter 可能让整个主游戏画面看起来都被模糊。
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          // 与左侧 GameDrawer 保持一致：
          // 使用轻微的白色透明叠层，而不是更重的黑色压暗层。
          color: const Color.fromARGB(255, 253, 253, 253).withOpacity(0.1),
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: NovelPalette.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(.08),
              width: 1,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}


class _ArchivePageScaffold extends StatelessWidget {
  const _ArchivePageScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: SizedBox(
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(3),
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: NovelPalette.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                trailing!,
                const SizedBox(width: 6),
              ],
              _PanelCloseButton(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withOpacity(.05),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PanelCloseButton extends StatelessWidget {
  const _PanelCloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: NovelPalette.muted,
          ),
        ),
      ),
    );
  }
}

class _MiniTabs extends StatelessWidget {
  const _MiniTabs({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final int selected;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(labels.length, (index) {
          final active = index == selected;
          return Material(
            color: active
                ? NovelPalette.accent.withOpacity(.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => onChanged(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      color:
                          active ? NovelPalette.accent : NovelPalette.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          decoration: BoxDecoration(
            color: NovelPalette.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.number,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? number;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: highlighted
                ? NovelPalette.accent.withOpacity(.055)
                : Colors.white.withOpacity(.018),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: highlighted
                  ? NovelPalette.accent.withOpacity(.25)
                  : Colors.white.withOpacity(.07),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: highlighted
                      ? NovelPalette.accent.withOpacity(.10)
                      : Colors.white.withOpacity(.025),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: highlighted
                        ? NovelPalette.accent.withOpacity(.16)
                        : Colors.white.withOpacity(.055),
                  ),
                ),
                child: number != null
                    ? Text(
                        '$number',
                        style: const TextStyle(
                          color: NovelPalette.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Icon(icon, color: NovelPalette.accent, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: NovelPalette.text,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: NovelPalette.muted,
                size: 16,
              ),
            ],
          ),
        ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withOpacity(.055)
            : Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.035),
                  borderRadius: BorderRadius.circular(6),
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
                  right: -5,
                  bottom: -5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 19,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      style: TextStyle(
                        color: NovelPalette.text,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NovelPalette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description.trim().isEmpty ? _itemTypeLabel(itemType) : description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.7,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (actionText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 10),
            Material(
              color: Colors.white.withOpacity(.09),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: loading ? null : onAction,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 62),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: showPointIcon
                          ? Colors.white.withOpacity(.09)
                          : NovelPalette.accent.withOpacity(.19),
                    ),
                  ),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.8, color: NovelPalette.accent),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (showPointIcon) ...<Widget>[
                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF4C542)),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              actionText,
                              style: TextStyle(
                                color: showPointIcon ? NovelPalette.text : NovelPalette.accent,
                                fontSize: 11,
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

class _FallbackLetter extends StatelessWidget {
  const _FallbackLetter(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(value, style: const TextStyle(color: NovelPalette.accent, fontSize: 20, fontWeight: FontWeight.w800)));
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(color: NovelPalette.text, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.018),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(.07)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: NovelPalette.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.character, required this.fallbackName});
  final NovelCharacter? character;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: Colors.white.withOpacity(.025),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: character?.avatarUrl.isNotEmpty == true
              ? Image.network(
                  character!.avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.person_outline_rounded,
                    color: NovelPalette.muted,
                  ),
                )
              : const Icon(
                  Icons.person_outline_rounded,
                  color: NovelPalette.muted,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                character?.name ?? fallbackName,
                style: const TextStyle(
                  color: NovelPalette.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                [character?.gender ?? '', stringValue(character?.persona['age'])]
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(
                  color: NovelPalette.muted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.016),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(.065)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: NovelPalette.muted,
              fontSize: 10,
              letterSpacing: .6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character, this.onTap});
  final NovelCharacter character;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final relationship = character.affectionLabel.trim().isNotEmpty
        ? character.affectionLabel.trim()
        : (character.isMain ? '主角' : '故事角色');
    final progress = (character.affection.clamp(0, 100) / 100).toDouble();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.016),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.white.withOpacity(.065)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: character.isMain
                        ? NovelPalette.accent.withOpacity(.28)
                        : Colors.white.withOpacity(.07),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: character.avatarUrl.isNotEmpty
                      ? character.avatarUrl
                      : character.portraitUrl,
                  fit: BoxFit.cover,
                  fallbackText: character.name,
                  fallbackIcon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            character.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 13.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          relationship,
                          style: TextStyle(
                            color: character.isMain
                                ? NovelPalette.accent
                                : NovelPalette.muted,
                            fontSize: 9.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: 3,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white.withOpacity(.06),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  NovelPalette.accent.withOpacity(.82),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          character.isMain ? '—' : '${character.affection}',
                          style: TextStyle(
                            color: character.isMain
                                ? NovelPalette.muted
                                : NovelPalette.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (character.status.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 7),
                      Text(
                        stringValue(
                          character.status['latest_dynamic'] ??
                              character.status['status_text'] ??
                              character.status['mood'],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 9.8,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...<Widget>[
                const SizedBox(width: 7),
                Icon(
                  Icons.chevron_right_rounded,
                  color: NovelPalette.muted.withOpacity(.48),
                  size: 17,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _JourneyPanel extends StatefulWidget {
  const _JourneyPanel({required this.controller});
  final NovelGameController controller;

  @override
  State<_JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<_JourneyPanel> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshJourney();
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Column(
          children: <Widget>[
            if (loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: NovelPalette.accent,
                  ),
                ),
              ),
            Expanded(
              child: _JourneyBody(
                data: widget.controller.journey,
                loading: loading,
                onRefresh: _refresh,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JourneyBody extends StatelessWidget {
  const _JourneyBody({
    required this.data,
    required this.loading,
    required this.onRefresh,
  });

  final JsonMap data;
  final bool loading;
  final Future<void> Function() onRefresh;

  JsonMap _source() {
    // 某些后端版本会再包一层 journey / data。只展开真正的内容层，
    // 不把 scenario_id、success、code 这类元数据误当成“经历”。
    final nestedJourney = asJsonMap(data['journey']);
    if (nestedJourney.isNotEmpty) return nestedJourney;
    final nestedData = asJsonMap(data['data']);
    if (nestedData.isNotEmpty) return nestedData;
    return data;
  }

  List<dynamic> _listOf(JsonMap source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List && value.isNotEmpty) return value;
      if (value is Map && value.isNotEmpty) return value.values.toList();
    }
    return const <dynamic>[];
  }

  String _plainText(dynamic value) {
    if (value is String || value is num || value is bool) {
      return stringValue(value).trim();
    }
    return '';
  }

  String _entryText(dynamic raw) {
    if (raw == null) return '';
    if (raw is String || raw is num || raw is bool) {
      return stringValue(raw).trim();
    }
    final map = asJsonMap(raw);
    if (map.isEmpty) return '';

    final title = stringValue(
      map['event'] ??
          map['title'] ??
          map['name'] ??
          map['content'] ??
          map['text'] ??
          map['summary'],
    ).trim();
    final detail = stringValue(
      map['impact'] ??
          map['result'] ??
          map['description'] ??
          map['detail'] ??
          map['memory'],
    ).trim();
    final time = stringValue(
      map['chapter'] ?? map['time'] ?? map['date'] ?? map['turn_label'],
    ).trim();

    final core = title.isNotEmpty && detail.isNotEmpty && detail != title
        ? '$title：$detail'
        : (title.isNotEmpty ? title : detail);
    if (core.isEmpty) return '';
    return time.isEmpty ? core : '$time · $core';
  }

  @override
  Widget build(BuildContext context) {
    final source = _source();
    final title = _plainText(
      source['scenario_title'] ?? source['title'] ?? source['scenario_name'],
    );
    final summary = _plainText(
      source['journey_summary'] ??
          source['story_summary'] ??
          source['summary'] ??
          source['description'],
    );

    final achievements = _listOf(
      source,
      const <String>['key_achievements', 'achievements', 'important_experiences'],
    ).map(_entryText).where((e) => e.isNotEmpty).toList(growable: false);

    final events = _listOf(
      source,
      const <String>['triggered_events', 'events', 'event_history', 'timeline', 'records', 'journey'],
    ).map(_entryText).where((e) => e.isNotEmpty).toList(growable: false);

    final milestones = _listOf(
      source,
      const <String>['milestones', 'key_milestones', 'past_milestones'],
    ).map(_entryText).where((e) => e.isNotEmpty).toList(growable: false);

    final hasRealContent = summary.isNotEmpty ||
        achievements.isNotEmpty ||
        events.isNotEmpty ||
        milestones.isNotEmpty;

    if (!hasRealContent) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 32),
          children: <Widget>[
            Center(
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 30,
                    color: NovelPalette.muted.withOpacity(.55),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    loading ? '正在翻阅故事…' : '故事刚刚开始',
                    style: const TextStyle(
                      color: NovelPalette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!loading) ...<Widget>[
                    const SizedBox(height: 7),
                    const Text(
                      '新的经历会随着剧情推进记录在这里',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: NovelPalette.muted,
                        fontSize: 10.8,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.isEmpty ? '你的旅程' : title,
                  style: const TextStyle(
                    color: NovelPalette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  summary.isEmpty ? '故事留下的节点与记忆' : summary,
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.8,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          if (achievements.isNotEmpty)
            _JourneySectionCard(
              title: '重要经历',
              children: achievements
                  .map((item) => _JourneyBulletText(text: item))
                  .toList(),
            ),
          if (events.isNotEmpty)
            _JourneySectionCard(
              title: '事件轨迹',
              children: events
                  .map((item) => _JourneyBulletText(text: item))
                  .toList(),
            ),
          if (milestones.isNotEmpty)
            _JourneySectionCard(
              title: '关键节点',
              children: milestones
                  .map((item) => _JourneyBulletText(text: item))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _JourneySectionCard extends StatelessWidget {
  const _JourneySectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: NovelPalette.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _JourneyBulletText extends StatelessWidget {
  const _JourneyBulletText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              color: Colors.white.withOpacity(.55),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: NovelPalette.text.withOpacity(.76),
                fontSize: 11.8,
                height: 1.58,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyHeading extends StatelessWidget {
  const _JourneyHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          transform: Matrix4.rotationZ(.78),
          decoration: BoxDecoration(
            color: NovelPalette.accent.withOpacity(.88),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: NovelPalette.accent.withOpacity(.28),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            color: NovelPalette.text,
            fontSize: 12.8,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
      ],
    );
  }
}

class _JourneyNpcBlock extends StatelessWidget {
  const _JourneyNpcBlock({required this.npc});
  final JsonMap npc;
  @override
  Widget build(BuildContext context) {
    final name = stringValue(npc['char_name'] ?? npc['name'], '未知角色');
    final avatar = stringValue(npc['avatar'] ?? npc['avatar_url']);
    final events = npc['events'] is List
        ? (npc['events'] as List).map(stringValue).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: NovelPalette.accent.withOpacity(.55)),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: avatar,
                  fit: BoxFit.cover,
                  fallbackText: name,
                  fallbackIcon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 11),
              Text(
                name,
                style: const TextStyle(
                  color: NovelPalette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (events.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 18, top: 10),
              padding: const EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withOpacity(.10),
                    style: BorderStyle.solid,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final event in events)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        event,
                        style: const TextStyle(
                          color: NovelPalette.muted,
                          fontSize: 11.5,
                          height: 1.55,
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
}

class _DynamicValue extends StatelessWidget {
  const _DynamicValue({required this.value});
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (value as List)
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('· ${_dynamicText(item)}', style: const TextStyle(color: NovelPalette.text, height: 1.55)),
                ))
            .toList(),
      );
    }
    if (value is Map) {
      final map = asJsonMap(value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text('${_journeyTitle(entry.key)}：${_dynamicText(entry.value)}', style: const TextStyle(color: NovelPalette.text, height: 1.55)),
                ))
            .toList(),
      );
    }
    return Text(stringValue(value), style: const TextStyle(color: NovelPalette.text, height: 1.7));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.auto_stories_outlined, color: Colors.white.withOpacity(.18), size: 38),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(color: NovelPalette.muted, fontSize: 12.5)),
        ],
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
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
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

String _consumableAction(String type) {
  return switch (type) {
    'gift' => '赠送',
    'blind_box' => '开启',
    'lucky_card' => '启用',
    _ => '使用',
  };
}

String _journeyTitle(String key) {
  const labels = <String, String>{
    'summary': '旅程概述',
    'milestones': '重要记忆',
    'events': '命运节点',
    'triggered_events': '触发事件',
    'relationships': '人物关系',
    'current_task': '当前任务',
    'past_milestones': '往昔里程碑',
    'immutable_facts': '既定事实',
  };
  return labels[key] ?? key.replaceAll('_', ' ');
}

String _dynamicText(dynamic value) {
  if (value is Map) {
    final map = asJsonMap(value);
    return stringValue(map['label'] ?? map['display'] ?? map['text'] ?? map['name'] ?? map.values.join(' · '));
  }
  return stringValue(value);
}


class _CleanActionButton extends StatelessWidget {
  const _CleanActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.isPrimary = false,
    this.primaryColor = const Color(0xFF76B900),
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool isPrimary;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: isPrimary
          ? primaryColor.withOpacity(enabled ? 1 : 0.4)
          : Colors.white.withOpacity(enabled ? 0.06 : 0.02),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 32, // 更纤薄的按钮
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (loading)
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: isPrimary ? Colors.white : primaryColor,
                  ),
                )
              else
                Icon(
                  icon,
                  size: 13,
                  color: isPrimary ? Colors.white : Colors.white.withOpacity(0.8),
                ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : Colors.white.withOpacity(0.8),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
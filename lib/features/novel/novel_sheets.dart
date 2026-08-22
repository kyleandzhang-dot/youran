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

/// 防止背包 / 角色 / 经历 / 主角资料被连续点击后重复 push。
/// 锁从开始打开一直保持到对应页面真正关闭。
final Set<String> _novelSingleOpenPages = <String>{};

Future<void> _runNovelPageOnce(
  String pageKey,
  Future<void> Function() action,
) async {
  if (!_novelSingleOpenPages.add(pageKey)) return;
  try {
    await action();
  } finally {
    _novelSingleOpenPages.remove(pageKey);
  }
}

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
          // 将深色背景换为纯白，填满上下间隙
          backgroundColor: const Color(0xFFFFFFFF),
          // 移除 SafeArea，将安全区处理下放到 _GameStyleBackdrop 和 _CharacterArchiveBackground 中
          body: child,
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

class _ArchivePageScaffold extends StatelessWidget {
  const _ArchivePageScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFF151515);
    const textPrimary = Color(0xFFF2F2F2);
    const textMuted = Color(0xFF969696);

    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: SizedBox.expand(child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveEmptyState extends StatelessWidget {
  const _ArchiveEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF929292),
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ),
    );
  }
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
  await _runNovelPageOnce('inventory', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _GameStyleInventoryPage(controller: controller),
    );
  });
}

/// 主游戏底部 Tab 使用的背包页。
class NovelInventoryTab extends StatelessWidget {
  const NovelInventoryTab({
    super.key,
    required this.controller,
  });

  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    return _GameStyleInventoryPage(
      controller: controller,
      embedded: true,
    );
  }
}

/// 旧“状态”调用保留兼容，实际统一打开背包。
Future<void> showNovelPlayerStatusSheet(
  BuildContext context,
  NovelGameController controller,
) => showNovelInventorySheet(context, controller);

class _InventoryPanel extends StatefulWidget {
  const _InventoryPanel({required this.controller});
  final NovelGameController controller;

  @override
  State<_InventoryPanel> createState() => _InventoryPanelState();
}

class _PlayerSkillView {
  const _PlayerSkillView({
    required this.name,
    this.mastery = '',
    this.description = '',
    this.isAbility = false,
  });

  final String name;
  final String mastery;
  final String description;
  final bool isAbility;
}

class _InventoryPanelState extends State<_InventoryPanel> {
  String busy = '';
  bool loading = true;
  bool skillsExpanded = false;
  bool equippedExpanded = false;

  static const Set<String> _wearableTypes = <String>{
    'weapon', 'wearable', 'armor', 'accessory', 'head', 'face', 'upper', 'lower', 'feet', 'back', 'handheld'
  };

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
    await Future.wait<void>(<Future<void>>[
      widget.controller.refreshInventory(notify: false),
      widget.controller.refreshCharacterStatus(notify: false),
    ]);
    if (mounted) setState(() => loading = false);
  }

  List<NovelInventoryItem> _allItems(NovelInventoryData data) {
    final result = <NovelInventoryItem>[];
    final seen = <String>{};
    for (final item in <NovelInventoryItem>[
      ...data.storyItems,
      ...data.consumables,
    ]) {
      final key = item.id.trim().isNotEmpty
          ? 'id:${item.id.trim()}'
          : '${item.itemType.trim()}:${item.name.trim()}';
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  String _itemSlot(NovelInventoryItem item) {
    final raw = item.raw;
    final explicit = stringValue(raw['slot'] ?? raw['wear_slot']).trim().toLowerCase();
    if (explicit.isNotEmpty) {
      if (explicit.contains('头')) return 'head';
      if (explicit.contains('面')) return 'face';
      if (explicit.contains('上身') || explicit.contains('衣')) return 'upper';
      if (explicit.contains('下身') || explicit.contains('裤')) return 'lower';
      if (explicit.contains('脚') || explicit.contains('鞋')) return 'feet';
      if (explicit.contains('背') || explicit.contains('披风') || explicit.contains('翅膀')) return 'back';
      if (explicit.contains('手持') || explicit.contains('武器') || explicit == 'weapon') return 'handheld';
      if (explicit.contains('饰') || explicit.contains('首饰') || explicit.contains('项链') || explicit.contains('戒指')) return 'accessory';
      return explicit;
    }
    return switch (item.itemType.trim().toLowerCase()) {
      'weapon' => 'handheld',
      'wearable' || 'armor' => 'upper',
      'accessory' => 'accessory',
      _ => '',
    };
  }

  bool _isWearable(NovelInventoryItem item) {
    return item.isEquipped ||
        _wearableTypes.contains(item.itemType.trim().toLowerCase()) ||
        _itemSlot(item).isNotEmpty;
  }

  List<_PlayerSkillView> _skills(NovelCharacter? host) {
    final status = host?.status ?? const <String, dynamic>{};
    final result = <_PlayerSkillView>[];
    final names = <String>{};
    final rawSkills = status['skills'];
    if (rawSkills is List) {
      for (final raw in rawSkills) {
        if (raw is String) {
          final name = raw.trim();
          if (name.isNotEmpty && names.add(name)) {
            result.add(_PlayerSkillView(name: name));
          }
          continue;
        }
        if (raw is Map) {
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          final name = stringValue(map['name']).trim();
          if (name.isEmpty || !names.add(name)) continue;
          result.add(_PlayerSkillView(
            name: name,
            mastery: stringValue(map['mastery']).trim(),
            description: stringValue(map['description']).trim(),
          ));
        }
      }
    }

    final rawAbilities = status['abilities'];
    if (rawAbilities is List) {
      for (final raw in rawAbilities) {
        final name = stringValue(raw).trim();
        if (name.isNotEmpty && names.add(name)) {
          result.add(_PlayerSkillView(name: name, isAbility: true));
        }
      }
    }
    return result;
  }

  Future<void> _toggleWear(NovelInventoryItem item) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = item.id);
    try {
      await widget.controller.setEquipped(item, !item.isEquipped);
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  Future<void> _handleItem(NovelInventoryItem item) async {
    if (busy.isNotEmpty) return;
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
            title: '赠送道具',
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
        if (mounted) _showRewardDialog(reward);
      } else if (item.itemType == 'lucky_card') {
        widget.controller.toggleLuckyCard();
      }
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  void _showRewardDialog(NovelBlindBoxReward reward) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '开启结果',
      barrierColor: Colors.black.withOpacity(0.65),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NovelPalette.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(.1)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 10)),
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: NovelPalette.accent.withOpacity(0.15), 
                    shape: BoxShape.circle,
                    border: Border.all(color: NovelPalette.accent.withOpacity(0.3))
                  ),
                  child: Icon(reward.type == 'score' ? Icons.star_rounded : Icons.redeem_outlined, color: NovelPalette.accent, size: 28),
                ),
                const SizedBox(height: 16),
                const Text('开启成功', style: TextStyle(color: NovelPalette.text, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  reward.type == 'score' ? '获得 ${reward.score} 积分' : '获得 ${reward.name} ×1',
                  style: const TextStyle(color: NovelPalette.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: NovelPalette.accent,
                      foregroundColor: NovelPalette.accentDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('收下', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                )
              ]
            ),
          )
        )
      )
    );
  }

  Color _conditionColor(String condition) {
    final c = condition.toLowerCase();
    if (c.contains('死') || c.contains('dying')) return const Color(0xFFC15CFF);
    if (c.contains('重伤') || c.contains('heavy')) return const Color(0xFFEF5D5D);
    if (c.contains('轻伤') || c.contains('light')) return const Color(0xFFF2B648);
    if (c.contains('健康') || c.contains('恢复')) return const Color(0xFF5F665F);
    return Colors.white.withOpacity(.7);
  }

  Future<void> _showItemDetailDialog(NovelInventoryItem item, {required bool isWearable}) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情',
      barrierColor: Colors.black.withOpacity(.75),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 310,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.08)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 10)),
                    ]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76, height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(.06)),
                        ),
                        padding: const EdgeInsets.all(12.0),
                        child: NovelArtwork(
                          url: item.imageUrl,
                          assetCandidates: ['assets/images/${item.itemType.trim()}.webp'],
                          fallbackText: _itemFallback(item.itemType),
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(item.name, style: const TextStyle(color: NovelPalette.text, fontSize: 16.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      if (item.quantity > 1) ...[
                        const SizedBox(height: 6),
                        Text('拥有数量: ${item.quantity}', style: TextStyle(color: NovelPalette.muted.withOpacity(0.8), fontSize: 11)),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        item.description.trim().isEmpty ? '暂无详细描述' : item.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NovelPalette.muted, fontSize: 12.5, height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withOpacity(.12)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('关闭', style: TextStyle(color: NovelPalette.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                            )
                          ),
                          if (isWearable) ...[
                             const SizedBox(width: 12),
                             Expanded(
                               child: FilledButton(
                                 style: FilledButton.styleFrom(
                                   backgroundColor: item.isEquipped ? Colors.white.withOpacity(0.1) : NovelPalette.accent,
                                   foregroundColor: item.isEquipped ? Colors.white : NovelPalette.accentDark,
                                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                   padding: const EdgeInsets.symmetric(vertical: 14),
                                 ),
                                 onPressed: () {
                                   Navigator.of(ctx).pop();
                                   _toggleWear(item);
                                 },
                                 child: Text(
                                   item.isEquipped ? '卸下' : '穿戴',
                                   style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)
                                 ),
                               )
                             ),
                          ]
                        ]
                      )
                    ]
                  )
                ),
              )
            )
          )
        );
      }
    );
  }

  Widget _buildSkillRow(_PlayerSkillView skill) {
    final meta = skill.isAbility
        ? '能力'
        : (skill.mastery.trim().isNotEmpty ? skill.mastery.trim() : '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  skill.name,
                  style: const TextStyle(
                    color: NovelPalette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (skill.description.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    skill.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: NovelPalette.muted.withOpacity(.78),
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                meta,
                style: const TextStyle(
                  color: NovelPalette.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEquippedRow(NovelInventoryItem item) {
    return InkWell(
      onTap: () => _showItemDetailDialog(
        item,
        isWearable: true,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NovelPalette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '已穿戴',
              style: TextStyle(
                color: NovelPalette.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandAction({
    required bool expanded,
    required int hiddenCount,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          expanded ? '收起' : '展开全部 · 还有 $hiddenCount 条',
          style: const TextStyle(
            color: NovelPalette.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStage(
    NovelCharacter? host,
    List<NovelInventoryItem> equipped,
    List<_PlayerSkillView> skills,
  ) {
    final name = host?.name.trim().isNotEmpty == true
        ? host!.name
        : widget.controller.protagonistName;
    // 背包顶部只读取角色头像，不使用立绘。
    final avatar = host?.avatarUrl.trim() ?? '';

    final status = host?.status ?? const <String, dynamic>{};
    final identity =
        stringValue(status['identity'] ?? host?.persona['identity']).trim();
    final level = stringValue(status['level']).trim();
    final condition = widget.controller.protagonistCondition;
    const fallbackAsset = 'assets/images/male.webp';

    // 顶部信息直接平铺，不使用整块卡片容器。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipOval(
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: NovelArtwork(
                    url: avatar,
                    assetCandidates: const <String>[fallbackAsset],
                    fit: BoxFit.cover,
                  ),
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
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NovelPalette.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => showNovelHostProfileSheet(
                            context,
                            widget.controller,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Text(
                              '详情',
                              style: TextStyle(
                                color: NovelPalette.muted,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        if (identity.isNotEmpty) _MinimalTag(identity),
                        if (level.isNotEmpty) _MinimalTag('境界 $level'),
                        if (condition.isNotEmpty)
                          _MinimalTag(
                            condition,
                            color: _conditionColor(condition),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (skills.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '技能',
                    style: TextStyle(
                      color: NovelPalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${skills.length}',
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ...skills.take(skillsExpanded ? skills.length : 3).map(_buildSkillRow),
            if (skills.length > 3)
              _buildExpandAction(
                expanded: skillsExpanded,
                hiddenCount: skills.length - 3,
                onTap: () => setState(() => skillsExpanded = !skillsExpanded),
              ),
          ],
          if (equipped.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '当前穿戴',
                    style: TextStyle(
                      color: NovelPalette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${equipped.length}',
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ...equipped.take(equippedExpanded ? equipped.length : 3).map(_buildEquippedRow),
            if (equipped.length > 3)
              _buildExpandAction(
                expanded: equippedExpanded,
                hiddenCount: equipped.length - 3,
                onTap: () => setState(() => equippedExpanded = !equippedExpanded),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInventoryPage(
    NovelCharacter? host,
    List<NovelInventoryItem> allItems,
    List<NovelInventoryItem> equipped,
    List<_PlayerSkillView> skills,
  ) {
    return RefreshIndicator(
      color: NovelPalette.accent,
      backgroundColor: const Color(0xFF222222),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 34),
        children: <Widget>[
          _buildHeroStage(host, equipped, skills),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(.06),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '背包',
                    style: TextStyle(
                      color: NovelPalette.text,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${allItems.length} 件',
                  style: const TextStyle(
                    color: NovelPalette.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (allItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 46),
              child: _ArchiveEmptyState(
                text: loading ? '正在整理...' : '空空如也',
              ),
            )
          else
            ...allItems.map((item) {
              final isWearable = _isWearable(item);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ItemCardTile(
                  item: item,
                  isWearable: isWearable,
                  busy: busy == item.id,
                  onAction: () => _toggleWear(item),
                  onTap: () => _showItemDetailDialog(
                    item,
                    isWearable: isWearable,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final host = widget.controller.protagonist;
        final data = widget.controller.inventory;
        final skills = _skills(host);
        final allItems = _allItems(data);
        final equipped = allItems
            .where((item) => _isWearable(item) && item.isEquipped)
            .toList();

        return _buildInventoryPage(
          host,
          allItems,
          equipped,
          skills,
        );
      },
    );
  }
}

class _MinimalTag extends StatelessWidget {
  const _MinimalTag(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NovelPalette.muted;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        text,
        style: TextStyle(
          color: c,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          height: 1.25,
        ),
      ),
    );
  }
}

class _ItemCardTile extends StatelessWidget {
  final NovelInventoryItem item;
  final bool isWearable;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _ItemCardTile({
    required this.item,
    required this.isWearable,
    required this.busy,
    required this.onTap,
    required this.onAction,
  });

  // 根据物品类型返回短文本标签
  String _itemTypeShortLabel(String type) {
    return switch (type.trim().toLowerCase()) {
      'misc' => '普通',
      'consumable' => '消耗',
      'material' => '材料',
      'quest' => '任务',
      'gift' => '赠礼',
      'blind_box' => '福袋',
      'lucky_card' => '特殊',
      'weapon' => '武器',
      'wearable' || 'armor' => '防具',
      'accessory' => '饰品',
      _ => '物品',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isEquipped = item.isEquipped && isWearable;
    final description = item.description.trim();

    // 在外部留出底边距，替代原先简单的垂直 Padding
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        // 如果已穿戴，给予极淡的主题色背景暗示；否则使用统一的微透明背景
        color: isEquipped
            ? NovelPalette.accent.withOpacity(.035)
            : Colors.white.withOpacity(.018),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                // 同样，已穿戴的边框颜色稍微加深
                color: isEquipped
                    ? NovelPalette.accent.withOpacity(.15)
                    : Colors.white.withOpacity(.045),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          // 增加 Flexible 保证名字过长时可以被截断，不会挤压右侧元素
                          Flexible(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: NovelPalette.text,
                                fontSize: 13.5,
                                fontWeight: isEquipped ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 物品类型小标签
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.04),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _itemTypeShortLabel(item.itemType),
                              style: const TextStyle(
                                color: NovelPalette.muted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // 数量徽章
                          if (item.quantity > 1) ...<Widget>[
                            const SizedBox(width: 6),
                            Text(
                              '×${item.quantity}',
                              style: const TextStyle(
                                color: NovelPalette.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (description.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 5),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: NovelPalette.muted.withOpacity(.75),
                            fontSize: 11.2,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isWearable) ...<Widget>[
                  const SizedBox(width: 12),
                  // 将原本纯文字的操作按钮，改为带有边框的小型实体按钮
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: busy ? null : onAction,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isEquipped
                              ? Colors.transparent
                              : NovelPalette.accent.withOpacity(.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isEquipped
                                ? Colors.white.withOpacity(.12)
                                : NovelPalette.accent.withOpacity(.25),
                          ),
                        ),
                        child: busy
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: NovelPalette.muted,
                                ),
                              )
                            : Text(
                                isEquipped ? '卸下' : '穿戴',
                                style: TextStyle(
                                  color: isEquipped ? NovelPalette.muted : NovelPalette.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final _PlayerSkillView skill;
  const _SkillCard({required this.skill});

  @override
  Widget build(BuildContext context) {
    final meta = skill.isAbility ? '能力' : (skill.mastery.trim().isNotEmpty ? skill.mastery.trim() : '');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  skill.name,
                  style: const TextStyle(color: NovelPalette.text, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (meta.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    meta,
                    style: const TextStyle(color: NovelPalette.muted, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (skill.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              skill.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NovelPalette.muted, fontSize: 12, height: 1.55),
            ),
          ],
        ],
      ),
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

class NovelDeveloperPreviewActions {
  const NovelDeveloperPreviewActions({
    required this.weatherOverride,
    required this.timeOverride,
    required this.setWeatherOverride,
    required this.setTimeOverride,
    required this.previewCharacterSetup,
    required this.previewOpening,
    required this.previewSceneArrival,
    required this.previewStoryBrewing,
    required this.previewLoading,
    required this.previewFailure,
    required this.previewFateRevert,
    required this.previewBalance,
    required this.previewDice,
    required this.previewTimeSkip,
    required this.previewEndingIntro,
    required this.previewEnding,
    required this.previewAffectionUp,
    required this.previewAffectionDown,
    required this.previewItemObtained,
    required this.previewScoreGain,
    required this.previewGoalRefresh,
    required this.previewGoalSuccess,
    required this.previewGoalFailure,
    required this.previewDamage,
    required this.previewRecovery,
    required this.previewRisk,
  });

  final NovelWeatherEffect? Function() weatherOverride;
  final NovelTimePeriod? Function() timeOverride;
  final Future<void> Function(NovelWeatherEffect? value) setWeatherOverride;
  final void Function(NovelTimePeriod? value) setTimeOverride;

  final Future<void> Function() previewCharacterSetup;
  final Future<void> Function() previewOpening;
  final Future<void> Function() previewSceneArrival;
  final Future<void> Function() previewStoryBrewing;
  final Future<void> Function() previewLoading;
  final Future<void> Function() previewFailure;
  final Future<void> Function() previewFateRevert;
  final Future<void> Function() previewBalance;
  final Future<void> Function() previewDice;
  final Future<void> Function() previewTimeSkip;
  final Future<void> Function() previewEndingIntro;
  final Future<void> Function() previewEnding;

  // 直接反馈预览：全部只作用于当前客户端，不写真实剧情状态。
  final Future<void> Function() previewAffectionUp;
  final Future<void> Function() previewAffectionDown;
  final Future<void> Function() previewItemObtained;
  final Future<void> Function() previewScoreGain;
  final Future<void> Function() previewGoalRefresh;
  final Future<void> Function() previewGoalSuccess;
  final Future<void> Function() previewGoalFailure;
  final Future<void> Function() previewDamage;
  final Future<void> Function() previewRecovery;
  final Future<void> Function() previewRisk;
}

const Color _novelDrawerAccent = NovelPalette.accent;

Future<void> showNovelSettingsSheet(
  BuildContext context,
  NovelGameController controller, {
  NovelDeveloperPreviewActions? developerPreview,
}) async {
  await _showNovelEndDrawer<void>(
    context,
    child: _SettingsPanel(
      controller: controller,
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
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(onBack == null ? 18 : 12, 14, 12, 12),
          child: Row(
            children: <Widget>[
              if (onBack != null) ...<Widget>[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: const SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 13,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
                  borderRadius: BorderRadius.circular(8),
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
  const _SettingsPanel({
    required this.controller,
    this.developerPreview,
  });

  final NovelGameController controller;
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
        if (_showDeveloperTools && developerPreview != null) {
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
                              activeTrackColor: _novelDrawerAccent,
                              inactiveTrackColor: Colors.white.withOpacity(.08),
                              thumbColor: _novelDrawerAccent,
                              overlayColor: _novelDrawerAccent.withOpacity(.08),
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
                    Divider(height: 18, color: Colors.white.withOpacity(.14)),
                    Row(
                      children: <Widget>[
                        const Text(
                          '文字速度',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          settings.textSpeedLabel,
                          style: TextStyle(
                            color: AppColors.textOnDark.withOpacity(.88),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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
              const SizedBox(height: 24),
              const _CleanSettingsHeader(
                icon: Icons.tune_rounded,
                title: '声音与引擎',
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
                                child: Text(model.name, style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5)),
                              ))
                          .toList(),
                      child: _CleanSettingsRow(
                        icon: Icons.hub_outlined,
                        title: '生成引擎模型',
                        subtitle: _modelLabel(),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDarkMuted, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              if (developerPreview != null) ...<Widget>[
                const SizedBox(height: 26),
                Divider(height: 1, color: Colors.white.withOpacity(.10)),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _showDeveloperTools = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.science_outlined,
                            size: 17,
                            color: AppColors.textOnDarkMuted,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '开发者测试',
                                  style: TextStyle(
                                    color: AppColors.textOnDark,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  '天气、时间与关键页面美术预览',
                                  style: TextStyle(
                                    color: AppColors.textOnDarkMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textOnDarkMuted,
                            size: 18,
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


class _DeveloperToolsPanel extends StatefulWidget {
  const _DeveloperToolsPanel({
    required this.actions,
    required this.onBack,
  });

  final NovelDeveloperPreviewActions actions;
  final VoidCallback onBack;

  @override
  State<_DeveloperToolsPanel> createState() => _DeveloperToolsPanelState();
}

class _DeveloperToolsPanelState extends State<_DeveloperToolsPanel> {
  NovelDeveloperPreviewActions get actions => widget.actions;

  Future<void> _openPreview(Future<void> Function() preview) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await preview();
  }

  @override
  Widget build(BuildContext context) {
    final currentWeather = actions.weatherOverride();
    final currentTime = actions.timeOverride();
    const weatherOptions = <NovelWeatherEffect?>[
      null,
      NovelWeatherEffect.none,
      NovelWeatherEffect.cloudy,
      NovelWeatherEffect.rain,
      NovelWeatherEffect.heavyRain,
      NovelWeatherEffect.thunderstorm,
      NovelWeatherEffect.snow,
      NovelWeatherEffect.blizzard,
    ];
    const timeOptions = <NovelTimePeriod?>[
      null,
      NovelTimePeriod.morning,
      NovelTimePeriod.noon,
      NovelTimePeriod.afternoon,
      NovelTimePeriod.evening,
      NovelTimePeriod.night,
      NovelTimePeriod.midnight,
    ];

    return _SettingsDrawerScaffold(
      title: '开发者测试',
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: <Widget>[
          Text(
            '仅改变当前客户端的预览状态，不写入剧情数据，也不会主动请求生成接口。',
            style: TextStyle(
              color: AppColors.textOnDarkMuted.withOpacity(.88),
              fontSize: 10.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          const _DeveloperSectionTitle(
            title: '环境预览',
            subtitle: '直接观察背景、光照与天气效果',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '天气',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: weatherOptions.map((effect) {
                    final selected = currentWeather == effect;
                    return _DeveloperChoiceChip(
                      label: effect?.label ?? '自动',
                      selected: selected,
                      onTap: () async {
                        await actions.setWeatherOverride(effect);
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
                Divider(height: 22, color: Colors.white.withOpacity(.10)),
                const Text(
                  '时间',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: timeOptions.map((period) {
                    final selected = currentTime == period;
                    return _DeveloperChoiceChip(
                      label: period?.label ?? '自动',
                      selected: selected,
                      onTap: () {
                        actions.setTimeOverride(period);
                        if (mounted) setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _DeveloperSectionTitle(
            title: '直接反馈预览',
            subtitle: '关闭测试抽屉后播放真实剧情页会使用的反馈效果',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _DeveloperPreviewRow(
                  title: '角色好感 +2',
                  subtitle: '当前对白角色爱心与数字原位放大；角色未出场则等出场再播放',
                  onTap: () => _openPreview(actions.previewAffectionUp),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '角色好感 -2',
                  subtitle: '当前对白角色爱心与数字原位缩放反馈，不再弹 HUD 卡片',
                  onTap: () => _openPreview(actions.previewAffectionDown),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '获得物品',
                  subtitle: '模拟获得“云岚宗令牌 ×1”，仅显示无背景纯文字提示',
                  onTap: () => _openPreview(actions.previewItemObtained),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '获得积分',
                  subtitle: '模拟 +13 积分，直接让右上角星星与数字原位放大',
                  onTap: () => _openPreview(actions.previewScoreGain),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标刷新',
                  subtitle: '临时替换顶部当前目标并播放目标更新提示',
                  onTap: () => _openPreview(actions.previewGoalRefresh),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标完成',
                  subtitle: '绿色完成动画，复用正式目标成功效果',
                  onTap: () => _openPreview(actions.previewGoalSuccess),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '目标失败',
                  subtitle: '红色震动失败动画，复用正式目标失败效果',
                  onTap: () => _openPreview(actions.previewGoalFailure),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '角色掉血',
                  subtitle: '临时切到重伤，测试屏幕边缘受伤反馈',
                  onTap: () => _openPreview(actions.previewDamage),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '伤势恢复',
                  subtitle: '测试恢复状态与伤势提示',
                  onTap: () => _openPreview(actions.previewRecovery),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '风险 / 警戒',
                  subtitle: '测试行动失败后留下持续风险的提示',
                  onTap: () => _openPreview(actions.previewRisk),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _DeveloperSectionTitle(
            title: '页面预览',
            subtitle: '关闭测试抽屉后直接展示目标页面',
          ),
          const SizedBox(height: 10),
          _CleanSettingsCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _DeveloperPreviewRow(
                  title: '角色确认',
                  subtitle: '首次进入世界前的角色确认页',
                  onTap: () => _openPreview(actions.previewCharacterSetup),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '故事开场',
                  subtitle: '序章文字与背景过场',
                  onTap: () => _openPreview(actions.previewOpening),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '更换场景',
                  subtitle: '预览中央场景名，以及左上角地点与目标的淡出、恢复',
                  onTap: () => _openPreview(actions.previewSceneArrival),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '加载故事',
                  subtitle: '预览“故事正在展开”的流光动画；轻触页面即可结束',
                  onTap: () => _openPreview(actions.previewStoryBrewing),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '载入世界',
                  subtitle: '初始化中的全屏载入状态',
                  onTap: () => _openPreview(actions.previewLoading),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '载入失败',
                  subtitle: '“世界暂时无法载入”失败页面',
                  onTap: () => _openPreview(actions.previewFailure),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '命运回溯',
                  subtitle: '死亡后的回溯提示页面',
                  onTap: () => _openPreview(actions.previewFateRevert),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '余额不足',
                  subtitle: '无法继续生成剧情时的提示',
                  onTap: () => _openPreview(actions.previewBalance),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '命运判定',
                  subtitle: '骰子判定结果全屏反馈',
                  onTap: () => _openPreview(actions.previewDice),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '时间跳转',
                  subtitle: '跨日 / 跨时段的转场页面',
                  onTap: () => _openPreview(actions.previewTimeSkip),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '终章转场',
                  subtitle: '进入结局前的黑屏提示',
                  onTap: () => _openPreview(actions.previewEndingIntro),
                ),
                _DeveloperPreviewDivider(),
                _DeveloperPreviewRow(
                  title: '结局页面',
                  subtitle: '最终结局、共同记忆与命运轨迹',
                  onTap: () => _openPreview(actions.previewEnding),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperSectionTitle extends StatelessWidget {
  const _DeveloperSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          style: const TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _DeveloperChoiceChip extends StatelessWidget {
  const _DeveloperChoiceChip({
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
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? _novelDrawerAccent.withOpacity(.12)
                : Colors.white.withOpacity(.025),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? _novelDrawerAccent.withOpacity(.42)
                  : Colors.white.withOpacity(.07),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _novelDrawerAccent : AppColors.textOnDarkMuted,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeveloperPreviewDivider extends StatelessWidget {
  const _DeveloperPreviewDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(.10));
  }
}

class _DeveloperPreviewRow extends StatelessWidget {
  const _DeveloperPreviewRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 11.5,
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
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.textOnDarkMuted,
              ),
            ],
          ),
        ),
      ),
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
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 108,
          height: 82,
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
                    size: 13,
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
    this.fontFamily,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
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
            color: _novelDrawerAccent.withOpacity(.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            trailing,
            style: const TextStyle(
              color: _novelDrawerAccent,
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
                      ? _novelDrawerAccent
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
                    ? _novelDrawerAccent.withOpacity(.10)
                    : Colors.white.withOpacity(.025),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? _novelDrawerAccent.withOpacity(.48)
                      : Colors.white.withOpacity(.07),
                ),
              ),
              child: Text(
                char,
                style: TextStyle(
                  color: selected ? _novelDrawerAccent : AppColors.textOnDark,
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(.065)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: _novelDrawerAccent.withOpacity(.78), size: 18),
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
  await _runNovelPageOnce('host-profile', () async {
    final host = controller.protagonist;
    // 获取主角的唯一标识，用于在人物列表中精准定位
    final hostKey = host != null && host.id.trim().isNotEmpty
        ? host.id.trim()
        : (host?.name.trim() ?? controller.protagonistName);

    // 直接打开包含大立绘的“角色总览页”，并聚焦到主角
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(
        controller: controller,
        focusCharacterKey: hostKey,
        focusRequestId: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });
}

Future<void> showNovelCharactersSheet(
  BuildContext context,
  NovelGameController controller,
) async {
  await _runNovelPageOnce('characters', () async {
    // 兼容旧调用：独立打开时仍保留原来的全屏归档页。
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(controller: controller),
    );
  });
}

/// 主游戏底部 Tab 使用的人物页。
/// embedded=true 时不再显示“关闭”按钮，由右侧一级导航负责页面切换。
class NovelCharactersTab extends StatelessWidget {
  const NovelCharactersTab({
    super.key,
    required this.controller,
    this.focusCharacterKey = '',
    this.focusRequestId = 0,
  });

  final NovelGameController controller;
  final String focusCharacterKey;
  final int focusRequestId;

  @override
  Widget build(BuildContext context) {
    return _CharactersPanel(
      controller: controller,
      embedded: true,
      focusCharacterKey: focusCharacterKey,
      focusRequestId: focusRequestId,
    );
  }
}


class _CharactersPanel extends StatefulWidget {
  const _CharactersPanel({
    required this.controller,
    this.embedded = false,
    this.focusCharacterKey = '',
    this.focusRequestId = 0,
  });

  final NovelGameController controller;
  final bool embedded;
  final String focusCharacterKey;
  final int focusRequestId;

  @override
  State<_CharactersPanel> createState() => _CharactersPanelState();
}

class _CharactersPanelState extends State<_CharactersPanel> {
  int filter = 0; // 0 全部 / 1 亲密 / 2 普通
  bool loading = true;
  String selectedCharacterKey = '';


  @override
  void initState() {
    super.initState();
    selectedCharacterKey = widget.focusCharacterKey.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant _CharactersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusChanged =
        widget.focusRequestId != oldWidget.focusRequestId ||
        widget.focusCharacterKey != oldWidget.focusCharacterKey;
    if (!focusChanged) return;

    final key = widget.focusCharacterKey.trim();
    if (key.isEmpty) return;

    // 从剧情对话框跳入人物页时，先回到“全部”，再精确定位当前说话角色。
    // 不依赖当前亲密/普通筛选，避免目标角色被筛掉后看起来像“没有定位”。
    filter = 0;
    selectedCharacterKey = key;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => loading = true);
    await widget.controller.refreshCharacterStatus();
    if (mounted) setState(() => loading = false);
  }

  bool _isClose(NovelCharacter c) => c.affection >= 60;

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  List<NovelCharacter> _applyFilter(List<NovelCharacter> source) {
    // 主角固定放在“全部”的第一个；亲密/普通只筛 NPC，避免把主角硬塞进关系分类。
    if (filter == 1) {
      return source.where((c) => !c.isMain && _isClose(c)).toList();
    }
    if (filter == 2) {
      return source.where((c) => !c.isMain && !_isClose(c)).toList();
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
    return values.isNotEmpty ? values.first : '这个人物的故事还没有完全展开。';
  }

  String _identityOf(NovelCharacter c) {
    final identity = stringValue(c.status['identity'] ?? c.persona['identity']).trim();
    if (identity.isNotEmpty) return identity;
    final occupation = stringValue(c.status['occupation'] ?? c.persona['occupation']).trim();
    return occupation;
  }

  NovelCharacter _selected(List<NovelCharacter> source) {
    if (source.isEmpty) {
      throw StateError('No character available');
    }
    final currentKey = selectedCharacterKey.trim();
    if (currentKey.isNotEmpty) {
      for (final item in source) {
        if (_characterKey(item) == currentKey) return item;
      }
    }
    return source.first;
  }

  void _changeFilter(int value) {
    if (filter == value) return;
    setState(() {
      filter = value;
      selectedCharacterKey = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final scenarioCharacters =
            widget.controller.scenario?.characters.values.toList() ??
                <NovelCharacter>[];

        NovelCharacter? host = widget.controller.protagonist;
        if (host == null) {
          for (final item in scenarioCharacters) {
            if (item.isMain) {
              host = item;
              break;
            }
          }
        }

        final npcs = scenarioCharacters
            .where((character) => !character.isMain)
            .toList();
        npcs.sort((a, b) {
          if (_isClose(a) != _isClose(b)) return _isClose(a) ? -1 : 1;
          return b.affection.compareTo(a.affection);
        });

        // 人物页第一位永远是主角，后面才是 NPC。
        final characters = <NovelCharacter>[
          if (host != null) host,
          ...npcs,
        ];

        if (characters.isEmpty) {
          return _CharacterArchiveBackground(
            controller: widget.controller,
            embedded: widget.embedded,
            child: _ArchiveEmptyState(
              text: loading ? '正在整理人物档案…' : '还没有人物资料',
            ),
          );
        }

        final closeCount = npcs.where(_isClose).length;
        final normalCount = npcs.length - closeCount;
        final filtered = _applyFilter(characters);

        if (filtered.isEmpty) {
          return _CharacterArchiveBackground(
            controller: widget.controller,
            embedded: widget.embedded,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final horizontalInset = compact ? 10.0 : 28.0;
                final verticalInset = compact ? 3.0 : 8.0;

                // 空筛选状态仍然复用正常角色页的同一套宽度、边距和底部占位。
                // 这样“全部 / 亲密 / 普通”的坐标不会因为有没有头像而变化。
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalInset,
                        verticalInset,
                        horizontalInset,
                        verticalInset,
                      ),
                      child: Column(
                        children: <Widget>[
                          _CharacterArchiveHeader(
                            onClose: widget.embedded
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                          const Expanded(
                            child: _ArchiveEmptyState(text: '当前筛选下暂无角色'),
                          ),
                          _CharacterFilterBar(
                            filter: filter,
                            total: characters.length,
                            closeCount: closeCount,
                            normalCount: normalCount,
                            onChanged: _changeFilter,
                          ),
                          // 与正常状态的 _CharacterThumbStrip 高度完全一致。
                          const SizedBox(height: 106),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        final selected = _selected(filtered);

        return _CharacterArchiveBackground(
          controller: widget.controller,
          embedded: widget.embedded,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final horizontalInset = compact ? 10.0 : 28.0;
              final verticalInset = compact ? 3.0 : 8.0;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      verticalInset,
                      horizontalInset,
                      verticalInset,
                    ),
                    child: Column(
                      children: <Widget>[
                        _CharacterArchiveHeader(
                          onClose: widget.embedded
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: _CharacterShowcaseStage(
                            controller: widget.controller,
                            character: selected,
                            summary: _summaryOf(selected),
                            identity: _identityOf(selected),
                            compact: compact,
                          ),
                        ),
                        // “全部 / 亲密 / 普通”只控制下面的人物列表，
                        // 放到生成立绘区域之后、头像栏之前，手机阅读顺序更自然。
                        _CharacterFilterBar(
                          filter: filter,
                          total: characters.length,
                          closeCount: closeCount,
                          normalCount: normalCount,
                          onChanged: _changeFilter,
                        ),
                        _CharacterThumbStrip(
                          characters: filtered,
                          selectedKey: _characterKey(selected),
                          onSelected: (character) {
                            setState(() => selectedCharacterKey =
                                _characterKey(character));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _NovelPrimaryTabSafeContent extends StatelessWidget {
  const _NovelPrimaryTabSafeContent({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: Padding(
        // 一级导航已回到右侧 HUD：取消整块底部预留，
        // 只在右侧留一条窄安全区，避免列表/资料文字被导航覆盖。
        padding: EdgeInsets.only(
          right: compact ? 54.0 : 62.0,
          bottom: safeBottom,
        ),
        child: child,
      ),
    );
  }
}

class _CharacterArchiveBackground extends StatelessWidget {
  const _CharacterArchiveBackground({
    required this.controller,
    required this.child,
    this.embedded = false,
  });

  final NovelGameController controller;
  final Widget child;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = embedded
        ? _NovelPrimaryTabSafeContent(child: child)
        : SafeArea(child: child);

    return ColoredBox(
      color: _archiveBackground,
      child: content,
    );
  }
}

class _CharacterArchiveHeader extends StatelessWidget {
  const _CharacterArchiveHeader({
    this.onClose,
  });

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 6),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '人物',
                  style: TextStyle(
                    color: Color(0xFF272824),
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'CHARACTERS',
                  style: TextStyle(
                    color: Color(0x995F605B),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.1,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            _CharacterHeaderButton(
              tooltip: '关闭',
              icon: Icons.close_rounded,
              onTap: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

class _CharacterHeaderButton extends StatelessWidget {
  const _CharacterHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? _archiveMutedSoft
                  : _archiveTextSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterFilterBar extends StatelessWidget {
  const _CharacterFilterBar({
    required this.filter,
    required this.total,
    required this.closeCount,
    required this.normalCount,
    required this.onChanged,
  });

  final int filter;
  final int total;
  final int closeCount;
  final int normalCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 3),
      child: Row(
        children: <Widget>[
          _CharacterFilterText(
            label: '全部',
            count: total,
            selected: filter == 0,
            onTap: () => onChanged(0),
          ),
          const SizedBox(width: 18),
          _CharacterFilterText(
            label: '亲密',
            count: closeCount,
            selected: filter == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(width: 18),
          _CharacterFilterText(
            label: '普通',
            count: normalCount,
            selected: filter == 2,
            onTap: () => onChanged(2),
          ),
          const Spacer(),
          Container(
            width: 54,
            height: .7,
            color: _archiveLine,
          ),
        ],
      ),
    );
  }
}

class _CharacterFilterText extends StatelessWidget {
  const _CharacterFilterText({
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? _archiveText
                    : _archiveMuted,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: selected
                    ? _archiveMuted
                    : _archiveMutedSoft,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterShowcaseStage extends StatefulWidget {
  const _CharacterShowcaseStage({
    required this.controller,
    required this.character,
    required this.summary,
    required this.identity,
    required this.compact,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final String summary;
  final String identity;
  final bool compact;

  @override
  State<_CharacterShowcaseStage> createState() =>
      _CharacterShowcaseStageState();
}

class _CharacterShowcaseStageState extends State<_CharacterShowcaseStage> {
  String _previewPortraitUrl = '';

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  String get _portraitUrl {
    final preview = _previewPortraitUrl.trim();
    if (preview.isNotEmpty) return preview;

    // 上方人物舞台只允许使用“立绘”。
    // 头像是底部人物切换栏的素材，不能拿来顶替大立绘。
    return widget.character.portraitUrl.trim();
  }

  @override
  void didUpdateWidget(covariant _CharacterShowcaseStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) != _characterKey(widget.character)) {
      _previewPortraitUrl = '';
    }
  }

  void _showPortrait(String value) {
    if (!mounted) return;
    setState(() => _previewPortraitUrl = value.trim());
  }

  String get _relationLabel {
    if (widget.character.isMain) return '主角';
    return widget.character.affectionLabel.trim().isNotEmpty
        ? widget.character.affectionLabel.trim()
        : (widget.character.affection >= 60 ? '亲密' : '普通');
  }

  @override
  Widget build(BuildContext context) {
    final fallbackAsset = widget.character.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // 手机端不再按桌面“两栏”思维缩小人物。
        // 立绘承担主视觉，资料层缩窄并浮在右侧，让人物真正成为页面主体。
        final portraitWidth = widget.compact
            ? math.min(constraints.maxWidth * .76, 430.0)
            : math.min(constraints.maxWidth * .54, 490.0);
        final infoWidth = widget.compact
            ? math.min(constraints.maxWidth * .43, 210.0)
            : math.min(constraints.maxWidth * .41, 340.0);

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: widget.compact ? -portraitWidth * .14 : 18,
              bottom: widget.compact ? -h * .025 : -h * .05,
              child: IgnorePointer(
                child: SizedBox(
                  width: portraitWidth,
                  height: h * (widget.compact ? .96 : 1.02),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: NovelArtwork(
                      key: ValueKey<String>(
                        'showcase-${_portraitUrl}-${widget.character.name}',
                      ),
                      url: _portraitUrl,
                      assetCandidates: <String>[fallbackAsset],
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      fallbackText: widget.character.name,
                      fallbackIcon: Icons.person_outline_rounded,
                    ),
                  ),
                ),
              ),
            ),            Positioned(
              right: widget.compact ? 7 : 26,
              top: widget.compact ? 13 : 34,
              width: infoWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _CharacterShowcaseInfo(
                    character: widget.character,
                    summary: widget.summary,
                    identity: widget.identity,
                    relationLabel: _relationLabel,
                    compact: widget.compact,
                  ),
                  // 手机端把操作区跟人物资料收成一个紧凑信息层，
                  // 下方再自然衔接筛选与头像栏，避免中段出现无意义空白。
                  SizedBox(height: widget.compact ? 12 : 24),
                  _CharacterQuickPortraitEditor(
                    controller: widget.controller,
                    character: widget.character,
                    compact: widget.compact,
                    onPortraitChanged: _showPortrait,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CharacterShowcaseInfo extends StatelessWidget {
  const _CharacterShowcaseInfo({
    required this.character,
    required this.summary,
    required this.identity,
    required this.relationLabel,
    required this.compact,
  });

  final NovelCharacter character;
  final String summary;
  final String identity;
  final String relationLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final nameSize = compact ? 30.0 : 37.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          character.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _archiveText,
            fontSize: nameSize,
            height: .95,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          identity.isEmpty
              ? (character.isMain ? '主角' : '故事人物')
              : identity,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF616B64),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 64,
          height: 1,
          color: _archiveLine,
        ),
        const SizedBox(height: 10),
        Text(
          summary,
          maxLines: compact ? 4 : 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _archiveTextSoft.withOpacity(.90),
            fontSize: compact ? 10.8 : 11.8,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 11),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              character.isMain
                  ? Icons.stars_rounded
                  : Icons.favorite_border_rounded,
              size: 14,
              color: _archiveMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                character.isMain
                    ? relationLabel
                    : '$relationLabel  ·  ${character.affection}',
                style: const TextStyle(
                  color: Color(0xFF4E5851),
                  fontSize: 10.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CharacterQuickPortraitEditor extends StatefulWidget {
  const _CharacterQuickPortraitEditor({
    required this.controller,
    required this.character,
    required this.compact,
    required this.onPortraitChanged,
  });

  final NovelGameController controller;
  final NovelCharacter character;
  final bool compact;
  final ValueChanged<String> onPortraitChanged;

  @override
  State<_CharacterQuickPortraitEditor> createState() =>
      _CharacterQuickPortraitEditorState();
}

class _CharacterQuickPortraitEditorState
    extends State<_CharacterQuickPortraitEditor> {
  late final TextEditingController _promptController;
  late final FocusNode _promptFocusNode;
  bool _generating = false;
  bool _uploading = false;
  String _errorText = '';
  int _requestToken = 0;

  String _characterKey(NovelCharacter c) =>
      c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _promptFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _CharacterQuickPortraitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_characterKey(oldWidget.character) != _characterKey(widget.character)) {
      _requestToken++;
      _promptController.clear();
      _errorText = '';
      _generating = false;
      _uploading = false;
    }
  }

  @override
  void dispose() {
    _promptFocusNode.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generatePortrait() async {
    if (_generating || _uploading) return;

    final target = widget.character;
    final targetKey = _characterKey(target);
    final requestToken = ++_requestToken;
    final prompt = _promptController.text.trim();

    setState(() {
      _generating = true;
      _errorText = '';
    });

    try {
      final result = await widget.controller.generatePortrait(
        character: target,
        prompt: prompt,
        style: 'anime',
      );

      // 即使生成过程中用户已经切到另一个角色，也只更新最初发起生成的角色，
      // 避免把 A 的生成结果误写到 B 身上。
      await widget.controller.updateCharacterVisuals(
        character: target,
        portraitUrl: result.portraitUrl,
        avatarUrl: result.avatarUrl,
      );
      widget.controller.clearMessages();

      if (!mounted) return;
      final stillCurrent = requestToken == _requestToken &&
          _characterKey(widget.character) == targetKey;
      if (stillCurrent) {
        widget.onPortraitChanged(result.portraitUrl);
      }

      // 生成结果里同时包含头像；刷新后底部缩略栏立即切换到新头像。
      await widget.controller.refreshCharacterStatus();
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '生成立绘失败：$error';
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _pickAndApplyLocalPortrait() async {
    if (_generating || _uploading) return;

    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.size > 12 * 1024 * 1024) {
      if (!mounted) return;
      setState(() => _errorText = '图片请控制在 12MB 以内');
      return;
    }

    final target = widget.character;
    final targetKey = _characterKey(target);
    final requestToken = ++_requestToken;

    setState(() {
      _uploading = true;
      _errorText = '';
    });

    try {
      final portraitUrl = await widget.controller.uploadCharacterImage(
        bytes: file.bytes!,
        filename: file.name.isEmpty ? 'portrait.jpg' : file.name,
        contentType: _imageContentType(file.name),
      );

      // 本地上传只替换立绘；角色尚无头像时才用同一张图兜底头像。
      final avatarUrl = target.avatarUrl.trim().isEmpty
          ? portraitUrl
          : target.avatarUrl;

      await widget.controller.updateCharacterVisuals(
        character: target,
        portraitUrl: portraitUrl,
        avatarUrl: avatarUrl,
      );
      widget.controller.clearMessages();

      if (!mounted) return;
      final stillCurrent = requestToken == _requestToken &&
          _characterKey(widget.character) == targetKey;
      if (stillCurrent) {
        widget.onPortraitChanged(portraitUrl);
      }

      await widget.controller.refreshCharacterStatus();
    } catch (error) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _errorText = error is NovelBackendException
            ? error.message
            : '上传立绘失败：$error';
      });
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 游戏页本身已经关闭 resizeToAvoidBottomInset。
    // 这里不再根据键盘高度手动平移编辑区：手机聚焦输入框时保持原坐标，
    // 避免“更换立绘”区域向上撞进角色资料；键盘只覆盖屏幕底部内容。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
        const Text(
          '更换立绘',
          style: TextStyle(
            color: Color(0xFF414A44),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _archiveSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _archiveLine,
              width: 1,
            ),
          ),
          constraints: BoxConstraints(
            minHeight: widget.compact ? 104 : 112,
          ),
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          child: TextField(
            controller: _promptController,
            focusNode: _promptFocusNode,
            enabled: !_generating,
            minLines: 4,
            maxLines: widget.compact ? 4 : 5,
            scrollPadding: EdgeInsets.zero,
            cursorColor: NovelPalette.accent,
            style: TextStyle(
              color: _archiveText,
              fontSize: widget.compact ? 10.6 : 11.2,
              height: 1.45,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '可留空直接生成；也可写发型、服装、气质等调整…',
              hintStyle: TextStyle(
                color: Color(0x88727C75),
                fontSize: 10.2,
                height: 1.4,
              ),
            ),
          ),
        ),
        if (_errorText.isNotEmpty) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            _errorText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD98A83),
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _uploading) ? null : _generatePortrait,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _generating
                      ? _archiveSurfaceSoft
                      : _archiveThemeGreen,
                  border: Border.all(
                    color: _generating
                        ? _archiveLine
                        : _archiveThemeGreen,
                    width: .9,
                  ),
                ),
                child: _generating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: NovelPalette.accent,
                            ),
                          ),
                          SizedBox(width: 7),
                          Text(
                            '生成中…',
                            style: TextStyle(
                              color: Color(0xFF4E514C),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '生成立绘',
                        style: TextStyle(
                          color: NovelPalette.accentDark,
                          fontSize: 11.4,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .6,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _uploading)
                  ? null
                  : _pickAndApplyLocalPortrait,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _uploading
                      ? _archiveSurfaceSoft
                      : Colors.transparent,
                  border: Border.all(
                    color: _uploading
                        ? _archiveLine
                        : _archiveAccent.withOpacity(.55),
                    width: .9,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_uploading) ...<Widget>[
                      const SizedBox.square(
                        dimension: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: NovelPalette.accentDeep,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _uploading ? '上传中…' : '本地上传',
                      style: const TextStyle(
                        color: _archiveAccent,
                        fontSize: 10.4,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .35,
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
    );
  }
}

class _CharacterThumbStrip extends StatelessWidget {
  const _CharacterThumbStrip({
    required this.characters,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<NovelCharacter> characters;
  final String selectedKey;
  final ValueChanged<NovelCharacter> onSelected;

  String _keyOf(NovelCharacter c) => c.id.trim().isNotEmpty ? c.id.trim() : c.name.trim();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // 名字已经移到头像卡片外部，因此把原来过大的上下内边距收紧。
        // 保持整个头像栏仍为 106 高，不改变“全部 / 亲密 / 普通”的固定位置。
        padding: const EdgeInsets.fromLTRB(14, 3, 18, 2),
        itemCount: characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final character = characters[index];
          final selected = _keyOf(character) == selectedKey;
          // 底部角色栏只显示头像；头像为空时，使用默认男女立绘兜底。
          // 上方舞台则始终只读取 character.portraitUrl。
          final fallbackAsset = character.gender.trim() == '女'
              ? 'assets/images/portrait_female.webp'
              : 'assets/images/portrait_male.png';
          final image = character.avatarUrl.trim();
          return GestureDetector(
            onTap: () => onSelected(character),
            child: SizedBox(
              width: 66,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 66,
                    height: 82,
                    decoration: BoxDecoration(
                      color: _archiveSurfaceSoft,
                      borderRadius: BorderRadius.zero,
                      border: Border.all(
                        color: selected
                            ? _archiveThemeGreen
                            : _archiveLine,
                        width: selected ? 1.35 : 1,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        NovelArtwork(
                          url: image,
                          assetCandidates: <String>[fallbackAsset],
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          fallbackText: character.name,
                          fallbackIcon: Icons.person_outline_rounded,
                        ),
                        if (selected)
                          const Positioned(
                            right: 3,
                            top: 3,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: _archiveThemeGreen,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 66,
                    child: Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? _archiveText : _archiveTextSoft,
                        fontSize: 9.2,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                        letterSpacing: .1,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}


Future<void> showNovelNpcProfileSheet(
  BuildContext context,
  NovelGameController controller,
  NovelCharacter character,
) async {
  await _runNovelPageOnce('character-profile', () async {
    final key = character.id.trim().isNotEmpty ? character.id.trim() : character.name.trim();
    // 同样直接打开“角色总览页”，并聚焦到该 NPC
    await _showNovelArchivePage<void>(
      context,
      child: _CharactersPanel(
        controller: controller,
        focusCharacterKey: key,
        focusRequestId: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  });
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
    return const Color(0xFF626862);
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
        : 'assets/images/portrait_female.webp';

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
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF202520),
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
              color: _archiveMuted,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '形象设定',
              style: TextStyle(
                color: _archiveText,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 依靠 AspectRatio 保证比例，用 constraints 约束平板上的极限宽度，防止溢出
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_generating || _saving) ? null : _pickLocalImage,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white, // 纯白底
                      borderRadius: BorderRadius.circular(12),
                      // 去掉了所有外框
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
          ),
        ),
        if (_hasPortrait) ...<Widget>[
          const SizedBox(height: 7),
          Center(
            child: Text(
              '点击立绘可上传',
              style: TextStyle(
                color: _archiveMutedSoft,
                fontSize: 10.2,
              ),
            ),
          ),
        ],

        const SizedBox(height: 22),
        
        Text(
          '额外形象要求（可选）',
          style: TextStyle(
            color: _archiveMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white, // 融入在极浅灰卡片上的纯白输入框
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _promptController,
            enabled: !_generating && !_saving,
            minLines: 3,
            maxLines: 5,
            cursorColor: primaryGreen,
            style: const TextStyle(
              color: _archiveText,
              fontSize: 12,
              height: 1.5,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '留空按角色完整设定生成；例如：裙摆更轻盈、气质更清冷、仙气更强……',
              hintStyle: TextStyle(
                color: _archiveMutedSoft,
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

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 42,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_generating || _saving) ? null : _generatePortrait,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: (_generating || _saving)
                      ? _archiveMutedSoft.withOpacity(0.3)
                      : primaryGreen,
                ),
                child: _generating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '生成中…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '生成立绘',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
              ),
            ),
          ),
        ),

        if (_hasPendingChanges) ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _archiveText,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _archiveMutedSoft.withOpacity(0.3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: (_generating || _saving) ? null : _savePortrait,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '保存立绘',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
            ),
          ),
        ],
      ],
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
          ? _archiveSurfaceSoft
          : disabled
              ? _archiveBackground
              : _archiveSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? _archiveText
                  : disabled
                      ? _archiveMutedSoft
                      : _archiveMuted,
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
    this.greenPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool primary;
  final bool greenPrimary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: greenPrimary
          ? (enabled ? _archiveThemeGreen : _archiveSurfaceSoft)
          : primary
              ? (enabled ? _archiveText : _archiveSurfaceSoft)
              : (enabled ? _archiveSurfaceSoft : _archiveBackground),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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
                    color: greenPrimary
                        ? NovelPalette.accentDark
                        : (primary
                            ? _archiveSurface
                            : _archiveMuted),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 13,
                  color: greenPrimary
                      ? NovelPalette.accentDark
                      : (primary
                          ? _archiveSurface
                          : _archiveMuted),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: greenPrimary
                        ? (enabled
                            ? NovelPalette.accentDark
                            : _archiveMutedSoft)
                        : (primary
                            ? _archiveSurface
                            : (enabled
                                ? _archiveText
                                : _archiveMutedSoft)),
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
                        color: _archiveMuted,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '点击上传',
                        style: TextStyle(
                          color: _archiveText,
                          fontSize: 11.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '或在下方生成新的立绘',
                        style: TextStyle(
                          color: _archiveMutedSoft,
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
                          borderRadius: BorderRadius.circular(8),
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
                              color: _archiveText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          target.isMain ? '主角' : '角色',
                          style: TextStyle(
                            color: _archiveMutedSoft,
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
                        color: _archiveSurfaceSoft,
                        borderRadius: BorderRadius.circular(8),
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
                                        color: _archiveText,
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
                        color: _archiveMutedSoft,
                        fontSize: 10.2,
                      ),
                    ),

                    const SizedBox(height: 16),

      

                    Text(
                      '额外形象要求（可选）',
                      style: TextStyle(
                        color: _archiveMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: _archiveSurfaceSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: promptController,
                        enabled: !generating && !saving,
                        minLines: 3,
                        maxLines: 5,
                        cursorColor: NovelPalette.accent,
                        style: const TextStyle(
                          color: _archiveText,
                          fontSize: 12.3,
                          height: 1.55,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText:
                              '留空按角色完整设定生成；例如：服装更轻盈、气质更清冷、减少华丽首饰…',
                          hintStyle: TextStyle(
                            color: _archiveMutedSoft,
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
                            greenPrimary: true,
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
  await _runNovelPageOnce('journey', () async {
    await _showNovelArchivePage<void>(
      context,
      child: _GameStyleJourneyPage(controller: controller),
    );
  });
}

/// 主游戏底部 Tab 使用的经历页。
class NovelJourneyTab extends StatelessWidget {
  const NovelJourneyTab({
    super.key,
    required this.controller,
  });

  final NovelGameController controller;

  @override
  Widget build(BuildContext context) {
    return _GameStyleJourneyPage(
      controller: controller,
      embedded: true,
    );
  }
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
                        borderRadius: BorderRadius.circular(8),
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
                        borderRadius: BorderRadius.circular(8),
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
                        borderRadius: BorderRadius.circular(10), // 从 4 改为 10，更柔和
                        border: Border.all(
                          color: Colors.white.withOpacity(.08), // 边框稍微变淡
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withOpacity(.30), // 阴影减轻压迫感
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
                                width: 54, // 头像尺寸从 62 调小到 54，削弱对立感
                                height: 54,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: NovelPalette.accent.withOpacity(.28),
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
                                      '确认你的角色',
                                      style: TextStyle(
                                        color: NovelPalette.text,
                                        fontSize: 17, // 从 19 调小到 17
                                        fontWeight: FontWeight.w700, // 从 800 超粗体改为 700
                                        letterSpacing: .2,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '这是你在这个世界中的身份，确认后即可进入故事。',
                                      style: TextStyle(
                                        color: NovelPalette.muted.withOpacity(.75), // 从 .86 调低
                                        fontSize: 11, // 从 11.5 调小
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
                              color: NovelPalette.muted, // 从 text 换成柔和的 muted
                              fontSize: 11, // 标签再调小一点点
                              fontWeight: FontWeight.w600, // 从 700 减到 600
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
                              fontSize: 13, // 从 14.5 减到 13
                              fontWeight: FontWeight.w500, // 从 600 减到 500
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
                              fillColor: Colors.white.withOpacity(.02), // 降低背景对比度
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10, // 把输入框压扁，显得纤细
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8), // 微圆角
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.06),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: NovelPalette.accent.withOpacity(.62),
                                ),
                              ),
                              disabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.white.withOpacity(.04),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '角色背景',
                            style: TextStyle(
                              color: NovelPalette.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 170),
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), // 内边距压细
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.02), // 降低背景色对比
                              borderRadius: BorderRadius.circular(8), // 改成 8 统一圆角
                              border: Border.all(
                                color: Colors.white.withOpacity(.06),
                              ),
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(
                                background,
                                style: TextStyle(
                                  color: NovelPalette.text.withOpacity(.70),
                                  fontSize: 11.5, // 稍微缩小字号
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 42, // 主按钮从 46 压低到 42，变得纤长精致
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: NovelPalette.accent,
                                foregroundColor: NovelPalette.accentDark,
                                disabledBackgroundColor:
                                    NovelPalette.accent.withOpacity(.45),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8), // 统一 8px
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
                                      width: 16, // loading 图标缩小
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: NovelPalette.accentDark,
                                      ),
                                    )
                                  : const Text(
                                      '进入故事',
                                      style: TextStyle(
                                        fontSize: 13, // 从 13.5 降低
                                        fontWeight: FontWeight.w700, // 从超粗的 800 降低到 700
                                        letterSpacing: 1.0, // 加一点字间距提升透气感
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
        color: Colors.white.withOpacity(.025), // 稍微压暗背景
        borderRadius: BorderRadius.circular(6), // 匹配总体微圆角风格
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: NovelPalette.muted.withOpacity(.82), // 稍微降低字体对比度
          fontSize: 10.5,
          fontWeight: FontWeight.w500, // 从 600 改为更柔和的 500
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
        borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: highlighted
                ? NovelPalette.accent.withOpacity(.055)
                : Colors.white.withOpacity(.018),
            borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(8),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.02),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                      color: Colors.black.withOpacity(.8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w400,
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
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description.trim().isEmpty ? _itemTypeLabel(itemType) : description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (actionText.isNotEmpty) ...<Widget>[
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: loading ? null : onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(.2)), // 幽灵边框
                  ),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.0, color: Colors.white),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (showPointIcon) ...<Widget>[
                              const Icon(Icons.star_rounded, size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              actionText,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 2.0,
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
        borderRadius: BorderRadius.circular(6),
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
            borderRadius: BorderRadius.circular(8),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.split('').join(' '), // 标题拉开字间距
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 10,
              letterSpacing: 4.0,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.016),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(.065)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: <Widget>[
                SizedBox(
                  height: constraints.maxHeight,
                  child: Center(
                    child: Text(
                      loading ? '正在整理经历…' : '故事刚刚开始',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9A9A9A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            decoration: BoxDecoration(
              color: _archiveSurfaceSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.isEmpty ? '你的旅程' : title,
                  style: const TextStyle(
                    color: _archiveText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  summary.isEmpty ? '故事留下的节点与记忆' : summary,
                  style: const TextStyle(
                    color: _archiveMuted,
                    fontSize: 11.2,
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
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                color: _archiveMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            decoration: BoxDecoration(
              color: _archiveSurfaceSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: children),
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: _archiveMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _archiveTextSoft,
                fontSize: 12.2,
                height: 1.65,
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




// ============================================================================
// Light archive palette
// 人物 / 背包 / 档案 / 经历统一使用近白冷中性色。
// 强调色统一引用 NovelPalette 的抹茶绿体系，只用于选中、主操作和状态。
// ============================================================================
const Color _archiveBackground = Color(0xFFFFFFFF);
const Color _archiveSurface = Color(0xFFFFFFFF);
const Color _archiveSurfaceSoft = Color(0xFFF6F7F6);
const Color _archiveText = Color(0xFF1F2420);
const Color _archiveTextSoft = Color(0xFF404640);
const Color _archiveMuted = Color(0xFF707770);
const Color _archiveMutedSoft = Color(0xFF969C96);
const Color _archiveLine = Color(0xFFE4E8E4);
const Color _archiveAccent = NovelPalette.accentDeep;
const Color _archiveThemeGreen = NovelPalette.accent;

// 经历页与人物 / 背包 / 设置统一引用 NovelPalette 主绿色；正文和结构线保持中性灰。
const Color _journeyMatcha = NovelPalette.accent;
const Color _journeyMatchaDeep = NovelPalette.accentDeep;
const Color _journeyMatchaSoft = NovelPalette.accentSoft;
const Color _journeyMatchaLine = NovelPalette.accentLine;

// ============================================================================
// Game archive visual system
// 角色 / 角色档案 / 背包 / 经历共用一套“深色场景 + 香槟金信息层”视觉语言。
// 只借鉴游戏信息层级，不照搬参考游戏的货币栏、功能大厅等无关结构。
// ============================================================================

class _GameStyleBackdrop extends StatelessWidget {
  const _GameStyleBackdrop({
    required this.controller,
    required this.child,
    this.embedded = false,
    this.overlayColor = const Color(0x42000000),
    this.lightTheme = false,
  });

  final NovelGameController controller;
  final Widget child;
  final bool embedded;
  final Color overlayColor;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    // 独立全屏打开时，由它负责提供安全区
    final content = embedded
        ? _NovelPrimaryTabSafeContent(child: child)
        : SafeArea(child: child);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (lightTheme) ...<Widget>[
          const ColoredBox(color: _archiveBackground),
        ] else ...<Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.02),
                radius: 1.08,
                colors: <Color>[
                  Color(0xFF272B32),
                  Color(0xFF191C22),
                  Color(0xFF090B0F),
                ],
                stops: <double>[0, .58, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x26000000),
                  Colors.transparent,
                  Color(0x3D000000),
                ],
                stops: <double>[0, .46, 1],
              ),
            ),
          ),
        ],
        content,
      ],
    );
  }
}



class _GameStyleHeader extends StatelessWidget {
  const _GameStyleHeader({
    required this.title,
    required this.english,
    this.onClose,
    this.lightTheme = false,
  });

  final String title;
  final String english;
  final VoidCallback? onClose;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 13, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: lightTheme
                        ? _archiveText
                        : const Color(0xFFF5F7FA),
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    shadows: lightTheme
                        ? const <Shadow>[]
                        : const <Shadow>[
                            Shadow(
                              color: Color(0x88000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  english,
                  style: TextStyle(
                    color: lightTheme
                        ? _archiveMutedSoft
                        : const Color(0x99DCE1E7),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null) ...<Widget>[
            _GameStyleHeaderIcon(
              tooltip: '关闭',
              icon: Icons.close_rounded,
              onTap: onClose,
              lightTheme: lightTheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _GameStyleHeaderIcon extends StatelessWidget {
  const _GameStyleHeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.lightTheme = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? (lightTheme
                      ? _archiveMutedSoft
                      : const Color(0x667D7565))
                  : (lightTheme
                      ? _archiveTextSoft
                      : const Color(0xFFE2E6EB)),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameStyleSectionTitle extends StatelessWidget {
  const _GameStyleSectionTitle({
    required this.title,
    this.count,
    this.lightTheme = false,
  });

  final String title;
  final int? count;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: lightTheme
                ? _archiveTextSoft
                : const Color(0xFFE7EAEE),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
          ),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              color: lightTheme
                  ? _archiveMuted
                  : const Color(0xFF827B6D),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: .7,
            color: lightTheme
                ? _archiveLine
                : const Color(0x2EFFFFFF),
          ),
        ),
      ],
    );
  }
}

class _GameStyleSkillView {
  const _GameStyleSkillView({
    required this.name,
    this.mastery = '',
    this.description = '',
    this.isAbility = false,
  });

  final String name;
  final String mastery;
  final String description;
  final bool isAbility;
}

class _GameStyleInventoryPage extends StatefulWidget {
  const _GameStyleInventoryPage({
    required this.controller,
    this.embedded = false,
  });

  final NovelGameController controller;
  final bool embedded;

  @override
  State<_GameStyleInventoryPage> createState() => _GameStyleInventoryPageState();
}

class _GameStyleInventoryPageState extends State<_GameStyleInventoryPage> {
  bool loading = true;
  String busy = '';

  static const Set<String> _wearableTypes = <String>{
    'weapon',
    'wearable',
    'armor',
    'accessory',
    'head',
    'face',
    'upper',
    'lower',
    'feet',
    'back',
    'handheld',
  };

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
    await Future.wait<void>(<Future<void>>[
      widget.controller.refreshInventory(notify: false),
      widget.controller.refreshCharacterStatus(notify: false),
    ]);
    if (mounted) setState(() => loading = false);
  }

  List<NovelInventoryItem> _allItems(NovelInventoryData data) {
    final result = <NovelInventoryItem>[];
    final seen = <String>{};
    for (final item in <NovelInventoryItem>[
      ...data.storyItems,
      ...data.consumables,
    ]) {
      final key = item.id.trim().isNotEmpty
          ? 'id:${item.id.trim()}'
          : '${item.itemType.trim()}:${item.name.trim()}';
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  String _itemSlot(NovelInventoryItem item) {
    final raw = item.raw;
    final explicit = stringValue(raw['slot'] ?? raw['wear_slot']).trim().toLowerCase();
    if (explicit.isNotEmpty) {
      if (explicit.contains('头')) return 'head';
      if (explicit.contains('面')) return 'face';
      if (explicit.contains('上身') || explicit.contains('衣')) return 'upper';
      if (explicit.contains('下身') || explicit.contains('裤')) return 'lower';
      if (explicit.contains('脚') || explicit.contains('鞋')) return 'feet';
      if (explicit.contains('背') || explicit.contains('披风') || explicit.contains('翅膀')) return 'back';
      if (explicit.contains('手持') || explicit.contains('武器') || explicit == 'weapon') return 'handheld';
      if (explicit.contains('饰') || explicit.contains('首饰') || explicit.contains('项链') || explicit.contains('戒指')) return 'accessory';
      return explicit;
    }
    return switch (item.itemType.trim().toLowerCase()) {
      'weapon' => 'handheld',
      'wearable' || 'armor' => 'upper',
      'accessory' => 'accessory',
      _ => '',
    };
  }

  bool _isWearable(NovelInventoryItem item) {
    return item.isEquipped ||
        _wearableTypes.contains(item.itemType.trim().toLowerCase()) ||
        _itemSlot(item).isNotEmpty;
  }

  String _typeLabel(String type) {
    return switch (type.trim().toLowerCase()) {
      'consumable' => '消耗',
      'material' => '材料',
      'quest' => '任务',
      'gift' => '赠礼',
      'blind_box' => '福袋',
      'lucky_card' => '特殊',
      'weapon' => '武器',
      'wearable' || 'armor' => '防具',
      'accessory' => '饰品',
      _ => '物品',
    };
  }

  List<_GameStyleSkillView> _skills(NovelCharacter? host) {
    final status = host?.status ?? const <String, dynamic>{};
    final result = <_GameStyleSkillView>[];
    final names = <String>{};
    final rawSkills = status['skills'];
    if (rawSkills is List) {
      for (final raw in rawSkills) {
        if (raw is String) {
          final name = raw.trim();
          if (name.isNotEmpty && names.add(name)) {
            result.add(_GameStyleSkillView(name: name));
          }
          continue;
        }
        if (raw is Map) {
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          final name = stringValue(map['name']).trim();
          if (name.isEmpty || !names.add(name)) continue;
          result.add(_GameStyleSkillView(
            name: name,
            mastery: stringValue(map['mastery']).trim(),
            description: stringValue(map['description']).trim(),
          ));
        }
      }
    }
    final rawAbilities = status['abilities'];
    if (rawAbilities is List) {
      for (final raw in rawAbilities) {
        final name = stringValue(raw).trim();
        if (name.isNotEmpty && names.add(name)) {
          result.add(_GameStyleSkillView(name: name, isAbility: true));
        }
      }
    }
    return result;
  }

  Future<void> _toggleWear(NovelInventoryItem item) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = item.id);
    try {
      await widget.controller.setEquipped(item, !item.isEquipped);
    } finally {
      if (mounted) setState(() => busy = '');
    }
  }

  Future<void> _showItemDetail(NovelInventoryItem item) async {
    final wearable = _isWearable(item);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情',
      barrierColor: Colors.black.withOpacity(.72),
      pageBuilder: (dialogContext, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: _archiveSurface,
                  border: Border.all(color: _archiveLine, width: .8),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x22000000), blurRadius: 28, offset: Offset(0, 12)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              color: Color(0xFF252622),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _typeLabel(item.itemType),
                          style: const TextStyle(
                            color: Color(0xFF646660),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (item.quantity > 1) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '持有 ×${item.quantity}',
                        style: const TextStyle(color: Color(0xFF696B65), fontSize: 10.5),
                      ),
                    ],
                    const SizedBox(height: 13),
                    Container(height: .7, color: _archiveLine),
                    const SizedBox(height: 13),
                    Text(
                      item.description.trim().isEmpty ? '暂无详细描述' : item.description.trim(),
                      style: const TextStyle(
                        color: Color(0xFF3D3E3A),
                        fontSize: 12,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              '关闭',
                              style: TextStyle(color: Color(0xFF60625C), fontSize: 11.5),
                            ),
                          ),
                        ),
                        if (wearable) ...<Widget>[
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: item.isEquipped
                                    ? _archiveSurfaceSoft
                                    : _archiveAccent,
                                foregroundColor: item.isEquipped
                                    ? _archiveMuted
                                    : _archiveSurface,
                                shape: const RoundedRectangleBorder(),
                              ),
                              onPressed: busy.isNotEmpty
                                  ? null
                                  : () {
                                      Navigator.of(dialogContext).pop();
                                      unawaited(_toggleWear(item));
                                    },
                              child: Text(item.isEquipped ? '卸下' : '穿戴'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hero(NovelCharacter? host, List<NovelInventoryItem> equipped, List<_GameStyleSkillView> skills) {
    final name = host?.name.trim().isNotEmpty == true
        ? host!.name
        : widget.controller.protagonistName;
    final status = host?.status ?? const <String, dynamic>{};
    final identity = stringValue(status['identity'] ?? host?.persona['identity']).trim();
    final level = stringValue(status['level']).trim();
    final condition = widget.controller.protagonistCondition.trim();
    final avatar = host?.avatarUrl.trim() ?? '';
    final fallback = host?.gender.trim() == '女'
        ? 'assets/images/female.webp'
        : 'assets/images/male.webp';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _archiveLine, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: NovelArtwork(
                  url: avatar,
                  assetCandidates: <String>[fallback],
                  fit: BoxFit.cover,
                  fallbackText: name,
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
                        color: Color(0xFF22231F),
                        fontSize: 21,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: <Widget>[
                        if (identity.isNotEmpty) _GameStyleMetaText(identity, lightTheme: true),
                        if (level.isNotEmpty) _GameStyleMetaText('境界 · $level', lightTheme: true),
                        if (condition.isNotEmpty) _GameStyleMetaText(condition, lightTheme: true),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => showNovelHostProfileSheet(context, widget.controller),
                child: const Text(
                  '档案',
                  style: TextStyle(
                    color: Color(0xFF555752),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (skills.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            _GameStyleSectionTitle(title: '技能', count: skills.length, lightTheme: true),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: skills.take(8).map((skill) {
                final meta = skill.isAbility
                    ? '能力'
                    : (skill.mastery.isEmpty ? '' : skill.mastery);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: _archiveSurfaceSoft,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    meta.isEmpty ? skill.name : '${skill.name} · $meta',
                    style: const TextStyle(
                      color: Color(0xFF383A35),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (equipped.isNotEmpty) ...<Widget>[
            const SizedBox(height: 17),
            _GameStyleSectionTitle(title: '当前穿戴', count: equipped.length, lightTheme: true),
            const SizedBox(height: 7),
            Wrap(
              spacing: 13,
              runSpacing: 6,
              children: equipped.map((item) {
                return InkWell(
                  onTap: () => _showItemDetail(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        color: Color(0xFF343631),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inventoryList(List<NovelInventoryItem> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _GameStyleSectionTitle(title: '物品', count: items.length, lightTheme: true),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Expanded(
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _archiveSurfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  loading ? '正在整理…' : '空空如也',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF62645F),
                    fontSize: 11.5,
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: _archiveSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _archiveLine, width: 1),
              ),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < items.length; i++) ...<Widget>[
                    _GameStyleInventoryRow(
                      item: items[i],
                      typeLabel: _typeLabel(items[i].itemType),
                      wearable: _isWearable(items[i]),
                      busy: busy == items[i].id,
                      onTap: () => _showItemDetail(items[i]),
                      onWear: () => _toggleWear(items[i]),
                    ),
                    if (i != items.length - 1)
                      Container(
                        height: .7,
                        margin: const EdgeInsets.symmetric(horizontal: 13),
                        color: _archiveLine,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final host = widget.controller.protagonist;
        final data = widget.controller.inventory;
        final items = _allItems(data);
        final equipped = items.where((item) => _isWearable(item) && item.isEquipped).toList();
        final skills = _skills(host);

        return _GameStyleBackdrop(
          controller: widget.controller,
          embedded: widget.embedded,
          lightTheme: true,
          child: Column(
            children: <Widget>[
              _GameStyleHeader(
                title: '背包',
                english: 'INVENTORY',
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
                lightTheme: true,
              ),
              Expanded(
                child: ColoredBox(
                  color: _archiveBackground,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 8 : 26,
                          compact ? 2 : 8,
                          compact ? 8 : 26,
                          compact ? 4 : 10,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: _archiveAccent,
                              backgroundColor: _archiveSurface,
                              child: CustomScrollView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                slivers: <Widget>[
                                  SliverToBoxAdapter(
                                    child: _hero(host, equipped, skills),
                                  ),
                                  // 空背包时灰色物品区域继续铺满剩余高度。
                                  if (items.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _inventoryList(items),
                                    )
                                  else
                                    SliverToBoxAdapter(
                                      child: _inventoryList(items),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GameStyleInventoryRow extends StatelessWidget {
  const _GameStyleInventoryRow({
    required this.item,
    required this.typeLabel,
    required this.wearable,
    required this.busy,
    required this.onTap,
    required this.onWear,
  });

  final NovelInventoryItem item;
  final String typeLabel;
  final bool wearable;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onWear;

  @override
  Widget build(BuildContext context) {
    final equipped = wearable && item.isEquipped;
    return Material(
      color: equipped ? Color(0x0D4F8E4A) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 11, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: equipped
                                  ? _archiveText
                                  : _archiveText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typeLabel,
                          style: const TextStyle(
                            color: Color(0xFF666862),
                            fontSize: 9.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.quantity > 1) ...<Widget>[
                          const SizedBox(width: 6),
                          Text(
                            '×${item.quantity}',
                            style: const TextStyle(
                              color: Color(0xFF5F615B),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item.description.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.description.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF656761),
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (wearable) ...<Widget>[
                const SizedBox(width: 10),
                InkWell(
                  onTap: busy ? null : onWear,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: equipped ? _archiveLine : _archiveTextSoft,
                        width: 1,
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.3,
                              color: Color(0xFF60625C),
                            ),
                          )
                        : Text(
                            equipped ? '卸下' : '穿戴',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: equipped
                                  ? _archiveMuted
                                  : _archiveText,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GameStyleMetaText extends StatelessWidget {
  const _GameStyleMetaText(
    this.text, {
    this.accent = false,
    this.lightTheme = false,
  });

  final String text;
  final bool accent;
  final bool lightTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // 白绿主题下使用淡绿底色
        color: lightTheme 
            ? NovelPalette.accent.withOpacity(.12) 
            : Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          // 白绿主题下使用绿色文字
          color: lightTheme
              ? NovelPalette.accentDeep
              : (accent
                  ? const Color(0xFFD9DEE4)
                  : const Color(0xFFA5ABB3)),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GameStyleCharacterProfilePage extends StatelessWidget {
  const _GameStyleCharacterProfilePage({
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

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map(stringValue).where((e) => e.trim().isNotEmpty).toList();
  }

  Color _conditionColor(String value) {
    final v = value.toLowerCase();
    if (v.contains('濒死') || v.contains('dying') || v.contains('near_death')) {
      return const Color(0xFF9E4F78);
    }
    if (v.contains('重伤') || v.contains('heavy')) return const Color(0xFFE07A78);
    if (v.contains('轻伤') || v.contains('light')) return const Color(0xFFA16A2B);
    return _archiveTextSoft;
  }

  // 小标题：大写字母间距，替代原来的“色块 + 加粗标题”表单式写法
  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _archiveMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }

  // 一条极细的分隔线，用留白 + 发丝线区分区块，而不是灰底色块
  Widget _hairline() {
    return Container(height: .7, color: _archiveLine);
  }

  // 正文段落：不再套灰色卡片容器，靠留白与小标题建立层级
  Widget _paragraphSection(String title, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionLabel(title),
          const SizedBox(height: 14),
          Text(
            text.trim(),
            style: const TextStyle(
              color: _archiveTextSoft,
              fontSize: 14,
              height: 1.9,
              fontWeight: FontWeight.w500,
              letterSpacing: .1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = character;
    final status = c?.status ?? const <String, dynamic>{};
    final persona = c?.persona ?? const <String, dynamic>{};
    final name = c?.name.trim().isNotEmpty == true ? c!.name : fallbackName;
    final identity = stringValue(status['identity'] ?? persona['identity']).trim();
    final level = stringValue(status['level']).trim();
    final combatPower = stringValue(status['combat_power']).trim();
    final deathCount = intValue(status['death_count'], -1);
    final rawCondition = stringValue(status['current_condition'], condition).trim();
    final personality = stringValue(status['personality'] ?? persona['personality']).trim();
    final background = stringValue(status['background'] ?? persona['background']).trim();
    final description = stringValue(status['description'] ?? persona['description']).trim();
    final appearance = stringValue(status['appearance'] ?? persona['appearance']).trim();
    final injuries = _stringList(status['injuries']);
    final limits = _stringList(status['known_limits']);
    final conditionColor = _conditionColor(rawCondition);
    final hasStatus = injuries.isNotEmpty || limits.isNotEmpty;
    final hasParagraphs = description.isNotEmpty ||
        personality.isNotEmpty ||
        background.isNotEmpty ||
        appearance.isNotEmpty;

    final avatar = c?.avatarUrl.trim().isNotEmpty == true
        ? c!.avatarUrl.trim()
        : (c?.portraitUrl.trim().isNotEmpty == true ? c!.portraitUrl.trim() : '');
    final fallback = c?.gender.trim() == '男'
        ? 'assets/images/portrait_male.png'
        : 'assets/images/portrait_female.webp';

    return _GameStyleBackdrop(
      controller: controller,
      lightTheme: true,
      child: Column(
        children: <Widget>[
          _GameStyleHeader(
            title: isHostProfile ? '主角档案' : '角色档案',
            english: 'PROFILE',
            onClose: () => Navigator.of(context).pop(),
            lightTheme: true,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isHostProfile ? double.infinity : 900,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      isHostProfile ? 26 : 30,
                      18,
                      isHostProfile ? 26 : 30,
                      64,
                    ),
                    children: <Widget>[
                      // --- 1. 人物头部：头像 + 名字，不再套灰底卡片 ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SizedBox.square(
                              dimension: 96,
                              child: NovelArtwork(
                                url: avatar,
                                assetCandidates: <String>[fallback],
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                fallbackText: name,
                                fallbackIcon: Icons.person_outline_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _archiveText,
                                    fontSize: 25,
                                    height: 1.15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  identity.isEmpty ? (isHostProfile ? '故事主角' : '故事人物') : identity,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _archiveMuted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // --- 2. 标签行：性别 / 境界 / 轮回 / 好感，留出充足呼吸感 ---
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          if (c?.gender.trim().isNotEmpty == true)
                            _GameStyleMetaText(c!.gender.trim(), lightTheme: true),
                          if (level.isNotEmpty)
                            _GameStyleMetaText('境界 · $level', lightTheme: true),
                          if (deathCount >= 0)
                            _GameStyleMetaText(
                              '轮回 · $deathCount',
                              accent: deathCount > 0,
                              lightTheme: true,
                            ),
                          if (c != null && !c.isMain)
                            _GameStyleMetaText(
                              '${c.affectionLabel.isEmpty ? '好感' : c.affectionLabel} · ${c.affection}',
                              accent: true,
                              lightTheme: true,
                            ),
                        ],
                      ),

                      // --- 3. 状态 / 战力，一行淡淡带过，不再装进色块 ---
                      if (rawCondition.isNotEmpty || combatPower.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: conditionColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rawCondition.isEmpty ? '状态未知' : rawCondition,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: conditionColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (combatPower.isNotEmpty)
                              Text(
                                '战力 $combatPower',
                                style: const TextStyle(
                                  color: _archiveMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],

                      // --- 4. 状态记录：去掉灰底卡片，用留白 + 细线区隔 ---
                      if (hasStatus) ...<Widget>[
                        const SizedBox(height: 36),
                        _hairline(),
                        const SizedBox(height: 24),
                        _sectionLabel('状态记录'),
                        const SizedBox(height: 14),
                        for (final injury in injuries)
                          _GameStyleProfileStatusLine(text: injury, color: const Color(0xFFE07A78)),
                        for (final limit in limits)
                          _GameStyleProfileStatusLine(text: '限制：$limit', color: _archiveMuted),
                      ],

                      // --- 5. 简介 / 性格 / 身世 / 外貌，逐段留白，不再逐个套卡片 ---
                      if (!hasStatus && hasParagraphs) ...<Widget>[
                        const SizedBox(height: 36),
                        _hairline(),
                      ],
                      _paragraphSection('人物简介', description),
                      _paragraphSection('性格特征', personality),
                      _paragraphSection(isHostProfile ? '身世' : '人物背景', background),
                      _paragraphSection('外貌设定', appearance),

                      // --- 6. 形象编辑：唯一保留浅底容器的区块，因为它承载可交互控件 ---
                      if (c != null) ...<Widget>[
                        const SizedBox(height: 40),
                        _hairline(),
                        const SizedBox(height: 24),
                        _sectionLabel('形象设定'),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7F6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: _InlineCharacterVisualEditor(
                            controller: controller,
                            character: c,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameStyleProfileStatusLine extends StatelessWidget {
  const _GameStyleProfileStatusLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4, 
              height: 4, 
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.55, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameStyleJourneyRecord {
  const _GameStyleJourneyRecord({
    required this.title,
    this.detail = '',
    this.time = '',
  });

  final String title;
  final String detail;
  final String time;

  bool get hasDetail => detail.trim().isNotEmpty && detail.trim() != title.trim();
}

class _GameStyleJourneyPage extends StatefulWidget {
  const _GameStyleJourneyPage({
    required this.controller,
    this.embedded = false,
  });

  final NovelGameController controller;
  final bool embedded;

  @override
  State<_GameStyleJourneyPage> createState() => _GameStyleJourneyPageState();
}

class _GameStyleJourneyPageState extends State<_GameStyleJourneyPage> {
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

  JsonMap _source(JsonMap data) {
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

  _GameStyleJourneyRecord? _recordOf(dynamic raw) {
    if (raw == null) return null;

    if (raw is String || raw is num || raw is bool) {
      final text = stringValue(raw).trim();
      if (text.isEmpty) return null;
      return _GameStyleJourneyRecord(title: text);
    }

    final map = asJsonMap(raw);
    if (map.isEmpty) return null;

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
      map['chapter'] ??
          map['time'] ??
          map['date'] ??
          map['turn_label'],
    ).trim();

    final primary = title.isNotEmpty ? title : detail;
    if (primary.isEmpty) return null;

    return _GameStyleJourneyRecord(
      title: primary,
      detail: title.isNotEmpty ? detail : '',
      time: time,
    );
  }

  List<_GameStyleJourneyRecord> _recordsOf(
    JsonMap source,
    List<String> keys,
  ) {
    return _listOf(source, keys)
        .map(_recordOf)
        .whereType<_GameStyleJourneyRecord>()
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final source = _source(widget.controller.journey);

        final title = _plainText(
          source['scenario_title'] ??
              source['title'] ??
              source['scenario_name'],
        );

        final summary = _plainText(
          source['journey_summary'] ??
              source['story_summary'] ??
              source['summary'] ??
              source['description'],
        );

        final achievements = _recordsOf(
          source,
          const <String>[
            'key_achievements',
            'achievements',
            'important_experiences',
          ],
        );

        final events = _recordsOf(
          source,
          const <String>[
            'triggered_events',
            'events',
            'event_history',
            'timeline',
            'records',
            'journey',
          ],
        );

        final milestones = _recordsOf(
          source,
          const <String>[
            'milestones',
            'key_milestones',
            'past_milestones',
          ],
        );

        final hasContent = summary.isNotEmpty ||
            achievements.isNotEmpty ||
            events.isNotEmpty ||
            milestones.isNotEmpty;

        return _GameStyleBackdrop(
          controller: widget.controller,
          embedded: widget.embedded,
          lightTheme: true,
          child: Column(
            children: <Widget>[
              _GameStyleHeader(
                title: '经历',
                english: 'JOURNEY',
                onClose: widget.embedded
                    ? null
                    : () => Navigator.of(context).pop(),
                lightTheme: true,
              ),
              Expanded(
                child: ColoredBox(
                  color: _archiveBackground,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 10 : 30,
                          compact ? 2 : 8,
                          compact ? 10 : 30,
                          compact ? 4 : 12,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              color: NovelPalette.accent,
                              backgroundColor: _archiveSurface,
                              child: hasContent
                                  ? ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          26, 14, 26, 46),
                                      children: <Widget>[
                                        _JourneyStoryOpening(
                                          title: title.isEmpty
                                              ? '你的旅程'
                                              : title,
                                          summary: summary,
                                          achievements:
                                              achievements.length,
                                          events: events.length,
                                          milestones: milestones.length,
                                        ),
                                        if (achievements.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'MEMORIES',
                                            title: '重要经历',
                                            records: achievements,
                                          ),
                                        if (events.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'STORYLINE',
                                            title: '事件轨迹',
                                            records: events,
                                          ),
                                        if (milestones.isNotEmpty)
                                          _GameStyleJourneySection(
                                            eyebrow: 'MILESTONES',
                                            title: '关键节点',
                                            records: milestones,
                                          ),
                                      ],
                                    )
                                  : ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          28, 4, 28, 38),
                                      children: <Widget>[
                                        SizedBox(
                                          height:
                                              MediaQuery.sizeOf(context).height *
                                                  .56,
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                const Text(
                                                  '“',
                                                  style: TextStyle(
                                                    color:
                                                        Color(0xFFD7DCD7),
                                                    fontSize: 52,
                                                    height: .8,
                                                    fontWeight:
                                                        FontWeight.w300,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  loading
                                                      ? '正在整理你的故事…'
                                                      : '故事刚刚开始',
                                                  style: const TextStyle(
                                                    color: _archiveText,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    letterSpacing: .4,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  loading
                                                      ? '把散落的片段重新排成一条旅程。'
                                                      : '当新的选择留下痕迹，它们会在这里成为你的旅程。',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: _archiveMuted,
                                                    fontSize: 11.2,
                                                    height: 1.65,
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
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JourneyStoryOpening extends StatelessWidget {
  const _JourneyStoryOpening({
    required this.title,
    required this.summary,
    required this.achievements,
    required this.events,
    required this.milestones,
  });

  final String title;
  final String summary;
  final int achievements;
  final int events;
  final int milestones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'STORY JOURNAL',
            style: TextStyle(
              color: NovelPalette.accentDeep,
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            style: const TextStyle(
              color: _archiveText,
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: _archiveSurfaceSoft,
              border: Border.all(color: _archiveLine, width: .8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              summary.isEmpty
                  ? '故事仍在继续。每一次选择、相遇与转折，都会在这里留下痕迹。'
                  : summary,
              style: const TextStyle(
                color: _archiveTextSoft,
                fontSize: 12.6,
                height: 1.78,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            runSpacing: 6,
            children: <Widget>[
              _JourneyCountText(label: '经历', value: achievements),
              _JourneyCountText(label: '事件', value: events),
              _JourneyCountText(label: '节点', value: milestones),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: _archiveLine),
        ],
      ),
    );
  }
}

class _JourneyCountText extends StatelessWidget {
  const _JourneyCountText({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label  $value',
      style: const TextStyle(
        color: _archiveMuted,
        fontSize: 9.8,
        fontWeight: FontWeight.w600,
        letterSpacing: .25,
      ),
    );
  }
}

class _GameStyleJourneySection extends StatelessWidget {
  const _GameStyleJourneySection({
    required this.eyebrow,
    required this.title,
    required this.records,
  });

  final String eyebrow;
  final String title;
  final List<_GameStyleJourneyRecord> records;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            eyebrow,
            style: const TextStyle(
              color: NovelPalette.accentDeep,
              fontSize: 8.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: _archiveText,
                  fontSize: 14.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${records.length}',
                style: const TextStyle(
                  color: _archiveMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          for (var i = 0; i < records.length; i++)
            _GameStyleJourneyEntry(
              record: records[i],
              index: i,
              first: i == 0,
              last: i == records.length - 1,
            ),
        ],
      ),
    );
  }
}

class _GameStyleJourneyEntry extends StatelessWidget {
  const _GameStyleJourneyEntry({
    required this.record,
    required this.index,
    required this.first,
    required this.last,
  });

  final _GameStyleJourneyRecord record;
  final int index;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final number = (index + 1).toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 2 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 31,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                number,
                style: const TextStyle(
                  color: _archiveMutedSoft,
                  fontSize: 9.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .7,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (record.time.isNotEmpty) ...<Widget>[
                  Text(
                    record.time,
                    style: const TextStyle(
                      color: _archiveMuted,
                      fontSize: 9.3,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .25,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  record.title,
                  style: const TextStyle(
                    color: _archiveText,
                    fontSize: 12.7,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.hasDetail) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    record.detail,
                    style: const TextStyle(
                      color: _archiveTextSoft,
                      fontSize: 11.5,
                      height: 1.72,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (!last) ...<Widget>[
                  const SizedBox(height: 17),
                  Container(height: .8, color: _archiveLine),
                  const SizedBox(height: 17),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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

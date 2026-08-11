import 'package:flutter/material.dart';

/// 毛玻璃视觉体系。
///
/// 抽屉整体是一层透明的磨砂玻璃，透出背后内容的模糊光影；
/// 强调绿只用于选中态文字底色，其余保持克制。
class AppColors {
  const AppColors._();

  // 深色基底：仅作为毛玻璃的底色叠加，实际显示为半透明
  static const Color ink = Color(0xFF15131C);
  static const Color inkRaised = Color(0xFF1E1B29);
  static const Color inkBorder = Color(0xFF2C2836);

  // 票券卡片：暖米色纸张质感（保留供其他场景使用）
  static const Color paper = Color(0xFFF6EEDF);
  static const Color paperInk = Color(0xFF23180F);
  static const Color paperMuted = Color(0xFF8C7C63);

  // 强调色：与设置面板 --accent 对齐
  static const Color accent = Color.fromARGB(255, 129, 246, 112);
  static const Color accentDeep = Color.fromARGB(255, 169, 249, 128);

  // 深色底上的文字
  static const Color textOnDark = Color(0xFFF5F1E6);
  static const Color textOnDarkMuted = Color(0xFF8B8796);

  static const List<BoxShadow> ticketShadow = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 8)),
  ];

  static List<BoxShadow> accentGlow({double opacity = 0.32}) => [
        BoxShadow(
          color: accent.withOpacity(opacity),
          offset: const Offset(0, 6),
        ),
      ];
}

/// 世界/游戏存档卡片的数据模型
class GameData {
  const GameData({
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.id,
    required this.mode,
  });

  final String title;
  final String category;
  final String imageUrl;

  /// 剧本真实 id，点击进入时用它设为当前剧本
  final String id;

  /// 原始 mode 字段（chat/novel/rpg/online...），以后按模式分发路由用
  final String mode;
}

/// 抽屉头部头像
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.isLoggedIn,
    required this.size,
    required this.onTap,
  });

  final bool isLoggedIn;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.inkRaised,
              border: Border.all(
                color: isLoggedIn ? AppColors.accent : AppColors.inkBorder,
                width: isLoggedIn ? 1.6 : 1,
              ),
            ),
            child: Icon(
              isLoggedIn ? Icons.person_rounded : Icons.person_outline_rounded,
              color: isLoggedIn ? AppColors.accent : AppColors.textOnDarkMuted,
              size: size * 0.5,
            ),
          ),
          if (isLoggedIn)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                  border: Border.all(color: AppColors.ink, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

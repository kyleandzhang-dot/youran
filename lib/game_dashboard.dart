import 'package:flutter/material.dart';

/// 全局配色，风格延续首页的深色 + 低饱和金色（E8C58B）
class AppColors {
  const AppColors._();

  static const Color drawer = Color(0xFF14161A);
  static const Color border = Color(0x1FFFFFFF);
  static const Color surfaceRaised = Color(0x14FFFFFF);
  static const Color selected = Color(0x1FE8C58B);
  static const Color borderSelected = Color(0x66E8C58B);
  static const Color textPrimary = Color(0xFFF5F1E9);
  static const Color textSecondary = Color(0xFFC9C4BA);
  static const Color textMuted = Color(0xFF8B877E);
  static const Color buttonPrimary = Color(0xFFE8C58B);
  static const Color onButtonPrimary = Color(0xFF1A1710);
}

/// 世界/游戏存档卡片的数据模型
class GameData {
  const GameData({
    required this.title,
    required this.category,
    required this.imageUrl,
  });

  final String title;
  final String category;
  final String imageUrl;
}

/// 抽屉头部用的头像，未登录时显示占位图标
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          isLoggedIn ? Icons.person_rounded : Icons.person_outline_rounded,
          color: isLoggedIn ? AppColors.textPrimary : AppColors.textMuted,
          size: size * 0.55,
        ),
      ),
    );
  }
}
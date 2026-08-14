import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovelSettingsService extends ChangeNotifier {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  // 默认剧情阅读字体使用项目内置的 MiSans Regular。
  String fontKey = 'font-misans';
  double fontSize = 15;
  String themeKey = 'theme-glass';
  String customBackground = '';
  String artStyle = 'anime';
  bool weatherEffectsEnabled = true;
  bool typingSoundEnabled = true;

  Future<void> load() async {
    fontKey = await _prefs.getString('novel-font') ?? 'font-misans';
    fontSize = (await _prefs.getInt('novel-size') ?? 15).toDouble();
    themeKey = await _prefs.getString('novel-theme') ?? 'theme-glass';
    customBackground = await _prefs.getString('novel-custom-bg') ?? '';
    artStyle = await _prefs.getString('novel-art-style') ?? 'anime';
    weatherEffectsEnabled =
        await _prefs.getBool('novel-weather-effects-enabled') ?? true;
    typingSoundEnabled =
        await _prefs.getBool('novel-typing-sound-enabled') ?? true;
    // 现在只保留“黑体 / MiSans”两种字体。
    // 旧版本保存过的文楷、宋体或旧 serif key，统一迁移到默认 MiSans；
    // 旧 sans key 则继续对应系统黑体。
    if (fontKey == 'font-sans') {
      fontKey = 'font-hei';
    } else if (fontKey != 'font-hei' && fontKey != 'font-misans') {
      fontKey = 'font-misans';
    }
    await _prefs.setString('novel-font', fontKey);
    // 兼容旧 Flutter 版本曾使用的画风 key，统一到 Vue 当前四种风格。
    if (artStyle == '3d') artStyle = 'stylized_3d';
    if (artStyle == 'real') artStyle = 'realistic';
    notifyListeners();
  }

  Future<void> setFont(String value) async {
    // 设置页只允许黑体和 MiSans，其他历史 key 一律回到 MiSans。
    fontKey = value == 'font-hei' ? 'font-hei' : 'font-misans';
    await _prefs.setString('novel-font', fontKey);
    notifyListeners();
  }

  Future<void> setFontSize(double value) async {
    fontSize = value.clamp(12.0, 24.0).toDouble();
    await _prefs.setInt('novel-size', fontSize.round());
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    themeKey = value;
    await _prefs.setString('novel-theme', value);
    notifyListeners();
  }

  Future<void> setArtStyle(String value) async {
    artStyle = value;
    await _prefs.setString('novel-art-style', value);
    notifyListeners();
  }


  Future<void> setWeatherEffectsEnabled(bool value) async {
    weatherEffectsEnabled = value;
    await _prefs.setBool('novel-weather-effects-enabled', value);
    notifyListeners();
  }

  Future<void> setTypingSoundEnabled(bool value) async {
    typingSoundEnabled = value;
    await _prefs.setBool('novel-typing-sound-enabled', value);
    notifyListeners();
  }

  Future<void> setCustomBackground(String value) async {
    customBackground = value;
    if (value.isEmpty) {
      await _prefs.remove('novel-custom-bg');
    } else {
      await _prefs.setString('novel-custom-bg', value);
    }
    notifyListeners();
  }

  String? get fontFamily {
    return switch (fontKey) {
      // 黑体继续使用当前平台系统字体。
      'font-hei' => null,
      // MiSans 是默认剧情阅读字体；异常/旧 key 也回退到 MiSans。
      'font-misans' => 'NovelMiSans',
      _ => 'NovelMiSans',
    };
  }

  Color get backgroundColor {
    return switch (themeKey) {
      'theme-fresh' => const Color(0xFFFFFFFF),
      'theme-dark' => const Color(0xFF1E1E1E),
      'theme-green' => const Color(0xFFC7EDCC),
      'theme-sepia' => const Color(0xFFF6EFE0),
      _ => const Color(0xFF090A09),
    };
  }

  bool get isDark => themeKey == 'theme-dark' || themeKey == 'theme-glass';
}

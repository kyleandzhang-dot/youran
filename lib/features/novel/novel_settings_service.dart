import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovelSettingsService extends ChangeNotifier {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  String fontKey = 'font-wenkai';
  double fontSize = 15;
  String themeKey = 'theme-glass';
  String customBackground = '';
  String artStyle = 'anime';
  bool weatherEffectsEnabled = true;

  Future<void> load() async {
    fontKey = await _prefs.getString('novel-font') ?? 'font-wenkai';
    fontSize = (await _prefs.getInt('novel-size') ?? 15).toDouble();
    themeKey = await _prefs.getString('novel-theme') ?? 'theme-glass';
    customBackground = await _prefs.getString('novel-custom-bg') ?? '';
    artStyle = await _prefs.getString('novel-art-style') ?? 'anime';
    weatherEffectsEnabled =
        await _prefs.getBool('novel-weather-effects-enabled') ?? true;
    // 兼容旧 Flutter 版本曾使用的字体 key，并统一成 Vue 当前 key。
    if (fontKey == 'font-serif') fontKey = 'font-song';
    if (fontKey == 'font-sans') fontKey = 'font-hei';
    // 兼容旧 Flutter 版本曾使用的画风 key，统一到 Vue 当前四种风格。
    if (artStyle == '3d') artStyle = 'stylized_3d';
    if (artStyle == 'real') artStyle = 'realistic';
    notifyListeners();
  }

  Future<void> setFont(String value) async {
    fontKey = value;
    await _prefs.setString('novel-font', value);
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
      'font-wenkai' => 'NovelWenKai',
      'font-song' => 'NovelSerif',
      // 系统黑体和 MiSans 在未提供对应字体资产时使用系统字体兜底。
      'font-hei' || 'font-misans' => null,
      _ => null,
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

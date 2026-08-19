import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovelSettingsService extends ChangeNotifier {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  // 默认剧情阅读字体使用系统黑体；用户可在设置中切换四种字体。
  String fontKey = 'font-hei';
  double fontSize = 13;
  String themeKey = 'theme-glass';
  String customBackground = '';
  String artStyle = 'anime';
  bool weatherEffectsEnabled = true;
  bool typingSoundEnabled = true;

  Future<void> load() async {
    fontKey = await _prefs.getString('novel-font') ?? 'font-hei';
    fontSize = (await _prefs.getInt('novel-size') ?? 13).toDouble();
    themeKey = await _prefs.getString('novel-theme') ?? 'theme-glass';
    // 旧版本的绿色阅读主题不再属于当前小说美术体系，自动迁移到深色玻璃主题。
    if (themeKey == 'theme-green') {
      themeKey = 'theme-glass';
      await _prefs.setString('novel-theme', themeKey);
    }
    customBackground = await _prefs.getString('novel-custom-bg') ?? '';
    artStyle = await _prefs.getString('novel-art-style') ?? 'anime';
    weatherEffectsEnabled =
        await _prefs.getBool('novel-weather-effects-enabled') ?? true;
    typingSoundEnabled =
        await _prefs.getBool('novel-typing-sound-enabled') ?? true;
    // 剧情阅读字体支持：黑体 / MiSans / 宋体 / 文楷。
    // 兼容旧版本曾使用过的 key；未知 key 回到默认系统黑体。
    fontKey = switch (fontKey) {
      'font-sans' => 'font-hei',
      'font-serif' || 'font-songti' => 'font-song',
      'font-kai' => 'font-wenkai',
      'font-hei' || 'font-misans' || 'font-song' || 'font-wenkai' => fontKey,
      _ => 'font-hei',
    };
    await _prefs.setString('novel-font', fontKey);
    // 兼容旧 Flutter 版本曾使用的画风 key，统一到 Vue 当前四种风格。
    if (artStyle == '3d') artStyle = 'stylized_3d';
    if (artStyle == 'real') artStyle = 'realistic';
    notifyListeners();
  }

  Future<void> setFont(String value) async {
    const allowed = <String>{
      'font-hei',
      'font-misans',
      'font-song',
      'font-wenkai',
    };
    fontKey = allowed.contains(value) ? value : 'font-hei';
    await _prefs.setString('novel-font', fontKey);
    notifyListeners();
  }

  static const Map<String, String> fontLabels = <String, String>{
    'font-hei': '黑体',
    'font-misans': 'MiSans',
    'font-song': '宋体',
    'font-wenkai': '文楷',
  };

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
      // 黑体使用当前平台默认 sans-serif 字体。
      'font-hei' => null,
      'font-misans' => 'NovelMiSans',
      'font-song' => 'WenJinMinchoP0',
      'font-wenkai' => 'LXGWWenKaiGBScreen',
      // 异常 key 与未加载状态都回到默认系统黑体。
      _ => null,
    };
  }

  Color get backgroundColor {
    return switch (themeKey) {
      'theme-fresh' => const Color(0xFFFFFFFF),
      'theme-dark' => const Color(0xFF1E1E1E),
      // 兼容极旧 key：即使未经过 load() 迁移，也不再回退到绿色。
      'theme-green' => const Color(0xFF15120F),
      'theme-sepia' => const Color(0xFFF6EFE0),
      _ => const Color(0xFF15120F),
    };
  }

  bool get isDark => themeKey == 'theme-dark' || themeKey == 'theme-glass';
}

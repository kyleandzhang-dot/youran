import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api/api_client.dart';
import 'api/scenario_editor_api.dart';
import 'app_shared.dart';

const Color _editorInk = Color(0xFF151921);
const Color _editorInkSoft = Color(0xFF1F2530);
const Color _editorSurface = Color(0xFF1D222B);
const Color _editorFieldBg = Color(0xFF11141A);
const Color _editorAccent = Color(0xFF76B900);
const Color _editorText = Color(0xFFFFFFFF);
const Color _editorTextSoft = Color(0xFFE2E8F0);
const Color _editorMuted = Color(0x88FFFFFF);
const Color _editorLine = Color(0x14FFFFFF);

const BorderRadius _editorRadius = BorderRadius.all(Radius.circular(6));
const BorderRadius _editorRadiusLg = BorderRadius.all(Radius.circular(8));

enum ScenarioEditorSection {
  overview,
  characters,
  story,
  bgm,
  lorebook,
}

enum ScenarioMediaKind {
  cover,
  avatar,
  portrait,
  bgm,
}

class ScenarioMediaTarget {
  const ScenarioMediaTarget({
    required this.kind,
    this.characterIndex,
    this.bgmIndex,
  });

  final ScenarioMediaKind kind;
  final int? characterIndex;
  final int? bgmIndex;
}

class ScenarioMediaUploadResult {
  const ScenarioMediaUploadResult({
    required this.url,
    this.r2Key,
  });

  final String url;
  final String? r2Key;
}

typedef ScenarioMediaPicker = Future<ScenarioMediaUploadResult?> Function(
  BuildContext context,
  ScenarioMediaTarget target,
);

/// Connect this callback to the application's actual TTS synthesis/playback service.
/// The editor deliberately does not invent a TTS endpoint or provider-specific voice IDs.
typedef ScenarioVoicePreview = Future<void> Function(
  ScenarioVoicePreviewRequest request,
);

class ScenarioVoicePreviewRequest {
  const ScenarioVoicePreviewRequest({
    required this.characterName,
    required this.voice,
    required this.speed,
    required this.pitch,
    required this.text,
  });

  final String characterName;
  final String voice;
  final double speed;
  final double pitch;
  final String text;
}

class ScenarioEditPage extends StatefulWidget {
  const ScenarioEditPage({
    super.key,
    required this.scenarioId,
    this.api,
    this.onPublish,
    this.onDeleted,
    this.onPickMedia,
    this.onPreviewVoice,
  });

  final String scenarioId;
  final ScenarioEditorApi? api;
  final VoidCallback? onPublish;
  final VoidCallback? onDeleted;
  final ScenarioMediaPicker? onPickMedia;
  final ScenarioVoicePreview? onPreviewVoice;

  @override
  State<ScenarioEditPage> createState() => _ScenarioEditPageState();
}

class _ScenarioEditPageState extends State<ScenarioEditPage> {
  static const Color _pageBg = _editorInk;
  static const Color _danger = Color(0xFFE0554A);

  late final ScenarioEditorApi _api;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _openingController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _cotController = TextEditingController();
  final _responseStyleController = TextEditingController();
  final _mainStoryController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _actionLoading = false;
  bool _dirty = false;
  String? _error;

  ScenarioEditorSection _section = ScenarioEditorSection.overview;

  String _id = '';
  String _coverUrl = '';
  String _mode = 'chat';
  List<String> _tags = <String>[];
  Map<String, dynamic> _worldSetting = <String, dynamic>{};
  List<Map<String, dynamic>> _characters = <Map<String, dynamic>>[];
  Map<String, dynamic> _lorebook = <String, dynamic>{
    'enabled': true,
    'entries': <dynamic>[],
  };
  List<Map<String, dynamic>> _bgmList = <Map<String, dynamic>>[];
  final Set<int> _changedBgmIndexes = <int>{};
  final Set<int> _uploadingBgmIndexes = <int>{};
  final AudioPlayer _bgmPreviewPlayer = AudioPlayer();
  StreamSubscription<ProcessingState>? _bgmPreviewCompleteSubscription;
  int? _previewBgmIndex;
  bool _previewBgmPlaying = false;
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ScenarioEditorApi();
    _bgmPreviewCompleteSubscription =
        _bgmPreviewPlayer.processingStateStream.listen((state) {
      if (state != ProcessingState.completed || !mounted) return;
      setState(() {
        _previewBgmIndex = null;
        _previewBgmPlaying = false;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _openingController.dispose();
    _systemPromptController.dispose();
    _cotController.dispose();
    _responseStyleController.dispose();
    _mainStoryController.dispose();
    _bgmPreviewCompleteSubscription?.cancel();
    _bgmPreviewPlayer.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleCharacters => _characters
      .asMap()
      .entries
      .where((entry) => entry.value['role']?.toString() != 'companion')
      .map((entry) => <String, dynamic>{
            ...entry.value,
            '__realIndex': entry.key,
          })
      .toList();

  List<Map<String, dynamic>> get _plotPoints {
    final value = _worldSetting['key_plot_points'];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map<Map<String, dynamic>>((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{
        'arc': '探索',
        'goal': item?.toString() ?? '',
        'state': item?.toString() ?? '',
        'pacing': 'normal',
      };
    }).toList();
  }

  List<Map<String, dynamic>> get _loreEntries {
    final value = _lorebook['entries'];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map<Map<String, dynamic>>((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    }).toList();
  }

  int get _configuredBgmCount => _bgmList
      .where((item) => (item['url']?.toString().trim().isNotEmpty ?? false))
      .length;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _api.getScenarioDetail(widget.scenarioId);
      if (!mounted) return;

      _id = data['id']?.toString() ?? widget.scenarioId;
      _titleController.text = data['title']?.toString() ?? '';
      _descriptionController.text = data['description']?.toString() ?? '';
      _coverUrl = data['cover_url']?.toString() ?? '';
      _mode = data['mode']?.toString() ?? 'chat';
      _openingController.text = data['opening_message']?.toString() ?? '';
      _systemPromptController.text = data['system_prompt']?.toString() ?? '';
      _cotController.text = data['cot_instruction']?.toString() ?? '';
      _responseStyleController.text = data['response_style']?.toString() ?? '';

      final rawTags = data['tags'];
      _tags = rawTags is List
          ? rawTags.map((e) => e.toString()).toList()
          : <String>[];

      final rawWorld = data['world_setting'];
      _worldSetting = rawWorld is Map
          ? rawWorld.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};

      final topMainStory = data['main_story_arc'];
      _worldSetting['main_story_arc'] =
          _worldSetting['main_story_arc'] ?? topMainStory ?? '';

      final rawPoints =
          _worldSetting['key_plot_points'] ?? data['key_plot_points'];
      final normalizedPoints = <Map<String, dynamic>>[];
      if (rawPoints is List) {
        for (final point in rawPoints) {
          if (point is String) {
            normalizedPoints.add(_newPlotPoint(goal: point));
          } else if (point is Map) {
            normalizedPoints.add(
              point.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
        }
      }
      _worldSetting['key_plot_points'] = normalizedPoints;
      _mainStoryController.text =
          _worldSetting['main_story_arc']?.toString() ?? '';

      final sourceCharacters =
          data['characters_detailed'] ?? data['characters'];
      _characters = <Map<String, dynamic>>[];
      if (sourceCharacters is List) {
        for (final raw in sourceCharacters) {
          if (raw is! Map) continue;
          final map = raw.map((key, value) => MapEntry(key.toString(), value));
          _characters.add(_normalizeCharacter(map));
        }
      }

      final rawLorebook = data['lorebook'];
      if (rawLorebook is Map) {
        _lorebook = rawLorebook.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else {
        _lorebook = <String, dynamic>{
          'enabled': true,
          'entries': <Map<String, dynamic>>[],
        };
      }
      _lorebook['entries'] = _loreEntries;

      _buildBgmList();
      _changedBgmIndexes.clear();

      setState(() {
        _dirty = false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  Map<String, dynamic> _normalizeCharacter(Map<String, dynamic> source) {
    final persona = _parseMap(source['persona']);
    final jsonData = <String, dynamic>{
      ...persona,
      ..._parseMap(source['json_data']),
    };

    final initialConfig = _parseMap(source['initial_config']);
    final customAttributes = _parseMap(source['custom_attributes']);

    if ((jsonData['voice']?.toString().trim().isEmpty ?? true)) {
      jsonData['voice'] = customAttributes['voice'] ?? source['voice'] ?? '';
    }
    if ((jsonData['voice_name']?.toString().trim().isEmpty ?? true)) {
      jsonData['voice_name'] =
          customAttributes['voice_name'] ?? source['voice_name'] ?? '';
    }
    if ((jsonData['trial_url']?.toString().trim().isEmpty ?? true)) {
      jsonData['trial_url'] =
          customAttributes['trial_url'] ?? source['trial_url'] ?? '';
    }
    jsonData['voice_speed'] ??=
        customAttributes['voice_speed'] ?? source['voice_speed'] ?? 1.0;
    jsonData['voice_pitch'] ??=
        customAttributes['voice_pitch'] ?? source['voice_pitch'] ?? 1.1;

    return <String, dynamic>{
      'id': source['id'] ?? DateTime.now().microsecondsSinceEpoch,
      'name': source['name']?.toString() ?? '',
      'role': source['role']?.toString() ?? 'npc',
      'avatar': (source['avatar_url'] ?? source['avatar'])?.toString() ?? '',
      'avatar_seed': source['avatar_seed']?.toString() ?? '',
      'portrait':
          (source['portrait_url'] ?? source['portrait'])?.toString() ?? '',
      'greeting': source['greeting']?.toString() ?? '',
      'persona': persona,
      'initial_config': initialConfig,
      'json_data': jsonData,
      'custom_attributes': customAttributes,
      'voice':
          jsonData['voice'] ?? customAttributes['voice'] ?? source['voice'] ?? '',
      'voice_speed': jsonData['voice_speed'] ??
          customAttributes['voice_speed'] ??
          source['voice_speed'] ??
          1.0,
      'voice_pitch': jsonData['voice_pitch'] ??
          customAttributes['voice_pitch'] ??
          source['voice_pitch'] ??
          1.1,
    };
  }

  Map<String, dynamic> _parseMap(dynamic value) {
    if (value is Map<String, dynamic>) return <String, dynamic>{...value};
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    if (value is String && value.trim().isNotEmpty) {
      return <String, dynamic>{'background': value};
    }
    return <String, dynamic>{};
  }

  void _buildBgmList() {
    final bgmConfig = _parseMap(_worldSetting['bgm_config']);
    final normal = _parseMap(bgmConfig['normal']);
    final combat = _parseMap(bgmConfig['combat']);
    final emotional = _parseMap(bgmConfig['emotional']);

    _bgmList = <Map<String, dynamic>>[
      _bgm('daily_slow', '日常', '舒缓', '慢节奏', 'normal', 'low', normal['low']),
      _bgm('daily_fast', '日常', '欢快', '快节奏', 'normal', 'high', normal['high']),
      _bgm('combat_slow', '冲突', '对峙', '慢节奏', 'combat', 'low', combat['low']),
      _bgm('combat_fast', '冲突', '高潮', '快节奏', 'combat', 'high', combat['high']),
      _bgm('emotion_slow', '情感', '忧伤', '慢节奏', 'emotional', 'low',
          emotional['low']),
      _bgm('emotion_fast', '情感', '爆发', '快节奏', 'emotional', 'high',
          emotional['high']),
    ];
  }

  Map<String, dynamic> _bgm(
    String type,
    String category,
    String title,
    String pace,
    String sceneMode,
    String level,
    dynamic url,
  ) {
    return <String, dynamic>{
      'type': type,
      'category': category,
      'title': title,
      'pace': pace,
      'scene_mode': sceneMode,
      'level': level,
      'url': url?.toString() ?? '',
      'r2_key': '',
    };
  }

  void _markDirty() {
    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  void _setSection(ScenarioEditorSection section) {
    if (_section == section) return;
    if (section != ScenarioEditorSection.bgm && _previewBgmIndex != null) {
      _bgmPreviewPlayer.stop();
      _previewBgmIndex = null;
      _previewBgmPlaying = false;
    }
    setState(() => _section = section);
  }

  Future<void> _handleBackNavigation() async {
    if (!_dirty || _saving) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final discard = await _confirm(
      title: '放弃未保存的修改？',
      description: '当前页面有尚未保存的设定修改，直接退出将丢失本次更改。',
      confirmText: '放弃并退出',
      danger: true,
    );
    if (discard && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleController.text.trim().isEmpty) {
      _showSnack('世界标题不能为空', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      _worldSetting['main_story_arc'] = _mainStoryController.text;
      _worldSetting['bgm_config'] = <String, dynamic>{
        'normal': <String, dynamic>{
          'low': _bgmUrl('daily_slow'),
          'high': _bgmUrl('daily_fast'),
        },
        'combat': <String, dynamic>{
          'low': _bgmUrl('combat_slow'),
          'high': _bgmUrl('combat_fast'),
        },
        'emotional': <String, dynamic>{
          'low': _bgmUrl('emotion_slow'),
          'high': _bgmUrl('emotion_fast'),
        },
      };

      if (_changedBgmIndexes.isNotEmpty) {
        final items = _changedBgmIndexes.map((index) {
          final bgm = _bgmList[index];
          return <String, dynamic>{
            'scene_mode': bgm['scene_mode'],
            'level': bgm['level'],
            'url': bgm['url']?.toString() ?? '',
            'r2_key': bgm['r2_key']?.toString() ?? '',
          };
        }).toList();
        await _api.saveBgmConfig(widget.scenarioId, items);
      }

      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text,
        'cover_url': _coverUrl,
        'tags': _tags,
        'mode': _mode,
        'opening_message': _openingController.text,
        'system_prompt': _systemPromptController.text,
        'cot_instruction': _cotController.text,
        'response_style': _responseStyleController.text,
        'main_story_arc': _mainStoryController.text,
        'key_plot_points': _worldSetting['key_plot_points'] ?? <dynamic>[],
        'world_setting': _worldSetting,
        'characters': _characters.map(_characterPayload).toList(),
        'lorebook': <String, dynamic>{
          'enabled': _lorebook['enabled'] ?? true,
          'entries': _lorebook['entries'] ?? <dynamic>[],
        },
      };

      await _api.updateScenario(widget.scenarioId, payload);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _changedBgmIndexes.clear();
      });
      _showSnack('保存成功');
    } on ApiException catch (e) {
      _showSnack(e.message, error: true);
    } catch (e) {
      _showSnack('保存失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _characterPayload(Map<String, dynamic> c) {
    final jsonData = _parseMap(c['json_data']);
    final persona = <String, dynamic>{..._parseMap(c['persona']), ...jsonData};
    final customAttributes = _parseMap(c['custom_attributes']);
    return <String, dynamic>{
      'id': c['id'],
      'name': c['name']?.toString() ?? '',
      'role': c['role']?.toString() ?? 'npc',
      'avatar': c['avatar']?.toString() ?? '',
      'avatar_seed': c['avatar_seed']?.toString() ?? '',
      'portrait': c['portrait']?.toString() ?? '',
      'greeting': c['greeting']?.toString() ?? '',
      'persona': persona,
      'initial_config': _parseMap(c['initial_config']),
      'voice':
          jsonData['voice'] ?? customAttributes['voice'] ?? c['voice'] ?? '',
      'voice_speed': jsonData['voice_speed'] ??
          customAttributes['voice_speed'] ??
          c['voice_speed'] ??
          1.0,
      'voice_pitch': jsonData['voice_pitch'] ??
          customAttributes['voice_pitch'] ??
          c['voice_pitch'] ??
          1.1,
    };
  }

  String _bgmUrl(String type) {
    final item = _bgmList.firstWhere(
      (e) => e['type'] == type,
      orElse: () => <String, dynamic>{},
    );
    return item['url']?.toString() ?? '';
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: error ? _danger : _editorAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _editorInkSoft,
        shape: const RoundedRectangleBorder(
          borderRadius: _editorRadius,
          side: BorderSide(color: _editorLine),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  ScenarioMediaPicker get _mediaPicker =>
      widget.onPickMedia ?? _pickMediaInternally;

  Future<ScenarioMediaUploadResult?> _pickMediaInternally(
    BuildContext pickerContext,
    ScenarioMediaTarget target,
  ) async {
    final isBgm = target.kind == ScenarioMediaKind.bgm;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: isBgm ? FileType.custom : FileType.image,
        allowedExtensions: isBgm
            ? const <String>['mp3', 'm4a', 'aac', 'ogg', 'wav']
            : null,
        allowMultiple: false,
        withData: true,
      );
    } catch (error) {
      _showSnack('无法打开文件选择器：${_cleanUploadError(error)}', error: true);
      return null;
    }

    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showSnack('${file.name} 读取失败', error: true);
      return null;
    }

    final category = switch (target.kind) {
      ScenarioMediaKind.cover => 'scenario/cover',
      ScenarioMediaKind.avatar => 'char/avatar',
      ScenarioMediaKind.portrait => 'char/portrait',
      ScenarioMediaKind.bgm => 'bgm',
    };

    try {
      final Uint8List uploadBytes;
      final String uploadFileName;
      final String contentType;

      if (isBgm) {
        uploadBytes = bytes;
        uploadFileName = file.name;
        contentType = _contentTypeForUpload(file.name, isAudio: true);
      } else {
        var sourceBytes = bytes;
        if (target.kind == ScenarioMediaKind.cover) {
          final cropped = await _cropSquareCover(pickerContext, bytes);
          if (cropped == null) return null;
          sourceBytes = cropped;
        }

        uploadBytes = await _convertImageToWebp(
          sourceBytes,
          targetSize: target.kind == ScenarioMediaKind.cover ? 1024 : null,
        );
        uploadFileName = _webpFileName(file.name);
        contentType = 'image/webp';
      }

      final signature = await ApiClient.instance.post(
        '/r2/get-signature',
        body: <String, dynamic>{
          'filename': uploadFileName,
          'content_type': contentType,
          'category': category,
        },
      );
      final data = _unwrapUploadData(signature);
      final uploadUrl = '${data['upload_url'] ?? ''}'.trim();
      final publicUrl = '${data['public_url'] ?? ''}'.trim();
      final key = '${data['key'] ?? ''}'.trim();
      if (uploadUrl.isEmpty || publicUrl.isEmpty) {
        throw Exception('服务器未返回有效上传地址');
      }

      final response = await http.put(
        Uri.parse(uploadUrl),
        headers: <String, String>{'Content-Type': contentType},
        body: uploadBytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('R2 上传失败（${response.statusCode}）');
      }

      return ScenarioMediaUploadResult(
        url: publicUrl,
        r2Key: key.isEmpty ? null : key,
      );
    } catch (error) {
      _showSnack('上传失败：${_cleanUploadError(error)}', error: true);
      return null;
    }
  }

  Map<String, dynamic> _unwrapUploadData(Map<String, dynamic> response) {
    final raw = response['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return response;
  }

  Future<Uint8List> _convertImageToWebp(
    Uint8List bytes, {
    int? targetSize,
  }) async {
    final converted = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: targetSize ?? 4096,
      minHeight: targetSize ?? 4096,
      quality: 88,
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (converted.isEmpty) {
      throw Exception('图片转换 WebP 失败');
    }
    return converted;
  }

  Future<Uint8List?> _cropSquareCover(
    BuildContext context,
    Uint8List bytes,
  ) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SquareCoverCropDialog(image: bytes),
    );
  }

  String _webpFileName(String originalName) {
    final trimmed = originalName.trim();
    final dot = trimmed.lastIndexOf('.');
    final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    final safeBase = base.isEmpty ? 'image' : base;
    return '$safeBase.webp';
  }

  String _contentTypeForUpload(String fileName, {required bool isAudio}) {
    final name = fileName.toLowerCase();
    if (isAudio) {
      if (name.endsWith('.m4a')) return 'audio/mp4';
      if (name.endsWith('.aac')) return 'audio/aac';
      if (name.endsWith('.ogg')) return 'audio/ogg';
      if (name.endsWith('.wav')) return 'audio/wav';
      return 'audio/mpeg';
    }
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _cleanUploadError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('ApiException: ', '')
      .trim();

  Future<void> _editCover() async {
    if (_uploadingCover) return;
    setState(() => _uploadingCover = true);
    final result = await _mediaPicker(
      context,
      const ScenarioMediaTarget(kind: ScenarioMediaKind.cover),
    );
    if (!mounted) return;
    setState(() => _uploadingCover = false);
    if (result == null) return;
    setState(() => _coverUrl = result.url);
    _markDirty();
  }

  Future<void> _toggleBgmPreview(int index) async {
    if (index < 0 || index >= _bgmList.length) return;
    final url = _bgmList[index]['url']?.toString().trim() ?? '';
    if (url.isEmpty || _uploadingBgmIndexes.contains(index)) return;

    try {
      if (_previewBgmIndex == index) {
        if (_previewBgmPlaying) {
          await _bgmPreviewPlayer.pause();
          if (!mounted) return;
          setState(() => _previewBgmPlaying = false);
        } else {
          _bgmPreviewPlayer.play();
          if (!mounted) return;
          setState(() => _previewBgmPlaying = true);
        }
        return;
      }

      await _bgmPreviewPlayer.stop();
      await _bgmPreviewPlayer.setUrl(url);
      _bgmPreviewPlayer.play();
      if (!mounted) return;
      setState(() {
        _previewBgmIndex = index;
        _previewBgmPlaying = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewBgmIndex = null;
        _previewBgmPlaying = false;
      });
      _showSnack('试听失败：${_cleanUploadError(error)}', error: true);
    }
  }

  Future<void> _stopBgmPreviewIfNeeded(int index) async {
    if (_previewBgmIndex != index) return;
    await _bgmPreviewPlayer.stop();
    if (!mounted) return;
    setState(() {
      _previewBgmIndex = null;
      _previewBgmPlaying = false;
    });
  }

  Future<void> _editBgmMedia(int index) async {
    if (_uploadingBgmIndexes.contains(index)) return;
    await _stopBgmPreviewIfNeeded(index);
    if (!mounted) return;
    setState(() => _uploadingBgmIndexes.add(index));
    final result = await _mediaPicker(
      context,
      ScenarioMediaTarget(kind: ScenarioMediaKind.bgm, bgmIndex: index),
    );
    if (!mounted) return;
    setState(() => _uploadingBgmIndexes.remove(index));
    if (result == null) return;
    setState(() {
      _bgmList[index]['url'] = result.url;
      _bgmList[index]['r2_key'] = result.r2Key ?? '';
      _changedBgmIndexes.add(index);
    });
    _markDirty();
  }

  Future<String?> _showTextDialog({
    required String title,
    required String hint,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _editorInkSoft,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: _editorRadiusLg,
            side: BorderSide(color: _editorLine),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _editorText,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: AppColors.textOnDark),
            decoration: _inputDecoration(hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textOnDarkMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text(
                '完成',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _addTag() async {
    final value = await _showTextDialog(title: '新增标签', hint: '例如：纯爱、悬疑、校园');
    final tag = value?.trim() ?? '';
    if (tag.isEmpty || _tags.contains(tag) || !mounted) return;
    setState(() => _tags.add(tag));
    _markDirty();
  }

  Future<void> _editTag(int index) async {
    final value = await _showTextDialog(
      title: '编辑标签',
      hint: '标签名称',
      initialValue: _tags[index],
    );
    final tag = value?.trim() ?? '';
    if (tag.isEmpty || !mounted) return;
    setState(() => _tags[index] = tag);
    _markDirty();
  }

  void _removeTag(int index) {
    setState(() => _tags.removeAt(index));
    _markDirty();
  }

  Map<String, dynamic> _newPlotPoint({String goal = ''}) {
    return <String, dynamic>{
      'arc': '探索',
      'goal': goal,
      'state': goal,
      'scene': '',
      'player_facing_problem': '',
      'tension': '',
      'completion_condition': '',
      'exit': '',
      'hook': '',
      'pacing': 'normal',
      'node_type': 'anchor',
      'completion_variants': <dynamic>[],
      'fail_handling': 'cost',
    };
  }

  void _addPlotPoint() {
    final points = _plotPoints..add(_newPlotPoint());
    setState(() => _worldSetting['key_plot_points'] = points);
    _markDirty();
  }

  void _updatePlotPoint(int index, String field, dynamic value) {
    final points = _plotPoints;
    points[index] = <String, dynamic>{...points[index], field: value};
    if (field == 'goal') points[index]['state'] = value;
    if (field == 'player_facing_problem') points[index]['tension'] = value;
    if (field == 'completion_condition') points[index]['exit'] = value;
    setState(() => _worldSetting['key_plot_points'] = points);
    _markDirty();
  }

  void _removePlotPoint(int index) {
    final points = _plotPoints..removeAt(index);
    setState(() => _worldSetting['key_plot_points'] = points);
    _markDirty();
  }

  void _addCharacter() {
    final now = DateTime.now().microsecondsSinceEpoch;
    setState(() {
      _characters.add(<String, dynamic>{
        'id': now,
        'name': '新角色',
        'role': 'npc',
        'avatar': '',
        'avatar_seed': '',
        'portrait': '',
        'greeting': '',
        'voice': '',
        'voice_speed': 1.0,
        'voice_pitch': 1.1,
        'custom_attributes': <String, dynamic>{
          'voice': '',
          'voice_name': '',
          'trial_url': '',
          'voice_speed': 1.0,
          'voice_pitch': 1.1,
        },
        'persona': <String, dynamic>{},
        'initial_config': <String, dynamic>{
          'affection': 0,
          'stress': 0,
          'relationship_status': '陌生',
        },
        'json_data': <String, dynamic>{
          'identity': '',
          'gender': '未知',
          'age': '',
          'appearance': '',
          'background': '',
          'personality': <String>[],
          'likes': <String>[],
          'dislikes': <String>[],
          'speech_style': <String>[],
          'secret': '',
          'examples': '',
          'voice': '',
          'voice_name': '',
          'trial_url': '',
          'voice_speed': 1.0,
          'voice_pitch': 1.1,
        },
      });
    });
    _markDirty();
    _editCharacter(_characters.length - 1);
  }

  Future<void> _editCharacter(int realIndex) async {
    if (realIndex < 0 || realIndex >= _characters.length) return;
    final canDelete = _characters[realIndex]['role']?.toString() != 'companion';
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CharacterEditorSheet(
        character: _deepCopyMap(_characters[realIndex]),
        onPickMedia: _mediaPicker,
        characterIndex: realIndex,
        canDelete: canDelete,
      ),
    );
    if (result == null || !mounted) return;
    if (result['__deleted'] == true) {
      await _confirmRemoveCharacter(realIndex);
      return;
    }
    setState(() => _characters[realIndex] = result);
    _markDirty();
  }

  Future<void> _confirmRemoveCharacter(int realIndex) async {
    if (realIndex < 0 || realIndex >= _characters.length) return;
    if (_characters[realIndex]['role']?.toString() == 'companion') {
      _showSnack('系统角色无法删除', error: true);
      return;
    }
    final name = _characters[realIndex]['name']?.toString().trim() ?? '';
    final ok = await _confirm(
      title: '删除角色',
      description: '确定要删除角色「${name.isEmpty ? '未命名' : name}」吗？',
      confirmText: '确认删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _characters.removeAt(realIndex));
    _markDirty();
  }

  void _addLoreEntry() {
    final entries = _loreEntries;
    entries.add(<String, dynamic>{
      'uid': DateTime.now().millisecondsSinceEpoch % 2000000000,
      'keys': <String>[''],
      'content': '',
      'enabled': true,
    });
    setState(() => _lorebook['entries'] = entries);
    _markDirty();
  }

  void _updateLoreEntry(int index, String field, dynamic value) {
    final entries = _loreEntries;
    if (field == 'key') {
      entries[index]['keys'] = <String>[value.toString()];
    } else {
      entries[index][field] = value;
    }
    setState(() => _lorebook['entries'] = entries);
    _markDirty();
  }

  void _removeLoreEntry(int index) {
    final entries = _loreEntries..removeAt(index);
    setState(() => _lorebook['entries'] = entries);
    _markDirty();
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    try {
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
    } catch (_) {
      return <String, dynamic>{...source};
    }
  }

  Future<void> _showMoreMenu() async {
    final displayId = _id.isEmpty ? widget.scenarioId : _id;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: _editorInkSoft,
              borderRadius: _editorRadiusLg,
              border: Border.all(color: _editorLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _menuRow(
                  icon: Icons.restart_alt_rounded,
                  title: '重置剧情',
                  subtitle: '清空对话记录，重新开始体验',
                  onTap: () => Navigator.pop(sheetContext, 'reset'),
                ),
                const SizedBox(height: 10),
                _menuRow(
                  icon: Icons.delete_outline_rounded,
                  title: '删除剧本',
                  subtitle: '永久删除该剧本及所有设定数据',
                  danger: true,
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
                const SizedBox(height: 14),
                Text(
                  'WORLD ID · $displayId',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.28),
                    fontSize: 10.5,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == 'reset') await _confirmReset();
    if (action == 'delete') await _confirmDelete();
  }

  Widget _menuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: _editorRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: _editorRadius,
          border: Border.all(
            color: danger ? _danger.withOpacity(0.22) : _editorLine,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: danger ? _danger : AppColors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? _danger : AppColors.textOnDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textOnDarkMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String description,
    required String confirmText,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _editorInkSoft,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: _editorRadiusLg,
          side: BorderSide(color: _editorLine),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _editorText,
          ),
        ),
        content: Text(
          description,
          style: const TextStyle(
            color: AppColors.textOnDarkMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textOnDarkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: danger ? _danger : AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirmReset() async {
    final ok = await _confirm(
      title: '重置剧情进度',
      description: '确定要清空所有对话记录吗？剧本设定不会被删除。',
      confirmText: '确认重置',
    );
    if (!ok) return;
    setState(() => _actionLoading = true);
    try {
      await _api.resetScenario(widget.scenarioId);
      if (!mounted) return;
      setState(() => _actionLoading = false);
      Navigator.of(context).pop(true);
      return;
    } on ApiException catch (e) {
      _showSnack(e.message, error: true);
    } finally {
      if (mounted && _actionLoading) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await _confirm(
      title: '删除剧本',
      description: '确定要永久删除该剧本吗？此操作无法撤销。',
      confirmText: '确认删除',
      danger: true,
    );
    if (!ok) return;
    setState(() => _actionLoading = true);
    try {
      await _api.deleteScenario(widget.scenarioId);
      if (!mounted) return;
      widget.onDeleted?.call();
      setState(() => _actionLoading = false);
      Navigator.of(context).pop(true);
      return;
    } on ApiException catch (e) {
      _showSnack(e.message, error: true);
    } finally {
      if (mounted && _actionLoading) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Widget _buildSaveActionButton({bool compact = false}) {
    final active = _dirty || _saving;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 9),
      child: Material(
        color: active ? _editorAccent : Colors.white.withOpacity(0.06),
        borderRadius: _editorRadius,
        child: InkWell(
          onTap: (!_dirty || _saving) ? null : _save,
          borderRadius: _editorRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 11 : 14,
              vertical: compact ? 4 : 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saving)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Color(0xFF0C0C0C),
                    ),
                  )
                else
                  Icon(
                    active ? Icons.check_rounded : Icons.check_rounded,
                    size: compact ? 14 : 15,
                    color: active
                        ? const Color(0xFF0C0C0C)
                        : Colors.white.withOpacity(0.38),
                  ),
                const SizedBox(width: 5),
                Text(
                  _saving
                      ? '保存中'
                      : _dirty
                          ? '保存'
                          : '已保存',
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF0C0C0C)
                        : Colors.white.withOpacity(0.38),
                    fontSize: compact ? 11.8 : 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final phoneLandscape =
        landscape && media.size.height <= 560 && media.size.width <= 1100;
    final sidebarWidth = landscape
        ? phoneLandscape
            ? (media.size.width * .22).clamp(156.0, 196.0).toDouble()
            : (media.size.width * .21).clamp(228.0, 276.0).toDouble()
        : 0.0;

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _pageBg,
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _editorAccent,
                surface: _pageBg,
              ),
          inputDecorationTheme: const InputDecorationTheme(
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        child: Scaffold(
          backgroundColor: _pageBg,
          resizeToAvoidBottomInset: true,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.25),
                radius: 1.15,
                colors: <Color>[
                  Color(0xFF282F3C),
                  Color(0xFF1D222C),
                  Color(0xFF151921),
                ],
                stops: <double>[0, .52, 1],
              ),
            ),
            child: _loading
                ? _buildLoading()
                : _error != null
                    ? _buildError()
                    : Stack(
                        children: [
                          if (landscape)
                            _buildLandscapeEditor(
                              sidebarWidth,
                              phoneLandscape: phoneLandscape,
                            )
                          else
                            CustomScrollView(
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                _buildAppBar(),
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 820),
                                      child: _buildHero(),
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 820),
                                      child: _buildSectionTabs(),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 16, 16, 42),
                                  sliver: SliverToBoxAdapter(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 820),
                                        child: _buildCurrentSection(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_actionLoading)
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withOpacity(0.55),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeEditor(
    double sidebarWidth, {
    required bool phoneLandscape,
  }) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildLandscapeTopBar(compact: phoneLandscape),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _editorInkSoft.withOpacity(.32),
                      border: const Border(
                        right: BorderSide(color: _editorLine, width: 1),
                      ),
                    ),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        phoneLandscape ? 10 : 14,
                        phoneLandscape ? 8 : 12,
                        phoneLandscape ? 10 : 14,
                        20,
                      ),
                      children: [
                        _buildLandscapeHero(compact: phoneLandscape),
                        SizedBox(height: phoneLandscape ? 10 : 16),
                        _buildVerticalSectionTabs(compact: phoneLandscape),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontalPadding = phoneLandscape
                          ? 12.0
                          : constraints.maxWidth >= 1100
                              ? 24.0
                              : constraints.maxWidth >= 720
                                  ? 18.0
                                  : 14.0;
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          phoneLandscape ? 10 : 16,
                          horizontalPadding,
                          28,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: _buildCurrentSection(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeTopBar({required bool compact}) {
    return SizedBox(
      height: compact ? 44 : 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _editorInkSoft.withOpacity(0.65),
          border: const Border(bottom: BorderSide(color: _editorLine)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                visualDensity: VisualDensity.compact,
                onPressed: _handleBackNavigation,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: _editorTextSoft,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '编辑世界',
                style: TextStyle(
                  color: _editorText,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .6,
                ),
              ),
              if (_dirty) ...[
                const SizedBox(width: 10),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: _editorAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  '未保存修改',
                  style: TextStyle(
                    color: _editorAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              _buildSaveActionButton(compact: true),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '更多操作',
                visualDensity: VisualDensity.compact,
                onPressed: _showMoreMenu,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: _editorTextSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeHero({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: _editorRadius,
        border: Border.all(color: _editorLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _editCover,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: compact ? 48 : 60,
                  height: compact ? 48 : 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: _editorRadius,
                    border: Border.all(color: _editorLine),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _coverUrl.isEmpty
                      ? const Icon(
                          Icons.landscape_outlined,
                          size: 22,
                          color: AppColors.textOnDarkMuted,
                        )
                      : Image.network(
                          CdnUtil.resize(_coverUrl, width: 180),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textOnDarkMuted,
                          ),
                        ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: compact ? 20 : 22,
                    height: compact ? 20 : 22,
                    decoration: BoxDecoration(
                      color: _editorAccent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _pageBg, width: 2),
                    ),
                    child: _uploadingCover
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: Color(0xFF0C0C0C),
                            ),
                          )
                        : const Icon(
                            LucideIcons.camera,
                            size: 11,
                            color: Color(0xFF0C0C0C),
                          ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 9 : 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modeLabel(_mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _editorAccent.withOpacity(0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _titleController,
                  onChanged: (_) => _markDirty(),
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: compact ? 13 : 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: '输入世界名称…',
                    hintStyle: TextStyle(color: AppColors.textOnDarkMuted),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(ScenarioEditorSection, String, IconData, String?)> get _tabDefinitions {
    final charCount = _visibleCharacters.length;
    final plotCount = _plotPoints.length;
    final bgmCount = _configuredBgmCount;
    final loreCount = _loreEntries.length;
    return <(ScenarioEditorSection, String, IconData, String?)>[
      (ScenarioEditorSection.overview, '基础', Icons.tune_rounded, null),
      (
        ScenarioEditorSection.characters,
        '角色',
        Icons.people_alt_outlined,
        charCount > 0 ? '$charCount' : null
      ),
      (
        ScenarioEditorSection.story,
        '剧情',
        Icons.route_rounded,
        plotCount > 0 ? '$plotCount' : null
      ),
      (
        ScenarioEditorSection.bgm,
        'BGM',
        Icons.graphic_eq_rounded,
        bgmCount > 0 ? '$bgmCount/6' : null
      ),
      (
        ScenarioEditorSection.lorebook,
        '知识库',
        Icons.menu_book_outlined,
        loreCount > 0 ? '$loreCount' : null
      ),
    ];
  }

  Widget _buildVerticalSectionTabs({required bool compact}) {
    final tabs = _tabDefinitions;

    return Column(
      children: [
        for (final item in tabs) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: _editorRadius,
              onTap: () => _setSection(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 12,
                  vertical: compact ? 8 : 11,
                ),
                decoration: BoxDecoration(
                  color: _section == item.$1
                      ? _editorAccent.withOpacity(.13)
                      : Colors.transparent,
                  borderRadius: _editorRadius,
                  border: Border.all(
                    color: _section == item.$1
                        ? _editorAccent.withOpacity(.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      item.$3,
                      size: compact ? 15 : 17,
                      color:
                          _section == item.$1 ? _editorAccent : _editorMuted,
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          color: _section == item.$1
                              ? _editorText
                              : _editorMuted,
                          fontSize: compact ? 12 : 13,
                          fontWeight: _section == item.$1
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (item.$4 != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _section == item.$1
                              ? _editorAccent.withOpacity(0.2)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          item.$4!,
                          style: TextStyle(
                            color: _section == item.$1
                                ? _editorAccent
                                : _editorMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 3 : 5),
        ],
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 2.2, color: _editorAccent),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppColors.textOnDarkMuted,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textOnDarkMuted,
                  height: 1.5,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新加载'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: _editorInk.withOpacity(0.92),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: _handleBackNavigation,
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 19,
          color: _editorTextSoft,
        ),
      ),
      centerTitle: false,
      titleSpacing: 0,
      title: Row(
        children: [
          const Text(
            '编辑世界',
            style: TextStyle(
              color: _editorText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          if (_dirty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _editorAccent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '未保存',
                style: TextStyle(
                  color: _editorAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        _buildSaveActionButton(),
        const SizedBox(width: 4),
        IconButton(
          tooltip: '更多',
          onPressed: _showMoreMenu,
          icon: const Icon(Icons.more_horiz_rounded, color: _editorTextSoft),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _editorSurface.withOpacity(0.65),
          borderRadius: _editorRadiusLg,
          border: Border.all(color: _editorLine),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _editCover,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: _editorFieldBg,
                      borderRadius: _editorRadius,
                      border: Border.all(color: _editorLine),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _coverUrl.isEmpty
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 26,
                                color: AppColors.textOnDarkMuted,
                              ),
                              SizedBox(height: 4),
                              Text(
                                '上传封面',
                                style: TextStyle(
                                  color: AppColors.textOnDarkMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          )
                        : Image.network(
                            CdnUtil.resize(_coverUrl, width: 300),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textOnDarkMuted,
                            ),
                          ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _editorAccent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _pageBg, width: 2.5),
                      ),
                      child: _uploadingCover
                          ? const Padding(
                              padding: EdgeInsets.all(5),
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF0C0C0C),
                              ),
                            )
                          : const Icon(
                              LucideIcons.camera,
                              size: 13,
                              color: Color(0xFF0C0C0C),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _modeLabel(_mode),
                          style: const TextStyle(
                            color: _editorTextSoft,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '点击名称可直接修改',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.32),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _editorFieldBg,
                      borderRadius: _editorRadius,
                      border: Border.all(color: _editorLine),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _titleController,
                            onChanged: (_) => _markDirty(),
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 17,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: const InputDecoration(
                              hintText: '给世界起个响亮的名字…',
                              hintStyle:
                                  TextStyle(color: AppColors.textOnDarkMuted),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.pencil,
                          size: 14,
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTabs() {
    final tabs = _tabDefinitions;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = tabs[index];
          final selected = _section == item.$1;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: _editorRadius,
              onTap: () => _setSection(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? _editorAccent.withOpacity(0.14)
                      : _editorSurface.withOpacity(0.5),
                  borderRadius: _editorRadius,
                  border: Border.all(
                    color: selected
                        ? _editorAccent.withOpacity(0.55)
                        : _editorLine,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$3,
                      size: 15,
                      color: selected ? _editorAccent : _editorMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: selected ? _editorText : _editorMuted,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (item.$4 != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: selected
                              ? _editorAccent.withOpacity(0.22)
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          item.$4!,
                          style: TextStyle(
                            color: selected ? _editorAccent : _editorMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentSection() {
    switch (_section) {
      case ScenarioEditorSection.overview:
        return _buildOverviewSection();
      case ScenarioEditorSection.characters:
        return _buildCharactersSection();
      case ScenarioEditorSection.story:
        return _buildStorySection();
      case ScenarioEditorSection.bgm:
        return _buildBgmSection();
      case ScenarioEditorSection.lorebook:
        return _buildLorebookSection();
    }
  }

  Widget _buildOverviewSection() {
    Widget buildTagEditor() {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _tags.length; i++)
            GestureDetector(
              onTap: () => _editTag(i),
              child: Container(
                padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
                decoration: BoxDecoration(
                  color: _editorFieldBg,
                  borderRadius: _editorRadius,
                  border: Border.all(color: _editorLine),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '# ${_tagLabel(_tags[i])}',
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _removeTag(i),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: _addTag,
            borderRadius: _editorRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _editorAccent.withOpacity(0.1),
                borderRadius: _editorRadius,
                border: Border.all(color: _editorAccent.withOpacity(.24)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 14, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text(
                    '新增标签',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    Widget buildWorldField({required bool wide}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('世界观与背景设定', subtitle: '交代时代背景、世界规则与主要冲突'),
          const SizedBox(height: 8),
          _editorTextField(
            controller: _descriptionController,
            hint: '输入世界观描述、时代背景、主要冲突和玩家需要知道的信息…',
            minLines: wide ? 7 : 5,
            maxLines: wide ? 14 : 10,
          ),
        ],
      );
    }

    Widget buildOpeningField({required bool wide}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('开场白', subtitle: '玩家进入世界后看到的第一段话'),
          const SizedBox(height: 8),
          _editorTextField(
            controller: _openingController,
            hint: '用极具代入感的场景描写或角色台词开启故事…',
            minLines: wide ? 7 : 5,
            maxLines: wide ? 14 : 10,
          ),
        ],
      );
    }

    final hasAdvancedConfig =
        _systemPromptController.text.trim().isNotEmpty ||
            _cotController.text.trim().isNotEmpty ||
            _responseStyleController.text.trim().isNotEmpty;

    return Column(
      children: [
        _sectionCard(
          title: '基础设定',
          subtitle: '决定玩家第一眼看到的世界面貌与开篇体验',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('主题标签'),
              const SizedBox(height: 8),
              buildTagEditor(),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 600;
                  if (!wide) {
                    return Column(
                      children: [
                        buildWorldField(wide: false),
                        const SizedBox(height: 18),
                        buildOpeningField(wide: false),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: buildWorldField(wide: true)),
                      const SizedBox(width: 14),
                      Expanded(child: buildOpeningField(wide: true)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: _editorSurface.withOpacity(0.65),
            borderRadius: _editorRadiusLg,
            border: Border.all(color: _editorLine),
          ),
          child: ExpansionTile(
            initiallyExpanded: hasAdvancedConfig,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            shape: const RoundedRectangleBorder(borderRadius: _editorRadiusLg),
            collapsedShape:
                const RoundedRectangleBorder(borderRadius: _editorRadiusLg),
            iconColor: _editorAccent,
            collapsedIconColor: _editorMuted,
            title: Row(
              children: [
                const Icon(
                  LucideIcons.sparkles,
                  size: 16,
                  color: _editorAccent,
                ),
                const SizedBox(width: 8),
                const Text(
                  '高级 AI 设定（选填）',
                  style: TextStyle(
                    color: _editorText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasAdvancedConfig) ...[
                  const SizedBox(width: 8),
                  _tinyBadge('已配置'),
                ],
              ],
            ),
            subtitle: const Text(
              '自定义底层系统指令、思维链（CoT）推理规则与回复文风要求',
              style: TextStyle(color: _editorMuted, fontSize: 11.5),
            ),
            children: [
              const Divider(height: 16, color: _editorLine),
              _fieldLabel('系统指令 (System Prompt)',
                  subtitle: '约束 AI 扮演规则与全局行为准则'),
              const SizedBox(height: 8),
              _editorTextField(
                controller: _systemPromptController,
                hint: '例如：你是一个擅长冷硬派科幻叙事的 DM，严格遵守世界物理法则…',
                minLines: 3,
                maxLines: 8,
              ),
              const SizedBox(height: 14),
              _fieldLabel('回复文风 (Response Style)',
                  subtitle: '控制叙事口吻、描写颗粒度与台词风格'),
              const SizedBox(height: 8),
              _editorTextField(
                controller: _responseStyleController,
                hint: '例如：多用环境烘托心理，对话简练克制，避免使用现代网络流行语…',
                minLines: 2,
                maxLines: 6,
              ),
              const SizedBox(height: 14),
              _fieldLabel('思维链指令 (CoT Instruction)',
                  subtitle: '引导 AI 在正式输出前先进行逻辑推演'),
              const SizedBox(height: 8),
              _editorTextField(
                controller: _cotController,
                hint: '例如：每次回复前先检查角色当前好感度与所处场景是否合理…',
                minLines: 2,
                maxLines: 6,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCharactersSection() {
    final characters = _visibleCharacters;
    return _sectionCard(
      title: '登场角色',
      subtitle: '点击卡片编辑角色立绘、人设与专属配音',
      trailing: FilledButton.tonalIcon(
        onPressed: _addCharacter,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('新增角色'),
        style: FilledButton.styleFrom(
          backgroundColor: _editorAccent.withOpacity(0.14),
          foregroundColor: AppColors.accent,
          shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
      child: characters.isEmpty
          ? _emptyState('还没有登场角色', '点击右上角「新增角色」创建第一个 NPC 或主角档案')
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1040
                    ? 3
                    : width >= 540
                        ? 2
                        : 1;
                const gap = 10.0;
                final itemWidth = columns == 1
                    ? width
                    : (width - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final character in characters)
                      SizedBox(
                        width: itemWidth,
                        child: _characterRow(
                          character,
                          compact: columns > 1,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _characterRow(
    Map<String, dynamic> character, {
    bool compact = false,
  }) {
    final realIndex = character['__realIndex'] as int;
    final avatar = character['avatar']?.toString() ?? '';
    final jsonData = _parseMap(character['json_data']);
    final initialConfig = _parseMap(character['initial_config']);
    final role = character['role']?.toString() ?? 'npc';
    final identity = jsonData['identity']?.toString().trim() ?? '';
    final relationship =
        initialConfig['relationship_status']?.toString().trim() ?? '';
    final gender = jsonData['gender']?.toString().trim() ?? '';
    final age = jsonData['age']?.toString().trim() ?? '';
    final voiceName = jsonData['voice_name']?.toString().trim() ?? '';
    final rawTraits = jsonData['personality'];
    final traits = rawTraits is List
        ? rawTraits
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .take(compact ? 2 : 3)
            .toList()
        : <String>[];
    final meta = <String>[
      if (relationship.isNotEmpty) relationship,
      if (gender.isNotEmpty && gender != '未知') gender,
      if (age.isNotEmpty) '$age岁',
      if (voiceName.isNotEmpty) '🎙 $voiceName',
      ...traits,
    ];
    final avatarSize = compact ? 48.0 : 54.0;

    return Material(
      color: _editorFieldBg,
      borderRadius: _editorRadius,
      child: InkWell(
        onTap: () => _editCharacter(realIndex),
        borderRadius: _editorRadius,
        child: Container(
          padding: EdgeInsets.all(compact ? 11 : 13),
          decoration: BoxDecoration(
            borderRadius: _editorRadius,
            border: Border.all(color: _editorLine),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: _editorRadius,
                  border: Border.all(color: _editorLine),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar.isEmpty
                    ? const Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.textOnDarkMuted,
                      )
                    : Image.network(
                        CdnUtil.resize(avatar, width: 120),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.textOnDarkMuted,
                        ),
                      ),
              ),
              SizedBox(width: compact ? 11 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            character['name']?.toString().trim().isNotEmpty ==
                                    true
                                ? character['name'].toString()
                                : '未命名角色',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: compact ? 13.5 : 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _tinyBadge(role == 'player' ? '主角' : 'NPC'),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      identity.isNotEmpty ? identity : '点击补充角色身份与外貌背景…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: identity.isNotEmpty
                            ? AppColors.textOnDarkMuted
                            : AppColors.textOnDarkMuted.withOpacity(.55),
                        fontSize: compact ? 11.5 : 12,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted.withOpacity(.82),
                          fontSize: compact ? 10.5 : 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 4 : 8),
              IconButton(
                tooltip: '删除角色',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmRemoveCharacter(realIndex),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: Colors.white.withOpacity(0.35),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textOnDarkMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorySection() {
    if (_mode != 'novel') {
      return _sectionCard(
        title: '剧情流程',
        subtitle: '该模块主要用于互动小说模式',
        child: _emptyState('当前不是互动小说模式', '仅在互动小说模式下需要配置分幕剧情节点'),
      );
    }

    final points = _plotPoints;

    Widget buildMainStory(bool wide) {
      return _sectionCard(
        title: '主线大纲',
        subtitle: '从开篇到结局的整体走向',
        child: _editorTextField(
          controller: _mainStoryController,
          hint: '用几段话说明主线目标、关键转折和结局方向…',
          minLines: wide ? 12 : 5,
          maxLines: wide ? 24 : 12,
        ),
      );
    }

    Widget buildPlotPoints() {
      return _sectionCard(
        title: '关键剧情节点',
        subtitle: 'AI 将按顺序推进 · 共 ${points.length} 个节点',
        trailing: FilledButton.tonalIcon(
          onPressed: _addPlotPoint,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('新增节点'),
          style: FilledButton.styleFrom(
            backgroundColor: _editorAccent.withOpacity(0.14),
            foregroundColor: AppColors.accent,
            shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        child: points.isEmpty
            ? _emptyState('暂无剧情节点', '添加节点后可明确每一幕的目标、困境和完成信号')
            : Column(
                children: [
                  for (var i = 0; i < points.length; i++) ...[
                    _plotPointCard(i, points[i]),
                    if (i != points.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        if (!wide) {
          return Column(
            children: [
              buildMainStory(false),
              const SizedBox(height: 14),
              buildPlotPoints(),
            ],
          );
        }

        final outlineWidth =
            (constraints.maxWidth * .36).clamp(240.0, 380.0).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: outlineWidth, child: buildMainStory(true)),
            const SizedBox(width: 14),
            Expanded(child: buildPlotPoints()),
          ],
        );
      },
    );
  }

  Widget _plotPointCard(int index, Map<String, dynamic> point) {
    String clean(dynamic value) => value?.toString().trim() ?? '';

    final goalValue = clean(point['goal']).isNotEmpty
        ? clean(point['goal'])
        : clean(point['state']);
    final scene = clean(point['scene']);
    final problem = clean(point['player_facing_problem']).isNotEmpty
        ? clean(point['player_facing_problem'])
        : clean(point['tension']);
    final completion = clean(point['completion_condition']).isNotEmpty
        ? clean(point['completion_condition'])
        : clean(point['exit']);
    final hook = clean(point['hook']);
    final pacing = clean(point['pacing']);
    final paceLabel = switch (pacing) {
      'fast' => '快节奏 · 1轮',
      'slow' => '慢节奏 · 4轮',
      _ => '正常 · 2轮',
    };
    final primarySummary = <String>[
      if (scene.isNotEmpty) '地点 · $scene',
      if (problem.isNotEmpty) '困境 · $problem',
    ].join('  ·  ');
    final secondarySummary = <String>[
      if (completion.isNotEmpty) '完成 · $completion',
      if (hook.isNotEmpty) '悬念 · $hook',
    ].join('  ·  ');
    final summary = <String>[
      if (primarySummary.isNotEmpty) primarySummary,
      if (secondarySummary.isNotEmpty) secondarySummary,
    ];

    return ExpansionTile(
      tilePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      collapsedShape: const RoundedRectangleBorder(
        borderRadius: _editorRadius,
        side: BorderSide(color: _editorLine),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: _editorRadius,
        side: BorderSide(color: _editorAccent.withOpacity(.4)),
      ),
      backgroundColor: _editorFieldBg,
      collapsedBackgroundColor: _editorFieldBg,
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _editorAccent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: AppColors.accent,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          _arcBadge(point['arc']?.toString() ?? '探索'),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              goalValue.isNotEmpty ? goalValue : '未填写节点目标',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textOnDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _removePlotPoint(index),
            borderRadius: _editorRadius,
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textOnDarkMuted,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          summary.isEmpty
              ? '$paceLabel · 点击展开补充地点、困境和完成条件'
              : '$paceLabel · ${summary.first}'
                  '${summary.length > 1 ? '\n${summary[1]}' : ''}',
          maxLines: summary.isEmpty ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textOnDarkMuted.withOpacity(.88),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ),
      children: [
        const Divider(height: 16, color: _editorLine),
        Row(
          children: [
            Expanded(
              child: _dropdownField(
                label: '剧情幕段',
                value: point['arc']?.toString() ?? '探索',
                items: const <String>['诱发', '探索', '突转', '至暗', '终章'],
                labels: const <String>[
                  '第一幕 · 开端',
                  '第二幕 · 发展',
                  '第三幕 · 转折',
                  '第四幕 · 低谷',
                  '第五幕 · 结局',
                ],
                onChanged: (value) => _updatePlotPoint(index, 'arc', value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dropdownField(
                label: '推进节奏',
                value: point['pacing']?.toString() ?? 'normal',
                items: const <String>['fast', 'normal', 'slow'],
                labels: const <String>['快 · 1轮', '正常 · 2轮', '慢 · 4轮'],
                onChanged: (value) => _updatePlotPoint(index, 'pacing', value),
              ),
            ),
          ],
        ),
        _inlineInitialField(
          label: '这个节点讲什么',
          value: (point['goal'] ?? point['state'])?.toString() ?? '',
          hint: '角色处境、关系变化、这一节要完成什么…',
          minLines: 2,
          onChanged: (value) => _updatePlotPoint(index, 'goal', value),
        ),
        _inlineInitialField(
          label: '发生在哪里',
          value: point['scene']?.toString() ?? '',
          hint: '例如：黄巾军后方隐秘的草药营帐',
          onChanged: (value) => _updatePlotPoint(index, 'scene', value),
        ),
        _inlineInitialField(
          label: '玩家的核心困境',
          value:
              (point['player_facing_problem'] ?? point['tension'])?.toString() ??
                  '',
          hint: '玩家为什么会继续推进这一节？',
          onChanged: (value) =>
              _updatePlotPoint(index, 'player_facing_problem', value),
        ),
        _inlineInitialField(
          label: '完成信号',
          value:
              (point['completion_condition'] ?? point['exit'])?.toString() ??
                  '',
          hint: '故事演到什么程度就推进下一节？',
          onChanged: (value) =>
              _updatePlotPoint(index, 'completion_condition', value),
        ),
        _inlineInitialField(
          label: '结尾悬念',
          value: point['hook']?.toString() ?? '',
          hint: '这一节结束时留下什么钩子？',
          onChanged: (value) => _updatePlotPoint(index, 'hook', value),
        ),
      ],
    );
  }

  Widget _buildBgmSection() {
    final groups = <String, List<int>>{
      '日常氛围': <int>[],
      '冲突战斗': <int>[],
      '情感共鸣': <int>[],
    };
    for (var i = 0; i < _bgmList.length; i++) {
      final cat = _bgmList[i]['category']?.toString() ?? '';
      if (cat == '日常') groups['日常氛围']?.add(i);
      if (cat == '冲突') groups['冲突战斗']?.add(i);
      if (cat == '情感') groups['情感共鸣']?.add(i);
    }

    return _sectionCard(
      title: '情景 BGM',
      subtitle: '每种情绪配备慢/快两档音乐，AI 会根据剧情紧张度自动切换',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups.entries) ...[
            Text(
              group.key,
              style: const TextStyle(
                color: _editorTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final index in group.value) ...[
              _bgmRow(index),
              const SizedBox(height: 8),
            ],
            if (group.key != groups.keys.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _bgmRow(int index) {
    final item = _bgmList[index];
    final url = item['url']?.toString() ?? '';
    final uploading = _uploadingBgmIndexes.contains(index);
    final isPreviewing = _previewBgmIndex == index && _previewBgmPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _editorFieldBg,
        borderRadius: _editorRadius,
        border: Border.all(
          color: isPreviewing ? _editorAccent.withOpacity(0.45) : _editorLine,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: url.isNotEmpty
                  ? _editorAccent.withOpacity(0.12)
                  : Colors.white.withOpacity(0.04),
              borderRadius: _editorRadius,
            ),
            child: Icon(
              uploading ? LucideIcons.loaderCircle : LucideIcons.music2,
              size: 17,
              color: url.isNotEmpty
                  ? AppColors.accent
                  : AppColors.textOnDarkMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${item['title']}',
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item['pace']}',
                        style: const TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  uploading
                      ? '正在上传音频…'
                      : isPreviewing
                          ? '正在试听播放…'
                          : url.isEmpty
                              ? '未配置音频'
                              : '已配置音频 · 可点击右侧试听',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: uploading || url.isNotEmpty
                        ? AppColors.accent
                        : AppColors.textOnDarkMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (url.isNotEmpty && !uploading) ...[
            IconButton(
              tooltip: isPreviewing ? '暂停' : '试听',
              onPressed: () => _toggleBgmPreview(index),
              icon: Icon(
                isPreviewing ? LucideIcons.pause : LucideIcons.play,
                size: 16,
                color: isPreviewing ? AppColors.accent : AppColors.textOnDark,
              ),
            ),
            IconButton(
              tooltip: '清除音频',
              onPressed: () async {
                await _stopBgmPreviewIfNeeded(index);
                if (!mounted) return;
                setState(() {
                  item['url'] = '';
                  item['r2_key'] = '';
                  _changedBgmIndexes.add(index);
                });
                _markDirty();
              },
              icon: const Icon(
                LucideIcons.trash2,
                size: 15,
                color: AppColors.textOnDarkMuted,
              ),
            ),
          ],
          InkWell(
            onTap: uploading ? null : () => _editBgmMedia(index),
            borderRadius: _editorRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: uploading
                    ? Colors.white.withOpacity(0.04)
                    : _editorAccent.withOpacity(0.12),
                borderRadius: _editorRadius,
                border: Border.all(
                  color: uploading
                      ? _editorLine
                      : _editorAccent.withOpacity(.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (uploading)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.accent,
                      ),
                    )
                  else
                    Icon(
                      url.isEmpty ? LucideIcons.upload : LucideIcons.refreshCw,
                      size: 13,
                      color: AppColors.accent,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    uploading
                        ? '上传中'
                        : url.isEmpty
                            ? '上传'
                            : '替换',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLorebookSection() {
    final entries = _loreEntries;
    return _sectionCard(
      title: '世界知识库 (Lorebook)',
      subtitle: '当对话中提及触发词时，自动将对应设定注入给 AI',
      trailing: FilledButton.tonalIcon(
        onPressed: _addLoreEntry,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: const Text('新增词条'),
        style: FilledButton.styleFrom(
          backgroundColor: _editorAccent.withOpacity(0.14),
          foregroundColor: AppColors.accent,
          shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
      child: entries.isEmpty
          ? _emptyState('暂无知识库词条', '将专有名词、组织势力、法则或道具做成词条，节省常驻上下文')
          : Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _loreEntryCard(i, entries[i]),
                  if (i != entries.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Widget _loreEntryCard(int index, Map<String, dynamic> entry) {
    final keys = entry['keys'];
    final firstKey =
        keys is List && keys.isNotEmpty ? keys.first?.toString() ?? '' : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: _editorRadius,
        border: Border.all(color: _editorLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _editorAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key_rounded, size: 13, color: AppColors.accent),
                    SizedBox(width: 4),
                    Text(
                      '触发词',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: firstKey,
                  onChanged: (value) => _updateLoreEntry(index, 'key', value),
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: '输入触发关键词，例如：圣剑 / 黑塔组织',
                    hintStyle: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除词条',
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeLoreEntry(index),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textOnDarkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: entry['content']?.toString() ?? '',
            onChanged: (value) => _updateLoreEntry(index, 'content', value),
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 13,
              height: 1.55,
            ),
            decoration: _inputDecoration('当检测到该关键词时，向 AI 补充的详细背景设定…'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    final size = MediaQuery.sizeOf(context);
    final dense = size.width > size.height;
    final phoneLandscape = dense && size.height <= 560 && size.width <= 1100;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(phoneLandscape ? 14 : (dense ? 16 : 18)),
      decoration: BoxDecoration(
        color: _editorSurface.withOpacity(0.65),
        borderRadius: _editorRadiusLg,
        border: Border.all(color: _editorLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3.5,
                height: 16,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  color: _editorAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _editorText,
                        fontSize: dense ? 15 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _editorMuted,
                        fontSize: dense ? 11.2 : 11.8,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          SizedBox(height: phoneLandscape ? 12 : (dense ? 14 : 16)),
          child,
        ],
      ),
    );
  }

  Widget _editorTextField({
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 6,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: (_) => _markDirty(),
      style: const TextStyle(
        color: AppColors.textOnDark,
        fontSize: 13.5,
        height: 1.6,
      ),
      decoration: _inputDecoration(hint),
    );
  }

  Widget _inlineInitialField({
    required String label,
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
    int minLines = 1,
  }) {
    final size = MediaQuery.sizeOf(context);
    final dense = size.width > size.height;
    return Padding(
      padding: EdgeInsets.only(top: dense ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          SizedBox(height: dense ? 6 : 8),
          TextFormField(
            initialValue: value,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: 5,
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 13.5,
              height: 1.5,
            ),
            decoration: _inputDecoration(hint),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required List<String> labels,
    required ValueChanged<String> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: safeValue,
          dropdownColor: _editorInkSoft,
          isExpanded: true,
          decoration: _inputDecoration(''),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: AppColors.textOnDarkMuted,
          ),
          items: [
            for (var i = 0; i < items.length; i++)
              DropdownMenuItem<String>(
                value: items[i],
                child: Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textOnDark,
                  ),
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {String? subtitle}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: _editorTextSoft,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    final size = MediaQuery.sizeOf(context);
    final dense = size.width > size.height;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontWeight: FontWeight.w400,
        fontSize: dense ? 12.3 : 13,
      ),
      filled: true,
      fillColor: _editorFieldBg,
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 13 : 15,
        vertical: dense ? 11 : 14,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: _editorRadius,
        borderSide: BorderSide(color: _editorLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _editorRadius,
        borderSide: BorderSide(
          color: _editorAccent.withOpacity(0.75),
          width: 1.2,
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    final size = MediaQuery.sizeOf(context);
    final dense = size.width > size.height;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: dense ? 24 : 36,
      ),
      decoration: BoxDecoration(
        color: _editorFieldBg,
        borderRadius: _editorRadius,
        border: Border.all(color: _editorLine),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.layers_outlined,
            color: AppColors.textOnDarkMuted,
            size: 32,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _editorAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _editorAccent.withOpacity(.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _arcBadge(String arc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _arcLabel(arc),
        style: const TextStyle(
          color: AppColors.textOnDarkMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _arcLabel(String arc) {
    const labels = <String, String>{
      '诱发': '第一幕·开端',
      '探索': '第二幕·发展',
      '突转': '第三幕·转折',
      '至暗': '第四幕·低谷',
      '终章': '第五幕·结局',
    };
    return labels[arc] ?? arc;
  }

  String _modeLabel(String mode) {
    const map = <String, String>{
      'chat': '独聊模式',
      'novel': '互动小说',
      'online': '多人联机',
      'rpg': '角色扮演',
      'group': '群聊模式',
    };
    return map[mode] ?? mode;
  }

  String _tagLabel(String tag) {
    const map = <String, String>{
      'romance': '纯爱',
      'horror': '怪谈',
    };
    return map[tag] ?? tag;
  }
}

class _SquareCoverCropDialog extends StatefulWidget {
  const _SquareCoverCropDialog({required this.image});

  final Uint8List image;

  @override
  State<_SquareCoverCropDialog> createState() => _SquareCoverCropDialogState();
}

class _SquareCoverCropDialogState extends State<_SquareCoverCropDialog> {
  final CropController _cropController = CropController();
  bool _cropping = false;
  String? _error;

  void _confirmCrop() {
    if (_cropping) return;
    setState(() {
      _cropping = true;
      _error = null;
    });
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    final dialogWidth = landscape
        ? math.min(media.size.width - 36, 860.0)
        : math.min(media.size.width - 28, 520.0);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: landscape ? 18 : 20,
        vertical: landscape ? 10 : 20,
      ),
      backgroundColor: _editorInkSoft,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: _editorRadiusLg,
        side: BorderSide(color: _editorLine),
      ),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: EdgeInsets.all(landscape ? 18 : 24),
          child: landscape
              ? _buildLandscapeCropContent(media.size, dialogWidth)
              : _buildPortraitCropContent(),
        ),
      ),
    );
  }

  Widget _buildLandscapeCropContent(Size screenSize, double dialogWidth) {
    final cropSize = math
        .min(screenSize.height - 72, dialogWidth * .54)
        .clamp(210.0, 430.0)
        .toDouble();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: cropSize,
          height: cropSize,
          child: _buildCropSurface(),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCropHeader(compact: true),
              const SizedBox(height: 14),
              const Text(
                '建议把人物主体和重要文字留在中间区域。横屏只是编辑布局变化，最终发现页仍按 1:1 方形封面展示。',
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFE0554A),
                    fontSize: 11.5,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _buildCropActions(compact: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitCropContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCropHeader(),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 1,
          child: _buildCropSurface(),
        ),
        const SizedBox(height: 16),
        const Text(
          '建议把人物主体和重要文字留在中间区域，发现页会按这个方形封面展示。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE0554A),
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _buildCropActions(),
      ],
    );
  }

  Widget _buildCropHeader({bool compact = false}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '裁剪剧本封面',
                style: TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                '固定 1:1 · 双指或滚轮缩放 · 拖动调整位置',
                maxLines: 2,
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: compact ? 10.8 : 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          onPressed: _cropping ? null : () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.close_rounded,
            size: compact ? 18 : 20,
            color: AppColors.textOnDarkMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildCropSurface() {
    return ClipRRect(
      borderRadius: _editorRadius,
      child: ColoredBox(
        color: Colors.black,
        child: Crop(
          image: widget.image,
          controller: _cropController,
          aspectRatio: 1,
          interactive: true,
          fixCropRect: true,
          initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
            size: 0.92,
            aspectRatio: 1,
          ),
          baseColor: Colors.black,
          maskColor: Colors.black.withOpacity(0.56),
          radius: 4,
          filterQuality: FilterQuality.medium,
          progressIndicator: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          cornerDotBuilder: (_, __) => const SizedBox.shrink(),
          onCropped: (result) {
            switch (result) {
              case CropSuccess(:final croppedImage):
                if (mounted) {
                  Navigator.of(context).pop(croppedImage);
                }
              case CropFailure(:final cause):
                if (!mounted) return;
                setState(() {
                  _cropping = false;
                  _error = '裁剪失败：$cause';
                });
            }
          },
        ),
      ),
    );
  }

  Widget _buildCropActions({bool compact = false}) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _cropping ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textOnDarkMuted,
              side: BorderSide.none,
              backgroundColor: Colors.white.withOpacity(0.05),
              minimumSize: Size.fromHeight(compact ? 42 : 48),
              shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
            ),
            child: Text(
              '取消',
              style: TextStyle(fontSize: compact ? 12.5 : 14),
            ),
          ),
        ),
        SizedBox(width: compact ? 10 : 14),
        Expanded(
          child: FilledButton(
            onPressed: _cropping ? null : _confirmCrop,
            style: FilledButton.styleFrom(
              backgroundColor: _editorAccent,
              foregroundColor: const Color(0xFF0B0B0B),
              minimumSize: Size.fromHeight(compact ? 42 : 48),
              shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
            ),
            child: _cropping
                ? SizedBox(
                    width: compact ? 18 : 20,
                    height: compact ? 18 : 20,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0B0B0B),
                    ),
                  )
                : Text(
                    '使用此封面',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12.5 : 14,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CharacterEditorSheet extends StatefulWidget {
  const _CharacterEditorSheet({
    required this.character,
    required this.characterIndex,
    this.onPickMedia,
    this.canDelete = true,
  });

  final Map<String, dynamic> character;
  final int characterIndex;
  final ScenarioMediaPicker? onPickMedia;
  final bool canDelete;

  @override
  State<_CharacterEditorSheet> createState() => _CharacterEditorSheetState();
}

class _CharacterEditorSheetState extends State<_CharacterEditorSheet> {
  late final Map<String, dynamic> _character;
  late final TextEditingController _name;
  late final TextEditingController _identity;
  late final TextEditingController _age;
  late final TextEditingController _appearance;
  late final TextEditingController _background;
  late final TextEditingController _avatarUrl;
  late final TextEditingController _portraitUrl;
  late final TextEditingController _relationship;
  late String _voiceValue;
  late String _voiceNameValue;
  late String _trialUrlValue;
  late double _voiceSpeed;
  late double _voicePitch;
  final AudioPlayer _voiceTrialPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _voiceTrialStateSubscription;
  String _currentVoiceTrialUrl = '';
  bool _previewingVoice = false;
  bool _uploadingAvatar = false;
  bool _uploadingPortrait = false;

  Map<String, dynamic> get _jsonData {
    final value = _character['json_data'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      final map = value.map((key, value) => MapEntry(key.toString(), value));
      _character['json_data'] = map;
      return map;
    }
    final map = <String, dynamic>{};
    _character['json_data'] = map;
    return map;
  }

  Map<String, dynamic> get _initialConfig {
    final value = _character['initial_config'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      final map = value.map((key, value) => MapEntry(key.toString(), value));
      _character['initial_config'] = map;
      return map;
    }
    final map = <String, dynamic>{};
    _character['initial_config'] = map;
    return map;
  }

  Map<String, dynamic> _parseCharacterMap(dynamic value) {
    if (value is Map<String, dynamic>) return <String, dynamic>{...value};
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  double _parseVoiceNumber(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _character = <String, dynamic>{...widget.character};
    final jsonData = _jsonData;
    final initialConfig = _initialConfig;
    _name = TextEditingController(text: _character['name']?.toString() ?? '');
    _identity =
        TextEditingController(text: jsonData['identity']?.toString() ?? '');
    _age = TextEditingController(text: jsonData['age']?.toString() ?? '');
    _appearance =
        TextEditingController(text: jsonData['appearance']?.toString() ?? '');
    _background =
        TextEditingController(text: jsonData['background']?.toString() ?? '');
    _avatarUrl =
        TextEditingController(text: _character['avatar']?.toString() ?? '');
    _portraitUrl =
        TextEditingController(text: _character['portrait']?.toString() ?? '');
    _relationship = TextEditingController(
      text: initialConfig['relationship_status']?.toString() ?? '陌生',
    );
    final customAttributes =
        _parseCharacterMap(_character['custom_attributes']);
    _voiceValue = (jsonData['voice'] ??
            customAttributes['voice'] ??
            _character['voice'] ??
            '')
        .toString()
        .trim();
    _voiceNameValue = (jsonData['voice_name'] ??
            customAttributes['voice_name'] ??
            _character['voice_name'] ??
            '')
        .toString()
        .trim();
    _trialUrlValue = (jsonData['trial_url'] ??
            customAttributes['trial_url'] ??
            _character['trial_url'] ??
            '')
        .toString()
        .trim();
    _voiceSpeed = _parseVoiceNumber(
      jsonData['voice_speed'] ??
          customAttributes['voice_speed'] ??
          _character['voice_speed'],
      1.0,
    ).clamp(0.5, 2.0).toDouble();
    _voicePitch = _parseVoiceNumber(
      jsonData['voice_pitch'] ??
          customAttributes['voice_pitch'] ??
          _character['voice_pitch'],
      1.1,
    ).clamp(0.5, 2.0).toDouble();

    _voiceTrialStateSubscription =
        _voiceTrialPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _previewingVoice = false;
          _currentVoiceTrialUrl = '';
        });
      } else if (_previewingVoice != state.playing) {
        setState(() => _previewingVoice = state.playing);
      }
    });
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _identity,
      _age,
      _appearance,
      _background,
      _avatarUrl,
      _portraitUrl,
      _relationship,
    ]) {
      controller.dispose();
    }
    _voiceTrialStateSubscription?.cancel();
    _voiceTrialPlayer.dispose();
    super.dispose();
  }

  Future<void> _pick(ScenarioMediaKind kind) async {
    if (widget.onPickMedia == null) return;
    if (kind == ScenarioMediaKind.avatar && _uploadingAvatar) return;
    if (kind == ScenarioMediaKind.portrait && _uploadingPortrait) return;

    setState(() {
      if (kind == ScenarioMediaKind.avatar) _uploadingAvatar = true;
      if (kind == ScenarioMediaKind.portrait) _uploadingPortrait = true;
    });

    final result = await widget.onPickMedia!(
      context,
      ScenarioMediaTarget(kind: kind, characterIndex: widget.characterIndex),
    );
    if (!mounted) return;

    setState(() {
      if (kind == ScenarioMediaKind.avatar) _uploadingAvatar = false;
      if (kind == ScenarioMediaKind.portrait) _uploadingPortrait = false;
      if (result != null && kind == ScenarioMediaKind.avatar) {
        _avatarUrl.text = result.url;
      }
      if (result != null && kind == ScenarioMediaKind.portrait) {
        _portraitUrl.text = result.url;
      }
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final jsonData = _jsonData;
    jsonData['identity'] = _identity.text;
    jsonData['age'] = _age.text;
    jsonData['appearance'] = _appearance.text;
    jsonData['background'] = _background.text;
    jsonData['voice'] = _voiceValue.trim();
    jsonData['voice_name'] = _voiceNameValue.trim();
    jsonData['trial_url'] = _trialUrlValue.trim();
    jsonData['voice_speed'] = _voiceSpeed;
    jsonData['voice_pitch'] = _voicePitch;

    final initialConfig = _initialConfig;
    initialConfig['relationship_status'] = _relationship.text.trim().isEmpty
        ? '陌生'
        : _relationship.text.trim();

    _character['name'] = _name.text.trim();
    _character['avatar'] = _avatarUrl.text.trim();
    _character['portrait'] = _portraitUrl.text.trim();
    _character['persona'] = <String, dynamic>{...jsonData};
    _character['json_data'] = jsonData;
    _character['initial_config'] = initialConfig;
    _character['voice'] = _voiceValue.trim();
    _character['voice_speed'] = _voiceSpeed;
    _character['voice_pitch'] = _voicePitch;
    final customAttributes = _parseCharacterMap(_character['custom_attributes'])
      ..['voice'] = _voiceValue.trim()
      ..['voice_name'] = _voiceNameValue.trim()
      ..['trial_url'] = _trialUrlValue.trim()
      ..['voice_speed'] = _voiceSpeed
      ..['voice_pitch'] = _voicePitch;
    _character['custom_attributes'] = customAttributes;

    Navigator.pop(context, _character);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final size = media.size;
    final availableHeight =
        math.max(320.0, size.height - bottomInset).toDouble();
    final landscape = size.width > size.height;
    final phoneLandscape =
        landscape && size.height <= 560 && size.width <= 1100;
    final portrait = _portraitUrl.text.trim();
    final avatar = _avatarUrl.text.trim();
    final isPlayer = _character['role']?.toString() == 'player';

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: landscape ? availableHeight : availableHeight * 0.94,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          gradient: RadialGradient(
            center: Alignment(0, -.18),
            radius: 1.05,
            colors: <Color>[
              Color(0xFF282F3C),
              Color(0xFF1D222C),
              Color(0xFF151921),
            ],
            stops: <double>[0, .52, 1],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: phoneLandscape ? 44 : (landscape ? 50 : 56),
              padding: EdgeInsets.symmetric(
                horizontal: phoneLandscape ? 6 : (landscape ? 10 : 14),
              ),
              decoration: const BoxDecoration(
                color: Color(0x661F2530),
                border: Border(bottom: BorderSide(color: _editorLine)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize:
                            phoneLandscape ? 12.5 : (landscape ? 13.5 : 14.5),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      isPlayer ? '主角档案' : '角色详情',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textOnDark,
                        fontSize:
                            phoneLandscape ? 13.5 : (landscape ? 14.5 : 16),
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  if (widget.canDelete)
                    IconButton(
                      tooltip: '删除该角色',
                      onPressed: () => Navigator.pop(
                        context,
                        <String, dynamic>{'__deleted': true},
                      ),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Color(0xFFE0554A),
                      ),
                    ),
                  TextButton(
                    onPressed: _save,
                    child: Text(
                      '完成',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize:
                            phoneLandscape ? 12.5 : (landscape ? 13.5 : 14.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: landscape
                  ? _buildLandscapeCharacterEditor(
                      portrait,
                      avatar,
                      phoneLandscape: phoneLandscape,
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                      children: [
                        _buildPortraitEditor(portrait),
                        const SizedBox(height: 14),
                        _buildIdentityEditor(avatar),
                        const SizedBox(height: 14),
                        _buildCharacterSettingsEditor(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeCharacterEditor(
    String portrait,
    String avatar, {
    required bool phoneLandscape,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = phoneLandscape
            ? (constraints.maxWidth * .29).clamp(190.0, 240.0).toDouble()
            : (constraints.maxWidth * .28).clamp(220.0, 320.0).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  phoneLandscape ? 8 : 12,
                  phoneLandscape ? 8 : 12,
                  phoneLandscape ? 6 : 8,
                  phoneLandscape ? 8 : 12,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: _buildPortraitEditor(portrait, fill: true),
                    ),
                    SizedBox(height: phoneLandscape ? 6 : 10),
                    _buildIdentityEditor(avatar, compact: true),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Colors.white.withOpacity(.05),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  phoneLandscape ? 8 : 12,
                  phoneLandscape ? 8 : 12,
                  phoneLandscape ? 10 : 14,
                  phoneLandscape ? 14 : 24,
                ),
                child: _buildCharacterSettingsEditor(compact: true),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPortraitEditor(String portrait, {bool fill = false}) {
    final surface = Container(
      decoration: BoxDecoration(
        color: _editorFieldBg,
        borderRadius: _editorRadiusLg,
        border: Border.all(color: _editorLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: portrait.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 40,
                          color: AppColors.textOnDarkMuted,
                        ),
                        SizedBox(height: 10),
                        Text(
                          '角色全身立绘',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Transform.scale(
                          scale: 1.08,
                          child: Image.network(
                            CdnUtil.resize(portrait, width: fill ? 720 : 900),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      ColoredBox(color: Colors.black.withOpacity(0.28)),
                      Padding(
                        padding: EdgeInsets.all(fill ? 6 : 8),
                        child: Image.network(
                          CdnUtil.resize(portrait, width: fill ? 960 : 1200),
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textOnDarkMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_uploadingPortrait)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: fill ? 10 : 12,
            bottom: fill ? 10 : 12,
            child: _mediaButton(
              label: _uploadingPortrait
                  ? '上传中'
                  : widget.onPickMedia != null
                      ? '替换立绘'
                      : '填写地址',
              loading: _uploadingPortrait,
              onTap: _uploadingPortrait
                  ? null
                  : widget.onPickMedia != null
                      ? () => _pick(ScenarioMediaKind.portrait)
                      : () => _showUrlEditor(_portraitUrl, '立绘地址'),
            ),
          ),
        ],
      ),
    );

    if (fill) return surface;
    return AspectRatio(aspectRatio: 4 / 5.4, child: surface);
  }

  Widget _buildIdentityEditor(String avatar, {bool compact = false}) {
    return _card(
      compact: compact,
      child: Row(
        children: [
          GestureDetector(
            onTap: _uploadingAvatar
                ? null
                : widget.onPickMedia != null
                    ? () => _pick(ScenarioMediaKind.avatar)
                    : () => _showUrlEditor(_avatarUrl, '头像地址'),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: compact ? 58 : 72,
                  height: compact ? 58 : 72,
                  decoration: BoxDecoration(
                    color: _editorFieldBg,
                    borderRadius: _editorRadius,
                    border: Border.all(color: _editorLine),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      avatar.isEmpty
                          ? Icon(
                              Icons.person_outline_rounded,
                              size: compact ? 24 : 28,
                              color: AppColors.textOnDarkMuted,
                            )
                          : Image.network(
                              CdnUtil.resize(avatar, width: 150),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.textOnDarkMuted,
                              ),
                            ),
                      if (_uploadingAvatar)
                        const ColoredBox(
                          color: Colors.black54,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _editorAccent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _editorInk, width: 2),
                    ),
                    child: const Icon(
                      LucideIcons.camera,
                      size: 11,
                      color: Color(0xFF0C0C0C),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              children: [
                _field(_name, '角色姓名', compact: compact, label: '姓名'),
                SizedBox(height: compact ? 8 : 10),
                _field(
                  _identity,
                  '例如：赛博黑客 / 帝国骑士',
                  compact: compact,
                  label: '身份定位',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterSettingsEditor({bool compact = false}) {
    Widget buildBasics() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _genderValue,
                  dropdownColor: _editorInkSoft,
                  decoration: _decoration(
                    '性别',
                    compact: compact,
                    label: '性别',
                  ),
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textOnDarkMuted,
                  ),
                  items: const ['男', '女', '未知']
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            style: TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: compact ? 12.2 : 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => _jsonData['gender'] = value ?? '未知',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _age,
                  '年龄',
                  compact: compact,
                  label: '年龄',
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          _field(
            _relationship,
            '例如：陌生 / 青梅竹马 / 宿敌',
            compact: compact,
            label: '与玩家的初始关系',
          ),
          SizedBox(height: compact ? 10 : 12),
          _field(
            _appearance,
            '外貌、穿搭与标志性细节…',
            minLines: compact ? 2 : 3,
            compact: compact,
            label: '外貌特征',
          ),
          SizedBox(height: compact ? 10 : 12),
          _field(
            _background,
            '过往经历、核心动机与性格反差…',
            minLines: compact ? 3 : 4,
            compact: compact,
            label: '背景与人设',
          ),
        ],
      );
    }

    Widget buildTraits() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _listTagsEditor('性格标签', 'personality', compact: compact),
          SizedBox(height: compact ? 12 : 16),
          _listTagsEditor('喜好事物', 'likes', compact: compact),
          SizedBox(height: compact ? 12 : 16),
          _listTagsEditor('厌恶事物', 'dislikes', compact: compact),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetTitle('角色设定', compact: compact),
              SizedBox(height: compact ? 12 : 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (compact && constraints.maxWidth >= 520) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: buildBasics()),
                        const SizedBox(width: 14),
                        Expanded(child: buildTraits()),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildBasics(),
                      SizedBox(height: compact ? 14 : 18),
                      buildTraits(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 12 : 14),
        _buildVoiceSettingsEditor(compact: compact),
      ],
    );
  }

  Widget _buildVoiceSettingsEditor({bool compact = false}) {
    final selectedName = _voiceNameValue.trim().isNotEmpty
        ? _voiceNameValue.trim()
        : (_voiceValue.trim().isNotEmpty ? _voiceValue.trim() : '尚未选择音色');
    final hasTrial = _trialUrlValue.trim().isNotEmpty;

    return _card(
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle('声音配置 (TTS)', compact: compact),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '为角色挑选专属音色，支持按性别与语种筛选并试听样本。',
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: compact ? 11 : 12,
              height: 1.45,
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Container(
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              color: _editorFieldBg,
              borderRadius: _editorRadius,
              border: Border.all(color: _editorLine),
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 36 : 40,
                  height: compact ? 36 : 40,
                  decoration: BoxDecoration(
                    color: _editorAccent.withOpacity(.12),
                    borderRadius: _editorRadius,
                  ),
                  child: Icon(
                    Icons.record_voice_over_outlined,
                    color: AppColors.accent,
                    size: compact ? 18 : 20,
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: compact ? 12.5 : 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 4),
                      Text(
                        _voiceValue.trim().isEmpty
                            ? '点击右侧按钮挑选音色'
                            : 'ID: ${_voiceValue.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted,
                          fontSize: compact ? 10 : 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasTrial) ...[
                  IconButton(
                    tooltip: _previewingVoice ? '暂停试听' : '试听音色',
                    onPressed: _previewVoice,
                    icon: Icon(
                      _previewingVoice
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_outline_rounded,
                      color: AppColors.accent,
                      size: 24,
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _openVoicePicker,
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: Text(
                    '选择音色',
                    style: TextStyle(fontSize: compact ? 11 : 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent.withOpacity(.45)),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 12,
                      vertical: compact ? 8 : 10,
                    ),
                    shape: const RoundedRectangleBorder(
                        borderRadius: _editorRadius),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          _voiceSlider(
            label: '语速',
            value: _voiceSpeed,
            suffix: '×',
            compact: compact,
            onChanged: (value) => setState(() => _voiceSpeed = value),
          ),
          SizedBox(height: compact ? 4 : 6),
          _voiceSlider(
            label: '音调',
            value: _voicePitch,
            suffix: '×',
            compact: compact,
            onChanged: (value) => setState(() => _voicePitch = value),
          ),
        ],
      ),
    );
  }

  Widget _voiceSlider({
    required String label,
    required double value,
    required String suffix,
    required bool compact,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: compact ? 36 : 42,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textOnDark,
              fontSize: compact ? 11.5 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.5, 2.0).toDouble(),
            min: 0.5,
            max: 2.0,
            divisions: 30,
            activeColor: AppColors.accent,
            inactiveColor: Colors.white.withOpacity(.12),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: compact ? 42 : 48,
          child: Text(
            '${value.toStringAsFixed(2)}$suffix',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: compact ? 11 : 12,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openVoicePicker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoicePickerSheet(
        selectedVoiceName: _voiceNameValue,
        selectedVoiceId: _voiceValue,
      ),
    );
    if (selected == null || !mounted) return;

    final actualVoiceId =
        (selected['id'] ?? selected['voice_id'] ?? selected['voice'] ?? '')
            .toString()
            .trim();
    final voiceName = (selected['name'] ?? selected['voice_name'] ?? '')
        .toString()
        .trim();
    final trialUrl = (selected['trial_url'] ?? '').toString().trim();

    setState(() {
      _voiceNameValue = voiceName;
      _trialUrlValue = trialUrl;
      if (actualVoiceId.isNotEmpty) _voiceValue = actualVoiceId;
      _jsonData['voice_name'] = _voiceNameValue;
      _jsonData['trial_url'] = _trialUrlValue;
      _jsonData['voice'] = _voiceValue;
    });
  }

  Future<void> _previewVoice() async {
    final url = _trialUrlValue.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('该角色暂未配置音色试听样本，请先选择音色。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      if (_currentVoiceTrialUrl == url && _voiceTrialPlayer.playing) {
        await _voiceTrialPlayer.pause();
        return;
      }

      if (_currentVoiceTrialUrl != url ||
          _voiceTrialPlayer.processingState == ProcessingState.idle ||
          _voiceTrialPlayer.processingState == ProcessingState.completed) {
        await _voiceTrialPlayer.stop();
        await _voiceTrialPlayer.setUrl(url);
        _currentVoiceTrialUrl = url;
      }

      if (mounted) setState(() => _previewingVoice = true);
      unawaited(_voiceTrialPlayer.play().catchError((Object error) {
        if (!mounted) return;
        setState(() => _previewingVoice = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('音色试听失败：$error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }));
    } catch (error) {
      if (!mounted) return;
      setState(() => _previewingVoice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('音色试听失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String get _genderValue {
    final raw = _jsonData['gender']?.toString() ?? '未知';
    if (raw == 'male') return '男';
    if (raw == 'female') return '女';
    if (raw == '男' || raw == '女' || raw == '未知') return raw;
    return '未知';
  }

  Future<void> _showUrlEditor(
      TextEditingController controller, String title) async {
    final temp = TextEditingController(text: controller.text);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _editorInkSoft,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: _editorRadiusLg,
          side: BorderSide(color: _editorLine),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textOnDark,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: TextField(
          controller: temp,
          style: const TextStyle(color: AppColors.textOnDark),
          decoration: _decoration('输入图片 URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textOnDarkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, temp.text),
            child: const Text(
              '完成',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    temp.dispose();
    if (value != null && mounted) {
      setState(() => controller.text = value.trim());
    }
  }

  Widget _mediaButton({
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Material(
      color: Colors.black.withOpacity(0.68),
      borderRadius: _editorRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: _editorRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    color: AppColors.accent,
                  ),
                )
              else
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 15,
                  color: AppColors.textOnDark,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: loading ? AppColors.accent : AppColors.textOnDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: _editorSurface.withOpacity(0.7),
        borderRadius: _editorRadiusLg,
        border: Border.all(color: _editorLine),
      ),
      child: child,
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    int minLines = 1,
    bool compact = false,
    String? label,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : 8,
      keyboardType: keyboardType,
      style: TextStyle(
        color: AppColors.textOnDark,
        fontSize: compact ? 12.5 : 13.5,
        height: compact ? 1.4 : 1.5,
      ),
      decoration: _decoration(
        hint,
        compact: compact,
        label: label,
      ),
    );
  }

  InputDecoration _decoration(
    String hint, {
    bool compact = false,
    String? label,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      floatingLabelBehavior: label == null
          ? FloatingLabelBehavior.never
          : FloatingLabelBehavior.always,
      labelStyle: TextStyle(
        color: AppColors.textOnDarkMuted,
        fontSize: compact ? 11.5 : 12,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.accent,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.28),
        fontSize: compact ? 12 : 13,
      ),
      filled: true,
      fillColor: _editorFieldBg,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 11 : 14,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: _editorRadius,
        borderSide: BorderSide(color: _editorLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _editorRadius,
        borderSide: BorderSide(color: _editorAccent.withOpacity(0.75)),
      ),
    );
  }

  Widget _listTagsEditor(String label, String field, {bool compact = false}) {
    final raw = _jsonData[field];
    final values =
        raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _editorTextSoft,
            fontSize: compact ? 11.5 : 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 8 : 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < values.length; i++)
              Container(
                padding: EdgeInsets.fromLTRB(
                  compact ? 9 : 10,
                  compact ? 5 : 6,
                  compact ? 6 : 7,
                  compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: _editorFieldBg,
                  borderRadius: _editorRadius,
                  border: Border.all(color: _editorLine),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      values[i],
                      style: TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: compact ? 11.5 : 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        values.removeAt(i);
                        setState(() => _jsonData[field] = values);
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: AppColors.textOnDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            InkWell(
              borderRadius: _editorRadius,
              onTap: () async {
                final controller = TextEditingController();
                final value = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: _editorInkSoft,
                    surfaceTintColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: _editorRadiusLg,
                      side: BorderSide(color: _editorLine),
                    ),
                    title: Text(
                      '添加$label',
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      onSubmitted: (v) => Navigator.pop(dialogContext, v),
                      style: const TextStyle(color: AppColors.textOnDark),
                      decoration: _decoration('输入内容后回车或点添加'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppColors.textOnDarkMuted),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(dialogContext, controller.text),
                        child: const Text(
                          '添加',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                controller.dispose();
                final text = value?.trim() ?? '';
                if (text.isNotEmpty && !values.contains(text) && mounted) {
                  values.add(text);
                  setState(() => _jsonData[field] = values);
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 5 : 6,
                ),
                decoration: BoxDecoration(
                  color: _editorAccent.withOpacity(0.1),
                  borderRadius: _editorRadius,
                  border: Border.all(color: _editorAccent.withOpacity(.24)),
                ),
                child: Text(
                  '+ 添加',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: compact ? 11.2 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text, {this.compact = false});
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _editorAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          text,
          style: TextStyle(
            color: AppColors.textOnDark,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Mirrors Vue's CharacterEditModal.vue voice drawer:
/// GET /tts/voices, filter by gender/language, and preview each voice's trial_url.
class _VoicePickerSheet extends StatefulWidget {
  const _VoicePickerSheet({
    required this.selectedVoiceName,
    required this.selectedVoiceId,
  });

  final String selectedVoiceName;
  final String selectedVoiceId;

  @override
  State<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<_VoicePickerSheet> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSubscription;

  List<Map<String, dynamic>> _voices = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String _filterGender = '全部';
  String _filterLanguage = '全部';
  String _playingUrl = '';

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _playingUrl = '');
      }
    });
    _loadVoices();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await ApiClient.instance.get('/tts/voices');
      final rawList = _extractVoiceList(response);
      if (rawList == null) {
        throw Exception('音色接口未返回 voices 列表');
      }

      final voices =
          rawList.whereType<Map>().map<Map<String, dynamic>>((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList();

      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loading = false;
        _error = voices.isEmpty ? '当前没有可用音色' : null;
        if (!_languages.contains(_filterLanguage)) {
          _filterLanguage = '全部';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '获取音色列表失败：$error';
      });
    }
  }

  List<dynamic>? _extractVoiceList(dynamic response) {
    if (response is List) return response;
    if (response is! Map) return null;

    final root = response;
    final rootVoices = root['voices'];
    if (rootVoices is List) return rootVoices;

    final data = root['data'];
    if (data is List) return data;
    if (data is Map) {
      final voices = data['voices'];
      if (voices is List) return voices;

      final nestedData = data['data'];
      if (nestedData is List) return nestedData;
      if (nestedData is Map && nestedData['voices'] is List) {
        return nestedData['voices'] as List;
      }
    }

    return null;
  }

  String _stringField(Map<String, dynamic> voice, String key) {
    return voice[key]?.toString().trim() ?? '';
  }

  String _voiceId(Map<String, dynamic> voice) {
    return _stringField(voice, 'id').isNotEmpty
        ? _stringField(voice, 'id')
        : (_stringField(voice, 'voice_id').isNotEmpty
            ? _stringField(voice, 'voice_id')
            : _stringField(voice, 'voice'));
  }

  List<String> get _languages {
    final values = _voices
        .map((voice) => _stringField(voice, 'language'))
        .where((language) => language.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return <String>['全部', ...values];
  }

  List<Map<String, dynamic>> get _filteredVoices {
    return _voices.where((voice) {
      final gender = _stringField(voice, 'gender');
      final language = _stringField(voice, 'language');
      final genderMatches = _filterGender == '全部' || gender == _filterGender;
      final languageMatches =
          _filterLanguage == '全部' || language == _filterLanguage;
      return genderMatches && languageMatches;
    }).toList();
  }

  bool _isSelected(Map<String, dynamic> voice) {
    final name = _stringField(voice, 'name');
    final id = _voiceId(voice);
    return (widget.selectedVoiceName.isNotEmpty &&
            name == widget.selectedVoiceName) ||
        (widget.selectedVoiceId.isNotEmpty && id == widget.selectedVoiceId);
  }

  Future<void> _toggleTrial(Map<String, dynamic> voice) async {
    final url = _stringField(voice, 'trial_url');
    if (url.isEmpty) {
      _showMessage('该音色暂无试听音频');
      return;
    }

    try {
      if (_playingUrl == url && _player.playing) {
        await _player.pause();
        return;
      }

      if (_playingUrl != url ||
          _player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        await _player.stop();
        await _player.setUrl(url);
        _playingUrl = url;
      }

      if (mounted) setState(() {});
      unawaited(_player.play().catchError((Object error) {
        if (!mounted) return;
        setState(() => _playingUrl = '');
        _showMessage('试听失败：$error');
      }));
    } catch (error) {
      if (!mounted) return;
      setState(() => _playingUrl = '');
      _showMessage('试听失败：$error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: _editorFieldBg,
      selectedColor: AppColors.accent.withOpacity(.18),
      labelStyle: TextStyle(
        color: selected ? AppColors.accent : AppColors.textOnDarkMuted,
        fontSize: 11.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? AppColors.accent.withOpacity(.45) : _editorLine,
      ),
      shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = (media.size.height * .84).clamp(360.0, 760.0).toDouble();
    final languages = _languages;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        gradient: RadialGradient(
          center: Alignment(0, -.18),
          radius: 1.05,
          colors: <Color>[
            Color(0xFF282F3C),
            Color(0xFF1D222C),
            Color(0xFF151921),
          ],
          stops: <double>[0, .52, 1],
        ),
        border: Border(top: BorderSide(color: _editorLine)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.record_voice_over_outlined,
                    color: AppColors.accent,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择角色音色',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '点击条目即可选用，或点右侧播放按钮先试听样本',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textOnDarkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _editorLine),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text(
                    '性别',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final gender in const <String>['全部', '男', '女']) ...[
                    _filterChip(
                      gender,
                      _filterGender == gender,
                      () => setState(() => _filterGender = gender),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 10),
                  const Text(
                    '语种',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _editorFieldBg,
                        borderRadius: _editorRadius,
                        border: Border.all(color: _editorLine),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: languages.contains(_filterLanguage)
                              ? _filterLanguage
                              : '全部',
                          isExpanded: true,
                          dropdownColor: _editorInkSoft,
                          icon: const Icon(
                            Icons.expand_more_rounded,
                            color: AppColors.textOnDarkMuted,
                            size: 18,
                          ),
                          style: const TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 12,
                          ),
                          items: languages.map((language) {
                            return DropdownMenuItem<String>(
                              value: language,
                              child: Text(language),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _filterLanguage = value);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _editorLine),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: AppColors.accent,
                            strokeWidth: 2,
                          ),
                          SizedBox(height: 12),
                          Text(
                            '正在获取音色列表…',
                            style: TextStyle(
                              color: AppColors.textOnDarkMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_off_outlined,
                                  color: AppColors.textOnDarkMuted,
                                  size: 30,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textOnDarkMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _loadVoices,
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16),
                                  label: const Text('重新加载'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredVoices.isEmpty
                          ? const Center(
                              child: Text(
                                '没有找到符合筛选条件的音色',
                                style: TextStyle(
                                  color: AppColors.textOnDarkMuted,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 24),
                              itemCount: _filteredVoices.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final voice = _filteredVoices[index];
                                final name = _stringField(voice, 'name');
                                final id = _voiceId(voice);
                                final language =
                                    _stringField(voice, 'language');
                                final gender = _stringField(voice, 'gender');
                                final trialUrl =
                                    _stringField(voice, 'trial_url');
                                final selected = _isSelected(voice);
                                final playing = trialUrl.isNotEmpty &&
                                    _playingUrl == trialUrl &&
                                    _player.playing;

                                return Material(
                                  color: selected
                                      ? AppColors.accent.withOpacity(.11)
                                      : _editorFieldBg,
                                  borderRadius: _editorRadius,
                                  child: InkWell(
                                    borderRadius: _editorRadius,
                                    onTap: () => Navigator.pop(context, voice),
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 11, 8, 11),
                                      decoration: BoxDecoration(
                                        borderRadius: _editorRadius,
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.accent.withOpacity(.6)
                                              : _editorLine,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.accent
                                                      .withOpacity(.18)
                                                  : Colors.white
                                                      .withOpacity(.04),
                                              borderRadius: _editorRadius,
                                            ),
                                            child: Icon(
                                              selected
                                                  ? Icons.check_rounded
                                                  : Icons.graphic_eq_rounded,
                                              color: selected
                                                  ? AppColors.accent
                                                  : AppColors.textOnDarkMuted,
                                              size: 19,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name.isEmpty ? id : name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppColors.textOnDark,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    if (language.isNotEmpty)
                                                      _voiceMetaTag(language),
                                                    if (gender.isNotEmpty)
                                                      _voiceMetaTag(gender),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                playing ? '暂停试听' : '试听音色',
                                            onPressed: trialUrl.isEmpty
                                                ? null
                                                : () => _toggleTrial(voice),
                                            icon: Icon(
                                              playing
                                                  ? Icons
                                                      .pause_circle_filled_rounded
                                                  : Icons
                                                      .play_circle_outline_rounded,
                                              color: trialUrl.isEmpty
                                                  ? AppColors.textOnDarkMuted
                                                      .withOpacity(.35)
                                                  : AppColors.accent,
                                              size: 26,
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppColors.textOnDarkMuted,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceMetaTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textOnDarkMuted,
          fontSize: 10,
        ),
      ),
    );
  }
}
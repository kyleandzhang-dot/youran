import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_shared.dart';
import 'api/api_client.dart';
import 'api/scenario_editor_api.dart';

enum ScenarioEditorSection {
  overview,
  characters,
  story,
  ai,
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

class ScenarioEditPage extends StatefulWidget {
  const ScenarioEditPage({
    super.key,
    required this.scenarioId,
    this.api,
    this.onPublish,
    this.onDeleted,
    this.onPickMedia,
  });

  final String scenarioId;
  final ScenarioEditorApi? api;
  final VoidCallback? onPublish;
  final VoidCallback? onDeleted;
  final ScenarioMediaPicker? onPickMedia;

  @override
  State<ScenarioEditPage> createState() => _ScenarioEditPageState();
}

class _ScenarioEditPageState extends State<ScenarioEditPage> {
  static const Color _pageBg = Color(0xFF0A0A0A);
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
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ScenarioEditorApi();
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
    return value
        .map<Map<String, dynamic>>((item) {
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
        })
        .toList();
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

      final rawPoints = _worldSetting['key_plot_points'] ?? data['key_plot_points'];
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

      final sourceCharacters = data['characters_detailed'] ?? data['characters'];
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

    return <String, dynamic>{
      'id': source['id'] ?? DateTime.now().microsecondsSinceEpoch,
      'name': source['name']?.toString() ?? '',
      'role': source['role']?.toString() ?? 'npc',
      'avatar': (source['avatar_url'] ?? source['avatar'])?.toString() ?? '',
      'avatar_seed': source['avatar_seed']?.toString() ?? '',
      'portrait': (source['portrait_url'] ?? source['portrait'])?.toString() ?? '',
      'greeting': source['greeting']?.toString() ?? '',
      'persona': persona,
      'initial_config': initialConfig,
      'json_data': jsonData,
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
      _bgm('emotion_slow', '情感', '忧伤', '慢节奏', 'emotional', 'low', emotional['low']),
      _bgm('emotion_fast', '情感', '爆发', '快节奏', 'emotional', 'high', emotional['high']),
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
    setState(() => _section = section);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleController.text.trim().isEmpty) {
      _showSnack('标题不能为空', error: true);
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
      'voice': jsonData['voice'],
      'voice_speed': jsonData['voice_speed'] ?? 1.0,
      'voice_pitch': jsonData['voice_pitch'] ?? 1.1,
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
        content: Text(message, style: TextStyle(color: error ? _danger : AppColors.accent)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(4),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  ScenarioMediaPicker get _mediaPicker => widget.onPickMedia ?? _pickMediaInternally;

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

    final contentType = _contentTypeForUpload(file.name, isAudio: isBgm);

    try {
      final signature = await ApiClient.instance.post(
        '/r2/get-signature',
        body: <String, dynamic>{
          'filename': file.name,
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
        body: bytes,
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

  Future<void> _editBgmMedia(int index) async {
    if (_uploadingBgmIndexes.contains(index)) return;
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
          backgroundColor: const Color(0xFF161616),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
              child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('完成', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
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
        },
      });
    });
    _markDirty();
    _editCharacter(_characters.length - 1);
  }

  Future<void> _editCharacter(int realIndex) async {
    if (realIndex < 0 || realIndex >= _characters.length) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CharacterEditorSheet(
        character: _deepCopyMap(_characters[realIndex]),
        onPickMedia: _mediaPicker,
        characterIndex: realIndex,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _characters[realIndex] = result);
    _markDirty();
  }

  void _removeCharacter(int realIndex) {
    if (_characters[realIndex]['role']?.toString() == 'companion') {
      _showSnack('系统角色无法删除', error: true);
      return;
    }
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
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                _menuRow(
                  icon: Icons.restart_alt_rounded,
                  title: '重置剧情',
                  subtitle: '清空对话记录，重新开始',
                  onTap: () => Navigator.pop(sheetContext, 'reset'),
                ),
                const SizedBox(height: 4),
                _menuRow(
                  icon: Icons.delete_outline_rounded,
                  title: '删除剧本',
                  subtitle: '永久删除该剧本及所有数据',
                  danger: true,
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
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
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? _danger : AppColors.accent),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDarkMuted),
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
        backgroundColor: const Color(0xFF161616),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(description, style: const TextStyle(color: AppColors.textOnDarkMuted, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText, style: TextStyle(color: danger ? _danger : AppColors.accent, fontWeight: FontWeight.w700)),
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
      // 与删除保持一致：明确告诉 GameShell 这个世界的数据生命周期已变化。
      // 若它正是当前游玩的世界，GameShell 会自动退出旧页面并打开世界列表。
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _pageBg,
        colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.accent,
              surface: _pageBg,
            ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          isDense: true,
        ),
      ),
      child: Scaffold(
        backgroundColor: _pageBg,
        body: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : Stack(
                    children: [
                      CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          _buildAppBar(),
                          SliverToBoxAdapter(child: _buildHero()),
                          SliverToBoxAdapter(child: _buildSectionTabs()),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 112),
                            sliver: SliverToBoxAdapter(child: _buildCurrentSection()),
                          ),
                        ],
                      ),
                      _buildBottomBar(),
                      if (_actionLoading)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withOpacity(0.5),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textOnDarkMuted),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textOnDarkMuted, height: 1.5),
              ),
              const SizedBox(height: 18),
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
      backgroundColor: _pageBg.withOpacity(0.95),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: AppColors.textOnDark),
      ),
      centerTitle: true,
      title: Column(
        children: [
          const Text(
            '编辑世界',
            style: TextStyle(color: AppColors.textOnDark, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (_dirty)
            const Text(
              '有未保存修改',
              style: TextStyle(color: AppColors.accent, fontSize: 9.5, fontWeight: FontWeight.w500),
            ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _showMoreMenu,
          icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textOnDark),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _editCover,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 82,
                  height: 108,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _coverUrl.isEmpty
                      ? const Icon(Icons.landscape_outlined, size: 30, color: AppColors.textOnDarkMuted)
                      : Image.network(
                          _coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textOnDarkMuted,
                          ),
                        ),
                ),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _pageBg, width: 2),
                    ),
                    child: _uploadingCover
                        ? const Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF0C0C0C),
                            ),
                          )
                        : const Icon(LucideIcons.camera, size: 12, color: Color(0xFF0C0C0C)),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _modeLabel(_mode),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _titleController,
                  onChanged: (_) => _markDirty(),
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: '给世界起个名字',
                    hintStyle: TextStyle(color: AppColors.textOnDarkMuted),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ID  ${_id.isEmpty ? widget.scenarioId : _id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 10.5,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTabs() {
    final tabs = <(ScenarioEditorSection, String, IconData)>[
      (ScenarioEditorSection.overview, '基础', Icons.tune_rounded),
      (ScenarioEditorSection.characters, '角色', Icons.people_alt_outlined),
      (ScenarioEditorSection.story, '剧情', Icons.route_rounded),
      (ScenarioEditorSection.ai, 'AI', Icons.auto_awesome_outlined),
      (ScenarioEditorSection.bgm, 'BGM', Icons.graphic_eq_rounded),
      (ScenarioEditorSection.lorebook, '知识库', Icons.menu_book_outlined),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
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
              onTap: () => _setSection(item.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? AppColors.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(item.$3, size: 14, color: selected ? AppColors.accent : AppColors.textOnDarkMuted),
                    const SizedBox(width: 6),
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.textOnDarkMuted,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
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
      case ScenarioEditorSection.ai:
        return _buildAiSection();
      case ScenarioEditorSection.bgm:
        return _buildBgmSection();
      case ScenarioEditorSection.lorebook:
        return _buildLorebookSection();
    }
  }

  Widget _buildOverviewSection() {
    return Column(
      children: [
        _sectionCard(
          title: '基础信息',
          subtitle: '玩家第一眼看到的世界介绍',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('标签'),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _tags.length; i++)
                    GestureDetector(
                      onTap: () => _editTag(i),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _tagLabel(_tags[i]),
                              style: const TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _removeTag(i),
                              child: const Icon(Icons.close_rounded, size: 13, color: AppColors.textOnDarkMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: _addTag,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.accent.withOpacity(0.3), style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 13, color: AppColors.accent),
                          const SizedBox(width: 3),
                          const Text(
                            '新增标签',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _fieldLabel('世界设定'),
              const SizedBox(height: 8),
              _editorTextField(
                controller: _descriptionController,
                hint: '输入世界观描述、时代背景、主要冲突和玩家需要知道的信息…',
                minLines: 5,
                maxLines: 10,
              ),
              const SizedBox(height: 18),
              _fieldLabel('开场白'),
              const SizedBox(height: 8),
              _editorTextField(
                controller: _openingController,
                hint: '玩家进入剧本后看到的第一段话…',
                minLines: 4,
                maxLines: 8,
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
      title: '角色',
      subtitle: '头像、立绘、身份、性格与关系初始值',
      trailing: TextButton.icon(
        onPressed: _addCharacter,
        icon: const Icon(Icons.add_rounded, size: 15),
        label: const Text('新增'),
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      child: characters.isEmpty
          ? _emptyState('还没有角色', '添加第一个 NPC 或主角档案')
          : Column(
              children: [
                for (var i = 0; i < characters.length; i++) ...[
                  _characterRow(characters[i]),
                  if (i != characters.length - 1)
                    Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                ],
              ],
            ),
    );
  }

  Widget _characterRow(Map<String, dynamic> character) {
    final realIndex = character['__realIndex'] as int;
    final avatar = character['avatar']?.toString() ?? '';
    final jsonData = _parseMap(character['json_data']);
    final role = character['role']?.toString() ?? 'npc';
    return InkWell(
      onTap: () => _editCharacter(realIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatar.isEmpty
                  ? const Icon(Icons.person_outline_rounded, color: AppColors.textOnDarkMuted)
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person_outline_rounded, color: AppColors.textOnDarkMuted),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          character['name']?.toString().trim().isNotEmpty == true
                              ? character['name'].toString()
                              : '未命名',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textOnDark, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _tinyBadge(role == 'player' ? '主角' : 'NPC'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    jsonData['identity']?.toString().trim().isNotEmpty == true
                        ? jsonData['identity'].toString()
                        : '尚未设置身份',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: () => _removeCharacter(realIndex),
              icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textOnDarkMuted),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDarkMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStorySection() {
    if (_mode != 'novel') {
      return _sectionCard(
        title: '剧情流程',
        subtitle: '该模块主要用于互动小说模式',
        child: _emptyState('当前不是互动小说模式', '你仍可以切换模式后使用完整剧情节点'),
      );
    }

    final points = _plotPoints;
    return Column(
      children: [
        _sectionCard(
          title: '主线大纲',
          subtitle: '从开篇到结局的整体走向',
          child: _editorTextField(
            controller: _mainStoryController,
            hint: '用几段话说明主线目标、关键变化和结局方向…',
            minLines: 5,
            maxLines: 12,
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: '关键剧情节点',
          subtitle: 'AI 按顺序推进 · 共 ${points.length} 个节点',
          trailing: TextButton.icon(
            onPressed: _addPlotPoint,
            icon: const Icon(Icons.add_rounded, size: 15),
            label: const Text('新增'),
            style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          ),
          child: points.isEmpty
              ? _emptyState('暂无剧情节点', '添加后可以明确每一幕的目标、困境和推进条件')
              : Column(
                  children: [
                    for (var i = 0; i < points.length; i++) ...[
                      _plotPointCard(i, points[i]),
                      if (i != points.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _plotPointCard(int index, Map<String, dynamic> point) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
      collapsedShape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(4),
      ),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(4),
      ),
      backgroundColor: Colors.white.withOpacity(0.015),
      collapsedBackgroundColor: Colors.white.withOpacity(0.015),
      leading: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.accent.withOpacity(0.3)),
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      title: Row(
        children: [
          _arcBadge(point['arc']?.toString() ?? '探索'),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (point['goal'] ?? point['state'])?.toString().trim().isNotEmpty == true
                  ? (point['goal'] ?? point['state']).toString()
                  : '未填写节点目标',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        onPressed: () => _removePlotPoint(index),
        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textOnDarkMuted),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _dropdownField(
                label: '剧情幕段',
                value: point['arc']?.toString() ?? '探索',
                items: const <String>['诱发', '探索', '突转', '至暗', '终章'],
                labels: const <String>['第一幕 · 开端', '第二幕 · 发展', '第三幕 · 转折', '第四幕 · 低谷', '第五幕 · 结局'],
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
        const SizedBox(height: 12),
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
          value: (point['player_facing_problem'] ?? point['tension'])?.toString() ?? '',
          hint: '玩家为什么会继续推进这一节？',
          onChanged: (value) => _updatePlotPoint(index, 'player_facing_problem', value),
        ),
        _inlineInitialField(
          label: '完成信号',
          value: (point['completion_condition'] ?? point['exit'])?.toString() ?? '',
          hint: '故事演到什么程度就推进下一节？',
          onChanged: (value) => _updatePlotPoint(index, 'completion_condition', value),
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

  Widget _buildAiSection() {
    return _sectionCard(
      title: 'AI 行为',
      subtitle: '控制模型怎么理解世界、怎么思考、怎么回复',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('系统提示词'),
          const SizedBox(height: 8),
          _editorTextField(
            controller: _systemPromptController,
            hint: '告诉 AI 它在这个世界中的身份、边界和行为规则…',
            minLines: 5,
            maxLines: 12,
          ),
          const SizedBox(height: 18),
          _fieldLabel('推理指令'),
          const SizedBox(height: 8),
          _editorTextField(
            controller: _cotController,
            hint: '内部剧情判断、状态检查或推进规则…',
            minLines: 4,
            maxLines: 10,
          ),
          const SizedBox(height: 18),
          _fieldLabel('回复风格'),
          const SizedBox(height: 8),
          _editorTextField(
            controller: _responseStyleController,
            hint: '例如：短句、电影感、减少旁白、重视角色动作…',
            minLines: 4,
            maxLines: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildBgmSection() {
    final groups = <String, List<int>>{
      '日常': <int>[],
      '冲突': <int>[],
      '情感': <int>[],
    };
    for (var i = 0; i < _bgmList.length; i++) {
      groups[_bgmList[i]['category']]?.add(i);
    }

    return _sectionCard(
      title: '情景 BGM',
      subtitle: '每种情绪准备慢/快两档，剧情可以自动切换',
      child: Column(
        children: [
          for (final group in groups.entries) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                group.key,
                style: const TextStyle(color: AppColors.textOnDark, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            for (final index in group.value) ...[
              _bgmRow(index),
              const SizedBox(height: 8),
            ],
            if (group.key != groups.keys.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _bgmRow(int index) {
    final item = _bgmList[index];
    final url = item['url']?.toString() ?? '';
    final uploading = _uploadingBgmIndexes.contains(index);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              border: Border.all(color: AppColors.accent.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              uploading ? LucideIcons.loaderCircle : LucideIcons.music2,
              size: 15,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item['pace']}',
                      style: const TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  uploading
                      ? '正在上传音频…'
                      : url.isEmpty
                          ? '未配置'
                          : '已配置 · MP3/WAV 等',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: uploading || url.isNotEmpty ? AppColors.accent : AppColors.textOnDarkMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (url.isNotEmpty && !uploading)
            InkWell(
              onTap: () {
                setState(() {
                  item['url'] = '';
                  item['r2_key'] = '';
                  _changedBgmIndexes.add(index);
                });
                _markDirty();
              },
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(LucideIcons.x, size: 14, color: AppColors.textOnDarkMuted),
              ),
            ),
          InkWell(
            onTap: uploading ? null : () => _editBgmMedia(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: uploading ? Colors.white.withOpacity(0.1) : AppColors.accent.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (uploading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.accent,
                      ),
                    )
                  else
                    Icon(
                      url.isEmpty ? LucideIcons.upload : LucideIcons.refreshCw,
                      size: 12,
                      color: AppColors.accent,
                    ),
                  const SizedBox(width: 5),
                  Text(
                    uploading
                        ? '上传中'
                        : url.isEmpty
                            ? '上传'
                            : '替换',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10.5,
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
      title: '世界知识库',
      subtitle: '${entries.length} 条设定 · 关键词命中后注入给 AI',
      trailing: TextButton.icon(
        onPressed: _addLoreEntry,
        icon: const Icon(Icons.add_rounded, size: 15),
        label: const Text('新增'),
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      child: entries.isEmpty
          ? _emptyState('暂无知识条目', '把地名、组织、规则、物品等设定做成关键词词条')
          : Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _loreEntryCard(i, entries[i]),
                  if (i != entries.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _loreEntryCard(int index, Map<String, dynamic> entry) {
    final keys = entry['keys'];
    final firstKey = keys is List && keys.isNotEmpty ? keys.first?.toString() ?? '' : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: firstKey,
                  onChanged: (value) => _updateLoreEntry(index, 'key', value),
                  style: const TextStyle(color: AppColors.textOnDark, fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: '触发关键词，例如：圣剑',
                    hintStyle: TextStyle(color: AppColors.textOnDarkMuted),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _removeLoreEntry(index),
                icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textOnDarkMuted),
              ),
            ],
          ),
          Divider(height: 10, color: Colors.white.withOpacity(0.05)),
          TextFormField(
            initialValue: entry['content']?.toString() ?? '',
            onChanged: (value) => _updateLoreEntry(index, 'content', value),
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, height: 1.5),
            decoration: const InputDecoration(
              hintText: '当检测到关键词时，向 AI 注入的背景描述…',
              hintStyle: TextStyle(color: AppColors.textOnDarkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          14,
          8,
          14,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: _pageBg.withOpacity(0.95),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: Material(
          color: _dirty ? AppColors.accent : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: _saving ? null : (_dirty ? _save : widget.onPublish),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0C0C)),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _dirty
                              ? Icons.save_outlined
                              : widget.onPublish != null
                                  ? Icons.rocket_launch_outlined
                                  : Icons.check_rounded,
                          size: 16,
                          color: _dirty ? const Color(0xFF0C0C0C) : AppColors.textOnDarkMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dirty
                              ? '保存修改'
                              : widget.onPublish != null
                                  ? '发布剧本'
                                  : '已保存',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _dirty ? const Color(0xFF0C0C0C) : AppColors.textOnDarkMuted,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppColors.textOnDark, fontSize: 14.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
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
      style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, height: 1.55),
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
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: value,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: 5,
            style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, height: 1.45),
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
          dropdownColor: const Color(0xFF161616),
          isExpanded: true,
          decoration: _inputDecoration(''),
          icon: const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.textOnDarkMuted),
          items: [
            for (var i = 0; i < items.length; i++)
              DropdownMenuItem<String>(
                value: items[i],
                child: Text(labels[i], style: const TextStyle(fontSize: 12, color: AppColors.textOnDark)),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textOnDark,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textOnDarkMuted, fontWeight: FontWeight.w400, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withOpacity(0.02),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: AppColors.accent.withOpacity(0.6), width: 1),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.08), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          const Icon(Icons.layers_outlined, color: AppColors.textOnDarkMuted, size: 24),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }

  Widget _tinyBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.accent, fontSize: 9.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _arcBadge(String arc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _arcLabel(arc),
        style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 10, fontWeight: FontWeight.w600),
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

class _CharacterEditorSheet extends StatefulWidget {
  const _CharacterEditorSheet({
    required this.character,
    required this.characterIndex,
    this.onPickMedia,
  });

  final Map<String, dynamic> character;
  final int characterIndex;
  final ScenarioMediaPicker? onPickMedia;

  @override
  State<_CharacterEditorSheet> createState() => _CharacterEditorSheetState();
}

class _CharacterEditorSheetState extends State<_CharacterEditorSheet> {
  static const Color _bg = Color(0xFF0A0A0A);

  late final Map<String, dynamic> _character;
  late final TextEditingController _name;
  late final TextEditingController _identity;
  late final TextEditingController _age;
  late final TextEditingController _appearance;
  late final TextEditingController _background;
  late final TextEditingController _secret;
  late final TextEditingController _examples;
  late final TextEditingController _greeting;
  late final TextEditingController _avatarUrl;
  late final TextEditingController _portraitUrl;
  late final TextEditingController _affection;
  late final TextEditingController _stress;

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

  @override
  void initState() {
    super.initState();
    _character = <String, dynamic>{...widget.character};
    final jsonData = _jsonData;
    final initialConfig = _initialConfig;
    _name = TextEditingController(text: _character['name']?.toString() ?? '');
    _identity = TextEditingController(text: jsonData['identity']?.toString() ?? '');
    _age = TextEditingController(text: jsonData['age']?.toString() ?? '');
    _appearance = TextEditingController(text: jsonData['appearance']?.toString() ?? '');
    _background = TextEditingController(text: jsonData['background']?.toString() ?? '');
    _secret = TextEditingController(text: jsonData['secret']?.toString() ?? '');
    _examples = TextEditingController(text: jsonData['examples']?.toString() ?? '');
    _greeting = TextEditingController(text: _character['greeting']?.toString() ?? '');
    _avatarUrl = TextEditingController(text: _character['avatar']?.toString() ?? '');
    _portraitUrl = TextEditingController(text: _character['portrait']?.toString() ?? '');
    _affection = TextEditingController(text: (initialConfig['affection'] ?? 0).toString());
    _stress = TextEditingController(text: (initialConfig['stress'] ?? 0).toString());
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _identity,
      _age,
      _appearance,
      _background,
      _secret,
      _examples,
      _greeting,
      _avatarUrl,
      _portraitUrl,
      _affection,
      _stress,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ScenarioMediaKind kind) async {
    if (widget.onPickMedia == null) return;
    final result = await widget.onPickMedia!(
      context,
      ScenarioMediaTarget(kind: kind, characterIndex: widget.characterIndex),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (kind == ScenarioMediaKind.avatar) _avatarUrl.text = result.url;
      if (kind == ScenarioMediaKind.portrait) _portraitUrl.text = result.url;
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final jsonData = _jsonData;
    jsonData['identity'] = _identity.text;
    jsonData['age'] = _age.text;
    jsonData['appearance'] = _appearance.text;
    jsonData['background'] = _background.text;
    jsonData['secret'] = _secret.text;
    jsonData['examples'] = _examples.text;

    final initialConfig = _initialConfig;
    initialConfig['affection'] = num.tryParse(_affection.text) ?? 0;
    initialConfig['stress'] = num.tryParse(_stress.text) ?? 0;
    initialConfig['relationship_status'] = initialConfig['relationship_status'] ?? '陌生';

    _character['name'] = _name.text.trim();
    _character['avatar'] = _avatarUrl.text.trim();
    _character['portrait'] = _portraitUrl.text.trim();
    _character['greeting'] = _greeting.text;
    _character['persona'] = <String, dynamic>{...jsonData};
    _character['json_data'] = jsonData;
    _character['initial_config'] = initialConfig;

    Navigator.pop(context, _character);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final portrait = _portraitUrl.text.trim();
    final avatar = _avatarUrl.text.trim();
    final isPlayer = _character['role']?.toString() == 'player';

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.94,
        decoration: BoxDecoration(
          color: _bg,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted)),
                  ),
                  Expanded(
                    child: Text(
                      isPlayer ? '主角档案' : '角色详情',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textOnDark, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _save, 
                    child: const Text('完成', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                children: [
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                                      Icon(Icons.image_outlined, size: 32, color: AppColors.textOnDarkMuted),
                                      SizedBox(height: 8),
                                      Text('角色立绘', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12)),
                                    ],
                                  ),
                                )
                              : Image.network(
                                  portrait,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_outlined, color: AppColors.textOnDarkMuted),
                                  ),
                                ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: _mediaButton(
                            label: widget.onPickMedia != null ? '替换立绘' : '填写地址',
                            onTap: widget.onPickMedia != null
                                ? () => _pick(ScenarioMediaKind.portrait)
                                : () => _showUrlEditor(_portraitUrl, '立绘地址'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onPickMedia != null
                              ? () => _pick(ScenarioMediaKind.avatar)
                              : () => _showUrlEditor(_avatarUrl, '头像地址'),
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: avatar.isEmpty
                                ? const Icon(Icons.person_outline_rounded, color: AppColors.textOnDarkMuted)
                                : Image.network(
                                    avatar,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.person_outline_rounded, color: AppColors.textOnDarkMuted),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            children: [
                              _field(_name, '姓名'),
                              const SizedBox(height: 8),
                              _field(_identity, '身份，例如：赛博黑客'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SheetTitle('角色设定'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _genderValue,
                                dropdownColor: const Color(0xFF161616),
                                decoration: _decoration('性别'),
                                items: const ['男', '女', '未知']
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: AppColors.textOnDark, fontSize: 12))))
                                    .toList(),
                                onChanged: (value) => _jsonData['gender'] = value ?? '未知',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: _field(_age, '年龄')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _field(_appearance, '外貌特征', minLines: 3),
                        const SizedBox(height: 10),
                        _field(_background, '背景 / 人设', minLines: 4),
                        const SizedBox(height: 10),
                        _listTagsEditor('性格标签', 'personality'),
                        const SizedBox(height: 10),
                        _listTagsEditor('喜欢', 'likes'),
                        const SizedBox(height: 10),
                        _listTagsEditor('讨厌', 'dislikes'),
                        const SizedBox(height: 10),
                        _listTagsEditor('说话风格', 'speech_style'),
                        const SizedBox(height: 10),
                        _field(_secret, '秘密 / 隐藏信息', minLines: 3),
                        const SizedBox(height: 10),
                        _field(_examples, '对话示例', minLines: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SheetTitle('对话与关系'),
                        const SizedBox(height: 12),
                        _field(_greeting, '角色开场白', minLines: 3),
                        if (!isPlayer) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _field(_affection, '初始好感')),
                              const SizedBox(width: 10),
                              Expanded(child: _field(_stress, '初始压力')),
                            ],
                          ),
                        ],
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

  String get _genderValue {
    final raw = _jsonData['gender']?.toString() ?? '未知';
    if (raw == 'male') return '男';
    if (raw == 'female') return '女';
    if (raw == '男' || raw == '女' || raw == '未知') return raw;
    return '未知';
  }

  Future<void> _showUrlEditor(TextEditingController controller, String title) async {
    final temp = TextEditingController(text: controller.text);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        title: Text(title, style: const TextStyle(color: AppColors.textOnDark, fontWeight: FontWeight.w600, fontSize: 15)),
        content: TextField(controller: temp, style: const TextStyle(color: AppColors.textOnDark), decoration: _decoration('输入 URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted))),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, temp.text),
            child: const Text('完成', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    temp.dispose();
    if (value != null && mounted) setState(() => controller.text = value.trim());
  }

  Widget _mediaButton({required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera_outlined, size: 14, color: AppColors.textOnDark),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(color: AppColors.textOnDark, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }

  Widget _field(TextEditingController controller, String hint, {int minLines = 1}) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : 8,
      style: const TextStyle(color: AppColors.textOnDark, fontSize: 12.5, height: 1.45),
      decoration: _decoration(hint),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withOpacity(0.02),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: AppColors.accent.withOpacity(0.6)),
      ),
    );
  }

  Widget _listTagsEditor(String label, String field) {
    final raw = _jsonData[field];
    final values = raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < values.length; i++)
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 5, 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(values[i], style: const TextStyle(color: AppColors.textOnDark, fontSize: 11)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        values.removeAt(i);
                        setState(() => _jsonData[field] = values);
                      },
                      child: const Icon(Icons.close_rounded, size: 13, color: AppColors.textOnDarkMuted),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onTap: () async {
                final controller = TextEditingController();
                final value = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: const Color(0xFF161616),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: Colors.white.withOpacity(0.08)),
                    ),
                    title: Text('添加$label', style: const TextStyle(color: AppColors.textOnDark, fontWeight: FontWeight.w600, fontSize: 15)),
                    content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: AppColors.textOnDark), decoration: _decoration('输入内容')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消', style: TextStyle(color: AppColors.textOnDarkMuted))),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, controller.text),
                        child: const Text('添加', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('+ 添加', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textOnDark,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
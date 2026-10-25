import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui';
import '../../app_shared.dart';
import 'cinema_api.dart';
import 'cinema_shot_stage.dart';

// 完全保留原版颜色常量
const Color _editorInk = Color(0xFF151921);
const Color _editorInkSoft = Color(0xFF1F2530);
const Color _editorSurface = Color(0xFF1D222B);
const Color _editorFieldBg = Color(0xFF11141A);
const Color _editorAccent = Color(0xFF76B900);
const Color _editorText = Color(0xFFFFFFFF);
const Color _editorTextSoft = Color(0xFFE2E8F0);
const Color _editorMuted = Color(0x88FFFFFF);
const Color _editorLine = Color(0x14FFFFFF);
const Color _danger = Color(0xFFE0554A);

const BorderRadius _editorRadius = BorderRadius.all(Radius.circular(6));
const BorderRadius _editorRadiusLg = BorderRadius.all(Radius.circular(8));

String _imageContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

enum _CinemaEditorTab {
  script,
  storyboard,
  cast,
  settings,
}

class CinemaEditorPage extends StatefulWidget {
  const CinemaEditorPage({super.key, required this.workId});
  final int workId;

  @override
  State<CinemaEditorPage> createState() => _CinemaEditorPageState();
}

class _CinemaEditorPageState extends State<CinemaEditorPage> {
  final _api = CinemaApi();

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _chapterTitle = TextEditingController();
  final _chapterText = TextEditingController();

  final _roleName = TextEditingController();
  final _rolePortrait = TextEditingController();
  final _roleVoice = TextEditingController();
  final _roleLook = TextEditingController();
  final _roleAliases = TextEditingController();

  Map<String, dynamic> _work = <String, dynamic>{};
  List<Map<String, dynamic>> _roles = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _itemsLoading = false;
  bool _analyzing = false;
  int _itemsLoadSeq = 0;
  static const List<String> _shotScales = <String>['wide', 'medium', 'close_up', 'detail'];

  int? _selectedChapter;
  _CinemaEditorTab _tab = _CinemaEditorTab.script;

  bool _loading = true;
  bool _saving = false;
  bool _workDirty = false;
  bool _chapterDirty = false;
  String? _error;

  bool get _anyDirty => _workDirty || _chapterDirty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _title, _description, _chapterTitle, _chapterText,
      _roleName, _rolePortrait, _roleVoice, _roleLook, _roleAliases,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getWork(widget.workId);
      final w = Map<String, dynamic>.from(data['work'] ?? data);
      final list = _parseList(data['chapters']);
      final charData = await _api.characters(widget.workId);
      final chars = _parseList(charData['characters']);

      if (!mounted) return;
      setState(() {
        _work = w;
        _chapters = list;
        _title.text = w['title']?.toString() ?? '';
        _description.text = w['description']?.toString() ?? '';

        _roles = chars;

        if (_selectedChapter != null) {
          final match = _chapters.where(
            (c) => int.tryParse(c['id'].toString()) == _selectedChapter,
          );
          if (match.isNotEmpty) {
            _chapterTitle.text = match.first['title']?.toString() ?? '';
            _chapterText.text = match.first['source_text']?.toString() ?? '';
          }
        } else if (_chapters.isNotEmpty) {
          final first = _chapters.first;
          _selectedChapter = int.tryParse(first['id'].toString());
          _chapterTitle.text = first['title']?.toString() ?? '';
          _chapterText.text = first['source_text']?.toString() ?? '';
        }

        _workDirty = false;
        _chapterDirty = false;
        _loading = false;
      });
      _loadItems();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载电影作品失败：$e';
      });
      _showSnack('加载电影作品失败：$e', error: true);
    }
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
        shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
        duration: const Duration(seconds: 2),
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
        shape: const RoundedRectangleBorder(borderRadius: _editorRadiusLg),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _editorText),
        ),
        content: Text(
          description,
          style: const TextStyle(color: _editorTextSoft, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: TextStyle(color: _editorTextSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: danger ? _danger : _editorAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBackNavigation() async {
    if (!_anyDirty || _saving) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final discard = await _confirm(
      title: '放弃未保存的修改？',
      description: '当前作品或章节有尚未保存的内容，直接退出将丢失更改。',
      confirmText: '放弃并退出',
      danger: true,
    );
    if (discard && mounted) {
      setState(() {
        _workDirty = false;
        _chapterDirty = false;
      });
      Navigator.of(context).pop();
    }
  }

  Future<void> _select(Map<String, dynamic> c) async {
    final nextId = int.tryParse(c['id'].toString());
    if (nextId == _selectedChapter) return;

    if (_chapterDirty) {
      final discard = await _confirm(
        title: '切换章节？',
        description: '当前章节有未保存的内容，切换章节将丢失未保存的修改。',
        confirmText: '仍然切换',
        danger: true,
      );
      if (!discard || !mounted) return;
    }

    setState(() {
      _selectedChapter = nextId;
      _chapterTitle.text = c['title']?.toString() ?? '';
      _chapterText.text = c['source_text']?.toString() ?? '';
      _chapterDirty = false;
    });
    _loadItems();
  }

  Future<void> _startNewChapter() async {
    if (_chapterDirty && _selectedChapter != null) {
      final discard = await _confirm(
        title: '新建章节？',
        description: '当前章节有未保存的内容，新建章节将清空当前编辑区。',
        confirmText: '继续新建',
        danger: true,
      );
      if (!discard || !mounted) return;
    }
    setState(() {
      _selectedChapter = null;
      _chapterTitle.clear();
      _chapterText.clear();
      _chapterDirty = false;
      _tab = _CinemaEditorTab.script;
    });
  }

  // 统一的全局保存逻辑
  Future<void> _saveAll() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (_chapterDirty && (_chapterTitle.text.trim().isNotEmpty || _chapterText.text.trim().isNotEmpty)) {
        int? targetChapterId = _selectedChapter;
        if (_selectedChapter == null) {
          final c = await _api.createChapter(
            widget.workId,
            title: _chapterTitle.text.trim(),
            text: _chapterText.text,
          );
          final created = Map<String, dynamic>.from(c['chapter'] ?? c);
          _chapters.add(created);
          targetChapterId = int.tryParse(created['id']?.toString() ?? '');
        } else {
          await _api.updateChapter(_selectedChapter!, <String, dynamic>{
            'title': _chapterTitle.text.trim(),
            'source_text': _chapterText.text,
          });
        }
        _selectedChapter = targetChapterId;
        _chapterDirty = false;
      }

      if (_workDirty) {
        final existingSettings = _work['settings'] is Map
            ? Map<String, dynamic>.from(_work['settings'])
            : <String, dynamic>{};
        await _api.updateWork(widget.workId, <String, dynamic>{
          'title': _title.text.trim(),
          'description': _description.text.trim(),
          'settings': existingSettings,
        });
        _workDirty = false;
      }

      await _load();
      if (mounted) _showSnack('修改已全部保存');
    } catch (e) {
      if (mounted) _showSnack('保存失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openRoleSheet({int? editIndex}) async {
    final isEdit = editIndex != null && editIndex >= 0 && editIndex < _roles.length;
    final initial = isEdit ? _roles[editIndex] : <String, dynamic>{};

    _roleName.text = initial['name']?.toString() ?? '';
    _rolePortrait.text = initial['portrait_url']?.toString() ?? '';
    _roleVoice.text = initial['voice_id']?.toString() ?? '';
    _roleLook.text = initial['appearance_prompt']?.toString() ?? '';
    _roleAliases.text = (initial['aliases'] is List) ? (initial['aliases'] as List).join(', ') : '';

    var generating = false;
    var gender = CinemaApi.normalizeGender(initial['gender']);
    var uploading = false;
    var portraitError = '';

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final portraitPreview = _rolePortrait.text.trim();
            final busy = generating || uploading;

            Future<void> pickAndUpload() async {
              if (busy) return;
              final picked = await FilePicker.pickFiles(
                type: FileType.image,
                allowMultiple: false,
                withData: true,
              );
              final file = picked?.files.single;
              if (file == null || file.bytes == null) return;
              if (file.size > 12 * 1024 * 1024) {
                setModalState(() => portraitError = '图片请控制在 12MB 以内');
                return;
              }
              setModalState(() {
                uploading = true;
                portraitError = '';
              });
              try {
                final url = await _api.uploadCharacterImage(
                  bytes: file.bytes!,
                  filename: file.name.isEmpty ? 'portrait.jpg' : file.name,
                  contentType: _imageContentType(file.name),
                );
                if (!sheetContext.mounted) return;
                setModalState(() {
                  _rolePortrait.text = url;
                  uploading = false;
                });
              } catch (e) {
                if (!sheetContext.mounted) return;
                setModalState(() {
                  uploading = false;
                  portraitError = '上传立绘失败：$e';
                });
              }
            }

            Future<void> generatePortrait() async {
              if (busy) return;
              if (_roleName.text.trim().isEmpty) {
                setModalState(() => portraitError = '请先填写角色名称');
                return;
              }
              setModalState(() {
                generating = true;
                portraitError = '';
              });
              try {
                final worldContext = <String>[
                  if (_title.text.trim().isNotEmpty) '《${_title.text.trim()}》',
                  if (_description.text.trim().isNotEmpty) _description.text.trim(),
                ].join(' ');
                final url = await _api.generateCharacterPortrait(
                  name: _roleName.text.trim(),
                  gender: gender,
                  appearancePrompt: _roleLook.text.trim(),
                  worldContext: worldContext,
                  style: 'anime',
                );
                if (!sheetContext.mounted) return;
                setModalState(() {
                  _rolePortrait.text = url;
                  generating = false;
                });
              } catch (e) {
                if (!sheetContext.mounted) return;
                setModalState(() {
                  generating = false;
                  portraitError = '生成立绘失败：$e';
                });
              }
            }

            Widget sectionLabel(String text) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    text,
                    style: const TextStyle(color: _editorMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                  ),
                );

            Widget spinner() => const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: _editorAccent),
                );

            final portraitBox = InkWell(
              onTap: busy ? null : pickAndUpload,
              borderRadius: _editorRadiusLg,
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  color: _editorFieldBg,
                  borderRadius: _editorRadiusLg,
                  border: Border.all(color: _editorLine),
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (portraitPreview.isEmpty)
                        const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: _editorMuted, size: 36),
                            SizedBox(height: 8),
                            Text('点击上传立绘', style: TextStyle(color: _editorMuted, fontSize: 12)),
                          ],
                        )
                      else
                        // contain：立绘完整显示，不裁切
                        Image.network(
                          portraitPreview,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: _editorMuted, size: 32),
                          ),
                        ),
                      if (busy)
                        ColoredBox(
                          color: Colors.black.withOpacity(0.55),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: _editorAccent),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  generating ? 'AI 生成中，约需几十秒…' : '上传中…',
                                  style: const TextStyle(color: _editorText, fontSize: 12),
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

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(
                  color: _editorInkSoft,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 固定头部 ──
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: _editorAccent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            isEdit ? '编辑演员角色' : '新增演员角色',
                            style: const TextStyle(color: _editorText, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (isEdit)
                          IconButton(
                            tooltip: '删除该角色',
                            onPressed: () => Navigator.pop(sheetContext, 'delete'),
                            icon: const Icon(Icons.delete_outline_rounded, color: _danger, size: 20),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded, color: _editorMuted),
                        ),
                      ],
                    ),
                    // ── 可滚动内容 ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 立绘：大图 + 操作按钮
                            Center(child: portraitBox),
                            const SizedBox(height: 12),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 360),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: busy ? null : generatePortrait,
                                        icon: generating ? spinner() : const Icon(Icons.auto_awesome_rounded, size: 16),
                                        label: Text(generating ? '生成中…' : 'AI 生成', style: const TextStyle(fontWeight: FontWeight.w800)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _editorAccent,
                                          foregroundColor: const Color(0xFF151921),
                                          disabledBackgroundColor: Colors.white.withOpacity(0.06),
                                          disabledForegroundColor: _editorMuted,
                                          minimumSize: const Size.fromHeight(40),
                                          shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: busy ? null : pickAndUpload,
                                        icon: uploading ? spinner() : const Icon(Icons.upload_rounded, size: 16),
                                        label: Text(uploading ? '上传中…' : '本地上传', style: const TextStyle(fontWeight: FontWeight.w700)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _editorText,
                                          disabledForegroundColor: _editorMuted,
                                          side: const BorderSide(color: _editorLine),
                                          minimumSize: const Size.fromHeight(40),
                                          shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (portraitError.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                portraitError,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: _danger, fontSize: 11.5, height: 1.4),
                              ),
                            ],
                            const SizedBox(height: 20),

                            // 基本信息
                            sectionLabel('基本信息'),
                            TextField(
                              controller: _roleName,
                              autofocus: !isEdit,
                              style: const TextStyle(color: _editorText, fontSize: 14),
                              decoration: _inputDecoration('例如：旁白 / 林默', label: '角色名称 *'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _roleVoice,
                              style: const TextStyle(color: _editorText, fontSize: 14),
                              decoration: _inputDecoration('输入 TTS Voice ID', label: '声音 ID (Voice ID)'),
                            ),
                            const SizedBox(height: 20),

                            sectionLabel('性别'),
                            DropdownButtonFormField<String>(
                              initialValue: gender,
                              dropdownColor: _editorInkSoft,
                              style: const TextStyle(color: _editorText, fontSize: 14),
                              decoration: _inputDecoration('', label: '角色性别'),
                              items: const [
                                DropdownMenuItem(value: 'male', child: Text('男')),
                                DropdownMenuItem(value: 'female', child: Text('女')),
                                DropdownMenuItem(value: 'other', child: Text('其他')),
                                DropdownMenuItem(value: 'unknown', child: Text('未知')),
                              ],
                              onChanged: busy ? null : (value) => setModalState(() => gender = value ?? 'unknown'),
                            ),
                            const SizedBox(height: 20),
                            // 外貌
                            sectionLabel('外貌（AI 生成立绘时参考）'),
                            TextField(
                              controller: _roleLook,
                              enabled: !generating,
                              minLines: 2,
                              maxLines: 4,
                              style: const TextStyle(color: _editorText, fontSize: 14),
                              decoration: _inputDecoration('年龄段、发型发色、服装、显著特征…', label: '外貌描述'),
                            ),
                            const SizedBox(height: 20),

                            // 别名
                            sectionLabel('别名'),
                            TextField(
                              controller: _roleAliases,
                              style: const TextStyle(color: _editorText, fontSize: 14),
                              decoration: _inputDecoration('用逗号分隔，例如：小默, 默哥', label: '解析时用来认出同一个人'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ── 固定底部 ──
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: TextButton.styleFrom(
                              foregroundColor: _editorTextSoft,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () {
                                    if (_roleName.text.trim().isEmpty) return;
                                    Navigator.pop(sheetContext, 'save');
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: _editorAccent,
                              foregroundColor: const Color(0xFF151921),
                              minimumSize: const Size.fromHeight(48),
                              shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                            ),
                            child: Text(isEdit ? '保存角色' : '添加角色', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (action == 'delete' && isEdit) {
      final id = int.tryParse(_roles[editIndex]['id']?.toString() ?? '');
      if (id == null) return;
      try {
        await _api.deleteCharacter(id);
        await _reloadCharacters();
        _showSnack('角色已删除');
      } catch (e) {
        _showSnack('删除失败：$e', error: true);
      }
      return;
    }

    if (action == 'save' && _roleName.text.trim().isNotEmpty) {
      final body = <String, dynamic>{
        'name': _roleName.text.trim(),
        'portrait_url': _rolePortrait.text.trim(),
        'gender': gender,
        'voice_id': _roleVoice.text.trim(),
        'appearance_prompt': _roleLook.text.trim(),
        'aliases': _roleAliases.text
            .split(RegExp(r'[,，、;；]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      };
      try {
        if (isEdit) {
          final id = int.tryParse(_roles[editIndex]['id']?.toString() ?? '');
          if (id == null) return;
          await _api.updateCharacter(id, body);
        } else {
          await _api.createCharacter(widget.workId, body);
        }
        await _reloadCharacters();
        _showSnack('角色已保存');
      } catch (e) {
        _showSnack('保存失败：$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_anyDirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _editorInk,
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _editorAccent, surface: _editorInk),
        ),
        child: Scaffold(
          backgroundColor: _editorInk,
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
            child: SafeArea(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _editorAccent))
                  : _error != null && _work.isEmpty
                      ? _buildErrorState()
                      : Column(
                          children: [
                            _buildTopBar(),
                            _buildHeroAndTabs(),
                            Expanded(child: _buildActiveTabBody()),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: _editorMuted),
            const SizedBox(height: 16),
            Text(_error ?? '加载失败', textAlign: TextAlign.center, style: const TextStyle(color: _editorMuted)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(foregroundColor: _editorAccent, side: const BorderSide(color: _editorLine)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final activeSave = _anyDirty || _saving;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: _handleBackNavigation,
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _editorTextSoft),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _title.text.trim().isEmpty ? '工作台' : _title.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _editorText, fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_anyDirty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _editorAccent.withOpacity(0.14), borderRadius: BorderRadius.circular(4)),
                    child: const Text('未保存', style: TextStyle(color: _editorAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: (!activeSave || _saving) ? null : _saveAll,
            icon: _saving 
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8, color: _editorInk))
                : const Icon(Icons.check_rounded, size: 15),
            label: Text(_saving ? '保存中' : _anyDirty ? '保存' : '已保存', style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: activeSave ? _editorAccent : _editorFieldBg,
              foregroundColor: activeSave ? const Color(0xFF151921) : _editorMuted,
              disabledBackgroundColor: _editorFieldBg,
              disabledForegroundColor: _editorMuted,
              shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              minimumSize: const Size(0, 34),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroAndTabs() {
    final tabs = [
      (_CinemaEditorTab.script, '章节剧本', Icons.movie_creation_outlined),
      (_CinemaEditorTab.storyboard, '分镜解析', Icons.auto_awesome_motion_outlined),
      (_CinemaEditorTab.cast, '演员角色', Icons.people_alt_outlined),
      (_CinemaEditorTab.settings, '作品设定', Icons.tune_rounded),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: tabs.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildTabPill(t),
                )).toList(),
              ),
            ),
          ),
          // 移除了这里的“新章节”按钮，统一移动到了左侧目录的固定底部
        ],
      ),
    );
  }

  Widget _buildTabPill((_CinemaEditorTab, String, IconData) item) {
    final selected = _tab == item.$1;
    return InkWell(
      borderRadius: _editorRadius,
      onTap: () {
        setState(() => _tab = item.$1);
        if (item.$1 == _CinemaEditorTab.storyboard) _loadItems();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? _editorAccent.withOpacity(0.14) : _editorSurface.withOpacity(0.55),
          borderRadius: _editorRadius,
        ),
        child: Row(
          children: [
            Icon(item.$3, size: 15, color: selected ? _editorAccent : _editorMuted),
            const SizedBox(width: 6),
            Text(
              item.$2,
              style: TextStyle(
                color: selected ? _editorText : _editorMuted,
                fontSize: 12.8,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabBody() {
    switch (_tab) {
      case _CinemaEditorTab.script: return _buildScriptWorkspace();
      case _CinemaEditorTab.storyboard: return _buildStoryboardWorkspace();
      case _CinemaEditorTab.cast: return _buildCastWorkspace();
      case _CinemaEditorTab.settings: return _buildSettingsWorkspace();
    }
  }

  Widget _buildScriptWorkspace() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 260, child: _buildChapterSidebar()),
              Expanded(child: Padding(padding: const EdgeInsets.all(16), child: _buildChapterEditorSurface())),
            ],
          );
        }
        return Column(
          children: [
            _buildCompactChapterStrip(),
            Expanded(child: Padding(padding: const EdgeInsets.all(14), child: _buildChapterEditorSurface())),
          ],
        );
      },
    );
  }

  Widget _buildChapterSidebar() {
    return Container(
      color: _editorInkSoft.withOpacity(0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              itemCount: _chapters.length,
              itemBuilder: (_, i) {
                final c = _chapters[i];
                final id = int.tryParse(c['id'].toString());
                final selected = _selectedChapter == id;
                final title = c['title']?.toString().trim() ?? '';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text('${i + 1}. ${title.isEmpty ? '未命名' : title}', maxLines: 1, style: TextStyle(color: selected ? _editorText : _editorTextSoft, fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: Text(c['source_text']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
                    selected: selected,
                    selectedTileColor: _editorAccent.withOpacity(0.13),
                    shape: RoundedRectangleBorder(borderRadius: _editorRadius),
                    onTap: () => _select(c),
                  ),
                );
              },
            ),
          ),
          // 统一底部边距为 16（与右侧内容框的 Padding 对齐），并加高按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: FilledButton.icon(
              onPressed: _startNewChapter,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建章节', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: _editorAccent,
                foregroundColor: const Color(0xFF151921),
                minimumSize: const Size.fromHeight(48), // 加高按钮解决“太矮”的问题
                shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactChapterStrip() {
    return Container(
      height: 46,
      alignment: Alignment.centerLeft,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _chapters.length + 1,
        itemBuilder: (_, i) {
          if (i == _chapters.length) {
            // 移动端横向列表的末尾也改为纯色新建按钮
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: ActionChip(
                label: const Text('✦ 新建章节', style: TextStyle(color: Color(0xFF151921), fontSize: 11.5, fontWeight: FontWeight.w700)),
                backgroundColor: _editorAccent,
                onPressed: _startNewChapter,
                side: BorderSide.none,
                shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                visualDensity: VisualDensity.compact,
              ),
            );
          }
          
          final c = _chapters[i];
          final id = int.tryParse(c['id'].toString());
          final selected = _selectedChapter == id;
          final title = c['title']?.toString().trim() ?? '';
          
          return Padding(
            padding: const EdgeInsets.only(right: 8, top: 7, bottom: 7),
            child: ChoiceChip(
              label: Text('${i + 1}. ${title.isEmpty ? '未命名' : title}'),
              selected: selected,
              onSelected: (_) => _select(c),
              backgroundColor: _editorFieldBg,
              selectedColor: _editorAccent.withOpacity(0.18),
              labelStyle: TextStyle(
                color: selected ? _editorAccent : _editorTextSoft,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildChapterEditorSurface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _chapterTitle,
          onChanged: (_) => setState(() => _chapterDirty = true),
          style: const TextStyle(color: _editorText, fontSize: 15.5, fontWeight: FontWeight.w700),
          decoration: _inputDecoration('输入章节标题，例如：第一幕 · 雨夜来客', label: '章节标题'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _chapterText,
            onChanged: (_) => setState(() => _chapterDirty = true),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(color: _editorText, fontSize: 13.8, height: 1.65),
            decoration: _inputDecoration('在此输入章节剧本正文、角色对话或小说原文…\n\n提示：先在「演员角色」Tab 中配置好登场人物立绘与声音 ID，放映时即可自动匹配角色演出。', label: '章节剧本正文'),
          ),
        ),
      ],
    );
  }

  Widget _buildCastWorkspace() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('演员角色库', style: TextStyle(color: _editorText, fontSize: 16, fontWeight: FontWeight.w700)),
            FilledButton.tonalIcon(
              onPressed: () => _openRoleSheet(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加角色'),
              style: FilledButton.styleFrom(
                backgroundColor: _editorAccent.withOpacity(0.14),
                foregroundColor: _editorAccent,
                shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
              ),
            )
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _roles.asMap().entries.map((e) => SizedBox(
            width: 320,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              tileColor: _editorFieldBg,
              shape: RoundedRectangleBorder(borderRadius: _editorRadius),
              leading: Container(
                width: 42,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: _editorRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: e.value['portrait_url']?.isNotEmpty == true
                    ? Image.network(
                        e.value['portrait_url'],
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: _editorMuted),
                      )
                    : const Icon(Icons.person_outline_rounded, color: _editorMuted),
              ),
              title: Text(e.value['name'] ?? '未命名', style: const TextStyle(color: _editorText, fontSize: 14, fontWeight: FontWeight.w700)),
              subtitle: Row(
                children: [
                  Icon(
                    Icons.record_voice_over_outlined,
                    size: 13,
                    color: e.value['voice_id']?.isNotEmpty == true ? _editorAccent : Colors.white.withOpacity(0.32),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      e.value['voice_id']?.isNotEmpty == true ? 'Voice: ${e.value['voice_id']}' : '未配置声音 ID',
                      style: TextStyle(
                        color: e.value['voice_id']?.isNotEmpty == true ? _editorTextSoft : Colors.white.withOpacity(0.38),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: _editorMuted, size: 18),
              onTap: () => _openRoleSheet(editIndex: e.key),
            ),
          )).toList(),
        ),
      ],
    );
  }

  // ───────────────────────── 分镜解析 ─────────────────────────

  List<Map<String, dynamic>> _parseList(dynamic raw) {
    return (raw as List? ?? <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _reloadCharacters() async {
    final data = await _api.characters(widget.workId);
    if (!mounted) return;
    setState(() => _roles = _parseList(data['characters']));
  }

  String get _chapterStatus {
    for (final c in _chapters) {
      if (int.tryParse(c['id'].toString()) == _selectedChapter) {
        return c['processing_status']?.toString() ?? '';
      }
    }
    return '';
  }

  String get _chapterError {
    for (final c in _chapters) {
      if (int.tryParse(c['id'].toString()) == _selectedChapter) {
        return c['processing_error']?.toString() ?? '';
      }
    }
    return '';
  }

  // 只更新状态字段，不动 source_text（编辑区的正文以本地为准）
  void _patchChapterMeta(dynamic raw) {
    if (raw is! Map) return;
    final id = raw['id']?.toString();
    final idx = _chapters.indexWhere((c) => c['id']?.toString() == id);
    if (idx < 0) return;
    _chapters[idx] = <String, dynamic>{
      ..._chapters[idx],
      'processing_status': raw['processing_status'],
      'processing_error': raw['processing_error'],
    };
  }

  Future<void> _loadItems() async {
    final id = _selectedChapter;
    if (id == null) {
      if (mounted) setState(() => _items = <Map<String, dynamic>>[]);
      return;
    }
    final seq = ++_itemsLoadSeq;
    setState(() => _itemsLoading = true);
    try {
      final data = await _api.chapterItems(id);
      if (!mounted || seq != _itemsLoadSeq || id != _selectedChapter) return;
      setState(() {
        _items = _parseList(data['items']);
        _patchChapterMeta(data['chapter']);
      });
    } catch (e) {
      if (mounted && seq == _itemsLoadSeq) _showSnack('加载分镜失败：$e', error: true);
    } finally {
      if (mounted && seq == _itemsLoadSeq) setState(() => _itemsLoading = false);
    }
  }

  Future<void> _analyzeChapter() async {
    if (_analyzing) return;
    if (_chapterDirty || _selectedChapter == null) {
      await _saveAll();
      if (!mounted || _chapterDirty || _selectedChapter == null) return;
    }
    final id = _selectedChapter!;
    setState(() => _analyzing = true);
    try {
      final res = await _api.analyzeChapter(id);
      if (!mounted) return;
      setState(() => _patchChapterMeta(res['chapter']));
      await _pollAnalysis(id);
    } catch (e) {
      _showSnack('解析失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _pollAnalysis(int id) async {
    for (var i = 0; i < 300; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Map<String, dynamic> data;
      try {
        data = await _api.getChapter(id);
      } catch (_) {
        continue; // 网络抖动，继续轮询
      }
      final status = data['processing_status']?.toString() ?? '';
      if (!mounted) return;
      setState(() => _patchChapterMeta(data));
      if (status == 'processing') continue;

      if (status == 'ready') {
        _showSnack('解析完成');
      } else if (status == 'failed') {
        _showSnack('解析失败：${data['processing_error'] ?? '未知错误'}', error: true);
      } else {
        _showSnack('解析期间正文被修改，请重新解析', error: true);
      }
      if (id == _selectedChapter) await _loadItems();
      try {
        await _reloadCharacters(); // 解析会往角色库里新增角色
      } catch (_) {}
      return;
    }
    _showSnack('解析超时，请稍后回到本页查看', error: true);
  }

  String? _characterNameById(String id) {
    for (final r in _roles) {
      if (r['id']?.toString() == id) return r['name']?.toString();
    }
    return null;
  }

  String _expandPrompt(String prompt) {
    return prompt.replaceAllMapped(RegExp(r'\{\{\s*char\s*:\s*(\d+)\s*\}\}'), (m) {
      final name = _characterNameById(m.group(1)!);
      return name == null ? '@?' : '@$name';
    });
  }

  Future<void> _openItemSheet(Map<String, dynamic> item, {required bool shot}) async {
    // shot=true：编辑整个镜头（提示词/镜头），item 必须是镜头首句；shot=false：编辑单句（文字/说话人）
    final itemId = int.tryParse(item['id']?.toString() ?? '');
    if (itemId == null) return;
    final promptCtl = TextEditingController(text: item['scene_prompt']?.toString() ?? '');
    final textCtl = TextEditingController(text: item['text']?.toString() ?? '');
    final originalPrompt = promptCtl.text.trim();
    final originalText = textCtl.text.trim();
    int? speakerId = int.tryParse(item['speaker_character_id']?.toString() ?? '');
    final originalSpeaker = speakerId;
    String? scale = item['shot_scale']?.toString();
    if (scale != null && !_shotScales.contains(scale)) scale = null;
    final originalScale = scale;
    final metadata = item['metadata'];
    var cameraMove = CinemaCameraMotion.normalize(item['camera_move'] ??
        (metadata is Map ? metadata['camera_move'] : null));
    final originalCameraMove = cameraMove;
    final title = shot
        ? '编辑镜头 ${((int.tryParse(item['shot_id']?.toString() ?? '') ?? 0) + 1)}'
        : '编辑第 ${(int.tryParse(item['item_index']?.toString() ?? '') ?? 0) + 1} 句';

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final roleList = _roles.where((r) => int.tryParse(r['id']?.toString() ?? '') != null).toList();
            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: const BoxDecoration(
                  color: _editorInkSoft,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title, style: const TextStyle(color: _editorText, fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close_rounded, color: _editorMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (shot) ...[
                        DropdownButtonFormField<String>(
                          initialValue: cameraMove,
                          dropdownColor: _editorInkSoft,
                          style: const TextStyle(color: _editorText, fontSize: 14),
                          decoration: _inputDecoration('', label: '运镜效果'),
                          items: CinemaCameraMotion.labels.entries.map((entry) =>
                              DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                          onChanged: (value) => setModalState(() => cameraMove = value ?? 'static'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          value: scale,
                          dropdownColor: _editorInkSoft,
                          style: const TextStyle(color: _editorText, fontSize: 14),
                          decoration: _inputDecoration('', label: '镜头'),
                          items: <DropdownMenuItem<String?>>[
                            const DropdownMenuItem<String?>(value: null, child: Text('未指定')),
                            ..._shotScales.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                          ],
                          onChanged: (v) => setModalState(() => scale = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: promptCtl,
                          minLines: 3,
                          maxLines: 8,
                          style: const TextStyle(color: _editorText, fontSize: 13.5, height: 1.5),
                          decoration: _inputDecoration('英文画面描述；点下面的角色可插入引用', label: '镜头画面提示词'),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: roleList
                              .map((r) => ActionChip(
                                    label: Text('@${r['name']}', style: const TextStyle(color: _editorAccent, fontSize: 12)),
                                    backgroundColor: _editorAccent.withOpacity(0.12),
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      final token = '{{char:${r['id']}}}';
                                      final text = promptCtl.text;
                                      final sel = promptCtl.selection;
                                      final start = sel.isValid ? sel.start : text.length;
                                      final end = sel.isValid ? sel.end : text.length;
                                      promptCtl.value = TextEditingValue(
                                        text: text.replaceRange(start, end, token),
                                        selection: TextSelection.collapsed(offset: start + token.length),
                                      );
                                    },
                                  ))
                              .toList(),
                        ),
                      ] else ...[
                        TextField(
                          controller: textCtl,
                          minLines: 2,
                          maxLines: 8,
                          style: const TextStyle(color: _editorText, fontSize: 14, height: 1.5),
                          decoration: _inputDecoration('解说词或台词', label: '文字'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          value: speakerId,
                          dropdownColor: _editorInkSoft,
                          style: const TextStyle(color: _editorText, fontSize: 14),
                          decoration: _inputDecoration('', label: '说话人'),
                          items: <DropdownMenuItem<int?>>[
                            const DropdownMenuItem<int?>(value: null, child: Text('旁白 / 未指定')),
                            ...roleList.map((r) => DropdownMenuItem<int?>(
                                  value: int.parse(r['id'].toString()),
                                  child: Text(r['name']?.toString() ?? '未命名'),
                                )),
                          ],
                          onChanged: (v) => setModalState(() => speakerId = v),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: _editorAccent,
                          foregroundColor: const Color(0xFF151921),
                          minimumSize: const Size.fromHeight(48),
                          shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                        ),
                        child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (save != true || !mounted) return;
    final body = <String, dynamic>{};
    if (shot) {
      if (promptCtl.text.trim() != originalPrompt) body['scene_prompt'] = promptCtl.text.trim();
      if (scale != originalScale) body['shot_scale'] = scale;
      if (cameraMove != originalCameraMove) body['camera_move'] = cameraMove;
    } else {
      if (textCtl.text.trim() != originalText) body['text'] = textCtl.text.trim();
      if (speakerId != originalSpeaker) body['speaker_character_id'] = speakerId;
    }
    if (body.isEmpty) return;
    try {
      await _api.updateItem(itemId, body);
      await _loadItems();
      _showSnack('已更新');
    } catch (e) {
      _showSnack('保存失败：$e', error: true);
    }
  }

  Widget _buildStoryboardWorkspace() {
    return Column(
      children: [
        _buildCompactChapterStrip(),
        _buildAnalyzeBar(),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildAnalyzeBar() {
    final status = _chapterStatus;
    final busy = _analyzing || status == 'processing';
    final analyzed = _items.any((e) => (e['scene_prompt']?.toString() ?? '').isNotEmpty);
    String label;
    Color color = _editorMuted;
    if (busy) {
      label = '解析中…（角色、分句、分镜）';
      color = _editorAccent;
    } else if (status == 'failed') {
      label = '解析失败';
      color = _danger;
    } else if (_items.isEmpty) {
      label = '未解析';
    } else if (status == 'pending') {
      label = '正文已修改，分镜待更新';
    } else if (analyzed) {
      final shotCount = _items.where((e) => e['shot_start'] == true).length;
      label = shotCount > 0 ? '已解析 $shotCount 个镜头 · ${_items.length} 句' : '已解析 ${_items.length} 句';
      color = _editorAccent;
    } else {
      label = '仅基础分句（未做分镜）';
    }
    final error = _chapterError;
    final canRun = _selectedChapter != null || _chapterDirty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8, color: _editorAccent)),
                ),
              Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600))),
              FilledButton.icon(
                onPressed: (busy || !canRun) ? null : _analyzeChapter,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(
                  _chapterDirty ? '保存并解析' : (_items.isEmpty || !analyzed ? '解析本章' : '重新解析'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _editorAccent,
                  foregroundColor: const Color(0xFF151921),
                  disabledBackgroundColor: _editorFieldBg,
                  disabledForegroundColor: _editorMuted,
                  minimumSize: const Size(0, 36),
                  shape: const RoundedRectangleBorder(borderRadius: _editorRadius),
                ),
              ),
            ],
          ),
          if (status == 'failed' && error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _danger, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  // 把连续的句子按 shot_id 归组；没有 shot_id 的旧数据每句单独成组
  List<List<Map<String, dynamic>>> _groupShots() {
    final groups = <List<Map<String, dynamic>>>[];
    String? lastKey;
    for (final it in _items) {
      final sid = it['shot_id']?.toString();
      final key = sid ?? 'solo-${it['id']}';
      if (key == lastKey && groups.isNotEmpty) {
        groups.last.add(it);
      } else {
        groups.add(<Map<String, dynamic>>[it]);
        lastKey = key;
      }
    }
    return groups;
  }

  Widget _buildItemList() {
    if (_selectedChapter == null) {
      return const Center(child: Text('先在「章节剧本」里写好并保存一章', style: TextStyle(color: _editorMuted, fontSize: 13)));
    }
    if (_itemsLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _editorAccent));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '这一章还没有解析。点「解析本章」，系统会理解剧情、改编成解说脚本，并按镜头划分、生成每个镜头的画面提示词。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _editorMuted, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }
    final groups = _groupShots();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: groups.length,
      itemBuilder: (_, i) => _buildShotCard(groups[i], i),
    );
  }

  Widget _buildShotCard(List<Map<String, dynamic>> lines, int index) {
    final start = lines.firstWhere((e) => e['shot_start'] == true, orElse: () => lines.first);
    final prompt = start['scene_prompt']?.toString() ?? '';
    final scale = start['shot_scale']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(color: _editorFieldBg, borderRadius: _editorRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: _editorRadius,
              onTap: () => _openItemSheet(start, shot: true),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('镜头 ${index + 1}', style: const TextStyle(color: _editorAccent, fontSize: 12, fontWeight: FontWeight.w800)),
                        if (scale.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(scale, style: const TextStyle(color: _editorMuted, fontSize: 11)),
                        ],
                        const Spacer(),
                        const Icon(Icons.edit_outlined, size: 15, color: _editorMuted),
                      ],
                    ),
                    if (prompt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: _editorRadius),
                        child: Text(
                          _expandPrompt(prompt),
                          style: const TextStyle(color: _editorMuted, fontSize: 11.5, height: 1.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            for (final line in lines) _buildLineRow(line),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildLineRow(Map<String, dynamic> line) {
    final isDialogue = line['item_type'] == 'dialogue';
    final speaker = (line['speaker']?.toString() ?? '').trim();
    final edited = line['edited'] == true;
    return InkWell(
      onTap: () => _openItemSheet(line, shot: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isDialogue ? _editorAccent : Colors.white).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isDialogue ? (speaker.isEmpty ? '对白' : speaker) : '解说',
                style: TextStyle(color: isDialogue ? _editorAccent : _editorTextSoft, fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line['text']?.toString() ?? '',
                style: const TextStyle(color: _editorText, fontSize: 13.5, height: 1.5),
              ),
            ),
            if (edited)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: Text('已改', style: TextStyle(color: _editorAccent, fontSize: 10.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsWorkspace() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('作品基础信息', style: TextStyle(color: _editorText, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        TextField(
          controller: _title,
          onChanged: (_) => setState(() => _workDirty = true),
          style: const TextStyle(color: _editorText, fontSize: 14.5, fontWeight: FontWeight.w700),
          decoration: _inputDecoration('输入电影或漫剧作品名称…', label: '作品名称'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _description,
          onChanged: (_) => setState(() => _workDirty = true),
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(color: _editorText, fontSize: 13.5, height: 1.6),
          decoration: _inputDecoration('简要介绍这部作品的世界背景、看点与故事主线…', label: '作品简介'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {String? label}) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      alignLabelWithHint: true,
      floatingLabelBehavior: label == null ? FloatingLabelBehavior.never : FloatingLabelBehavior.always,
      labelStyle: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12),
      floatingLabelStyle: const TextStyle(color: _editorAccent, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontWeight: FontWeight.w400, fontSize: 13),
      filled: true,
      fillColor: _editorFieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: const OutlineInputBorder(borderRadius: _editorRadius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: _editorRadius,
        borderSide: BorderSide(color: _editorAccent.withOpacity(0.75), width: 1.2),
      ),
    );
  }
}

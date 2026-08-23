import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:http/http.dart' as http;

import 'app_shared.dart';
import 'api/api_client.dart';

// --- 与 CreateWorldDialog 对齐的色彩体系 ---
const Color _background = Color(0xFFFCFDFB);
const Color _fieldBackground = Color(0xFFF4F6F2);
const Color _textPrimary = Color(0xFF303730);
const Color _textSecondary = Color(0xFF70786F);
const Color _textMuted = Color(0xFFA3AAA2);
const Color _themeGreen = Color.fromARGB(255, 129, 246, 112);
const Color _errorText = Color(0xFFC86760);

class ShareWorldMediaDraft {
  const ShareWorldMediaDraft({
    required this.url,
    this.r2Key,
  });

  final String url;
  final String? r2Key;

  Map<String, dynamic> toPublishJson({
    required int sortOrder,
    required String title,
    required String caption,
  }) {
    return <String, dynamic>{
      'url': url,
      if (r2Key != null && r2Key!.trim().isNotEmpty) 'r2_key': r2Key,
      'media_type': 'screenshot',
      'sort_order': sortOrder,
      'title': title,
      'caption': caption,
    };
  }
}

class ShareWorldPage extends StatefulWidget {
  const ShareWorldPage({
    super.key,
    required this.games,
    this.initialIndex = 0,
  });

  final List<GameData> games;
  final int initialIndex;

  static Future<bool?> show(
    BuildContext context, {
    required List<GameData> games,
    int initialIndex = 0,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭分享世界',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => ShareWorldPage(
        games: games,
        initialIndex: initialIndex,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ShareWorldPage> createState() => _ShareWorldPageState();
}

class _ShareWorldPageState extends State<ShareWorldPage>
    with SingleTickerProviderStateMixin {
  static const int _maxMediaCount = 10;
  static const String _r2Category = 'chat_background';
  static const String _r2CoverCategory = 'scenario_cover';

  static const List<String> _presetCategories = [
    '恋爱', '悬疑', '古风', '都市', '校园', '修仙',
    '玄幻', '末世', '系统', '穿越', '治愈', '恐怖', '搞笑',
  ];
  static const int _maxCategoryCount = 3;

  late int _selectedIndex;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _customCategoryController;
  late final AnimationController _shakeController;

  final List<ShareWorldMediaDraft> _media = <ShareWorldMediaDraft>[];
  final Set<String> _selectedCategories = <String>{};

  String _coverUrl = '';
  bool _uploadingCover = false;

  bool _publishing = false;
  bool _uploadingMedia = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;
  String? _errorTextMsg;
  bool _showShakeError = false;

  GameData? get _selectedGame {
    if (widget.games.isEmpty) return null;
    final index = _selectedIndex.clamp(0, widget.games.length - 1).toInt();
    return widget.games[index];
  }

  bool get _canPublish {
    return !_publishing &&
        !_uploadingMedia &&
        !_uploadingCover &&
        _selectedGame != null &&
        _titleController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty &&
        _coverUrl.trim().isNotEmpty &&
        _selectedCategories.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.games.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.games.length - 1).toInt();
    _titleController = TextEditingController(text: _selectedGame?.title ?? '');
    _descriptionController = TextEditingController();
    _customCategoryController = TextEditingController();
    _coverUrl = _selectedGame?.imageUrl ?? '';

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _titleController.addListener(_refresh);
    _descriptionController.addListener(_refresh);

    final initialGame = _selectedGame;
    if (initialGame != null) {
      unawaited(_loadExistingCategory(initialGame.id));
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_refresh);
    _titleController.dispose();
    _descriptionController.removeListener(_refresh);
    _descriptionController.dispose();
    _customCategoryController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      if (_showShakeError && _canPublish) {
        _showShakeError = false;
      }
      setState(() {});
    }
  }

  void _triggerShake(String msg) {
    setState(() {
      _errorTextMsg = msg;
      _showShakeError = true;
    });
    _shakeController.forward(from: 0.0);
  }

  String _modeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'chat': return '独聊';
      case 'novel': return '小说';
      case 'online': return '联机';
      case 'rpg': return 'RPG';
      case 'group': return '群聊';
      default: return mode.isEmpty ? '世界' : mode;
    }
  }

  Future<void> _chooseWorld() async {
    if (widget.games.isEmpty || _publishing || _uploadingMedia || _uploadingCover) return;

    FocusScope.of(context).unfocus();

    final next = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭世界选择',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        return _WorldPickerDialog(
          games: widget.games,
          selectedIndex: _selectedIndex,
          modeLabel: _modeLabel,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );

    if (next == null || !mounted || next == _selectedIndex) return;

    setState(() {
      _selectedIndex = next;
      _titleController.text = widget.games[next].title;
      _descriptionController.clear();
      _media.clear();
      _coverUrl = widget.games[next].imageUrl;
      _selectedCategories.clear();
      _customCategoryController.clear();
      _errorTextMsg = null;
      _showShakeError = false;
    });
    unawaited(_loadExistingCategory(widget.games[next].id));
  }

  Future<void> _pickAndUploadMedia() async {
    if (_uploadingMedia || _publishing || _uploadingCover) return;

    final remaining = _maxMediaCount - _media.length;
    if (remaining <= 0) {
      _triggerShake('最多添加 $_maxMediaCount 张展示图');
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
    } catch (error) {
      _triggerShake('无法打开相册：${_cleanError(error)}');
      return;
    }

    if (result == null || result.files.isEmpty || !mounted) return;

    final files = result.files.take(remaining).toList(growable: false);
    setState(() {
      _errorTextMsg = null;
      _uploadingMedia = true;
      _uploadDone = 0;
      _uploadTotal = files.length;
    });

    try {
      for (final file in files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw Exception('${file.name} 读取失败');
        }

        final draft = await _uploadOneMedia(
          fileName: file.name,
          bytes: bytes,
          contentType: _contentTypeFor(file.name),
        );

        if (!mounted) return;
        setState(() {
          _media.add(draft);
          _uploadDone += 1;
        });
      }
    } catch (error) {
      if (!mounted) return;
      _triggerShake('图片上传失败：${_cleanError(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingMedia = false;
          _uploadDone = 0;
          _uploadTotal = 0;
        });
      }
    }
  }

  Future<void> _loadExistingCategory(String scenarioId) async {
    try {
      final response = await ApiClient.instance.get('/scenario/$scenarioId/info');
      final data = _unwrapData(response);
      final raw = data['category'];
      if (raw is! List) return;

      final tags = raw
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .take(_maxCategoryCount)
          .toList(growable: false);

      if (tags.isEmpty || !mounted || _selectedGame?.id != scenarioId) return;

      setState(() {
        _selectedCategories
          ..clear()
          ..addAll(tags);
      });
    } catch (_) {
      // 静默失败
    }
  }

  Future<void> _pickAndUploadCover() async {
    if (_uploadingCover || _publishing) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
    } catch (error) {
      _triggerShake('无法打开相册：${_cleanError(error)}');
      return;
    }

    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _triggerShake('${file.name} 读取失败');
      return;
    }

    setState(() {
      _errorTextMsg = null;
      _uploadingCover = true;
    });

    try {
      final draft = await _uploadOneMedia(
        fileName: file.name,
        bytes: bytes,
        contentType: _contentTypeFor(file.name),
        r2Category: _r2CoverCategory,
      );
      if (!mounted) return;
      setState(() {
        _coverUrl = draft.url;
      });
    } catch (error) {
      if (!mounted) return;
      _triggerShake('封面上传失败：${_cleanError(error)}');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
        });
      }
    }
  }

  Future<ShareWorldMediaDraft> _uploadOneMedia({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    String? r2Category,
  }) async {
    final signatureResponse = await ApiClient.instance.post(
      '/r2/get-signature',
      body: <String, dynamic>{
        'filename': fileName,
        'content_type': contentType,
        'category': r2Category ?? _r2Category,
      },
    );

    final data = _unwrapData(signatureResponse);
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
      throw Exception('上传失败（${response.statusCode}）');
    }

    return ShareWorldMediaDraft(
      url: publicUrl,
      r2Key: key.isEmpty ? null : key,
    );
  }

  void _removeMedia(int index) {
    if (_publishing || _uploadingMedia || _uploadingCover) return;
    if (index < 0 || index >= _media.length) return;
    setState(() {
      _media.removeAt(index);
      _errorTextMsg = null;
    });
  }

  Future<void> _previewMedia(int index) async {
    if (index < 0 || index >= _media.length) return;
    final media = _media[index];
    FocusScope.of(context).unfocus();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭图片预览',
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      media.url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _publish() async {
    if (_publishing || _uploadingMedia || _uploadingCover) return;

    if (!_canPublish) {
      if (_selectedGame == null) {
        _triggerShake('请先选择一个世界');
      } else if (_titleController.text.trim().isEmpty) {
        _triggerShake('请填写公开标题');
      } else if (_descriptionController.text.trim().isEmpty) {
        _triggerShake('请填写公开简介');
      } else if (_coverUrl.trim().isEmpty) {
        _triggerShake('请上传封面图');
      } else if (_selectedCategories.isEmpty) {
        _triggerShake('请至少选择一个剧本类型');
      }
      return;
    }

    FocusScope.of(context).unfocus();

    final game = _selectedGame!;
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final mediaItems = _media.asMap().entries.map((entry) {
      return entry.value.toPublishJson(
        sortOrder: entry.key,
        title: title,
        caption: description,
      );
    }).toList(growable: false);

    setState(() {
      _errorTextMsg = null;
      _showShakeError = false;
      _publishing = true;
    });

    try {
      final response = await ApiClient.instance.post(
        '/scenario/publish',
        body: <String, dynamic>{
          'instance_id': game.id,
          'public_title': title,
          'public_description': description,
          'media_items': mediaItems,
          'cover_url': _coverUrl.trim(),
          'category': _selectedCategories.toList(growable: false),
        },
      );

      final data = _unwrapData(response);
      final code = int.tryParse('${response['code'] ?? data['code'] ?? ''}');
      final templateId = '${
        data['template_id'] ??
            data['id'] ??
            response['template_id'] ??
            response['id'] ??
            ''
      }'.trim();
      final success = code == 200 || templateId.isNotEmpty;

      if (!success) {
        throw Exception(
          '${response['message'] ?? data['message'] ?? '发布失败，请稍后重试'}',
        );
      }

      if (!mounted) return;
      setState(() => _publishing = false);
      await _showSuccess();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _errorTextMsg = _cleanError(error);
        _showShakeError = true;
      });
      _shakeController.forward(from: 0.0);
    }
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
    final raw = json['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return json;
  }

  String _contentTypeFor(String name) {
    final value = name.toLowerCase();
    if (value.endsWith('.png')) return 'image/png';
    if (value.endsWith('.webp')) return 'image/webp';
    if (value.endsWith('.gif')) return 'image/gif';
    if (value.endsWith('.bmp')) return 'image/bmp';
    if (value.endsWith('.heic') || value.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').replaceFirst('ApiException: ', '').trim();
  }

  Future<void> _showSuccess() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '发布成功',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                width: MediaQuery.sizeOf(context).width * 0.82,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _themeGreen.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: _textPrimary, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '发布成功',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _media.isEmpty ? '世界已发布到发现页。' : '世界与 ${_media.length} 张图已发布到发现页。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textSecondary, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _themeGreen,
                          foregroundColor: _textPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;

    return PopScope(
      canPop: !_publishing && !_uploadingMedia && !_uploadingCover,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(18, 20, 18, 20 + keyboard),
            child: Center(
              child: AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) {
                  final t = _shakeController.value;
                  final offset = _showShakeError ? math.sin(t * math.pi * 6) * 5 * (1 - t) : 0.0;
                  return Transform.translate(offset: Offset(offset, 0), child: child);
                },
                child: ConstrainedBox(
                  // 增加 maxHeight 限制，防止框页面太大，底部按钮即可固定在这个高度下。
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: media.size.height * 0.85, 
                  ),
                  child: Container(
                    width: media.size.width * 0.90,
                    decoration: BoxDecoration(
                      color: _background,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 固定顶部的 Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                          child: _buildHeader(),
                        ),
                        // 内部滚动区域，把滚动跟 Submit 拆开
                        Flexible(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildWorldSelector(),
                                const SizedBox(height: 16),
                                _buildCoverSection(),
                                const SizedBox(height: 16),
                                _buildInputFields(),
                                const SizedBox(height: 16),
                                _buildMediaManager(), // 展示图提升到剧本类型上方
                                const SizedBox(height: 16),
                                _buildCategorySection(),
                                if (_errorTextMsg != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _errorTextMsg!,
                                    style: const TextStyle(color: _errorText, fontSize: 11.5, height: 1.4),
                                  ),
                                ],
                                const SizedBox(height: 16), // 给底部留点缓冲空间
                              ],
                            ),
                          ),
                        ),
                        // 固定底部的发布按钮
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                          child: _buildSubmitButton(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '分享世界',
          style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        TextButton(
          onPressed: (_publishing || _uploadingMedia || _uploadingCover) ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: _textSecondary,
            disabledForegroundColor: _textMuted.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('关闭', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildWorldSelector() {
    final game = _selectedGame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '要分享的世界',
          style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: (_publishing || _uploadingMedia || _uploadingCover) ? null : _chooseWorld,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _fieldBackground,
              borderRadius: BorderRadius.circular(8),
              border: _showShakeError && game == null
                  ? Border.all(color: const Color(0xFFE9A6A1), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                _WorldCover(url: game?.imageUrl ?? '', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game?.title ?? '请选择一个世界',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: game != null ? _textPrimary : _textMuted,
                          fontSize: 14,
                          fontWeight: game != null ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (game != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _modeLabel(game.mode),
                          style: const TextStyle(color: _textSecondary, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: _textMuted.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '公开信息',
          style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _titleController,
          hintText: '公开标题',
          maxLines: 1,
          maxLength: 40,
          isTitle: true,
        ),
        const SizedBox(height: 10),
        _buildTextField(
          controller: _descriptionController,
          hintText: '世界简介',
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required int maxLines,
    required int maxLength,
    int? minLines,
    bool isTitle = false,
  }) {
    final hasError = _showShakeError && controller.text.trim().isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFFFFF6F5) : _fieldBackground,
        borderRadius: BorderRadius.circular(8),
        border: hasError ? Border.all(color: const Color(0xFFE9A6A1), width: 1) : null,
      ),
      child: TextField(
        controller: controller,
        enabled: !_publishing && !_uploadingMedia && !_uploadingCover,
        maxLines: maxLines,
        minLines: minLines,
        maxLength: maxLength,
        textInputAction: isTitle ? TextInputAction.next : TextInputAction.newline,
        cursorColor: _themeGreen,
        style: const TextStyle(color: _textPrimary, fontSize: 13.5, height: 1.5),
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          hintText: hintText,
          hintStyle: const TextStyle(color: _textMuted, fontSize: 13, height: 1.5),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCoverSection() {
    final hasCover = _coverUrl.trim().isNotEmpty;
    final coverError = _showShakeError && !hasCover;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              '封面',
              style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 4),
            Text(
              '*',
              style: TextStyle(color: _errorText, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: (_publishing || _uploadingCover) ? null : _pickAndUploadCover,
          child: Container(
            // 设置固定长宽为 1:1，而不是 double.infinity
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _fieldBackground,
              borderRadius: BorderRadius.circular(8),
              border: coverError
                  ? Border.all(color: const Color(0xFFE9A6A1), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: _uploadingCover
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _themeGreen),
                    ),
                  )
                : hasCover
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                                color: _textMuted,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '更换',
                                style: TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Icon(Icons.add_photo_alternate_outlined, size: 24, color: _textSecondary),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    final customTags = _selectedCategories
        .where((tag) => !_presetCategories.contains(tag))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              '剧本类型',
              style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 4),
            Text(
              '*',
              style: TextStyle(color: _errorText, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _presetCategories) _buildCategoryChip(tag),
            for (final tag in customTags) _buildCategoryChip(tag, removable: true),
            _buildAddCustomCategoryChip(),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String tag, {bool removable = false}) {
    final selected = _selectedCategories.contains(tag);
    final disabled = _publishing || _uploadingMedia || _uploadingCover;

    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              setState(() {
                if (selected) {
                  _selectedCategories.remove(tag);
                } else {
                  if (_selectedCategories.length >= _maxCategoryCount) {
                    _triggerShake('最多选 $_maxCategoryCount 个类型');
                    return;
                  }
                  _selectedCategories.add(tag);
                }
                if (_showShakeError && _selectedCategories.isNotEmpty) {
                  _showShakeError = false;
                }
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _themeGreen.withOpacity(0.22) : _fieldBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _themeGreen : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag,
              style: TextStyle(
                color: selected ? _textPrimary : _textSecondary,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (removable) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: disabled
                    ? null
                    : () => setState(() => _selectedCategories.remove(tag)),
                child: const Icon(LucideIcons.x, size: 12, color: _textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddCustomCategoryChip() {
    final disabled = _publishing || _uploadingMedia || _uploadingCover;
    return GestureDetector(
      onTap: disabled ? null : _showAddCustomCategoryDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _fieldBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _textMuted.withOpacity(0.4), width: 1, style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 12, color: _textSecondary),
            SizedBox(width: 4),
            Text(
              '自定义',
              style: TextStyle(color: _textSecondary, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCustomCategoryDialog() async {
    FocusScope.of(context).unfocus();
    _customCategoryController.clear();

    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '添加自定义类型',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, __, ___) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Container(
                  width: MediaQuery.sizeOf(dialogContext).width * 0.82,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  decoration: BoxDecoration(
                    color: _background,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '自定义剧本类型',
                        style: TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _fieldBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _customCategoryController,
                          autofocus: true,
                          maxLength: 8,
                          cursorColor: _themeGreen,
                          style: const TextStyle(color: _textPrimary, fontSize: 13.5),
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            hintText: '如：赛博朋克、宫斗',
                            hintStyle: TextStyle(color: _textMuted, fontSize: 13),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(foregroundColor: _textSecondary),
                            child: const Text('取消', style: TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(
                              _customCategoryController.text.trim(),
                            ),
                            style: TextButton.styleFrom(foregroundColor: _textPrimary),
                            child: const Text('添加', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result == null || result.isEmpty || !mounted) return;

    if (result.length > 8) {
      _triggerShake('类型标签最多 8 个字');
      return;
    }
    if (_selectedCategories.contains(result)) {
      return;
    }
    if (_selectedCategories.length >= _maxCategoryCount) {
      _triggerShake('最多选 $_maxCategoryCount 个类型');
      return;
    }

    setState(() {
      _selectedCategories.add(result);
      if (_showShakeError) _showShakeError = false;
    });
  }

  Widget _buildMediaManager() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '展示图',
          style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _media.length + ((_media.length < _maxMediaCount || _uploadingMedia) ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < _media.length) {
                return _MediaThumb(
                  item: _media[index],
                  removable: !_uploadingMedia && !_publishing && !_uploadingCover,
                  onRemove: () => _removeMedia(index),
                  onPreview: () => _previewMedia(index),
                );
              }
              if (_uploadingMedia) {
                return _UploadingMediaTile(done: _uploadDone, total: _uploadTotal);
              }
              return _AddMediaTile(onTap: _pickAndUploadMedia);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final disabled = _publishing || _uploadingMedia || _uploadingCover;
    final String buttonText = _publishing ? '正在发布...' : (_uploadingMedia ? '图片上传中...' : '发布');

    return Material(
      color: disabled ? _themeGreen.withOpacity(0.46) : _themeGreen,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                if (!_canPublish) {
                  _triggerShake('请完善必填信息');
                  return;
                }
                _publish();
              },
        child: SizedBox(
          height: 48,
          child: Center(
            child: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF303730)),
                  )
                : Text(
                    buttonText,
                    style: TextStyle(
                      color: disabled ? _textPrimary.withOpacity(0.5) : _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _WorldCover extends StatelessWidget {
  const _WorldCover({required this.url, required this.size});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: url.trim().isEmpty
            ? Container(
                color: _fieldBackground,
                child: const Icon(Icons.image_outlined, size: 20, color: _textMuted),
              )
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(
                color: _fieldBackground,
                child: const Icon(Icons.broken_image_outlined, size: 20, color: _textMuted),
              )),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.item,
    required this.removable,
    required this.onRemove,
    required this.onPreview,
  });

  final ShareWorldMediaDraft item;
  final bool removable;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: _fieldBackground,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPreview,
                child: Image.network(
                  item.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 18, color: _textMuted),
                  ),
                ),
              ),
            ),
          ),
          if (removable)
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                  child: const Icon(LucideIcons.x, size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddMediaTile extends StatelessWidget {
  const _AddMediaTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fieldBackground,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: const Center(
            child: Icon(LucideIcons.plus, size: 20, color: _textSecondary),
          ),
        ),
      ),
    );
  }
}

class _UploadingMediaTile extends StatelessWidget {
  const _UploadingMediaTile({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final value = total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: _fieldBackground, borderRadius: BorderRadius.circular(8)),
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 2,
            color: _themeGreen,
            backgroundColor: _textMuted.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}

class _WorldPickerDialog extends StatelessWidget {
  const _WorldPickerDialog({
    required this.games,
    required this.selectedIndex,
    required this.modeLabel,
  });

  final List<GameData> games;
  final int selectedIndex;
  final String Function(String) modeLabel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
            child: Container(
              width: size.width * 0.90,
              height: (size.height * 0.62).clamp(340.0, 520.0).toDouble(),
              decoration: BoxDecoration(
                color: _background,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选择世界',
                            style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: _textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('关闭', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFEAECE9)),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: games.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final game = games[index];
                        final selected = index == selectedIndex;

                        return Material(
                          color: selected ? _themeGreen.withOpacity(0.12) : _fieldBackground,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(index),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  _WorldCover(url: game.imageUrl, size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          game.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          modeLabel(game.mode),
                                          style: const TextStyle(color: _textSecondary, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check_circle_rounded, color: _themeGreen, size: 20),
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
          ),
        ),
      ),
    );
  }
}
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:http/http.dart' as http;

import 'app_shared.dart';
import 'api/api_client.dart';

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
      // 使用更深的遮罩压暗底层亮度，凸显毛玻璃弹窗
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => ShareWorldPage(
        games: games,
        initialIndex: initialIndex,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ShareWorldPage> createState() => _ShareWorldPageState();
}

class _ShareWorldPageState extends State<ShareWorldPage> {
  static const int _maxMediaCount = 10;
  static const String _r2Category = 'chat_background';
  
  // 完全对齐 game_drawer 的冰霜玻璃底色
  static const Color _glassColor = Color.fromARGB(25, 253, 253, 253);

  late int _selectedIndex;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  final List<ShareWorldMediaDraft> _media = <ShareWorldMediaDraft>[];

  bool _publishing = false;
  bool _uploadingMedia = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;
  String? _errorText;

  GameData? get _selectedGame {
    if (widget.games.isEmpty) return null;
    final index = _selectedIndex.clamp(0, widget.games.length - 1).toInt();
    return widget.games[index];
  }

  bool get _canPublish {
    return !_publishing &&
        !_uploadingMedia &&
        _selectedGame != null &&
        _titleController.text.trim().isNotEmpty &&
        _descriptionController.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.games.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.games.length - 1).toInt();
    _titleController = TextEditingController(text: _selectedGame?.title ?? '');
    _descriptionController = TextEditingController();
    _titleController.addListener(_refresh);
    _descriptionController.addListener(_refresh);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_refresh)
      ..dispose();
    _descriptionController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    if (widget.games.isEmpty || _publishing || _uploadingMedia) return;

    final next = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭世界选择',
      // 同样加深遮罩
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return _WorldPickerDialog(
          games: widget.games,
          selectedIndex: _selectedIndex,
          modeLabel: _modeLabel,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
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
      _errorText = null;
    });
  }

  Future<void> _pickAndUploadMedia() async {
    if (_uploadingMedia || _publishing) return;

    final remaining = _maxMediaCount - _media.length;
    if (remaining <= 0) {
      _setError('最多添加 $_maxMediaCount 张展示图');
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
      _setError('无法打开图片选择器：${_cleanError(error)}');
      return;
    }

    if (result == null || result.files.isEmpty || !mounted) return;

    final files = result.files.take(remaining).toList(growable: false);
    setState(() {
      _errorText = null;
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
      setState(() => _errorText = '图片上传失败：${_cleanError(error)}');
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

  Future<ShareWorldMediaDraft> _uploadOneMedia({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final signatureResponse = await ApiClient.instance.post(
      '/r2/get-signature',
      body: <String, dynamic>{
        'filename': fileName,
        'content_type': contentType,
        'category': _r2Category,
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
      throw Exception('R2 上传失败（${response.statusCode}）');
    }

    return ShareWorldMediaDraft(
      url: publicUrl,
      r2Key: key.isEmpty ? null : key,
    );
  }

  void _removeMedia(int index) {
    if (_publishing || _uploadingMedia) return;
    if (index < 0 || index >= _media.length) return;
    setState(() {
      _media.removeAt(index);
      _errorText = null;
    });
  }

  Future<void> _previewMedia(int index) async {
    if (index < 0 || index >= _media.length) return;
    final media = _media[index];

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭图片预览',
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _glassColor,
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4,
                            child: Image.network(
                              media.url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text(
                                  '图片加载失败',
                                  style: TextStyle(color: AppColors.textOnDarkMuted),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: _HeaderIconButton(
                            icon: LucideIcons.x,
                            onTap: () => Navigator.of(context).pop(),
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
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _publish() async {
    if (_publishing || _uploadingMedia) return;

    if (!_canPublish) {
      if (_selectedGame == null) {
        _setError('请先选择一个世界');
      } else if (_titleController.text.trim().isEmpty) {
        _setError('请填写公开标题');
      } else if (_descriptionController.text.trim().isEmpty) {
        _setError('请填写公开简介');
      }
      return;
    }

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
      _errorText = null;
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
        _errorText = _cleanError(error);
      });
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
    if (value.endsWith('.heic') || value.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('ApiException: ', '')
        .trim();
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _errorText = message);
  }

  Future<void> _showSuccess() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '发布成功',
      barrierColor: Colors.black.withOpacity(0.65),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    width: MediaQuery.sizeOf(context).width * 0.82,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    decoration: BoxDecoration(
                      color: _glassColor,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              '发布成功',
                              style: TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _media.isEmpty
                              ? '世界已发布到发现页。'
                              : '世界与 ${_media.length} 张展示图已发布到发现页。',
                          style: const TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Material(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(4),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(4),
                            child: const SizedBox(
                              height: 44,
                              width: double.infinity,
                              child: Center(
                                child: Text(
                                  '完成',
                                  style: TextStyle(
                                    color: Color(0xFF0C0C0C),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
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
    final maxHeight = (media.size.height - keyboard - 56).clamp(430.0, 650.0);

    return PopScope(
      canPop: !_publishing && !_uploadingMedia,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(18, 24, 18, keyboard + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: maxHeight,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    // 同步 game_drawer 的 26 高强度模糊
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26), 
                    child: Container(
                      width: media.size.width * 0.92,
                      decoration: BoxDecoration(
                        // 同步 game_drawer 的极光感白底微透
                        color: _glassColor, 
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08), 
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.white.withOpacity(0.05),
                          ),
                          Flexible(child: _buildContent()),
                          _buildFooter(),
                        ],
                      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '分享世界',
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: LucideIcons.x,
            onTap: (_publishing || _uploadingMedia)
                ? null
                : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final game = _selectedGame;

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(
              title: '当前世界',
              trailing: '点击更换',
            ),
            const SizedBox(height: 8),
            _WorldSelector(
              game: game,
              modeLabel: _modeLabel,
              onTap: _chooseWorld,
              enabled: !_publishing && !_uploadingMedia,
            ),
            const SizedBox(height: 20),
            const _SectionHeader(title: '发布信息'),
            const SizedBox(height: 8),
            _PublishInfoEditor(
              titleController: _titleController,
              descriptionController: _descriptionController,
              enabled: !_publishing && !_uploadingMedia,
            ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: '展示图',
              trailing: '${_media.length}/$_maxMediaCount',
            ),
            const SizedBox(height: 8),
            _MediaManager(
              media: _media,
              uploading: _uploadingMedia,
              uploadDone: _uploadDone,
              uploadTotal: _uploadTotal,
              canAdd: _media.length < _maxMediaCount &&
                  !_publishing &&
                  !_uploadingMedia,
              onAdd: _pickAndUploadMedia,
              onRemove: _removeMedia,
              onPreview: _previewMedia,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              _InlineError(text: _errorText!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Material(
        color: _canPublish ? AppColors.accent : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _canPublish ? _publish : null,
          child: SizedBox(
            height: 48,
            child: Center(
              child: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0C0C0C),
                      ),
                    )
                  : Text(
                      _uploadingMedia ? '上传中…' : '确认发布',
                      style: TextStyle(
                        color: _canPublish
                            ? const Color(0xFF0C0C0C)
                            : AppColors.textOnDarkMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? AppColors.textOnDarkMuted.withOpacity(0.30)
                : AppColors.textOnDarkMuted,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textOnDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: AppColors.textOnDarkMuted.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

class _WorldSelector extends StatelessWidget {
  const _WorldSelector({
    required this.game,
    required this.modeLabel,
    required this.onTap,
    required this.enabled,
  });

  final GameData? game;
  final String Function(String) modeLabel;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              _WorldCover(url: game?.imageUrl ?? '', size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game?.title ?? '暂无可分享世界',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (game != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              modeLabel(game!.mode),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (game != null) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            game == null ? '请先创建世界' : '选择要公开的世界存档',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textOnDarkMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: enabled
                    ? AppColors.textOnDarkMuted
                    : AppColors.textOnDarkMuted.withOpacity(0.30),
              ),
            ],
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
    final image = url.trim().isEmpty
        ? _fallback()
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      color: Colors.white.withOpacity(0.02),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 18,
        color: AppColors.textOnDarkMuted,
      ),
    );
  }
}

class _PublishInfoEditor extends StatelessWidget {
  const _PublishInfoEditor({
    required this.titleController,
    required this.descriptionController,
    required this.enabled,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          _FlatField(
            label: '标题',
            controller: titleController,
            hintText: '给这个世界一个公开标题',
            maxLength: 80,
            maxLines: 1,
            enabled: enabled,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Divider(
              height: 1,
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          _FlatField(
            label: '简介',
            controller: descriptionController,
            hintText: '一句话介绍玩法、设定或值得体验的地方',
            maxLength: 1000,
            minLines: 3,
            maxLines: 5,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

class _FlatField extends StatelessWidget {
  const _FlatField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.maxLength,
    required this.maxLines,
    required this.enabled,
    this.minLines,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final int? minLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: enabled,
            minLines: minLines,
            maxLines: maxLines,
            maxLength: maxLength,
            cursorColor: AppColors.accent,
            buildCounter: (
              context, {
              required currentLength,
              required isFocused,
              maxLength,
            }) => null,
            style: const TextStyle(
              color: AppColors.textOnDark,
              fontSize: 13,
              height: 1.5,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText,
              hintStyle: TextStyle(
                color: AppColors.textOnDarkMuted.withOpacity(0.6),
                fontSize: 12.5,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaManager extends StatelessWidget {
  const _MediaManager({
    required this.media,
    required this.uploading,
    required this.uploadDone,
    required this.uploadTotal,
    required this.canAdd,
    required this.onAdd,
    required this.onRemove,
    required this.onPreview,
  });

  final List<ShareWorldMediaDraft> media;
  final bool uploading;
  final int uploadDone;
  final int uploadTotal;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: media.isEmpty && !uploading
          ? _EmptyMediaButton(enabled: canAdd, onTap: onAdd)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: media.length + (canAdd || uploading ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index < media.length) {
                        return _MediaThumb(
                          index: index,
                          item: media[index],
                          removable: !uploading,
                          onRemove: () => onRemove(index),
                          onPreview: () => onPreview(index),
                        );
                      }
                      if (uploading) {
                        return _UploadingMediaTile(
                          done: uploadDone,
                          total: uploadTotal,
                        );
                      }
                      return _AddMediaTile(onTap: onAdd);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      uploading ? Icons.cloud_upload_outlined : Icons.photo_library_outlined,
                      size: 14,
                      color: uploading
                          ? AppColors.accent
                          : AppColors.textOnDarkMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        uploading
                            ? '正在上传 ${uploadDone.clamp(0, uploadTotal)}/$uploadTotal'
                            : '点击图片预览，右上角删除',
                        style: TextStyle(
                          color: uploading
                              ? AppColors.accent
                              : AppColors.textOnDarkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (!uploading && canAdd)
                      InkWell(
                        onTap: onAdd,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          child: Text(
                            '+ 继续添加',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _EmptyMediaButton extends StatelessWidget {
  const _EmptyMediaButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.accent.withOpacity(0.2),
                  ),
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: enabled
                      ? AppColors.accent
                      : AppColors.textOnDarkMuted.withOpacity(0.35),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '添加展示图',
                      style: TextStyle(
                        color: enabled
                            ? AppColors.textOnDark
                            : AppColors.textOnDarkMuted.withOpacity(0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '支持 JPG / PNG / WebP，最多 10 张',
                      style: TextStyle(
                        color: AppColors.textOnDarkMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.plus,
                size: 16,
                color: enabled
                    ? AppColors.accent
                    : AppColors.textOnDarkMuted.withOpacity(0.30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.index,
    required this.item,
    required this.removable,
    required this.onRemove,
    required this.onPreview,
  });

  final int index;
  final ShareWorldMediaDraft item;
  final bool removable;
  final VoidCallback onRemove;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPreview,
                child: Image.network(
                  item.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white.withOpacity(0.02),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      size: 16,
                      color: AppColors.textOnDarkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: removable ? onRemove : null,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.x,
                  size: 12,
                  color: removable
                      ? Colors.white
                      : Colors.white.withOpacity(0.30),
                ),
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.plus, size: 16, color: AppColors.accent),
              SizedBox(height: 6),
              Text(
                '添加',
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 10,
                ),
              ),
            ],
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
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.05),
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 2,
              color: AppColors.accent,
              backgroundColor: Colors.white.withOpacity(0.08),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$done/$total',
            style: const TextStyle(
              color: AppColors.textOnDarkMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE0554A).withOpacity(0.08),
        border: Border.all(
          color: const Color(0xFFE0554A).withOpacity(0.30),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: Color(0xFFE7685E),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFE98A83),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
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
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                // 同步 game_drawer 的 26 强模糊
                filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: Container(
                  width: size.width * 0.88,
                  height: (size.height * 0.56).clamp(300.0, 460.0),
                  decoration: BoxDecoration(
                    // 完全对齐 game_drawer 的玻璃底色
                    color: _ShareWorldPageState._glassColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '选择世界',
                                    style: TextStyle(
                                      color: AppColors.textOnDark,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _HeaderIconButton(
                              icon: LucideIcons.x,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.05),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          physics: const BouncingScrollPhysics(),
                          itemCount: games.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final game = games[index];
                            final selected = index == selectedIndex;
                            return Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.of(context).pop(index),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.accent.withOpacity(0.05)
                                        : Colors.white.withOpacity(0.02),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.accent.withOpacity(0.3)
                                          : Colors.white.withOpacity(0.08),
                                    ),
                                  ),
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
                                              style: const TextStyle(
                                                color: AppColors.textOnDark,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              modeLabel(game.mode),
                                              style: TextStyle(
                                                color: selected
                                                    ? AppColors.accent
                                                    : AppColors.textOnDarkMuted,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        selected
                                            ? Icons.check_circle_outline_rounded
                                            : LucideIcons.chevronRight,
                                        size: 16,
                                        color: selected
                                            ? AppColors.accent
                                            : AppColors.textOnDarkMuted
                                                .withOpacity(0.5),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_shared.dart';
import 'api/api_client.dart';
import 'api/mine_api.dart';
import 'api/model_config_api.dart';

class MineDialogs {
  MineDialogs._();

  static Future<String?> editName(
    BuildContext context, {
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    var saving = false;
    String? error;

    final result = await _showLight<String>(
      context,
      title: '修改昵称',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final name = controller.text.trim();
          if (name.isEmpty || saving || name == currentName) return;
          setState(() {
            saving = true;
            error = null;
          });
          try {
            await MineApi.updateUserName(name);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(name);
            }
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              saving = false;
              error = e.message;
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() {
              saving = false;
              error = '修改失败，请稍后重试';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _lightInput(
              controller: controller,
              hint: '输入新的昵称',
              autofocus: true,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _lightError(error!),
            ],
            const SizedBox(height: 20),
            _lightPrimaryButton(
              label: saving ? '保存中...' : '保存',
              enabled: !saving,
              onTap: submit,
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// 手机端头像编辑：使用统一的浅色主题弹窗。
  static Future<String?> editAvatar(BuildContext context) async {
    Uint8List? selectedBytes;
    String selectedFilename = 'avatar.webp';
    bool uploading = false;
    String? error;

    return _showLight<String>(
      context,
      title: '更换头像',
      builder: (dialogContext, setState) {
        Future<void> pickImage() async {
          if (uploading) return;
          setState(() => error = null);

          FilePickerResult? picked;
          try {
            picked = await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: false,
              withData: true,
            );
          } catch (_) {
            return;
          }

          if (picked == null || picked.files.isEmpty) return;
          final file = picked.files.first;
          final bytes = file.bytes;

          if (bytes == null || bytes.isEmpty) {
            if (!dialogContext.mounted) return;
            setState(() {
              error = '无法读取所选图片，请重新选择';
            });
            return;
          }

          if (!dialogContext.mounted) return;
          setState(() {
            selectedBytes = Uint8List.fromList(bytes);
            selectedFilename = file.name.trim().isEmpty
                ? 'avatar.webp'
                : file.name.trim();
            error = null;
          });
        }

        Future<void> submit() async {
          final bytes = selectedBytes;
          if (uploading || bytes == null || bytes.isEmpty) return;

          setState(() {
            uploading = true;
            error = null;
          });

          try {
            final uploadBytes = selectedFilename.toLowerCase().endsWith('.webp')
                ? bytes
                : await _convertImageToWebp(bytes);
            final uploadFilename = _webpFileName(selectedFilename);

            final url = await MineApi.uploadAndUpdateAvatar(
              bytes: uploadBytes,
              filename: uploadFilename,
            );
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop(url);
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              uploading = false;
              error = e.message;
            });
          } catch (e) {
            if (!dialogContext.mounted) return;
            final message = e
                .toString()
                .replaceFirst('Exception: ', '')
                .replaceFirst('ApiException: ', '')
                .trim();
            setState(() {
              uploading = false;
              error = message.isEmpty ? '头像上传失败，请稍后重试' : message;
            });
          }
        }

        final hasImage = selectedBytes != null;
        const textMuted = Color(0xFFA3AAA2);

        return PopScope(
          canPop: !uploading,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: uploading ? null : pickImage,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF4F6F2),
                      border: Border.all(
                        color: hasImage
                            ? const Color(0xFF9BD991)
                            : const Color(0xFFE1E6DE),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasImage
                        ? Image.memory(
                            selectedBytes!,
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                          )
                        : const Icon(
                            LucideIcons.imagePlus,
                            size: 30,
                            color: Color(0xFF7B8579),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasImage ? '点击头像可以重新选择图片' : '选择一张图片作为新的头像',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              if (error != null) ...[
                const SizedBox(height: 10),
                _lightError(error!),
              ],
              const SizedBox(height: 14),
              _lightPrimaryButton(
                label: uploading
                    ? '正在保存...'
                    : hasImage
                        ? '确认保存'
                        : '请先选择图片',
                enabled: hasImage && !uploading,
                onTap: submit,
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<Uint8List> _convertImageToWebp(Uint8List bytes) async {
    final converted = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 4096,
      minHeight: 4096,
      quality: 88,
      format: CompressFormat.webp,
      keepExif: false,
    );
    if (converted.isEmpty) {
      throw Exception('图片转换 WebP 失败');
    }
    return converted;
  }

  static String _webpFileName(String originalName) {
    final trimmed = originalName.trim();
    final dot = trimmed.lastIndexOf('.');
    final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    final safeBase = base.isEmpty ? 'avatar' : base;
    return '$safeBase.webp';
  }

  static Future<MineCheckinResult?> checkin(BuildContext context) async {
    MineCheckinStatus? status;
    MineCheckinResult? successResult;
    bool loading = true;
    bool submitting = false;
    bool loadStarted = false;
    String? error;

    const background = Color(0xFFFCFDFB);
    const fieldBackground = Color(0xFFF4F6F2);
    const border = Color(0xFFDCE2DA);
    const textPrimary = Color(0xFF303730);
    const textSecondary = Color(0xFF70786F);
    const textMuted = Color(0xFFA3AAA2);
    const themeGreen = Color.fromARGB(255, 129, 246, 112);

    return showGeneralDialog<MineCheckinResult>(
      context: context,
      barrierDismissible: !submitting,
      barrierLabel: '关闭签到',
      barrierColor: Colors.black.withOpacity(0.28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: StatefulBuilder(
              builder: (context, setState) {
                if (!loadStarted) {
                  loadStarted = true;
                  Future<void>(() async {
                    try {
                      final next = await MineApi.getCheckinStatus();
                      if (!dialogContext.mounted) return;
                      setState(() {
                        status = next;
                        loading = false;
                        error = null;
                      });
                    } on ApiException catch (e) {
                      if (!dialogContext.mounted) return;
                      setState(() {
                        loading = false;
                        error = e.message;
                      });
                    } catch (_) {
                      if (!dialogContext.mounted) return;
                      setState(() {
                        loading = false;
                        error = '签到状态获取失败，请稍后重试';
                      });
                    }
                  });
                }

                Future<void> submit() async {
                  if (loading ||
                      submitting ||
                      successResult != null ||
                      status?.checkedInToday == true) {
                    return;
                  }

                  setState(() {
                    submitting = true;
                    error = null;
                  });

                  try {
                    // 再向后端确认一次，避免页面状态过期后重复签到。
                    final latest = await MineApi.getCheckinStatus();
                    if (!dialogContext.mounted) return;

                    if (latest.checkedInToday) {
                      setState(() {
                        status = latest;
                        submitting = false;
                      });
                      return;
                    }

                    final result = await MineApi.dailyCheckin();
                    if (!dialogContext.mounted) return;

                    // 签到成功后重新读取 /user/checkin/status，
                    // 不在前端伪造“今天已签到”或签到天数。
                    final refreshedStatus = await MineApi.getCheckinStatus();
                    if (!dialogContext.mounted) return;

                    setState(() {
                      successResult = result;
                      submitting = false;
                      status = refreshedStatus;
                    });
                  } on ApiException catch (e) {
                    if (!dialogContext.mounted) return;

                    // 如果后端明确告诉前端“今天已签到”，立刻重拉真实状态。
                    final isAlreadyChecked =
                        e.message.contains('已签到') || e.message.contains('明天再来');

                    if (isAlreadyChecked) {
                      try {
                        final latest = await MineApi.getCheckinStatus();
                        if (!dialogContext.mounted) return;
                        setState(() {
                          status = latest;
                          submitting = false;
                          error = null;
                        });
                        return;
                      } catch (_) {
                        // 状态刷新失败时，仍保留后端原始错误消息。
                      }
                    }

                    setState(() {
                      submitting = false;
                      error = e.message;
                    });
                  } catch (_) {
                    if (!dialogContext.mounted) return;
                    setState(() {
                      submitting = false;
                      error = '签到失败，请稍后重试';
                    });
                  }
                }

                final media = MediaQuery.of(context);
                final currentStatus = status;
                final checked = currentStatus?.checkedInToday == true;
                final result = successResult;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: Container(
                      width: media.size.width * 0.90,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 190,
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF55A84A),
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '每日签到',
                                            style: TextStyle(
                                              color: textPrimary,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            '奖励与余额均以服务器实际返回为准',
                                            style: TextStyle(
                                              color: textSecondary,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: submitting
                                          ? null
                                          : () => Navigator.of(dialogContext).pop(),
                                      style: TextButton.styleFrom(
                                        foregroundColor: textSecondary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        '关闭',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 15, 16, 15),
                                  decoration: BoxDecoration(
                                    color: fieldBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: result != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: themeGreen
                                                        .withOpacity(0.22),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(
                                                    LucideIcons.check,
                                                    size: 16,
                                                    color: Color(0xFF3E8F37),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                const Text(
                                                  '签到成功',
                                                  style: TextStyle(
                                                    color: textPrimary,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 14),
                                            Row(
                                              children: [
                                                const Expanded(
                                                  child: Text(
                                                    '本次获得',
                                                    style: TextStyle(
                                                      color: textSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '+${result.reward} 积分',
                                                  style: const TextStyle(
                                                    color: textPrimary,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (result.balance != null) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Expanded(
                                                    child: Text(
                                                      '当前余额',
                                                      style: TextStyle(
                                                        color: textSecondary,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${result.balance}',
                                                    style: const TextStyle(
                                                      color: textPrimary,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    checked
                                                        ? '今天已经签到'
                                                        : '今天还没有签到',
                                                    style: const TextStyle(
                                                      color: textPrimary,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    '本月已签到 ${currentStatus?.days.length ?? 0} 天',
                                                    style: const TextStyle(
                                                      color: textSecondary,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (successResult?.balance != null)
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  const Text(
                                                    '当前余额',
                                                    style: TextStyle(
                                                      color: textMuted,
                                                      fontSize: 10.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${successResult!.balance}',
                                                    style: const TextStyle(
                                                      color: textPrimary,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                ),
                                if (error != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3F1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      error!,
                                      style: const TextStyle(
                                        color: Color(0xFFE0554A),
                                        fontSize: 11.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                Material(
                                  color: result != null
                                      ? const Color(0xFFEAF6E7)
                                      : checked
                                          ? const Color(0xFFE8ECE7)
                                          : submitting
                                              ? themeGreen.withOpacity(0.5)
                                              : themeGreen,
                                  borderRadius: BorderRadius.circular(8),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: result != null
                                        ? () => Navigator.of(dialogContext)
                                            .pop(result)
                                        : (!checked && !submitting)
                                            ? submit
                                            : null,
                                    child: SizedBox(
                                      height: 48,
                                      child: Center(
                                        child: Text(
                                          result != null
                                              ? '完成'
                                              : checked
                                                  ? '今日已签到'
                                                  : submitting
                                                      ? '正在签到...'
                                                      : '立即签到',
                                          style: TextStyle(
                                            color: result != null
                                                ? const Color(0xFF3D6E39)
                                                : checked
                                                    ? textMuted
                                                    : textPrimary,
                                            fontSize: 14,
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
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static Future<bool> redeem(BuildContext context) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return const _RedeemDialog();
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
    );

    return result == true;
  }

  static Future<void> announcements(BuildContext context) async {
    // 公告只改交互与排版：默认全部收起，点击单条展开/收起。
    // 接口与数据结构保持不变。
    int expandedIndex = -1;
    final announcementsFuture = MineApi.getAnnouncements();

    const background = Color(0xFFFDFEFC);
    const textPrimary = Color(0xFF303730);
    const textSecondary = Color(0xFF70786F);
    const textMuted = Color(0xFFA3AAA2);
    const softBackground = Color(0xFFF6F8F4);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.14),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  final media = MediaQuery.of(context);
                  final maxHeight = media.size.height * 0.76;

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxHeight,
                    ),
                    child: Container(
                      width: media.size.width * 0.90,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '系统公告',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                 ),
                                ),
                              ),
                              InkWell(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                borderRadius: BorderRadius.circular(18),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    LucideIcons.x,
                                    size: 18,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Flexible(
                            child: FutureBuilder<List<MineAnnouncement>>(
                              future: announcementsFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 36),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 28),
                                      child: Text(
                                        '公告加载失败，请稍后重试',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final items = snapshot.data ?? const <MineAnnouncement>[];
                                if (items.isEmpty) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 28),
                                      child: Text(
                                        '暂无系统公告',
                                        style: TextStyle(
                                          color: textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: items.length,
                                  itemBuilder: (_, index) {
                                    final item = items[index];
                                    final expanded = expandedIndex == index;
                                    final dateStr = item.createdAt.contains('T')
                                        ? item.createdAt.split('T').first
                                        : item.createdAt;

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index == items.length - 1 ? 0 : 8,
                                      ),
                                      child: Material(
                                        color: expanded ? softBackground : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              expandedIndex = expanded ? -1 : index;
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            item.title,
                                                            maxLines: expanded ? null : 1,
                                                            overflow: expanded
                                                                ? TextOverflow.visible
                                                                : TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              color: textPrimary,
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.w600,
                                                              height: 1.35,
                                                            ),
                                                          ),
                                                          if (dateStr.isNotEmpty) ...[
                                                            const SizedBox(height: 5),
                                                            Text(
                                                              dateStr,
                                                              style: const TextStyle(
                                                                color: textMuted,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    AnimatedRotation(
                                                      turns: expanded ? 0.5 : 0,
                                                      duration: const Duration(milliseconds: 160),
                                                      child: const Icon(
                                                        LucideIcons.chevronDown,
                                                        size: 16,
                                                        color: textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                AnimatedSize(
                                                  duration: const Duration(milliseconds: 180),
                                                  curve: Curves.easeOutCubic,
                                                  alignment: Alignment.topCenter,
                                                  child: expanded
                                                      ? Padding(
                                                          padding: const EdgeInsets.only(top: 12),
                                                          child: Text(
                                                            item.content.isEmpty
                                                                ? '暂无详细内容'
                                                                : item.content,
                                                            style: const TextStyle(
                                                              color: textSecondary,
                                                              fontSize: 13,
                                                              height: 1.7,
                                                            ),
                                                          ),
                                                        )
                                                      : const SizedBox.shrink(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  static Future<bool> feedback(BuildContext context) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    var loading = false;
    var successMode = false;
    String? error;

    final result = await _showLight<bool>(
      context,
      title: '问题反馈',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final title = titleController.text.trim();
          final content = contentController.text.trim();
          if (loading || successMode) return;
          if (title.isEmpty || content.isEmpty) {
            setState(() => error = '请填写标题和详细描述');
            return;
          }

          setState(() {
            loading = true;
            error = null;
          });
          try {
            await MineApi.submitFeedback(
              title: title,
              content: content,
            );
            if (!dialogContext.mounted) return;
            setState(() {
              loading = false;
              successMode = true;
            });
            await Future.delayed(const Duration(milliseconds: 800));
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              loading = false;
              error = e.message;
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() {
              loading = false;
              error = '发送失败，请重试';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _lightInput(
              controller: titleController,
              hint: '请概括您遇到的问题',
              enabled: !successMode,
            ),
            const SizedBox(height: 12),
            _lightInput(
              controller: contentController,
              hint: '请提供更多细节描述...',
              maxLines: 5,
              enabled: !successMode,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _lightError(error!),
            ],
            const SizedBox(height: 20),
            _lightPrimaryButton(
              label: successMode ? '提交成功' : (loading ? '提交中...' : '确认提交'),
              enabled: !loading && !successMode,
              onTap: submit,
            ),
          ],
        );
      },
    );

    titleController.dispose();
    contentController.dispose();
    return result == true;
  }

  /// 手机端退出登录确认：使用统一的浅色主题弹窗。
  static Future<bool> confirmLogout(BuildContext context) async {
    return await _showLight<bool>(
          context,
          title: '退出登录',
          builder: (dialogContext, setState) {
            // 改用更深的文字颜色，代替原本太淡的 textSecondary
            const textPrimary = Color(0xFF303730);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '确定要退出当前账号吗？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary, // 颜色加深
                    fontSize: 14,       // 字号从 13 调到 14
                    fontWeight: FontWeight.w500, // 增加一点字重
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24), // 间距稍微拉开一点
                _lightPrimaryButton(
                  label: '确认退出',
                  enabled: true,
                  danger: true,
                  onTap: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        ) ==
        true;
  }

  static Future<void> apiSettingsPending(BuildContext context) async {
    final baseUrlController = TextEditingController();
    final modelController = TextEditingController();
    final apiKeyController = TextEditingController();

    ModelConfigSnapshot? config;
    var loading = true;
    var loadStarted = false;
    var enableOwnKey = false;
    var toggling = false;
    var saving = false;
    var successMode = false;
    String? errorText;
    var selectedModelId = '';
    var models = <ModelOption>[];

    String modelNameFor(String id) {
      if (id.trim().isEmpty) return '未配置';
      for (final item in models) {
        if (item.id == id) return item.name;
      }
      final parts = id.split('/');
      return parts.isEmpty ? id : parts.last;
    }

    await _showLight<void>(
      context,
      title: '接口设置',
      maxWidth: 420,
      builder: (dialogContext, setState) {
        if (!loadStarted) {
          loadStarted = true;
          Future<void>(() async {
            try {
              final next = await ModelConfigApi.getConfig();
              if (!dialogContext.mounted) return;
              setState(() {
                config = next;
                enableOwnKey = next.enableOwnKey;
                selectedModelId = next.scenePreferences['novel'] ?? '';
                models = next.models;
                baseUrlController.text = next.customApi.baseUrl;
                modelController.text = next.customApi.modelName;
                apiKeyController.text = next.customApi.apiKey;
                loading = false;
              });
            } on ApiException catch (e) {
              if (!dialogContext.mounted) return;
              setState(() {
                loading = false;
                errorText = e.message;
              });
            } catch (_) {
              if (!dialogContext.mounted) return;
              setState(() {
                loading = false;
                errorText = '配置获取失败';
              });
            }
          });
        }

        Future<void> chooseModel() async {
          if (enableOwnKey || models.isEmpty) return;
          final selected = await _pickModel(
            dialogContext,
            title: '节点切换',
            models: models,
            currentId: selectedModelId,
          );
          if (!dialogContext.mounted || selected == null) return;
          try {
            await ModelConfigApi.updateScenePreference('novel', selected.id);
            if (!dialogContext.mounted) return;
            setState(() {
              selectedModelId = selected.id;
              errorText = null;
            });
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() => errorText = e.message);
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() => errorText = '保存异常');
          }
        }

        Future<void> toggleOwnKey(bool value) async {
          if (toggling) return;
          final previous = enableOwnKey;
          setState(() {
            toggling = true;
            enableOwnKey = value;
            errorText = null;
          });
          try {
            await ModelConfigApi.toggleOwnKey(value);
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              enableOwnKey = previous;
              errorText = e.message;
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() {
              enableOwnKey = previous;
              errorText = '操作失败';
            });
          } finally {
            if (dialogContext.mounted) {
              setState(() => toggling = false);
            }
          }
        }

        Future<void> saveCustomApi() async {
          if (!enableOwnKey || saving || successMode) return;
          final apiKey = apiKeyController.text.trim();
          final baseUrl = baseUrlController.text.trim();
          final modelName = modelController.text.trim();

          if (apiKey.isEmpty || baseUrl.isEmpty || modelName.isEmpty) {
            setState(() => errorText = '所有参数均需填写');
            return;
          }

          setState(() {
            saving = true;
            errorText = null;
          });

          try {
            final ok = await ModelConfigApi.testConnection(
              apiKey: apiKey,
              baseUrl: baseUrl,
              modelName: modelName,
            );
            if (!ok) {
              if (!dialogContext.mounted) return;
              setState(() {
                saving = false;
                errorText = '节点验证未通过';
              });
              return;
            }
            await ModelConfigApi.saveCustomApi(
              apiKey: apiKey,
              baseUrl: baseUrl,
              modelName: modelName,
            );
            if (!dialogContext.mounted) return;
            setState(() {
              saving = false;
              successMode = true;
            });
            await Future.delayed(const Duration(milliseconds: 1000));
            if (dialogContext.mounted) {
              setState(() => successMode = false);
            }
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              saving = false;
              errorText = e.message;
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setState(() {
              saving = false;
              errorText = '网络连接失败';
            });
          }
        }

        const textPrimary = Color(0xFF303730);
        const textSecondary = Color(0xFF70786F);
        const textMuted = Color(0xFFA3AAA2);
        const softBackground = Color(0xFFF4F6F2);

        if (loading) {
          return const SizedBox(
            height: 180,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          );
        }

        if (config == null && errorText != null) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                errorText!,
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
          );
        }

        final currentModelName = modelNameFor(selectedModelId);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: enableOwnKey
                  ? softBackground.withOpacity(0.72)
                  : softBackground,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enableOwnKey ? null : chooseModel,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '当前模型',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              enableOwnKey ? '使用自定义接口' : currentModelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!enableOwnKey)
                        const Icon(
                          LucideIcons.chevronRight,
                          size: 15,
                          color: textMuted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: softBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '自定义接口',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '开启后使用你自己的接口配置',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enableOwnKey,
                    onChanged: toggling ? null : toggleOwnKey,
                    // 开启时的滑块颜色
                    activeColor: Colors.white,
                    // 开启时与底部主按钮统一使用主题绿。
                    activeTrackColor: AppColors.accent,
                    // 关闭时的滑块与滑轨颜色
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFE2E6DF),
                    // 隐藏原生的自带边框，让开关更极简扁平
                    trackOutlineColor: WidgetStateProperty.all(Colors.transparent), 
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: enableOwnKey
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          _lightInput(
                            controller: baseUrlController,
                            hint: '接口地址',
                            enabled: !saving && !successMode,
                          ),
                          const SizedBox(height: 9),
                          _lightInput(
                            controller: modelController,
                            hint: '模型名称',
                            enabled: !saving && !successMode,
                          ),
                          const SizedBox(height: 9),
                          _lightInput(
                            controller: apiKeyController,
                            hint: '接口密钥',
                            enabled: !saving && !successMode,
                            obscureText: true,
                          ),
                          const SizedBox(height: 14),
                          _lightPrimaryButton(
                            label: successMode
                                ? '保存成功'
                                : saving
                                    ? '正在验证...'
                                    : '保存',
                            enabled: !saving && !successMode,
                            onTap: saveCustomApi,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 12),
              _lightError(errorText!),
            ],
          ],
        );
      },
    );

    baseUrlController.dispose();
    modelController.dispose();
    apiKeyController.dispose();
  }

  static Future<ModelOption?> _pickModel(
    BuildContext context, {
    required String title,
    required List<ModelOption> models,
    required String currentId,
  }) {
    return _showLight<ModelOption>(
      context,
      title: title,
      maxWidth: 410,
      builder: (dialogContext, setState) {
        const textPrimary = Color(0xFF303730);
        const textSecondary = Color(0xFF70786F);
        const softBackground = Color(0xFFF4F6F2);
        const selectedBackground = Color(0xFFEEF7EB);

        if (models.isEmpty) {
          return const SizedBox(
            height: 110,
            child: Center(
              child: Text(
                '暂无可用模型',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: models.length,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (_, index) {
              final item = models[index];
              final selected = item.id == currentId;

              return Material(
                color: selected ? selectedBackground : softBackground,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(dialogContext).pop(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected)
                          const Text(
                            '当前',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
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
      },
    );
  }

  static Future<T?> _showLight<T>(
    BuildContext context, {
    required String title,
    required Widget Function(
      BuildContext context,
      StateSetter setState,
    ) builder,
    double maxWidth = 380,
  }) {
    const background = Color(0xFFFCFDFB);
    const textPrimary = Color(0xFF303730);
    const textSecondary = Color(0xFF70786F);

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.16),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: StatefulBuilder(
              builder: (context, setState) {
                final media = MediaQuery.of(context);
                final keyboard = media.viewInsets.bottom;

                return AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    20,
                    18,
                    20 + keyboard,
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxWidth,
                          maxHeight: media.size.height * 0.82,
                        ),
                        child: Container(
                          width: media.size.width * 0.88,
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          color: textPrimary,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      style: TextButton.styleFrom(
                                        foregroundColor: textSecondary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        '关闭',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                builder(dialogContext, setState),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  static Widget _lightInput({
    required TextEditingController controller,
    required String hint,
    bool autofocus = false,
    bool enabled = true,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    const textPrimary = Color(0xFF303730);
    const textMuted = Color(0xFFA3AAA2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        minLines: maxLines > 1 ? 4 : 1,
        textAlignVertical:
            maxLines == 1 ? TextAlignVertical.center : TextAlignVertical.top,
        cursorColor: const Color(0xFF55A84A),
        style: const TextStyle(
          color: textPrimary,
          fontSize: 13.5,
          height: 1.5,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintStyle: TextStyle(
            color: textMuted,
            fontSize: 13,
          ),
          border: InputBorder.none,
        ).copyWith(hintText: hint),
      ),
    );
  }

  static Widget _lightPrimaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    // 提升背景和文字的对比度
    final background = danger
        ? const Color(0xFFFEE2E2) // 干净明亮的浅红背景
        : enabled
            ? AppColors.accent
            : const Color(0xFFE8EBE5);
    final foreground = danger
        ? const Color(0xFFDC2626) // 高对比度的深红色，非常清晰
        : enabled
            ? const Color(0xFF263026)
            : const Color(0xFFA3AAA2);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _lightError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFAA5A54),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}


class _RedeemDialog extends StatefulWidget {
  const _RedeemDialog();

  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  final TextEditingController _controller = TextEditingController();

  bool _loading = false;
  bool _successMode = false;
  String? _error;

  static const Color _background = Color(0xFFFCFDFB);
  static const Color _fieldBackground = Color(0xFFF4F6F2);
  static const Color _textPrimary = Color(0xFF303730);
  static const Color _textSecondary = Color(0xFF70786F);
  static const Color _textMuted = Color(0xFFA3AAA2);
  static const Color _themeGreen = Color.fromARGB(255, 129, 246, 112);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _loading || _successMode) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await MineApi.redeemCode(code);
      if (!mounted) return;

      // 兑换成功后立即关闭弹窗。
      // 外层收到 true 后会使用现有 AppNotice.success 显示成功通知。
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = '激活失败，请稍后重试';
      });
    }
  }

  void _close() {
    if (_loading) return;

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final width = media.size.width;

    return PopScope(
      canPop: !_loading,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
              18,
              20,
              18,
              20 + keyboard,
            ),
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    width: width * 0.90,
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '激活码',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _loading ? null : _close,
                              style: TextButton.styleFrom(
                                foregroundColor: _textSecondary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '关闭',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: _fieldBackground,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            enabled: !_loading && !_successMode,
                            cursorColor: const Color(0xFF55A84A),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '请输入激活码',
                              hintStyle: TextStyle(
                                color: _textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3F1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFAA5A54),
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Material(
                          color: _successMode
                              ? const Color(0xFFEAF6E7)
                              : _loading
                                  ? _themeGreen.withOpacity(0.50)
                                  : _themeGreen,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap:
                                (!_loading && !_successMode) ? _submit : null,
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: Text(
                                  _successMode
                                      ? '激活成功'
                                      : _loading
                                          ? '正在激活...'
                                          : '激活',
                                  style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
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
    );
  }
}
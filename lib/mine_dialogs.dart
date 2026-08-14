import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

    final result = await _show<String>(
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
            setState(() {
              saving = false;
              error = e.message;
            });
          } catch (_) {
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
            _input(
              controller: controller,
              hint: '输入新的昵称',
              autofocus: true,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _error(error!),
            ],
            const SizedBox(height: 20),
            _primaryButton(
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

  /// 手机端头像编辑
  static Future<String?> editAvatar(BuildContext context) async {
    Uint8List? selectedBytes;
    String selectedFilename = 'avatar.jpg';
    bool uploading = false;
    String? error;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.68),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickImage() async {
              if (uploading) return;
              setSheetState(() => error = null);
              FilePickerResult? picked;
              try {
                picked = await FilePicker.pickFiles(
                  type: FileType.image,
                  allowMultiple: false,
                  withData: true,
                );
              } catch (_) {
                return null;
              }
              if (picked == null || picked.files.isEmpty) return;
              final file = picked.files.first;
              final bytes = file.bytes;
              if (bytes == null || bytes.isEmpty) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  error = '无法读取所选图片，请重新选择';
                });
                return;
              }
              if (!sheetContext.mounted) return;
              setSheetState(() {
                selectedBytes = Uint8List.fromList(bytes);
                selectedFilename =
                    file.name.trim().isEmpty ? 'avatar.jpg' : file.name.trim();
                error = null;
              });
            }

            Future<void> submit() async {
              final bytes = selectedBytes;
              if (uploading || bytes == null || bytes.isEmpty) return;
              setSheetState(() {
                uploading = true;
                error = null;
              });
              try {
                final url = await MineApi.uploadAndUpdateAvatar(
                  bytes: bytes,
                  filename: selectedFilename,
                );
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop(url);
              } on ApiException catch (e) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  uploading = false;
                  error = e.message;
                });
              } catch (e) {
                if (!sheetContext.mounted) return;
                final message = e
                    .toString()
                    .replaceFirst('Exception: ', '')
                    .replaceFirst('ApiException: ', '')
                    .trim();
                setSheetState(() {
                  uploading = false;
                  error = message.isEmpty ? '头像上传失败，请稍后重试' : message;
                });
              }
            }

            final media = MediaQuery.of(context);
            final bottomPadding = media.padding.bottom;
            final hasImage = selectedBytes != null;

            return Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.12), width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '更换头像',
                        style: TextStyle(
                          color: AppColors.textOnDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      GestureDetector(
                        onTap: uploading ? null : () => Navigator.of(sheetContext).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.transparent,
                          child: const Icon(
                            LucideIcons.x,
                            size: 18,
                            color: AppColors.textOnDarkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: uploading ? null : pickImage,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: hasImage ? AppColors.accent : Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: hasImage
                          ? Image.memory(
                              selectedBytes!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Icon(
                                LucideIcons.imagePlus,
                                size: 32,
                                color: AppColors.textOnDarkMuted.withOpacity(0.7),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    hasImage ? '已选择图片，可再次点击区域重新选择' : '从本地选择一张图片',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.zero,
                    child: InkWell(
                      onTap: uploading ? null : pickImage,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.images,
                              size: 16,
                              color: uploading ? AppColors.textOnDarkMuted.withOpacity(0.5) : AppColors.textOnDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasImage ? '重新选择' : '浏览文件',
                              style: TextStyle(
                                color: uploading ? AppColors.textOnDarkMuted.withOpacity(0.5) : AppColors.textOnDark,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _error(error!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _primaryButton(
                      label: uploading ? '上传中...' : (hasImage ? '确认保存' : '请先选择文件'),
                      enabled: hasImage && !uploading,
                      onTap: submit,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<bool> redeem(BuildContext context) async {
    final controller = TextEditingController();
    var loading = false;
    var successMode = false;
    String? error;

    final result = await _show<bool>(
      context,
      title: '兑换激活码',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final code = controller.text.trim();
          if (code.isEmpty || loading || successMode) return;
          setState(() {
            loading = true;
            error = null;
          });
          try {
            await MineApi.redeemCode(code);
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
              error = '兑换失败，请检查网络连接';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _input(
              controller: controller,
              hint: '请输入激活码',
              autofocus: true,
              enabled: !successMode,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _error(error!),
            ],
            const SizedBox(height: 20),
            _primaryButton(
              label: successMode ? '兑换成功' : (loading ? '验证中...' : '确认兑换'),
              enabled: !loading && !successMode,
              onTap: submit,
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result == true;
  }

  static Future<void> announcements(BuildContext context) async {
    // 默认展开第一条
    var selectedIndex = 0;
    final announcementsFuture = MineApi.getAnnouncements();

    await _show<void>(
      context,
      title: '系统公告',
      maxWidth: 460, // 稍微加宽，让阅读体验更好
      builder: (dialogContext, setState) {
        return FutureBuilder<List<MineAnnouncement>>(
          future: announcementsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return const SizedBox(
                height: 160,
                child: Center(
                  child: Text(
                    '公告加载失败',
                    style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13),
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <MineAnnouncement>[];
            if (items.isEmpty) {
              return const SizedBox(
                height: 160,
                child: Center(
                  child: Text(
                    '暂无系统公告',
                    style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13),
                  ),
                ),
              );
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final item = items[index];
                  final active = index == selectedIndex;
                  final dateStr = item.createdAt.contains('T')
                      ? item.createdAt.split('T').first
                      : item.createdAt;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          // 点击已展开的项则收起，点击未展开的项则展开
                          selectedIndex = active ? -1 : index;
                        });
                      },
                      borderRadius: BorderRadius.zero,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: active 
                              ? Colors.white.withOpacity(0.04) 
                              : Colors.white.withOpacity(0.015),
                          border: Border.all(
                            color: active 
                                ? AppColors.accent.withOpacity(0.4) 
                                : Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 标题 & 日期头部
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            color: active ? AppColors.accent : AppColors.textOnDark,
                                            fontSize: 14,
                                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                          ),
                                        ),
                                        if (dateStr.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              color: AppColors.textOnDarkMuted.withOpacity(0.7),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    active ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                    size: 18,
                                    color: active ? AppColors.accent : AppColors.textOnDarkMuted.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                            // 展开的正文内容
                            AnimatedSize(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: active
                                  ? Container(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                                      child: Text(
                                        item.content.isEmpty ? '暂无详细内容' : item.content,
                                        style: const TextStyle(
                                          color: AppColors.textOnDarkMuted,
                                          fontSize: 13,
                                          height: 1.65,
                                        ),
                                      ),
                                    )
                                  : const SizedBox(width: double.infinity, height: 0),
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
      },
    );
  }

  static Future<bool> feedback(BuildContext context) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    var loading = false;
    var successMode = false;
    String? error;

    final result = await _show<bool>(
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
            _input(
              controller: titleController,
              hint: '请概括您遇到的问题',
              enabled: !successMode,
            ),
            const SizedBox(height: 12),
            _input(
              controller: contentController,
              hint: '请提供更多细节描述...',
              maxLines: 5,
              enabled: !successMode,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _error(error!),
            ],
            const SizedBox(height: 20),
            _primaryButton(
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

  static Future<bool> confirmLogout(BuildContext context) async {
    return await _show<bool>(
          context,
          title: '退出登录',
          builder: (dialogContext, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '确定要退出当前账号吗？',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                _primaryButton(
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

    await _show<void>(
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

        if (loading) {
          return const SizedBox(
            height: 220,
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
            height: 130,
            child: Center(
              child: Text(
                errorText!,
                style: const TextStyle(
                  color: AppColors.textOnDarkMuted,
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
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.zero,
              child: InkWell(
                onTap: enableOwnKey ? null : chooseModel,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 62),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.1),
                          border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1),
                        ),
                        child: const Icon(LucideIcons.cpu, size: 16, color: AppColors.accent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '当前节点',
                              style: TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              enableOwnKey ? '自定义配置' : currentModelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textOnDarkMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: AppColors.textOnDarkMuted.withOpacity(enableOwnKey ? 0.25 : 0.70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '使用外部接口',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '启用后将覆盖默认配置',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enableOwnKey,
                    onChanged: toggling ? null : toggleOwnKey,
                    activeColor: AppColors.accent,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: enableOwnKey
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          _input(controller: baseUrlController, hint: '接口地址 (Base URL)', enabled: !saving && !successMode),
                          const SizedBox(height: 10),
                          _input(controller: modelController, hint: '模型名称 (Model ID)', enabled: !saving && !successMode),
                          const SizedBox(height: 10),
                          _input(controller: apiKeyController, hint: '接口密钥 (API Key)', enabled: !saving && !successMode, obscureText: true),
                          const SizedBox(height: 16),
                          _primaryButton(
                            label: successMode ? '连接成功' : (saving ? '验证中...' : '保存配置'),
                            enabled: !saving && !successMode,
                            onTap: saveCustomApi,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 14),
              _error(errorText!),
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
    return _show<ModelOption>(
      context,
      title: title,
      maxWidth: 410,
      builder: (dialogContext, setState) {
        if (models.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: Text(
                '暂无可用节点',
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
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
            itemCount: models.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = models[index];
              final selected = item.id == currentId;

              return Material(
                color: selected ? AppColors.accent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.zero,
                child: InkWell(
                  onTap: () => Navigator.of(dialogContext).pop(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected ? AppColors.accent : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            LucideIcons.check,
                            size: 16,
                            color: AppColors.accent,
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

  static Future<T?> _show<T>(
    BuildContext context, {
    required String title,
    required Widget Function(
      BuildContext context,
      StateSetter setState,
    ) builder,
    double maxWidth = 380,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.68),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                    ),
                    child: Container(
                      width: MediaQuery.sizeOf(context).width * 0.88,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: AppColors.textOnDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.of(dialogContext).pop(),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    color: Colors.transparent,
                                    child: const Icon(
                                      LucideIcons.x,
                                      size: 18,
                                      color: AppColors.textOnDarkMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            builder(dialogContext, setState),
                          ],
                        ),
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
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  static Widget _input({
    required TextEditingController controller,
    required String hint,
    bool autofocus = false,
    bool enabled = true,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        minLines: maxLines > 1 ? 4 : 1,
        textAlignVertical: maxLines == 1 ? TextAlignVertical.center : TextAlignVertical.top,
        cursorColor: AppColors.accent,
        style: const TextStyle(
          color: AppColors.textOnDark,
          fontSize: 13.5,
          height: 1.5,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: const TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 13,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  static Widget _primaryButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger
        ? const Color(0xFFE0554A)
        : enabled
            ? AppColors.accent
            : Colors.white.withOpacity(0.06);

    return Material(
      color: color,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: (danger || !enabled) ? AppColors.textOnDarkMuted : const Color(0xFF121212),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _error(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE0554A).withOpacity(0.08),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: const Color(0xFFE0554A).withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, size: 16, color: Color(0xFFE0554A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFE0554A),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
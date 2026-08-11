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
            const SizedBox(height: 18),
            _primaryButton(
              label: saving ? '保存中…' : '保存',
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

  static Future<String?> editAvatar(BuildContext context) async {
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

    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _toast(context, '无法读取图片', isError: true);
      return null;
    }

    var uploading = false;
    String? error;

    return _show<String>(
      context,
      title: '修改头像',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          if (uploading) return;
          setState(() {
            uploading = true;
            error = null;
          });
          try {
            final url = await MineApi.uploadAndUpdateAvatar(
              bytes: bytes,
              filename: file.name.isEmpty ? 'avatar.jpg' : file.name,
            );
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(url);
            }
          } on ApiException catch (e) {
            setState(() {
              uploading = false;
              error = e.message;
            });
          } catch (_) {
            setState(() {
              uploading = false;
              error = '头像上传失败';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.memory(
                Uint8List.fromList(bytes),
                width: 112,
                height: 112,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '确认使用这张图片作为头像',
              style: TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: 12,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _error(error!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: _primaryButton(
                label: uploading ? '上传中…' : '确认',
                enabled: !uploading,
                onTap: submit,
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<MineCheckinResult?> checkin(BuildContext context) async {
    MineCheckinStatus? status;
    var loading = true;
    var submitting = false;
    String? error;

    return _show<MineCheckinResult>(
      context,
      title: '签到',
      maxWidth: 410,
      builder: (dialogContext, setState) {
        if (loading && status == null && error == null) {
          MineApi.getCheckinStatus().then((value) {
            if (!dialogContext.mounted) return;
            setState(() {
              status = value;
              loading = false;
            });
          }).catchError((_) {
            if (!dialogContext.mounted) return;
            setState(() {
              loading = false;
              error = '签到状态加载失败';
            });
          });
        }

        Future<void> submit() async {
          if (submitting || status?.checkedInToday == true) return;

          setState(() {
            submitting = true;
            error = null;
          });

          try {
            final result = await MineApi.dailyCheckin();
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop(result);
          } on ApiException catch (e) {
            if (!dialogContext.mounted) return;
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

        if (loading) {
          return const SizedBox(
            height: 250,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          );
        }

        final checked = status?.checkedInToday ?? false;
        final days = status?.days ?? const <String>[];
        final now = DateTime.now();
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final firstWeekday = DateTime(now.year, now.month, 1).weekday;
        final leadingEmpty = firstWeekday - 1;
        final progress = daysInMonth == 0
            ? 0.0
            : (days.length / daysInMonth).clamp(0.0, 1.0);
        final monthPrefix =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-';
        const weekLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.025),
                border: Border.all(
                  color: Colors.white.withOpacity(0.06),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${now.month} 月签到',
                          style: const TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '本月已签到 ${days.length} 天',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 10.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: checked
                          ? AppColors.accent.withOpacity(0.10)
                          : Colors.white.withOpacity(0.035),
                      border: Border.all(
                        color: checked
                            ? AppColors.accent.withOpacity(0.18)
                            : Colors.white.withOpacity(0.06),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      checked ? '今日已签到' : '今日待签到',
                      style: TextStyle(
                        color: checked
                            ? AppColors.accent
                            : AppColors.textOnDarkMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.055),
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                for (final label in weekLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: AppColors.textOnDarkMuted.withOpacity(0.72),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingEmpty + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                childAspectRatio: 1.08,
              ),
              itemBuilder: (_, index) {
                if (index < leadingEmpty) {
                  return const SizedBox.shrink();
                }

                final day = index - leadingEmpty + 1;
                final value = '$monthPrefix${day.toString().padLeft(2, '0')}';
                final done = days.contains(value);
                final today = now.day == day;

                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.accent.withOpacity(0.11)
                        : Colors.white.withOpacity(0.018),
                    border: Border.all(
                      color: done
                          ? AppColors.accent.withOpacity(0.24)
                          : today
                              ? Colors.white.withOpacity(0.22)
                              : Colors.white.withOpacity(0.045),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: done
                      ? const Icon(
                          LucideIcons.check,
                          size: 12,
                          color: AppColors.accent,
                        )
                      : Text(
                          '$day',
                          style: TextStyle(
                            color: today
                                ? AppColors.textOnDark
                                : AppColors.textOnDarkMuted,
                            fontSize: 9.5,
                            fontWeight: today
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                );
              },
            ),

            if (error != null) ...[
              const SizedBox(height: 10),
              _error(error!),
            ],

            const SizedBox(height: 16),

            if (checked)
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.025),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.055),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '今天已完成签到',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              _primaryButton(
                label: submitting ? '签到中…' : '立即签到',
                enabled: !submitting,
                onTap: submit,
              ),
          ],
        );
      },
    );
  }

  static Future<bool> redeem(BuildContext context) async {
    final controller = TextEditingController();
    var loading = false;
    String? error;

    final result = await _show<bool>(
      context,
      title: '兑换码',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final code = controller.text.trim();
          if (code.isEmpty || loading) return;
          setState(() {
            loading = true;
            error = null;
          });
          try {
            await MineApi.redeemCode(code);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } on ApiException catch (e) {
            setState(() {
              loading = false;
              error = e.message;
            });
          } catch (_) {
            setState(() {
              loading = false;
              error = '兑换失败，请检查兑换码';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _input(
              controller: controller,
              hint: '输入兑换码',
              autofocus: true,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _error(error!),
            ],
            const SizedBox(height: 18),
            _primaryButton(
              label: loading ? '兑换中…' : '确认兑换',
              enabled: !loading,
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
    var selectedIndex = 0;
    final announcementsFuture = MineApi.getAnnouncements();

    await _show<void>(
      context,
      title: '公告',
      maxWidth: 430,
      builder: (dialogContext, setState) {
        return FutureBuilder<List<MineAnnouncement>>(
          future: announcementsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 230,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return SizedBox(
                height: 160,
                child: Center(
                  child: Text(
                    '公告加载失败',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <MineAnnouncement>[];
            if (items.isEmpty) {
              return SizedBox(
                height: 150,
                child: Center(
                  child: Text(
                    '暂无公告',
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              );
            }

            if (selectedIndex >= items.length) selectedIndex = 0;
            final selected = items[selectedIndex];
            final selectedDate = selected.createdAt.contains('T')
                ? selected.createdAt.split('T').first
                : selected.createdAt;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 18),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final active = index == selectedIndex;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() {
                            selectedIndex = index;
                          }),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 150),
                            padding: const EdgeInsets.only(
                              left: 1,
                              right: 1,
                              top: 3,
                              bottom: 7,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: active
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? AppColors.textOnDark
                                    : AppColors.textOnDarkMuted,
                                fontSize: 11.5,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  constraints: const BoxConstraints(
                    minHeight: 190,
                    maxHeight: 360,
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.022),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.055),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Column(
                        key: ValueKey(selectedIndex),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.title,
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (selectedDate.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              selectedDate,
                              style: TextStyle(
                                color: AppColors.textOnDarkMuted,
                                fontSize: 9.8,
                              ),
                            ),
                          ],
                          const SizedBox(height: 13),
                          Text(
                            selected.content.isEmpty
                                ? '暂无详细内容'
                                : selected.content,
                            style: TextStyle(
                              color: AppColors.textOnDarkMuted,
                              fontSize: 11.8,
                              height: 1.65,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
    String? error;

    final result = await _show<bool>(
      context,
      title: '帮助与反馈',
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final title = titleController.text.trim();
          final content = contentController.text.trim();
          if (loading) return;
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
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } on ApiException catch (e) {
            setState(() {
              loading = false;
              error = e.message;
            });
          } catch (_) {
            setState(() {
              loading = false;
              error = '发送失败，请稍后重试';
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _input(
              controller: titleController,
              hint: '问题标题',
            ),
            const SizedBox(height: 10),
            _input(
              controller: contentController,
              hint: '详细描述',
              maxLines: 5,
              height: 120,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _error(error!),
            ],
            const SizedBox(height: 18),
            _primaryButton(
              label: loading ? '发送中…' : '提交反馈',
              enabled: !loading,
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
                Text(
                  '确定退出当前账号？',
                  style: TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 18),
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

  /// API 设置：保留模型选择与自定义 API。
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
    String? errorText;
    var selectedModelId = '';
    var models = <ModelOption>[];

    String modelNameFor(String id) {
      if (id.trim().isEmpty) return '未选择';
      for (final item in models) {
        if (item.id == id) return item.name;
      }
      final parts = id.split('/');
      return parts.isEmpty ? id : parts.last;
    }

    await _show<void>(
      context,
      title: 'API 设置',
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
                errorText = '配置加载失败';
              });
            }
          });
        }

        Future<void> chooseModel() async {
          if (enableOwnKey || models.isEmpty) return;

          final selected = await _pickModel(
            dialogContext,
            title: '选择模型',
            models: models,
            currentId: selectedModelId,
          );
          if (!dialogContext.mounted || selected == null) return;

          try {
            await ModelConfigApi.updateScenePreference(
              'novel',
              selected.id,
            );
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
            setState(() => errorText = '模型保存失败');
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
          if (!enableOwnKey || saving) return;

          final apiKey = apiKeyController.text.trim();
          final baseUrl = baseUrlController.text.trim();
          final modelName = modelController.text.trim();

          if (apiKey.isEmpty || baseUrl.isEmpty || modelName.isEmpty) {
            setState(() => errorText = '请填写完整配置');
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
                errorText = '连接验证失败，请检查配置';
              });
              return;
            }

            await ModelConfigApi.saveCustomApi(
              apiKey: apiKey,
              baseUrl: baseUrl,
              modelName: modelName,
            );

            if (!dialogContext.mounted) return;
            setState(() => saving = false);
            _toast(dialogContext, '配置已保存并启用');
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
              errorText = '网络异常';
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
                style: TextStyle(
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
              color: Colors.white.withOpacity(0.025),
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enableOwnKey ? null : chooseModel,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 62),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          LucideIcons.sparkles,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '模型选择',
                              style: TextStyle(
                                color: AppColors.textOnDark,
                                fontSize: 12.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              enableOwnKey
                                  ? '自定义 API 已启用'
                                  : currentModelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textOnDarkMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 15,
                        color: AppColors.textOnDarkMuted.withOpacity(
                          enableOwnKey ? 0.25 : 0.70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.018),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '自定义 API',
                          style: TextStyle(
                            color: AppColors.textOnDark,
                            fontSize: 12.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '使用自己的 OpenAI 兼容接口',
                          style: TextStyle(
                            color: AppColors.textOnDarkMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enableOwnKey,
                    onChanged: toggling ? null : toggleOwnKey,
                    activeColor: AppColors.accent,
                  ),
                ],
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: enableOwnKey
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          _input(
                            controller: baseUrlController,
                            hint: 'Base URL',
                            enabled: !saving,
                          ),
                          const SizedBox(height: 9),
                          _input(
                            controller: modelController,
                            hint: 'Model ID',
                            enabled: !saving,
                          ),
                          const SizedBox(height: 9),
                          _input(
                            controller: apiKeyController,
                            hint: 'API Key',
                            enabled: !saving,
                            obscureText: true,
                          ),
                          const SizedBox(height: 14),
                          _primaryButton(
                            label: saving ? '验证并保存中…' : '验证并保存',
                            enabled: !saving,
                            onTap: saveCustomApi,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (errorText != null) ...[
              const SizedBox(height: 10),
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
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                '暂无可用模型',
                style: TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 12,
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
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final item = models[index];
              final selected = item.id == currentId;

              return Material(
                color: selected
                    ? AppColors.accent.withOpacity(0.07)
                    : Colors.white.withOpacity(0.018),
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(dialogContext).pop(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected
                            ? AppColors.accent.withOpacity(0.20)
                            : Colors.white.withOpacity(0.05),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.textOnDark
                                  : AppColors.textOnDark,
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            LucideIcons.check,
                            size: 15,
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

  static Widget _settingsRow({
    required String title,
    required String trailing,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textOnDark,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.textOnDarkMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: AppColors.textOnDarkMuted.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  static Future<void> simplePending(
    BuildContext context, {
    required String title,
  }) async {
    await _show<void>(
      context,
      title: title,
      builder: (_, __) {
        return Text(
          '入口已保留，等对应接口代码接入后直接补功能。',
          style: TextStyle(
            color: AppColors.textOnDarkMuted,
            fontSize: 12,
            height: 1.6,
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
    double maxWidth = 390,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withOpacity(0.48),
      transitionDuration: const Duration(milliseconds: 180),
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
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161616),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.30),
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
                            SizedBox(
                              height: 30,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 38),
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.textOnDark,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    child: InkResponse(
                                      onTap: () => Navigator.of(dialogContext).pop(),
                                      radius: 20,
                                      child: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: Center(
                                          child: Icon(
                                            LucideIcons.x,
                                            size: 17,
                                            color: AppColors.textOnDarkMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
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
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(
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
  }

  static Widget _input({
    required TextEditingController controller,
    required String hint,
    bool autofocus = false,
    bool enabled = true,
    bool obscureText = false,
    int maxLines = 1,
    double height = 48,
  }) {
    return Container(
      height: height,
      alignment: maxLines == 1 ? Alignment.center : Alignment.topCenter,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        textAlignVertical: maxLines == 1
            ? TextAlignVertical.center
            : TextAlignVertical.top,
        cursorColor: AppColors.accent,
        style: TextStyle(
          color: enabled
              ? AppColors.textOnDark
              : AppColors.textOnDarkMuted.withOpacity(0.45),
          fontSize: 13.5,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.textOnDarkMuted.withOpacity(0.65),
            fontSize: 12.5,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: maxLines > 1
              ? const EdgeInsets.symmetric(vertical: 13)
              : EdgeInsets.zero,
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
            : AppColors.accent.withOpacity(0.18);

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF101010),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _error(String message) {
    return Text(
      message,
      style: const TextStyle(
        color: Color(0xFFE7685E),
        fontSize: 11.5,
      ),
    );
  }

  static void _toast(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF161616),
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
            style: TextStyle(
              color: isError
                  ? const Color(0xFFE7685E)
                  : AppColors.textOnDark,
            ),
          ),
        ),
      );
  }
}

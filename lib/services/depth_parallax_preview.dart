import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'depth_service.dart';

enum _DepthPreviewMode { original, depth, parallax }

/// Developer-only laboratory for validating the full visual chain:
/// local image -> Depth Anything V2 -> depth texture -> GPU parallax shader.
///
/// Desktop/web input uses mouse hover/drag. Touch devices use pointer movement.
/// The production Android/iOS background can later feed gyroscope values into
/// the same `viewX/viewY` shader inputs.
class DepthParallaxPreviewPage extends StatefulWidget {
  const DepthParallaxPreviewPage({super.key});

  @override
  State<DepthParallaxPreviewPage> createState() =>
      _DepthParallaxPreviewPageState();
}

class _DepthParallaxPreviewPageState extends State<DepthParallaxPreviewPage> {
  Uint8List? _sourceBytes;
  String _fileName = '';

  ui.Image? _sourceImage;
  ui.Image? _depthImage;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  _DepthPreviewMode _mode = _DepthPreviewMode.original;
  bool _picking = false;
  bool _warmingModel = false;
  bool _generating = false;
  String _status = '上传一张剧情背景图开始测试';
  bool _statusIsError = false;
  int? _lastInferenceMs;

  double _viewX = 0;
  double _viewY = 0;
  double _strength = 1.0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadShader());
    unawaited(_warmDepthModel());
  }

  Future<void> _warmDepthModel() async {
    if (_warmingModel || DepthService.instance.isReady) return;
    if (mounted) {
      setState(() {
        _warmingModel = true;
        _status = '正在预热 Depth Anything V2…';
        _statusIsError = false;
      });
    }
    try {
      await DepthService.instance.warmUp();
      if (!mounted || _sourceImage != null) return;
      setState(() {
        _status = '模型已就绪 · 上传一张剧情背景图开始测试';
        _statusIsError = false;
      });
    } catch (error, stack) {
      if (!mounted || _sourceImage != null) return;
      setState(() {
        _status = _formatErrorDetails(
          '模型预热失败',
          error,
          stack,
          hint: kIsWeb
              ? '请先给 web/index.html 加 ONNX Runtime Web 脚本。'
              : null,
        );
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _warmingModel = false);
    }
  }

  Future<void> _loadShader() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/depth_parallax.frag');
      if (!mounted) return;
      _program = program;
      _shader?.dispose();
      _shader = program.fragmentShader();
      setState(() {});
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _status = _formatErrorDetails('3D Shader 加载失败', error, stack);
        _statusIsError = true;
      });
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _pickImage() async {
    if (_picking || _generating) return;
    setState(() => _picking = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (!mounted || file == null || bytes == null || bytes.isEmpty) return;

      final sourceImage = await _decodeUiImage(bytes);
      if (!mounted) {
        sourceImage.dispose();
        return;
      }

      _sourceImage?.dispose();
      _depthImage?.dispose();
      _sourceImage = sourceImage;
      _depthImage = null;
      _sourceBytes = bytes;
      _fileName = file.name;
      _mode = _DepthPreviewMode.original;
      _viewX = 0;
      _viewY = 0;
      _lastInferenceMs = null;
      _statusIsError = false;
      _status = '原图已显示 · 正在生成 Depth…';
      setState(() {});

      // Give Flutter one frame to paint the source image before model loading
      // and preprocessing begin. The preview therefore never feels like a
      // black loading screen.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!mounted) return;
      await _generateDepth(bytes);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _status = _formatErrorDetails('选择图片失败', error, stack);
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _generateDepth(Uint8List bytes) async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _status = 'Depth Anything V2 正在本地计算…';
      _statusIsError = false;
    });

    final watch = Stopwatch()..start();
    try {
      final result = await DepthService.instance.generate(bytes);
      watch.stop();
      final depthImage = await _decodeUiImage(result.depthPng);

      if (!mounted) {
        depthImage.dispose();
        return;
      }

      _depthImage?.dispose();
      _depthImage = depthImage;
      _lastInferenceMs = watch.elapsedMilliseconds;
      _mode = _DepthPreviewMode.parallax;
      _status =
          'Depth 完成 ${watch.elapsedMilliseconds}ms · 移动鼠标 / 手指看 2.5D';
      _statusIsError = false;
    } catch (error, stack) {
      watch.stop();
      if (!mounted) return;
      _status = _formatErrorDetails(
        kIsWeb ? 'Chrome 深度推理失败' : 'Depth 推理失败',
        error,
        stack,
        hint: kIsWeb
            ? '先确认 web/index.html 已加载 onnxruntime-web 1.23.0；Chrome 建议开启 WebGPU。'
            : null,
      );
      _statusIsError = true;
      _mode = _DepthPreviewMode.original;
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _updateView(Offset localPosition, Size size) {
    if (_mode != _DepthPreviewMode.parallax ||
        _depthImage == null ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final x = ((localPosition.dx / size.width) * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();
    final y = ((localPosition.dy / size.height) * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();

    // Small low-pass filter: responsive enough for mouse/touch but avoids the
    // depth image looking nervous on tiny pointer movements.
    setState(() {
      _viewX = _viewX * .66 + x * .34;
      _viewY = _viewY * .66 + y * .34;
    });
  }

  void _resetView() {
    if (_viewX == 0 && _viewY == 0) return;
    setState(() {
      _viewX = 0;
      _viewY = 0;
    });
  }

  String _formatErrorDetails(
    String title,
    Object error,
    StackTrace stack, {
    String? hint,
  }) {
    final buffer = StringBuffer()..writeln('$title：$error');
    if (hint != null && hint.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(hint.trim());
    }

    final stackText = stack.toString().trim();
    if (stackText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stack trace:')
        ..write(stackText);
    }
    return buffer.toString();
  }

  Future<void> _copyStatus() async {
    await Clipboard.setData(ClipboardData(text: _status));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('完整报错已复制'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Widget _buildStatusMessage() {
    final style = TextStyle(
      color: _statusIsError
          ? const Color(0xFFFF9A9A)
          : Colors.white.withOpacity(.60),
      fontSize: 9.8,
      height: 1.45,
    );

    if (!_statusIsError) {
      return Text(
        _status,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9A9A).withOpacity(.055),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFF9A9A).withOpacity(.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                child: SelectableText(
                  _status,
                  style: style,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '复制完整报错',
            onPressed: _copyStatus,
            icon: const Icon(Icons.copy_rounded, size: 16),
            color: const Color(0xFFFFB0B0),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sourceImage?.dispose();
    _depthImage?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  Widget _buildImageSurface(BoxConstraints constraints) {
    final source = _sourceImage;
    if (source == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.view_in_ar_outlined,
              size: 46,
              color: Colors.white.withOpacity(.34),
            ),
            const SizedBox(height: 14),
            Text(
              '上传图片后自动生成 Depth\n然后移动鼠标或手指查看景深视差',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(.58),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _picking ? null : _pickImage,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('上传测试图片'),
            ),
          ],
        ),
      );
    }

    final sourceAspect = source.width / source.height;
    final maxW = math.max(1.0, constraints.maxWidth - 24);
    final maxH = math.max(1.0, constraints.maxHeight - 24);
    var width = maxW;
    var height = width / sourceAspect;
    if (height > maxH) {
      height = maxH;
      width = height * sourceAspect;
    }
    final previewSize = Size(width, height);

    Widget image;
    switch (_mode) {
      case _DepthPreviewMode.original:
        image = RawImage(
          image: source,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        );
        break;
      case _DepthPreviewMode.depth:
        final depth = _depthImage;
        image = depth == null
            ? _EmptyDepthSurface(generating: _generating)
            : RawImage(
                image: depth,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              );
        break;
      case _DepthPreviewMode.parallax:
        final depth = _depthImage;
        final shader = _shader;
        image = depth == null || shader == null
            ? RawImage(
                image: source,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              )
            : CustomPaint(
                painter: _DepthParallaxPainter(
                  shader: shader,
                  source: source,
                  depth: depth,
                  viewX: _viewX,
                  viewY: _viewY,
                  strength: _strength,
                ),
              );
        break;
    }

    return Center(
      child: MouseRegion(
        onHover: (event) => _updateView(event.localPosition, previewSize),
        onExit: (_) => _resetView(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove: (event) => _updateView(event.localPosition, previewSize),
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRect(
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFF080A0D)),
                child: image,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeButton(_DepthPreviewMode mode, String label) {
    final enabled = mode == _DepthPreviewMode.original || _depthImage != null;
    final selected = _mode == mode;
    return SizedBox(
      height: 34,
      child: selected
          ? FilledButton(
              onPressed: enabled ? () => setState(() => _mode = mode) : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 13),
              ),
              child: Text(label, style: const TextStyle(fontSize: 11)),
            )
          : OutlinedButton(
              onPressed: enabled ? () => setState(() => _mode = mode) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                foregroundColor: Colors.white.withOpacity(.78),
                side: BorderSide(color: Colors.white.withOpacity(.14)),
              ),
              child: Text(label, style: const TextStyle(fontSize: 11)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '2.5D 深度预览',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _picking || _generating ? null : _pickImage,
            icon: const Icon(Icons.upload_rounded, size: 17),
            label: Text(_sourceImage == null ? '上传图片' : '换图'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _buildImageSurface(constraints),
                    if (_generating)
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.58),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: Colors.white.withOpacity(.10),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.4,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '正在生成 Depth…',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.86),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF101319),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(.08)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _modeButton(_DepthPreviewMode.original, '原图'),
                      const SizedBox(width: 7),
                      _modeButton(_DepthPreviewMode.depth, 'Depth'),
                      const SizedBox(width: 7),
                      _modeButton(_DepthPreviewMode.parallax, '2.5D'),
                      const Spacer(),
                      IconButton(
                        tooltip: '镜头归中',
                        onPressed: _resetView,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        color: Colors.white.withOpacity(.72),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Text(
                        '视差强度',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.66),
                          fontSize: 10.5,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _strength,
                          min: .15,
                          max: 1.5,
                          onChanged: (value) =>
                              setState(() => _strength = value),
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          _strength.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.72),
                            fontSize: 10.5,
                            fontFeatures: const <ui.FontFeature>[
                              ui.FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  _buildStatusMessage(),
                  if (_fileName.isNotEmpty || _lastInferenceMs != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (_fileName.isNotEmpty) _fileName,
                        if (_lastInferenceMs != null)
                          'inference ${_lastInferenceMs}ms',
                        if (kIsWeb) 'Chrome/WebGPU 优先',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.34),
                        fontSize: 9.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDepthSurface extends StatelessWidget {
  const _EmptyDepthSurface({required this.generating});

  final bool generating;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF11151B),
      child: Center(
        child: Text(
          generating ? 'Depth 生成中…' : '还没有 Depth',
          style: TextStyle(
            color: Colors.white.withOpacity(.45),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _DepthParallaxPainter extends CustomPainter {
  const _DepthParallaxPainter({
    required this.shader,
    required this.source,
    required this.depth,
    required this.viewX,
    required this.viewY,
    required this.strength,
  });

  final ui.FragmentShader shader;
  final ui.Image source;
  final ui.Image depth;
  final double viewX;
  final double viewY;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, viewX);
    shader.setFloat(3, viewY);
    shader.setFloat(4, strength);
    shader.setFloat(5, 1.045 + strength * .035);
    shader.setImageSampler(0, source);
    shader.setImageSampler(1, depth);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _DepthParallaxPainter oldDelegate) {
    return oldDelegate.source != source ||
        oldDelegate.depth != depth ||
        oldDelegate.viewX != viewX ||
        oldDelegate.viewY != viewY ||
        oldDelegate.strength != strength ||
        oldDelegate.shader != shader;
  }
}

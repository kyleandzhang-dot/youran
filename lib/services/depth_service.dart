import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Depth Anything V2 Small (ONNX) local inference service.
///
/// Expected model asset:
///   assets/models/model_fp16.onnx
///
/// The service:
/// 1. decodes an image;
/// 2. resizes it while preserving aspect ratio (multiple of 14);
/// 3. applies ImageNet normalization;
/// 4. runs Depth Anything V2 locally with ONNX Runtime;
/// 5. returns a normalized grayscale depth PNG and raw normalized depth values.
class DepthService {
  DepthService._();

  static final DepthService instance = DepthService._();

  static const String modelAsset = 'assets/models/model_fp16.onnx';

  static const int _targetSize = 518;
  static const int _patchMultiple = 14;

  static const List<double> _mean = <double>[0.485, 0.456, 0.406];
  static const List<double> _std = <double>[0.229, 0.224, 0.225];

  final OnnxRuntime _runtime = OnnxRuntime();

  OrtSession? _session;
  Future<void>? _initializing;

  bool get isReady => _session != null;

  /// Loads the ONNX model once. Safe to call repeatedly.
  Future<void> warmUp() {
    if (_session != null) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (kIsWeb) {
        _session = await _createWebSession();
        return;
      }

      final available = await _runtime.getAvailableProviders();
      final preferredOrder = <OrtProvider>[
        OrtProvider.CORE_ML,
        OrtProvider.NNAPI,
        OrtProvider.DIRECT_ML,
        OrtProvider.XNNPACK,
        OrtProvider.CPU,
      ];
      final providers = preferredOrder
          .where(available.contains)
          .toList(growable: false);

      try {
        _session = await _runtime.createSessionFromAsset(
          modelAsset,
          options: providers.isEmpty
              ? null
              : OrtSessionOptions(
                  providers: providers,
                  intraOpNumThreads: 2,
                  interOpNumThreads: 1,
                ),
        );
      } catch (_) {
        _session = await _runtime.createSessionFromAsset(modelAsset);
      }
    } finally {
      _initializing = null;
    }
  }

  Future<OrtSession> _createWebSession() async {
    final available = await _runtime.getAvailableProviders();
    if (!available.contains(OrtProvider.WEB_GPU)) {
      throw UnsupportedError(
        '当前 Chrome 没有可用 WebGPU。请确认使用较新的 Chrome/Edge，并检查 chrome://gpu。',
      );
    }

    // flutter_onnxruntime 1.8.4 的 Web 实现会把传入路径直接交给
    // ort.InferenceSession.create()，不会经过 Flutter rootBundle。
    // Flutter Web 的项目资源在不同运行/构建模式下可能表现为这两种 URL，
    // 因此开发预览依次尝试，避免 asset key 与浏览器 URL 不一致。
    const candidates = <String>[
      'assets/assets/models/model_fp16.onnx',
      'assets/models/model_fp16.onnx',
    ];

    Object? lastError;
    for (final path in candidates) {
      try {
        return await _runtime.createSession(
          path,
          options: OrtSessionOptions(
            providers: const <OrtProvider>[OrtProvider.WEB_GPU],
          ),
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'WebGPU 模型会话创建失败。已尝试：${candidates.join(', ')}。最后错误：$lastError',
    );
  }

  /// Generates a depth map from [imageBytes].
  ///
  /// The returned [DepthResult.normalizedDepth] is 0..1 where larger values
  /// represent nearer areas for the Depth Anything V2 relative-depth output.
  /// [DepthResult.depthPng] is a grayscale preview: white = near, black = far.
  Future<DepthResult> generate(Uint8List imageBytes) async {
    await warmUp();
    final session = _session;
    if (session == null) {
      throw StateError('Depth Anything model failed to initialize.');
    }

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or damaged image data.');
    }
    // Respect JPEG/HEIF orientation metadata before calculating the model size.
    final source = img.bakeOrientation(decoded);

    final inputSize = _calculateInputSize(source.width, source.height);
    final resized = img.copyResize(
      source,
      width: inputSize.width,
      height: inputSize.height,
      interpolation: img.Interpolation.cubic,
    );

    final inputData = _toNormalizedChw(resized);
    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;

    final inputValue = await OrtValue.fromList(
      inputData,
      <int>[1, 3, resized.height, resized.width],
    );

    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run(<String, OrtValue>{inputName: inputValue});

      final output = outputs[outputName];
      if (output == null) {
        throw StateError('Depth model returned no output named "$outputName".');
      }

      final flatRaw = await output.asFlattenedList();
      final shape = output.shape;
      final dimensions = _depthDimensions(shape, flatRaw.length);

      if (dimensions.width * dimensions.height != flatRaw.length) {
        throw StateError(
          'Unexpected depth output: shape=$shape, values=${flatRaw.length}.',
        );
      }

      final normalized = _normalizeDepth(flatRaw);
      final preview = _makeDepthPreview(
        normalized,
        dimensions.width,
        dimensions.height,
      );

      return DepthResult(
        depthPng: preview,
        normalizedDepth: normalized,
        width: dimensions.width,
        height: dimensions.height,
        sourceWidth: source.width,
        sourceHeight: source.height,
      );
    } finally {
      await inputValue.dispose();
      if (outputs != null) {
        for (final value in outputs.values) {
          await value.dispose();
        }
      }
    }
  }

  /// Convenience method for the first test screen.
  ///
  /// Usage:
  ///   final png = await DepthService.instance.generatePng(bytes);
  ///   Image.memory(png);
  Future<Uint8List> generatePng(Uint8List imageBytes) async {
    return (await generate(imageBytes)).depthPng;
  }

  /// Releases the model session. Normally only needed when the app/service is
  /// being torn down permanently.
  Future<void> dispose() async {
    final session = _session;
    _session = null;
    if (session != null) {
      await session.close();
    }
  }

  _ImageSize _calculateInputSize(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image width and height must be positive.');
    }

    // Matches the Depth Anything / DPT "lower bound" behavior:
    // the shorter limiting scale reaches 518 while preserving aspect ratio,
    // then both dimensions are rounded to a multiple of the 14px ViT patch.
    final scaleWidth = _targetSize / width;
    final scaleHeight = _targetSize / height;
    final scale = math.max(scaleWidth, scaleHeight);

    var targetWidth = _roundToMultiple(width * scale, _patchMultiple);
    var targetHeight = _roundToMultiple(height * scale, _patchMultiple);

    // Guard against unusual ultra-wide/tall images consuming excessive memory.
    // This still keeps dimensions valid multiples of 14.
    const maxLongEdge = 1036; // 2 x 518
    final longEdge = math.max(targetWidth, targetHeight);
    if (longEdge > maxLongEdge) {
      final downScale = maxLongEdge / longEdge;
      targetWidth = math.max(
        _patchMultiple,
        _roundToMultiple(targetWidth * downScale, _patchMultiple),
      );
      targetHeight = math.max(
        _patchMultiple,
        _roundToMultiple(targetHeight * downScale, _patchMultiple),
      );
    }

    return _ImageSize(targetWidth, targetHeight);
  }

  int _roundToMultiple(num value, int multiple) {
    return math.max(multiple, (value / multiple).round() * multiple);
  }

  Float32List _toNormalizedChw(img.Image image) {
    final planeSize = image.width * image.height;
    final data = Float32List(planeSize * 3);
    final pixel = image.getPixelSafe(0, 0);

    var index = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.getPixel(x, y, pixel);

        final r = pixel.r.toDouble() / 255.0;
        final g = pixel.g.toDouble() / 255.0;
        final b = pixel.b.toDouble() / 255.0;

        data[index] = (r - _mean[0]) / _std[0];
        data[planeSize + index] = (g - _mean[1]) / _std[1];
        data[(planeSize * 2) + index] = (b - _mean[2]) / _std[2];
        index++;
      }
    }

    return data;
  }

  _ImageSize _depthDimensions(List<int> shape, int valueCount) {
    // Expected Depth Anything output is [1, H, W]. Some exports use
    // [1, 1, H, W], so support both.
    if (shape.length >= 2) {
      final width = shape.last;
      final height = shape[shape.length - 2];
      if (width > 0 && height > 0 && width * height == valueCount) {
        return _ImageSize(width, height);
      }
    }

    // Fallback only for a square tensor. This should normally never be needed.
    final side = math.sqrt(valueCount).round();
    if (side * side == valueCount) {
      return _ImageSize(side, side);
    }

    throw StateError('Cannot determine depth output dimensions: shape=$shape.');
  }

  Float32List _normalizeDepth(List raw) {
    if (raw.isEmpty) {
      throw StateError('Depth model returned an empty tensor.');
    }

    var minValue = double.infinity;
    var maxValue = double.negativeInfinity;

    for (final value in raw) {
      final v = (value as num).toDouble();
      if (!v.isFinite) continue;
      if (v < minValue) minValue = v;
      if (v > maxValue) maxValue = v;
    }

    if (!minValue.isFinite || !maxValue.isFinite) {
      throw StateError('Depth model returned only invalid values.');
    }

    final range = maxValue - minValue;
    final normalized = Float32List(raw.length);
    if (range.abs() < 1e-12) {
      normalized.fillRange(0, normalized.length, 0.5);
      return normalized;
    }

    for (var i = 0; i < raw.length; i++) {
      final v = (raw[i] as num).toDouble();
      normalized[i] = v.isFinite
          ? ((v - minValue) / range).clamp(0.0, 1.0).toDouble()
          : 0.0;
    }

    return normalized;
  }

  Uint8List _makeDepthPreview(
    Float32List depth,
    int width,
    int height,
  ) {
    final output = img.Image(width: width, height: height, numChannels: 3);

    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final value = (depth[row + x] * 255.0).round().clamp(0, 255);
        output.setPixelRgb(x, y, value, value, value);
      }
    }

    return img.encodePng(output, level: 4);
  }
}

class DepthResult {
  const DepthResult({
    required this.depthPng,
    required this.normalizedDepth,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  /// Grayscale PNG preview, white = nearer, black = farther.
  final Uint8List depthPng;

  /// Row-major normalized relative depth, range 0..1.
  /// Length is [width] * [height].
  final Float32List normalizedDepth;

  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
}

class _ImageSize {
  const _ImageSize(this.width, this.height);

  final int width;
  final int height;
}

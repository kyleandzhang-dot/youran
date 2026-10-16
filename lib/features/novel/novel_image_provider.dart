import 'package:flutter/painting.dart';

/// 剧情背景 / 分镜 CG 的统一图片入口。
///
/// precache、Image 组件、Depth 取像素、controller 预热 **必须全部走这里**，
/// 否则 ImageCache 的 key 不一致，同一张图会被重复下载 + 重复解码。
class NovelImageProvider {
  NovelImageProvider._();

  /// 解码时长边上限（物理像素）。原图更大也只解码到这个尺寸，
  /// 减少解码耗时和 GPU/内存占用；原图不够大则不会放大（不 upscale）。
  /// 固定常量而不是随屏幕变化，保证各处 ImageCache key 永远一致。
  static const int maxDecodeEdge = 2048;

  /// 完整图：下载原文件，但只解码到 [maxDecodeEdge]。
  static ImageProvider network(String url) {
    // 想要磁盘缓存（重启 App 不再重新下载）：
    // pubspec 加 cached_network_image，把下面的 NetworkImage(url)
    // 换成 CachedNetworkImageProvider(url) 即可，其它地方不用动。
    return ResizeImage(
      NetworkImage(url),
      width: maxDecodeEdge,
      height: maxDecodeEdge,
      policy: ResizeImagePolicy.fit,
    );
  }

  /// 【需要你补】由完整图 URL 推出小图 URL。返回 null = 没有小图，走单段加载。
  ///
  /// 小图建议：长边 ~480px、WebP、20~40KB，和完整图同时生成。
  /// 常见写法（按你后端实际命名改）：
  ///   a) 命名约定：  https://cdn/x/abc.png  ->  https://cdn/x/abc_thumb.webp
  ///      return url.replaceFirst(RegExp(r'\.(png|jpe?g|webp)(\?.*)?$'), '_thumb.webp');
  ///   b) Cloudflare Image Resizing：
  ///      return 'https://你的域名/cdn-cgi/image/width=480,format=webp/$path';
  static String? thumbUrlFor(String url) => null;

  /// 小图 provider；没有小图规则时返回 null。
  static ImageProvider? thumb(String url) {
    final t = thumbUrlFor(url)?.trim();
    if (t == null || t.isEmpty || t == url) return null;
    return NetworkImage(t); // 小图本身很小，无需 ResizeImage
  }
}

// lib/api/api_client.dart
//
// 通用 HTTP 客户端。
// 只负责：基础地址、鉴权、用户 ID、JSON 请求、统一异常。
// 不在这里放任何 StoreApi / UserApi / ProfileApi 等业务模型或业务接口。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.data,
  });

  final String message;
  final int? statusCode;
  final dynamic data;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// 可在启动时使用：
  /// flutter run --dart-define=API_BASE_URL=http://你的地址:3000/api/v1
  static const String _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.20.10.3:3000/api/v1',
  );

  static String get baseUrl => _trimTrailingSlash(_envBaseUrl);

  static String get webSocketBaseUrl {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return baseUrl;

    final scheme = switch (uri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => uri.scheme,
    };

    return uri.replace(scheme: scheme).toString();
  }

  String? accessToken;
  String? userId;

  final http.Client _client = http.Client();

  void setAccessToken(String? token) {
    final value = token?.trim();
    accessToken = (value == null || value.isEmpty) ? null : value;
  }

  void setUserId(String? id) {
    final value = id?.trim();
    userId = (value == null || value.isEmpty) ? null : value;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return _request(
      'GET',
      path,
      queryParams: queryParams,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return _request(
      'POST',
      path,
      body: body,
      queryParams: queryParams,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return _request(
      'PUT',
      path,
      body: body,
      queryParams: queryParams,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return _request(
      'PATCH',
      path,
      body: body,
      queryParams: queryParams,
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) {
    return _request(
      'DELETE',
      path,
      body: body,
      queryParams: queryParams,
      headers: headers,
    );
  }


  /// Multipart 上传（头像/图片等）。
  ///
  /// 保持与普通请求相同的鉴权头，不引入额外业务逻辑。
  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path, null);
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(<String, String>{
      'Accept': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (userId != null) 'X-User-ID': userId!,
      ...?headers,
    });

    if (fields != null) {
      request.fields.addAll(fields);
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
      ),
    );

    try {
      final streamed = await request
          .send()
          .timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('上传超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw ApiException('上传失败：${error.message}');
    } catch (error) {
      throw ApiException('上传失败：$error');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path, queryParams);

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (userId != null) 'X-User-ID': userId!,
      ...?headers,
    };

    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      late final http.Response response;

      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: requestHeaders)
              .timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          response = await _client
              .post(uri, headers: requestHeaders, body: encodedBody)
              .timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          response = await _client
              .put(uri, headers: requestHeaders, body: encodedBody)
              .timeout(const Duration(seconds: 30));
          break;
        case 'PATCH':
          response = await _client
              .patch(uri, headers: requestHeaders, body: encodedBody)
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          response = await _client
              .delete(uri, headers: requestHeaders, body: encodedBody)
              .timeout(const Duration(seconds: 30));
          break;
        default:
          throw ApiException('不支持的请求方法：$method');
      }

      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('请求超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw ApiException('网络请求失败：${error.message}');
    } catch (error) {
      throw ApiException('网络请求失败：$error');
    }
  }

  Uri _buildUri(
    String path,
    Map<String, dynamic>? queryParams,
  ) {
    final rawPath = path.trim();

    final Uri baseUri;
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      baseUri = Uri.parse(rawPath);
    } else {
      final normalizedPath = rawPath.startsWith('/') ? rawPath : '/$rawPath';
      baseUri = Uri.parse('$baseUrl$normalizedPath');
    }

    if (queryParams == null || queryParams.isEmpty) return baseUri;

    final nextQuery = <String, String>{
      ...baseUri.queryParameters,
      for (final entry in queryParams.entries)
        if (entry.value != null) entry.key: _queryValue(entry.value),
    };

    return baseUri.replace(queryParameters: nextQuery);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final dynamic decoded = _tryDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded == null) return <String, dynamic>{};

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }

      // 当前项目的 API 层统一按 Map 读取；
      // 如果某接口直接返回数组，则放入 data，保持调用端兼容。
      return <String, dynamic>{'data': decoded};
    }

    throw ApiException(
      _extractErrorMessage(decoded, response.statusCode),
      statusCode: response.statusCode,
      data: decoded,
    );
  }

  dynamic _tryDecode(String body) {
    final text = body.trim();
    if (text.isEmpty) return null;

    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  String _extractErrorMessage(dynamic data, int statusCode) {
    if (data is Map) {
      final candidates = [
        data['message'],
        data['detail'],
        data['error'],
        data['msg'],
      ];

      for (final value in candidates) {
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }

      final nested = data['data'];
      if (nested is Map) {
        final value = nested['message'] ?? nested['detail'] ?? nested['error'];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    return '请求失败（HTTP $statusCode）';
  }

  static String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  String _queryValue(dynamic value) {
    if (value is Iterable) {
      return value.map((e) => e.toString()).join(',');
    }
    return value.toString();
  }
}

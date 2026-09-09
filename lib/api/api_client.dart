// lib/api/api_client.dart
//
// 通用 HTTP 客户端。
// 只负责：基础地址、鉴权、用户 ID、JSON 请求、统一异常。
// 不在这里放任何 StoreApi / UserApi / ProfileApi 等业务模型或业务接口。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef UnauthorizedRefreshHandler = Future<String?> Function();

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
  /// flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
  ///    defaultValue: 'https://yoran.freedreamky.com/api/v1',
  static const String _envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://172.20.10.3:3000/api/v1',
  );

  static final Object _suppressUnauthorizedRefreshZoneKey = Object();

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
  UnauthorizedRefreshHandler? _unauthorizedRefreshHandler;

  void setAccessToken(String? token) {
    final value = token?.trim();
    accessToken = (value == null || value.isEmpty) ? null : value;
  }

  void setUserId(String? id) {
    final value = id?.trim();
    userId = (value == null || value.isEmpty) ? null : value;
  }

  /// 由 SessionManager 注入刷新逻辑，避免 ApiClient 反向 import SessionManager。
  /// 所有使用本客户端的普通 API 都会自动获得 401 -> refresh -> 原请求重试一次。
  void setUnauthorizedRefreshHandler(UnauthorizedRefreshHandler? handler) {
    _unauthorizedRefreshHandler = handler;
  }

  /// refresh 接口本身也可能通过 ApiClient 发请求。
  /// 用 Zone 只对当前 refresh 调用链关闭 401 自动刷新，避免 refresh 401 后递归等待自己。
  Future<T> withoutUnauthorizedRefresh<T>(Future<T> Function() action) {
    return runZoned<Future<T>>(
      action,
      zoneValues: <Object?, Object?>{
        _suppressUnauthorizedRefreshZoneKey: true,
      },
    );
  }

  bool get _unauthorizedRefreshSuppressed =>
      Zone.current[_suppressUnauthorizedRefreshZoneKey] == true;

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
  /// 与普通 JSON 请求一样支持 access token 过期后自动刷新并重试一次。
  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
    Map<String, String>? headers,
  }) {
    return _postMultipartBytes(
      path,
      fieldName: fieldName,
      bytes: bytes,
      filename: filename,
      fields: fields,
      headers: headers,
      allowUnauthorizedRetry: true,
    );
  }

  Future<Map<String, dynamic>> _postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
    Map<String, String>? headers,
    required bool allowUnauthorizedRetry,
  }) async {
    final uri = _buildUri(path, null);
    final tokenAtRequest = accessToken;
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(_buildHeaders(
      headers,
      includeContentType: false,
    ));

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

      if (await _shouldRetryUnauthorized(
        response: response,
        tokenAtRequest: tokenAtRequest,
        headers: headers,
        allowUnauthorizedRetry: allowUnauthorizedRetry,
      )) {
        return _postMultipartBytes(
          path,
          fieldName: fieldName,
          bytes: bytes,
          filename: filename,
          fields: fields,
          headers: headers,
          allowUnauthorizedRetry: false,
        );
      }

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
    bool allowUnauthorizedRetry = true,
  }) async {
    final uri = _buildUri(path, queryParams);
    final tokenAtRequest = accessToken;
    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      final response = await _sendJsonRequest(
        method,
        uri,
        body: encodedBody,
        headers: headers,
      );

      if (await _shouldRetryUnauthorized(
        response: response,
        tokenAtRequest: tokenAtRequest,
        headers: headers,
        allowUnauthorizedRetry: allowUnauthorizedRetry,
      )) {
        return _request(
          method,
          path,
          body: body,
          queryParams: queryParams,
          headers: headers,
          allowUnauthorizedRetry: false,
        );
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

  Future<http.Response> _sendJsonRequest(
    String method,
    Uri uri, {
    required String? body,
    Map<String, String>? headers,
  }) async {
    final requestHeaders = _buildHeaders(headers);

    switch (method) {
      case 'GET':
        return _client
            .get(uri, headers: requestHeaders)
            .timeout(const Duration(seconds: 30));
      case 'POST':
        return _client
            .post(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 30));
      case 'PUT':
        return _client
            .put(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 30));
      case 'PATCH':
        return _client
            .patch(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 30));
      case 'DELETE':
        return _client
            .delete(uri, headers: requestHeaders, body: body)
            .timeout(const Duration(seconds: 30));
      default:
        throw ApiException('不支持的请求方法：$method');
    }
  }

  Map<String, String> _buildHeaders(
    Map<String, String>? headers, {
    bool includeContentType = true,
  }) {
    return <String, String>{
      'Accept': 'application/json',
      if (includeContentType) 'Content-Type': 'application/json; charset=utf-8',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (userId != null) 'X-User-ID': userId!,
      ...?headers,
    };
  }

  Future<bool> _shouldRetryUnauthorized({
    required http.Response response,
    required String? tokenAtRequest,
    required Map<String, String>? headers,
    required bool allowUnauthorizedRetry,
  }) async {
    if (response.statusCode != 401 ||
        !allowUnauthorizedRetry ||
        tokenAtRequest == null ||
        _unauthorizedRefreshSuppressed ||
        _hasExplicitAuthorization(headers)) {
      return false;
    }

    // 如果别的并发 401 已经刷新好了 token，本请求直接用新 token 重试，
    // 不再触发第二次 refresh。
    final currentToken = accessToken;
    if (currentToken != null && currentToken != tokenAtRequest) {
      return true;
    }

    final handler = _unauthorizedRefreshHandler;
    if (handler == null) return false;

    final refreshedToken = await handler();
    final normalized = refreshedToken?.trim() ?? '';
    if (normalized.isEmpty) return false;

    // SessionManager 正常会先 setAccessToken；这里再兜底一次，确保自定义 handler
    // 只返回 token 但忘记写入客户端时，原请求仍能正确重试。
    if (accessToken != normalized) {
      setAccessToken(normalized);
    }
    return true;
  }

  bool _hasExplicitAuthorization(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return false;
    return headers.keys.any((key) => key.toLowerCase() == 'authorization');
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

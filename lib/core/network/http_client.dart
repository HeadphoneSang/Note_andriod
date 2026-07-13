// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:dio/dio.dart';

// ════════════════════════════════════════════════════════════════════════════
//  ApiResponse — 统一的后端响应模型
//  后端无论返回什么格式（标准 JSON 或纯字符串），都包装成这个对象返回给 UI 层
// ════════════════════════════════════════════════════════════════════════════

/// 统一 API 响应模型
///
/// 所有网络请求的返回值都封装成 [ApiResponse]，UI 层统一用 [isSuccess] 判断成功/失败。
///
/// 泛型 [T] 表示 data 字段的实际类型，例如：
///   `ApiResponse<List<Map>>`  → data 是一个 List
///   `ApiResponse<String>`     → data 是一个 String
class ApiResponse<T> {
  /// 业务状态码（通常是后端 JSON 里的 "code" 字段，如 200/400/500）
  final int? code;

  /// 后端返回的提示消息（通常是后端 JSON 里的 "message" 字段）
  final String? message;

  /// 真正的业务数据，类型由泛型 [T] 决定
  final T? data;

  /// 请求是否成功（true = 成功，false = 失败）
  final bool isSuccess;

  const ApiResponse({
    this.code,
    this.message,
    this.data,
    required this.isSuccess,
  });

  /// 快速创建一个成功响应
  ///
  /// 用法: ApiResponse.success(data)
  factory ApiResponse.success(T? data, {int? code, String? message}) {
    return ApiResponse(
      isSuccess: true,
      data: data,
      code: code,
      message: message,
    );
  }

  /// 快速创建一个失败响应
  ///
  /// 用法: ApiResponse.failure(message: '网络异常')
  factory ApiResponse.failure({int? code, String? message, T? data}) {
    return ApiResponse(
      isSuccess: false,
      data: data,
      code: code,
      message: message ?? '请求失败',
    );
  }

  @override
  String toString() =>
      'ApiResponse(code: $code, message: $message, data: $data, isSuccess: $isSuccess)';
}

/// HTTP 异常类
///
/// 用于表示网络层面的错误（非业务错误），如连接失败、超时等。
/// 目前暂时保留，可扩展用于全局错误处理。
class HttpException implements Exception {
  /// HTTP 状态码（如 404、500）
  final int? statusCode;

  /// 错误描述
  final String message;

  /// 额外的错误数据
  final dynamic data;

  const HttpException({this.statusCode, this.message = '网络异常', this.data});

  @override
  String toString() =>
      'HttpException(statusCode: $statusCode, message: $message)';
}

// ════════════════════════════════════════════════════════════════════════════
//  HttpClient — 统一的 HTTP 请求客户端
//  采用单例模式，整个 App 共享一个 Dio 实例
// ════════════════════════════════════════════════════════════════════════════

/// 统一的 HTTP 请求客户端（单例模式）
///
/// ```
/// // 1. 在 main() 中初始化
/// HttpClient.init(baseUrl: 'https://api.example.com');
///
/// // 2. 在任意地方发起请求
/// final res = await HttpClient.instance.get('/hello');
/// if (res.isSuccess) {
///   print(res.data);
/// }
/// ```
///
/// 支持功能：
/// - GET / POST / PUT / PATCH / DELETE
/// - 文件上传（带进度）、文件下载（带进度）
/// - 自动注入 Token（需实现 [TokenProvider]）
/// - 超时控制、错误中文提示、请求日志打印
class HttpClient {
  // ──────────────────────────────────────────────
  //  单例部分
  // ──────────────────────────────────────────────

  /// 内部持有的单例对象
  static HttpClient? _instance;

  /// Dio 实例（Dio 是真正发请求的三方库）
  late final Dio _dio;

  /// 私有构造方法 — 外部不能直接 new，只能通过 [init] 或 [instance] 获取
  ///
  /// 初始化时创建 Dio 实例，配置基础选项，并挂载内置拦截器。
  HttpClient._internal({
    String? baseUrl, // 基础地址，如 https://api.example.com
    Duration? connectTimeout, // 连接超时时间
    Duration? receiveTimeout, // 接收超时时间
    Map<String, dynamic>? headers, // 自定义请求头
    List<Interceptor>? interceptors, // 额外的拦截器（可选）
    TokenProvider? tokenProvider, // Token 管理（可选）
  }) {
    // 创建 Dio 实例并配置基础选项
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: connectTimeout ?? const Duration(seconds: 15),
        receiveTimeout: receiveTimeout ?? const Duration(seconds: 15),
        // 设置返回原始字符串，由 _handleResponse 自行判读是 JSON 还是纯文本
        responseType: ResponseType.plain,
        headers:
            headers ??
            {'Content-Type': 'application/json', 'Accept': 'application/json'},
      ),
    );

    // 挂载内置拦截器（按顺序执行）
    _dio.interceptors.addAll([
      _LogInterceptor(), // ① 日志：打印每次请求和响应
      _TokenInterceptor(tokenProvider), // ② Token：自动加 Authorization 头
      _ErrorInterceptor(), // ③ 错误：统一处理网络异常
      ...?interceptors, // ④ 外部传入的自定义拦截器（如果有）
    ]);
  }

  /// 初始化 HttpClient（只在 App 启动时调用一次）
  ///
  /// 通常放在 main() 里：
  /// ```dart
  /// void main() {
  ///   HttpClient.init(baseUrl: 'https://api.example.com');
  ///   runApp(MyApp());
  /// }
  /// ```
  static void init({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Map<String, dynamic>? headers,
    List<Interceptor>? interceptors,
    TokenProvider? tokenProvider,
  }) {
    _instance = HttpClient._internal(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: headers,
      interceptors: interceptors,
      tokenProvider: tokenProvider,
    );
  }

  /// 获取单例
  ///
  /// 如果还没初始化，会自动用默认配置创建一个实例。
  /// 建议先调用 [init] 明确配置 baseUrl。
  ///
  /// ```dart
  /// final res = await HttpClient.instance.get('/user/info');
  /// ```
  static HttpClient get instance {
    _instance ??= HttpClient._internal();
    return _instance!;
  }

  /// 获取原始 Dio 实例
  ///
  /// 某些特殊场景（如自定义拦截器、直接操作请求等）需要绕开封装方法，
  /// 可以直接访问 Dio 的原生 API。
  Dio get dio => _dio;

  // ──────────────────────────────────────────────
  //  对外提供的 HTTP 方法
  //  GET / POST / PUT / PATCH / DELETE
  // ──────────────────────────────────────────────

  /// GET 请求
  ///
  /// [path]  — 请求路径，如 '/hello'，会拼接到 baseUrl 后面
  /// [queryParameters] — URL 查询参数，如 {'page': 1, 'size': 20}
  /// [cancelToken] — 取消令牌，用于手动取消请求, 如 cancelToken.cancel() 切换页面后取消未完成的请求
  /// [options] — 额外的请求配置，如 headers、contentType 等，会
  /// ```dart
  /// final res = await HttpClient.instance.get<List>('/notes');
  /// ```
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// POST 请求 — 常用于创建数据
  ///
  /// [data]  — 请求体，可以是 Map、List、FormData 等
  ///
  /// ```dart
  /// final res = await HttpClient.instance.post(
  ///   '/notes',
  ///   data: {'title': '笔记标题', 'content': '内容'},
  /// );
  /// ```
  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// PUT 请求 — 常用于完整更新数据
  Future<ApiResponse<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      'PUT',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// PATCH 请求 — 常用于部分更新数据
  Future<ApiResponse<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// DELETE 请求 — 删除数据
  Future<ApiResponse<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      'DELETE',
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  // ──────────────────────────────────────────────
  //  核心请求处理（私有）
  //  所有对外方法最终都走到这里
  // ──────────────────────────────────────────────

  /// 核心请求方法 — 所有对外 HTTP 方法的最终出口
  ///
  /// 负责：① 合并配置 ② 发起真实请求 ③ 捕获异常并转为 ApiResponse
  Future<ApiResponse<T>> _request<T>(
    String method, // HTTP 方法：GET / POST / PUT / PATCH / DELETE
    String path, {
    dynamic data, // 请求体
    Map<String, dynamic>? queryParameters, // URL 查询参数
    Options? options, // 额外选项（可覆盖默认配置）
    CancelToken? cancelToken, // 取消令牌（用于手动取消请求）
  }) async {
    try {
      // 将外部传来的options的method覆盖为当前请求方法，确保正确发出请求
      final opts = (options ?? Options()).copyWith(method: method);

      // 发起真实请求
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: opts,
        cancelToken: cancelToken,
      );

      // 成功 → 包装成 ApiResponse
      return _handleResponse<T>(response);
    } on DioException catch (e) {
      // Dio 自身抛出的异常（超时、网络错误、HTTP 错误码等）
      print('DioException: ${e.type} | ${e.message} | ${e.error}');
      return _handleDioError<T>(e);
    } catch (e) {
      // 其他未知异常（如 JSON 解析失败、空指针等）
      return ApiResponse.failure(message: '未知错误: $e');
    }
  }

  /// 处理成功响应 — 将 Dio 的 Response 转为 ApiResponse
  ///
  /// 由于设置了 responseType=ResponseType.plain，
  /// 返回的 data 是原始字符串，这里自动判断是 JSON 还是纯文本：
  ///   - 如果是 JSON → 提取 code / message / data 字段
  ///   - 如果是纯文本 → 直接放进 data 字段
  ApiResponse<T> _handleResponse<T>(Response<dynamic> response) {
    var data = response.data;
    print('原始响应数据: $data');

    // 尝试将原始字符串解析为 JSON
    if (data is String && data.trim().isNotEmpty) {
      try {
        data = json.decode(data);
      } catch (_) {
        // 解析失败说明不是 JSON，保留原始字符串
      }
    }

    if (data is Map<String, dynamic>) {
      // 标准 JSON 响应体：{ "code": 200, "message": "ok", "data": ... }
      return ApiResponse<T>(
        isSuccess: true,
        code: data['code'] as int? ?? response.statusCode,
        message: data['message'] as String?,
        data: data['data'] as T?,
      );
    }
    // 非标准响应（纯文本或其他格式）→ 直接返回原始数据
    return ApiResponse<T>.success(data as T?);
  }

  /// 处理 Dio 异常 — 将 DioException 转为 ApiResponse
  ///
  /// 根据 Dio 的错误类型（超时、网络错误、HTTP 错误码等），
  /// 返回对应的中文提示消息，让 UI 层可以直接展示。
  ApiResponse<T> _handleDioError<T>(DioException e) {
    String message;
    int? statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        message = '连接超时'; // 客户端发出请求后，规定时间内没连上服务器
      case DioExceptionType.sendTimeout:
        message = '发送超时'; // 发送数据超时
      case DioExceptionType.receiveTimeout:
        message = '接收超时'; // 接收服务器响应超时
      case DioExceptionType.badResponse:
        // 服务器返回了 HTTP 错误码（4xx / 5xx）
        statusCode = e.response?.statusCode;
        final body = e.response?.data;
        if (body is Map<String, dynamic>) {
          // 如果后端返回了 JSON 错误体，优先取其中的 message 字段
          message =
              body['message'] as String? ?? _httpStatusMessage(statusCode);
        } else {
          message = _httpStatusMessage(statusCode);
        }
      case DioExceptionType.cancel:
        message = '请求已取消'; // 主动调用了 cancelToken.cancel()
      case DioExceptionType.connectionError:
        message = '网络连接失败，请检查网络'; // DNS 解析失败、无法连接等
      case DioExceptionType.badCertificate:
        message = '证书验证失败'; // HTTPS 证书校验不通过
      default:
        message = '网络异常'; // 兜底：未知错误类型
    }

    return ApiResponse<T>.failure(code: statusCode, message: message);
  }

  /// HTTP 状态码 → 中文说明
  ///
  /// 当服务器返回 4xx/5xx 但没有给 message 字段时，用这个映射生成提示。
  String _httpStatusMessage(int? statusCode) {
    switch (statusCode) {
      case 400:
        return '请求参数错误';
      case 401:
        return '未授权，请重新登录';
      case 403:
        return '拒绝访问';
      case 404:
        return '请求的资源不存在';
      case 405:
        return '请求方法不允许';
      case 408:
        return '请求超时';
      case 500:
        return '服务器内部错误';
      case 502:
        return '网关错误';
      case 503:
        return '服务不可用';
      case 504:
        return '网关超时';
      default:
        return '请求失败 ($statusCode)';
    }
  }

  // ──────────────────────────────────────────────
  //  文件上传 / 下载
  // ──────────────────────────────────────────────

  /// 下载文件到本地
  ///
  /// [url]       — 文件下载地址（完整 URL）
  /// [savePath]  — 保存到本地的路径，如 '/storage/emulated/0/Download/a.jpg'
  /// [onReceiveProgress] — 下载进度回调，(已接收, 总大小)
  ///
  /// ```dart
  /// final res = await HttpClient.instance.download(
  ///   'https://example.com/file.zip',
  ///   '/data/user/0/.../file.zip',
  ///   onReceiveProgress: (received, total) {
  ///     print('${received / total * 100}%');
  ///   },
  /// );
  /// ```
  Future<ApiResponse<String>> download(
    String url,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    try {
      final response = await _dio.download(
        url,
        savePath,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
      );
      return ApiResponse<String>.success(savePath, code: response.statusCode);
    } on DioException catch (e) {
      return _handleDioError<String>(e);
    } catch (e) {
      return ApiResponse.failure(message: '下载失败: $e');
    }
  }

  /// 上传文件（以 FormData 格式）
  ///
  /// [path]     — 上传接口路径，如 '/upload'
  /// [formData] — 要上传的文件数据，用 Dio 的 FormData 构造
  /// [onSendProgress] — 上传进度回调
  ///
  /// ```dart
  /// final formData = FormData.fromMap({
  ///   'file': await MultipartFile.fromFile('/path/to/image.jpg'),
  /// });
  /// final res = await HttpClient.instance.upload(
  ///   '/upload',
  ///   formData: formData,
  ///   onSendProgress: (sent, total) => print('$sent / $total'),
  /// );
  /// ```
  Future<ApiResponse<T>> upload<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    return _request<T>(
      'POST',
      path,
      data: formData,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      // 上传文件需要指定 multipart/form-data 内容类型
      options: Options(contentType: 'multipart/form-data'),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  拦截器 — 在请求/响应的不同阶段插入自定义逻辑
//  按添加顺序执行：请求阶段按序执行，响应/错误阶段反向执行
// ════════════════════════════════════════════════════════════════════════════

/// 日志拦截器
///
/// 在控制台打印每次请求和响应的信息，方便调试。
/// 执行时机：
///   - onRequest：  请求发出前
///   - onResponse： 收到响应后
///   - onError：    发生错误时
class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 打印请求方法 + 完整 URL
    print('🌐 [HTTP] --> ${options.method} ${options.uri}');
    if (options.data != null) {
      // 如果有请求体，也打印出来
      print('📦 [HTTP] Body: ${options.data}');
    }
    // 放行，让请求继续往下走
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 打印响应状态码 + URL
    print(
      '🌐 [HTTP] <-- ${response.statusCode} ${response.requestOptions.uri}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 打印错误类型和详情
    print('❌ [HTTP] ERROR: type=${err.type} | message=${err.message}');
    handler.next(err);
  }
}

/// Token 拦截器 — 自动在请求头中注入 Authorization
///
/// 请求发出前，自动从 [TokenProvider] 获取 Token，并写入请求头。
/// 收到 401 响应时，触发 [TokenProvider.onTokenExpired] 回调，
/// 外部可以在回调里执行 Token 刷新逻辑。
class _TokenInterceptor extends Interceptor {
  final TokenProvider? _tokenProvider;

  _TokenInterceptor(this._tokenProvider);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 从外部获取当前 Token
    final token = _tokenProvider?.getToken();
    if (token != null && token.isNotEmpty) {
      // 注入 Authorization: Bearer xxx
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 401 = Token 过期或无效 → 触发刷新回调
    if (err.response?.statusCode == 401) {
      _tokenProvider?.onTokenExpired?.call(err);
    }
    handler.next(err);
  }
}

/// 错误拦截器 — 统一处理常见网络异常
///
/// 主要用于连接类错误的兜底处理（如弹出全局提示）。
/// 实际错误消息的返回由 [_handleDioError] 处理。
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 网络连接类错误（断网、超时等）— 可在此触发全局 Toast
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      print('⚠️ [HTTP] 网络异常: ${err.message}');
    }
    handler.next(err);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TokenProvider — Token 存取接口
//  具体怎么存（SharedPreferences、本地文件、内存变量等）由外部实现
// ════════════════════════════════════════════════════════════════════════════

/// Token 提供者接口
///
/// 由外部实现具体的 Token 存取逻辑，例如用 shared_preferences 保存 Token。
///
/// ```dart
/// HttpClient.init(
///   tokenProvider: TokenProvider(
///     getToken: () => prefs.getString('token'),
///     onTokenExpired: (err) => _refreshToken(),
///   ),
/// );
/// ```
class TokenProvider {
  /// 获取当前 Token（每次请求前自动调用）
  ///
  /// 返回 null 或空字符串时不注入 Authorization 头。
  final String? Function() getToken;

  /// Token 过期回调（收到 401 时自动触发）
  ///
  /// 可在回调中执行刷新 Token 的逻辑，刷新成功后重试原请求。
  final void Function(DioException error)? onTokenExpired;

  const TokenProvider({required this.getToken, this.onTokenExpired});
}

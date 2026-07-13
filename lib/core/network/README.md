# HttpClient — 统一 HTTP 请求封装

基于 `dio` 的网络请求工具类，提供一致的请求/响应模型，内置日志、Token 注入、中文错误提示。

---

## 目录

- [快速开始](#快速开始)
- [API 参考](#api-参考)
- [响应处理](#响应处理)
- [错误处理](#错误处理)
- [拦截器](#拦截器)
- [Token 管理](#token-管理)
- [文件上传/下载](#文件上传下载)
- [FAQ](#faq)

---

## 快速开始

### 1. 初始化（`main.dart`）

```dart
import 'core/network/http_client.dart';

void main() {
  HttpClient.init(
    baseUrl: 'http://47.104.25.40:8080',
    connectTimeout: const Duration(seconds: 10),
  );
  runApp(const MyApp());
}
```

### 2. 发起请求

```dart
// GET
final res = await HttpClient.instance.get<String>('/hello');
if (res.isSuccess) {
  print('✅ 成功: ${res.data}');
} else {
  print('❌ 失败: ${res.message}');
}

// POST
final res = await HttpClient.instance.post<Map<String, dynamic>>(
  '/notes',
  data: {'title': '新笔记'},
);
```

---

## API 参考

### 实例化

| 方式 | 说明 |
|------|------|
| `HttpClient.init(...)` | 全局配置，在 `main()` 调用一次 |
| `HttpClient.instance` | 获取单例，任意地方直接使用 |

### HTTP 方法

所有方法返回值均为 `Future<ApiResponse<T>>`。

| 方法 | 签名 |
|------|------|
| `get` | `get<T>(String path, {queryParameters, options, cancelToken})` |
| `post` | `post<T>(String path, {data, queryParameters, options, cancelToken})` |
| `put` | `put<T>(String path, {data, queryParameters, options, cancelToken})` |
| `patch` | `patch<T>(String path, {data, queryParameters, options, cancelToken})` |
| `delete` | `delete<T>(String path, {data, queryParameters, options, cancelToken})` |

### 文件操作

| 方法 | 说明 |
|------|------|
| `download(url, savePath, {onReceiveProgress})` | 下载文件，返回 `ApiResponse<String>`（保存路径） |
| `upload(path, {formData, onSendProgress})` | 上传文件，需构造 `FormData` |

### 初始化参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `baseUrl` | `''` | 接口基础地址 |
| `connectTimeout` | `15秒` | 连接超时 |
| `receiveTimeout` | `15秒` | 接收超时 |
| `headers` | `Content-Type: application/json` | 自定义请求头 |
| `interceptors` | `[]` | 额外的 Dio 拦截器 |
| `tokenProvider` | `null` | Token 存取逻辑（见下文） |

---

## 响应处理

### ApiResponse 结构

```dart
class ApiResponse<T> {
  bool isSuccess;   // true = 成功, false = 失败
  int? code;        // 业务状态码
  String? message;  // 提示消息
  T? data;          // 业务数据
}
```

### 两种响应格式自动兼容

```dart
// 场景 A：后端返回 JSON → 自动解析
// {"code": 200, "message": "ok", "data": "Hello"}
res.data     // → "Hello"
res.code     // → 200
res.message  // → "ok"

// 场景 B：后端返回纯文本 → 直接透传
// "Hello Spring Boot!"
res.data     // → "Hello Spring Boot!"
res.code     // → null
res.message  // → null
```

### 典型用法

```dart
Future<void> loadNotes() async {
  final res = await HttpClient.instance.get<List>('/notes');

  if (!res.isSuccess) {
    showError(res.message);  // 显示中文错误
    return;
  }

  final notes = res.data ?? [];
  // 处理数据...
}
```

---

## 错误处理

### 异常 → 中文提示映射

| 场景 | 提示文字 |
|------|---------|
| 连接超时 | 连接超时 |
| 发送超时 | 发送超时 |
| 接收超时 | 接收超时 |
| 请求取消 | 请求已取消 |
| 断网 | 网络连接失败，请检查网络 |
| 证书错误 | 证书验证失败 |
| 400 | 请求参数错误 |
| 401 | 未授权，请重新登录 |
| 403 | 拒绝访问 |
| 404 | 请求的资源不存在 |
| 405 | 请求方法不允许 |
| 408 | 请求超时 |
| 500 | 服务器内部错误 |
| 502 | 网关错误 |
| 503 | 服务不可用 |
| 504 | 网关超时 |
| 其他 | 网络异常 / 请求失败 (statusCode) |

---

## 拦截器

内置三个拦截器，按以下顺序执行：

```
请求阶段（正向）             响应阶段（反向）
────────────────────────────────────────────
_LogInterceptor  →  打印请求日志
    ↓
_TokenInterceptor →  注入 Token 头
    ↓
_ErrorInterceptor →  检查网络状态
    ↓
      Dio（真实请求）
    ↓
_ErrorInterceptor ←  捕获网络异常
    ↓
_TokenInterceptor ←  检查 401 触发刷新
    ↓
_LogInterceptor  ←  打印响应日志
```

### 日志拦截器

控制台输出示例：

```
🌐 [HTTP] --> GET http://47.104.25.40:8080/hello
🌐 [HTTP] <-- 200 http://47.104.25.40:8080/hello
❌ [HTTP] ERROR: type=connectionTimeout | message=...
```

### 添加自定义拦截器

```dart
HttpClient.init(
  interceptors: [
    MyCustomInterceptor(),
  ],
);
```

---

## Token 管理

通过 `TokenProvider` 接入你的 Token 存取逻辑。

### 基本用法

```dart
HttpClient.init(
  tokenProvider: TokenProvider(
    // 每次请求前调用，返回当前 Token
    getToken: () => storage.getString('access_token'),
    // 收到 401 时触发，可在此执行刷新
    onTokenExpired: (err) async {
      final newToken = await refreshToken();
      storage.setString('access_token', newToken);
      // 重试原请求...
    },
  ),
);
```

### 实现原理

- `_TokenInterceptor.onRequest`：自动在请求头加 `Authorization: Bearer xxx`
- `_TokenInterceptor.onError`：检测到 401 时回调 `onTokenExpired`

---

## 文件上传/下载

### 下载

```dart
final res = await HttpClient.instance.download(
  'https://example.com/image.jpg',
  '/storage/emulated/0/Download/image.jpg',
  onReceiveProgress: (received, total) {
    final progress = received / total * 100;
    print('下载进度: ${progress.toStringAsFixed(1)}%');
  },
);
```

### 上传

```dart
final formData = FormData.fromMap({
  'file': await MultipartFile.fromFile(
    '/path/to/image.jpg',
    filename: 'avatar.jpg',
  ),
  'type': 'avatar',
});

final res = await HttpClient.instance.upload<Map>(
  '/upload',
  formData: formData,
  onSendProgress: (sent, total) {
    print('上传进度: ${sent / total * 100}%');
  },
);
```

---

## FAQ

### 为什么用单例？

整个 App 共享一个 Dio 实例，统一管理 baseUrl、超时、拦截器、Token，避免重复配置。

### 泛型 `<T>` 怎么用？

`ApiResponse<T>` 的 `T` 指定 `data` 字段的实际类型：

```dart
HttpClient.instance.get<String>('/hello')     // data → String
HttpClient.instance.get<Map>('/user/1')        // data → Map<String, dynamic>
HttpClient.instance.get<List>('/notes')        // data → List
```

### 后端返回格式不标准怎么办？

`_handleResponse` 会自动判断：
- 返回 JSON（`{"code":200, "data":...}`）→ 按标准格式解析
- 返回纯文本（`"Hello"`）→ 直接透传

两种情况都返回 `ApiResponse.success`。

### 请求被取消了怎么办？

`cancelToken.cancel()` 会触发 `DioExceptionType.cancel`，包装为 `ApiResponse.failure(message: '请求已取消')`，需要自己判断静默处理：

```dart
final res = await HttpClient.instance.get('/data');
if (res.message == '请求已取消') return;  // 不显示错误
```

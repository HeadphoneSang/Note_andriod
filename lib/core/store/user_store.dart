import 'package:flutter/foundation.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户信息模型
class UserInfo {
  final int id;
  final String account;
  final String gender;
  final String nickname;
  final String? avatar;
  final String? phoneNumber;
  final String? email;

  const UserInfo({
    required this.id,
    required this.account,
    required this.gender,
    required this.nickname,
    this.avatar,
    this.phoneNumber,
    this.email,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] ?? 0,
      account: json['account'] ?? 0,
      gender: json['gender'] ?? '',
      nickname: json['nickname'] ?? 'default_nickname',
      avatar: json['avatar'] ?? 'default_avatar',
      phoneNumber: json['phoneNumber'] ?? '000-0000-0000',
      email: json['email'] ?? "",
    );
  }
}

/// 全局用户状态管理
/// 用 `context.read<UserStore>()` 读取，`context.watch<UserStore>()` 监听变化
class UserStore extends ChangeNotifier {
  static const _kTokenKey = 'user_token';

  /// 全局引用，供 HttpClient 的 TokenProvider 静态调用
  static UserStore? _instance;
  static String? provideToken() => _instance?._token;

  // ---- 状态 ----
  UserInfo? _user;
  String? _token;
  bool _isLoggedIn = false;
  bool _initialized = false;

  UserStore() {
    _instance = this;
  }

  // ---- Getter ----
  UserInfo? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _isLoggedIn;
  bool get initialized => _initialized;

  /// 启动时调用：从本地读取 token，恢复登录状态
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenKey);

    if (_token != null) {
      // 有本地 token，尝试验证是否有效，同时获取用户信息
      try {
        final response = await HttpClient.instance.get<Map<String, dynamic>>(
          '/user/token-info',
          queryParameters: {'token': _token},
        );

        if (response.code == 200 && response.data != null) {
          // token 有效
          _user = UserInfo.fromJson(response.data!);
          _isLoggedIn = true;
          debugPrint('[UserStore] init() — token 验证通过');
        } else if (response.code == 401) {
          // token 失效
          debugPrint('[UserStore] init() — token 失效: ${response.message}');
          _token = null;
          await prefs.remove(_kTokenKey);
        }
      } catch (e) {
        // 网络错误（断网、超时等），不阻挡启动但也不标记登录
        debugPrint('[UserStore] init() — 验证 token 时网络异常: $e');
      }
    }
    _initialized = true;
    debugPrint('[UserStore] init() — isLoggedIn=$_isLoggedIn');
    notifyListeners();
  }

  // ---- 登录 ----
  Future<void> login({required UserInfo user, required String token}) async {
    _user = user;
    _token = token;
    _isLoggedIn = true;

    // 持久化 token
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    debugPrint('[UserStore] login() — token 已保存到本地');

    notifyListeners();
  }

  // ---- 登出 ----
  Future<void> logout() async {
    _user = null;
    _token = null;
    _isLoggedIn = false;

    // 清除本地 token
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    debugPrint('[UserStore] logout() — 本地 token 已清除');

    notifyListeners();
  }

  // ---- 更新用户信息（不改登录状态） ----
  void updateUser(UserInfo user) {
    _user = user;
    notifyListeners();
  }
}

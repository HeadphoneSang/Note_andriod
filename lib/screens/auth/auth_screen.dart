import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:provider/provider.dart';
import '../../core/store/user_store.dart';
import 'register_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountCtrl = TextEditingController(text: 'test');
  final _passwordCtrl = TextEditingController(text: '123123');
  final _captchaCodeCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  // 验证码
  String? _captchaImage;
  String? _captchaKey;

  @override
  void initState() {
    super.initState();
    _fetchCaptcha();
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _captchaCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCaptcha() async {
    try {
      final response = await HttpClient.instance.get<Map<String, dynamic>>(
        '/captcha',
      );
      if (response.code == 200 && response.data != null) {
        setState(() {
          _captchaImage = response.data!['image'];
          _captchaKey = response.data!['key'];
        });
      }
    } catch (e) {
      debugPrint('[AuthScreen] 获取验证码失败: $e');
    }
  }

  Future<void> _handlerLoginResponse(
    ApiResponse<Map<String, dynamic>> response,
  ) async {
    if (response.code == 200) {
      Map<String, dynamic> data = response.data!;
      String bToken = data['token']!;
      Map<String, dynamic> userInfo = data['userInfo']!;
      final store = context.read<UserStore>();
      await store.login(token: bToken, user: UserInfo.fromJson(userInfo));
    } else if (response.code == 400) {
      final errorMessage = response.message ?? '登录失败，请检查账号和密码';
      throw Exception(errorMessage);
    } else {
      throw Exception('登录失败，未知错误');
    }
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final ApiResponse<Map<String, dynamic>> loginResponse = await HttpClient
          .instance
          .post(
            '/user/login',
            data: {
              'account': _accountCtrl.text,
              'password': _passwordCtrl.text,
              'captchaKey': _captchaKey,
              'captchaCode': _captchaCodeCtrl.text,
            },
          );
      try {
        await _handlerLoginResponse(loginResponse);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/');
      } catch (e) {
        if (!mounted) return;
        _fetchCaptcha();
        _captchaCodeCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  ImageProvider? _captchaImageProvider() {
    if (_captchaImage == null) return null;
    try {
      final raw = _captchaImage!.contains(',')
          ? _captchaImage!.split(',').last
          : _captchaImage!;
      return MemoryImage(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.primaryColor.withValues(alpha: 0.15),
                Colors.white,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Logo
                  Icon(
                    Icons.lock_person_rounded,
                    size: 80,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '欢迎回来',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请登录您的账号以继续',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 48),

                  // 2. 账号（带行内验证）
                  TextFormField(
                    controller: _accountCtrl,
                    decoration: InputDecoration(
                      labelText: '账号',
                      hintText: '请输入账号',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                  ),
                  const SizedBox(height: 16),

                  // 3. 密码（带行内验证）
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入密码',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 16),

                  // 4. 验证码
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 验证码图片
                      GestureDetector(
                        onTap: _fetchCaptcha,
                        child: Container(
                          width: 120,
                          height: 56,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            color: Colors.grey.shade100,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: _captchaImage != null
                                ? Image(
                                    image: _captchaImageProvider()!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Center(child: Text('加载失败')),
                                  )
                                : const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 验证码输入框（带行内验证）
                      Expanded(
                        child: TextFormField(
                          controller: _captchaCodeCtrl,
                          decoration: InputDecoration(
                            labelText: '验证码',
                            hintText: '点击图片刷新',
                            prefixIcon: const Icon(Icons.security_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? '请输入验证码' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 5. 忘记密码
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: Text(
                        '忘记密码？',
                        style: TextStyle(color: theme.primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 6. 登录按钮
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: theme.primaryColor.withValues(
                        alpha: 0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            '登 录',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // 7. 去注册
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, animation, _) =>
                              const RegisterScreen(),
                          transitionsBuilder: (_, animation, _, child) =>
                              SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    },
                    child: Text(
                      '没有账号？去注册',
                      style: TextStyle(color: theme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

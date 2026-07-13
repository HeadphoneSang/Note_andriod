import 'package:flutter/material.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';

/// 路由名称常量
class RoutePaths {
  static const home = '/';
  static const auth = '/auth';
  static const register = '/register';
}

/// 路由配置
class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RoutePaths.home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case RoutePaths.auth:
        return MaterialPageRoute(
          builder: (_) => const AuthScreen(),
          settings: settings,
        );
      case RoutePaths.register:
        return MaterialPageRoute(
          builder: (_) => const RegisterScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
    }
  }
}

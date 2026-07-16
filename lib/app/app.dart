import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import '../core/store/user_store.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/home/home_screen.dart';
import 'router.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserStore(),
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppFlowyEditorLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 230, 220, 199),
          ),
        ),
        home: SafeArea(child: const _AppEntry()),
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}

/// 启动入口：读取本地 token → 有则进首页，无则进登录页
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserStore>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserStore>(
      builder: (context, store, child) {
        if (!store.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return store.isLoggedIn ? const HomeScreen() : const AuthScreen();
      },
    );
  }
}

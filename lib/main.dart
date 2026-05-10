import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/change_password_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'storage/project_repository.dart';
import 'storage/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsRepository.create();
  final projects = await ProjectRepository.create();
  final state = AppState(
    settingsRepository: settings,
    projectRepository: projects,
  );
  final auth = AuthState();
  // Поднимаем сохранённую сессию синхронно до построения дерева,
  // чтобы избежать вспышки экрана логина при перезагрузке страницы.
  await auth.bootstrap();
  runApp(ConstructionCalculatorApp(state: state, auth: auth));
}

class ConstructionCalculatorApp extends StatelessWidget {
  const ConstructionCalculatorApp({
    super.key,
    required this.state,
    required this.auth,
  });

  final AppState state;
  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<AuthState>.value(value: auth),
      ],
      child: MaterialApp(
        title: 'Калькулятор проектировщика',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
        // Делает текст во всём приложении выделяемым/копируемым.
        // SelectionArea показывает свой контекстное меню через Overlay,
        // поэтому оборачиваем child в собственный Overlay (не делим
        // его с навигаторным).
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          return Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => SelectionArea(child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Корневой роутер: показывает экран логина, экран принудительной
/// смены пароля или главное приложение в зависимости от состояния
/// `AuthState`.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (!auth.bootstrapped) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.signedIn) {
      return const LoginPage();
    }
    if (auth.mustChangePassword) {
      return const ChangePasswordPage(forced: true);
    }
    return const HomePage();
  }
}

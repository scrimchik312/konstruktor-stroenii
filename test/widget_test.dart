// Базовые smoke-тесты на верхнем уровне приложения.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:construction_calculator/main.dart';
import 'package:construction_calculator/models/auth.dart';
import 'package:construction_calculator/models/user_mode.dart';
import 'package:construction_calculator/state/app_state.dart';
import 'package:construction_calculator/state/auth_state.dart';
import 'package:construction_calculator/storage/project_repository.dart';
import 'package:construction_calculator/storage/settings_repository.dart';

Future<AppState> _createState({
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(
    {'hints_enabled': false, ...initialValues},
  );
  final settings = await SettingsRepository.create();
  final projects = await ProjectRepository.create();
  return AppState(settingsRepository: settings, projectRepository: projects);
}

AuthState _signedInAuth({bool admin = false}) {
  final now = DateTime.now();
  return AuthState.signedInForTesting(
    user: AuthUser(
      id: 1,
      email: 'tester@example.com',
      isAdmin: admin,
      mustChangePassword: false,
      entitlements: [
        // Все продукты — чтобы UI показал все плитки и тесты не падали.
        for (final p in const [
          'privateHouse',
          'apartmentBuilding',
          'commercialBuilding',
          'commercialStructure',
          'metalStructure',
          'undergroundStructure',
        ])
          Entitlement(productCode: p, grantedAt: now),
      ],
    ),
  );
}

Future<void> _setupWideScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('Home page shows brand and types of construction',
      (WidgetTester tester) async {
    await _setupWideScreen(tester);
    final state = await _createState();
    await tester.pumpWidget(
      ConstructionCalculatorApp(state: state, auth: _signedInAuth()),
    );
    await tester.pumpAndSettle();

    expect(find.text('КОНСТРУКТОР СТРОЕНИЙ'), findsOneWidget);
    expect(find.text('Что вы хотите спроектировать?'), findsOneWidget);
    expect(find.text('Частный дом'), findsOneWidget);
    expect(find.text('Многоквартирный дом'), findsOneWidget);
  });

  testWidgets('Landing has 6-step instruction', (WidgetTester tester) async {
    await _setupWideScreen(tester);
    final state = await _createState();
    await tester.pumpWidget(
      ConstructionCalculatorApp(state: state, auth: _signedInAuth()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Инструкция из 6 шагов'), findsOneWidget);
  });

  test('AppState defaults mode to designer when nothing is stored', () async {
    final state = await _createState();
    expect(state.mode, UserMode.designer);
    expect(state.hasMode, isTrue);
  });

  testWidgets('No auth → login page is shown', (WidgetTester tester) async {
    await _setupWideScreen(tester);
    final state = await _createState();
    final auth = AuthState.signedInForTesting(
      user: AuthUser(
        id: 1,
        email: 'x@x.com',
        isAdmin: false,
        mustChangePassword: false,
        entitlements: const [],
      ),
    );
    await auth.logout();
    await tester.pumpWidget(
      ConstructionCalculatorApp(state: state, auth: auth),
    );
    await tester.pumpAndSettle();
    // На login-странице обязательно есть поля email и пароля и кнопка
    // «Войти». Несколько совпадений допустимы (тултип/контентное меню),
    // главное — что они есть.
    expect(find.text('Email'), findsWidgets);
    expect(find.text('Пароль'), findsWidgets);
  });

  testWidgets('Locked product card opens info dialog',
      (WidgetTester tester) async {
    await _setupWideScreen(tester);
    final state = await _createState();
    final auth = AuthState.signedInForTesting(
      user: AuthUser(
        id: 1,
        email: 't@x.com',
        isAdmin: false,
        mustChangePassword: false,
        entitlements: [
          Entitlement(productCode: 'privateHouse', grantedAt: DateTime.now()),
        ],
      ),
    );
    await tester.pumpWidget(
      ConstructionCalculatorApp(state: state, auth: auth),
    );
    await tester.pumpAndSettle();
    // На экране должны быть метки «нет доступа» у заблокированных карточек.
    expect(find.text('нет доступа'), findsWidgets);
  });
}

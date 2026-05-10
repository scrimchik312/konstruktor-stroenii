/// Состояние авторизации поверх ChangeNotifier.
///
/// Хранит JWT и текущего пользователя в памяти, а также сериализованную
/// копию в [SharedPreferences] (`auth_token`, `auth_user_json`), чтобы
/// между перезагрузками страницы не приходилось логиниться заново.
///
/// Поведение:
/// 1. На старте пытается восстановить сессию из `SharedPreferences`,
///    проверяет токен через `GET /auth/me`. При успехе — `signedIn=true`.
///    При неуспехе (любая ошибка / 401) — токен стирается, состояние
///    остаётся `signedIn=false`.
/// 2. После `login(...)` или ручной перезагрузки `refresh()` — обновляет
///    `_user` и пересохраняет в SharedPreferences.
/// 3. Геттер [hasProduct] и [allowedProducts] позволяют UI быстро
///    проверять, что у юзера разрешено.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import '../services/auth_api.dart';

class AuthState extends ChangeNotifier {
  AuthState({AuthApi? api})
      : _api = api ?? AuthApi();

  /// Создать AuthState уже залогиненным (для тестов и сторибуков).
  /// Не дёргает сеть, не сохраняет в SharedPreferences.
  AuthState.signedInForTesting({
    required AuthUser user,
    String token = 'test-token',
    AuthApi? api,
  })  : _api = api ?? AuthApi(),
        _token = token,
        _user = user,
        _bootstrapped = true;

  final AuthApi _api;

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user_json';

  String? _token;
  AuthUser? _user;
  bool _bootstrapped = false;
  String? _lastError;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get bootstrapped => _bootstrapped;
  bool get signedIn => _token != null && _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get mustChangePassword => _user?.mustChangePassword ?? false;
  String? get lastError => _lastError;

  /// Список product_code, к которым у юзера есть доступ. Пустой, если
  /// не залогинен — UI должен сам обработать этот случай (показать
  /// сообщение «нет доступа, обратитесь к администратору»).
  Set<String> get allowedProducts =>
      _user?.entitlements.map((e) => e.productCode).toSet() ?? <String>{};

  bool hasProduct(String code) =>
      _user?.hasProduct(code) ?? false;

  /// Запускается один раз из main(): подтягивает сохранённую сессию.
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);
    final savedUserJson = prefs.getString(_userKey);
    if (savedToken == null || savedUserJson == null) {
      _bootstrapped = true;
      notifyListeners();
      return;
    }
    // Проверяем актуальность токена — если сервер ответит 401,
    // ловим, чистим хранилище и идём на логин.
    try {
      final user = await _api.me(savedToken);
      _token = savedToken;
      _user = user;
      // Пересохраним свежие данные пользователя на случай, если
      // админ выдал/отозвал продукт.
      await _persist();
    } on AuthApiException {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (_) {
      // Сеть/сервер недоступны — оставляем юзера залогиненным
      // оптимистично из локальной копии. Перепроверим при следующем
      // запросе.
      _token = savedToken;
      _user = AuthUser.fromJson(
        jsonDecode(savedUserJson) as Map<String, dynamic>,
      );
    }
    _bootstrapped = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token == null || _user == null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } else {
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    }
  }

  Future<void> login(String email, String password) async {
    _lastError = null;
    try {
      final result = await _api.login(email.trim().toLowerCase(), password);
      _token = result.token;
      _user = result.user;
      await _persist();
      notifyListeners();
    } on AuthApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      rethrow;
    } catch (e) {
      _lastError = 'Не удалось связаться с сервером: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _lastError = null;
    await _persist();
    notifyListeners();
  }

  /// Перепросить свежий /me у сервера и обновить локальный кеш.
  /// Используется после смены пароля или после возврата из админки,
  /// если ты сам себе что-то изменил.
  Future<void> refresh() async {
    final t = _token;
    if (t == null) return;
    try {
      final user = await _api.me(t);
      _user = user;
      await _persist();
      notifyListeners();
    } on AuthApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      } else {
        rethrow;
      }
    }
  }

  /// Сменить пароль и сразу обновить флаг `must_change_password`.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final t = _token;
    if (t == null) {
      throw StateError('Не залогинен');
    }
    await _api.changePassword(
      token: t,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    await refresh();
  }

  /// Удобная обёртка над AuthApi для админских действий — UI работает
  /// через AuthState, чтобы не дёргать токен в каждый виджет.
  AuthApi get api => _api;
}

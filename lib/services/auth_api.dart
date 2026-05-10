/// HTTP-клиент Auth API.
///
/// Лёгкий обёрточный слой над `package:http`, который скрывает работу с
/// JSON, заголовком Authorization и обработку ошибок: `200 OK` → парсинг
/// тела, всё остальное → выброс [AuthApiException] с человекочитаемым
/// сообщением (берётся из `detail` ответа сервера, если есть).
///
/// Базовый URL читается из `--dart-define=AUTH_API_BASE_URL=...` на этапе
/// сборки. По умолчанию указывает на текущий продакшн-инстанс.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth.dart';

const String kAuthApiBaseUrl = String.fromEnvironment(
  'AUTH_API_BASE_URL',
  defaultValue: 'https://89-169-141-69.sslip.io',
);

/// Бросается из [AuthApi] при любой не-2xx ошибке. Содержит код и
/// сообщение, пригодное для показа пользователю.
class AuthApiException implements Exception {
  AuthApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'AuthApiException($statusCode): $message';
}

class AuthApi {
  AuthApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? kAuthApiBaseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _decode(http.Response r) async {
    final body = r.body.isEmpty ? '{}' : r.body;
    final data = jsonDecode(body);
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return data;
    }
    String msg;
    if (data is Map && data['detail'] is String) {
      msg = data['detail'] as String;
    } else if (data is Map && data['detail'] is List) {
      msg = (data['detail'] as List).map((e) => e.toString()).join('; ');
    } else {
      msg = 'HTTP ${r.statusCode}';
    }
    throw AuthApiException(r.statusCode, msg);
  }

  Future<LoginResult> login(String email, String password) async {
    final r = await _client.post(
      _u('/auth/login'),
      headers: _headers(null),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = await _decode(r) as Map<String, dynamic>;
    return LoginResult.fromJson(data);
  }

  Future<AuthUser> me(String token) async {
    final r = await _client.get(_u('/auth/me'), headers: _headers(token));
    final data = await _decode(r) as Map<String, dynamic>;
    return AuthUser.fromJson(data);
  }

  Future<void> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    final r = await _client.post(
      _u('/auth/change-password'),
      headers: _headers(token),
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );
    await _decode(r);
  }

  Future<List<AdminUser>> listUsers(String token) async {
    final r = await _client.get(_u('/admin/users'), headers: _headers(token));
    final data = await _decode(r) as List<dynamic>;
    return data
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProductInfo>> listProducts(String token) async {
    final r =
        await _client.get(_u('/admin/products'), headers: _headers(token));
    final data = await _decode(r) as Map<String, dynamic>;
    return (data['products'] as List<dynamic>)
        .map((e) => ProductInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CreateUserResult> createUser({
    required String token,
    required String email,
    String? fullName,
    bool isAdmin = false,
    List<String> products = const [],
    String? note,
  }) async {
    final r = await _client.post(
      _u('/admin/users'),
      headers: _headers(token),
      body: jsonEncode({
        'email': email,
        if (fullName != null) 'full_name': fullName,
        'is_admin': isAdmin,
        'products': products,
        if (note != null) 'note': note,
      }),
    );
    final data = await _decode(r) as Map<String, dynamic>;
    return CreateUserResult.fromJson(data);
  }

  Future<AdminUser> grantProduct({
    required String token,
    required int userId,
    required String productCode,
    String? note,
  }) async {
    final r = await _client.post(
      _u('/admin/users/$userId/entitlements'),
      headers: _headers(token),
      body: jsonEncode({
        'product_code': productCode,
        if (note != null) 'note': note,
      }),
    );
    return AdminUser.fromJson(await _decode(r) as Map<String, dynamic>);
  }

  Future<AdminUser> revokeProduct({
    required String token,
    required int userId,
    required String productCode,
  }) async {
    final r = await _client.delete(
      _u('/admin/users/$userId/entitlements/$productCode'),
      headers: _headers(token),
    );
    return AdminUser.fromJson(await _decode(r) as Map<String, dynamic>);
  }

  Future<AdminUser> updateUser({
    required String token,
    required int userId,
    String? fullName,
    bool? isActive,
    bool? isAdmin,
  }) async {
    final r = await _client.patch(
      _u('/admin/users/$userId'),
      headers: _headers(token),
      body: jsonEncode({
        if (fullName != null) 'full_name': fullName,
        if (isActive != null) 'is_active': isActive,
        if (isAdmin != null) 'is_admin': isAdmin,
      }),
    );
    return AdminUser.fromJson(await _decode(r) as Map<String, dynamic>);
  }

  Future<String> resetPassword({
    required String token,
    required int userId,
  }) async {
    final r = await _client.post(
      _u('/admin/users/$userId/reset-password'),
      headers: _headers(token),
    );
    final data = await _decode(r) as Map<String, dynamic>;
    return data['temporary_password'] as String;
  }

  Future<void> deleteUser({
    required String token,
    required int userId,
  }) async {
    final r = await _client.delete(
      _u('/admin/users/$userId'),
      headers: _headers(token),
    );
    await _decode(r);
  }
}

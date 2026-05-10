/// Модели DTO для общения с Auth API.
library;

class Entitlement {
  Entitlement({
    required this.productCode,
    required this.grantedAt,
    this.note,
  });

  final String productCode;
  final DateTime grantedAt;
  final String? note;

  factory Entitlement.fromJson(Map<String, dynamic> j) => Entitlement(
        productCode: j['product_code'] as String,
        grantedAt: DateTime.parse(j['granted_at'] as String),
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'product_code': productCode,
        'granted_at': grantedAt.toIso8601String(),
        if (note != null) 'note': note,
      };
}

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    required this.isAdmin,
    required this.mustChangePassword,
    required this.entitlements,
    this.fullName,
  });

  final int id;
  final String email;
  final String? fullName;
  final bool isAdmin;
  final bool mustChangePassword;
  final List<Entitlement> entitlements;

  bool hasProduct(String code) =>
      entitlements.any((e) => e.productCode == code);

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as int,
        email: j['email'] as String,
        fullName: j['full_name'] as String?,
        isAdmin: (j['is_admin'] as bool?) ?? false,
        mustChangePassword: (j['must_change_password'] as bool?) ?? false,
        entitlements: (j['entitlements'] as List<dynamic>? ?? const [])
            .map((e) => Entitlement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (fullName != null) 'full_name': fullName,
        'is_admin': isAdmin,
        'must_change_password': mustChangePassword,
        'entitlements': entitlements.map((e) => e.toJson()).toList(),
      };
}

class LoginResult {
  LoginResult({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final AuthUser user;

  factory LoginResult.fromJson(Map<String, dynamic> j) => LoginResult(
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        user: AuthUser.fromJson(j['user'] as Map<String, dynamic>),
      );
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.email,
    required this.isAdmin,
    required this.isActive,
    required this.mustChangePassword,
    required this.createdAt,
    required this.entitlements,
    this.fullName,
  });

  final int id;
  final String email;
  final String? fullName;
  final bool isAdmin;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime createdAt;
  final List<Entitlement> entitlements;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as int,
        email: j['email'] as String,
        fullName: j['full_name'] as String?,
        isAdmin: (j['is_admin'] as bool?) ?? false,
        isActive: (j['is_active'] as bool?) ?? true,
        mustChangePassword: (j['must_change_password'] as bool?) ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
        entitlements: (j['entitlements'] as List<dynamic>? ?? const [])
            .map((e) => Entitlement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProductInfo {
  ProductInfo({required this.code, required this.title});
  final String code;
  final String title;

  factory ProductInfo.fromJson(Map<String, dynamic> j) =>
      ProductInfo(code: j['code'] as String, title: j['title'] as String);
}

class CreateUserResult {
  CreateUserResult({required this.user, required this.temporaryPassword});
  final AdminUser user;
  final String temporaryPassword;

  factory CreateUserResult.fromJson(Map<String, dynamic> j) => CreateUserResult(
        user: AdminUser.fromJson(j['user'] as Map<String, dynamic>),
        temporaryPassword: j['temporary_password'] as String,
      );
}

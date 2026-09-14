import 'parse_utils.dart';

/// Authenticated user profile (`GET /api/auth/me`).
class AuthUser {
  final int id;
  final String username;
  final bool isAdmin;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastLogin;

  const AuthUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    required this.isActive,
    this.createdAt,
    this.lastLogin,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: asInt(json['id']) ?? 0,
      username: asString(json['username']),
      isAdmin: asBool(json['is_admin']),
      isActive: asBool(json['is_active'], fallback: true),
      createdAt: parseServerDateTime(json['created_at']?.toString()),
      lastLogin: parseServerDateTime(json['last_login']?.toString()),
    );
  }
}

/// Successful login payload (`POST /api/auth/login`).
class LoginResult {
  final String accessToken;
  final String username;
  final bool isAdmin;

  const LoginResult({
    required this.accessToken,
    required this.username,
    required this.isAdmin,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      accessToken: asString(json['access_token']),
      username: asString(json['username']),
      isAdmin: asBool(json['is_admin']),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../models/user.dart';

/// Wrapper tipizzato degli endpoint `/api/auth/*`.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// `POST /api/auth/login` (senza trailing slash sul path).
  Future<LoginResult> login(String username, String password) async {
    final data = await _client.post(
      '/auth/login',
      body: {'username': username, 'password': password},
    );
    return LoginResult.fromJson(_asMap(data));
  }

  /// `POST /api/auth/logout` (best-effort lato chiamante).
  Future<void> logout() async {
    await _client.post('/auth/logout');
  }

  /// `GET /api/auth/me`.
  Future<AuthUser> me() async {
    final data = await _client.get('/auth/me');
    return AuthUser.fromJson(_asMap(data));
  }

  /// `POST /api/auth/change-password`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      '/auth/change-password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  /// `GET /api/auth/users` (solo admin).
  Future<List<AuthUser>> users() async {
    final data = await _client.get('/auth/users');
    if (data is! List) {
      throw ApiException('Risposta non valida dal server.');
    }
    return [
      for (final item in data)
        if (item is Map) AuthUser.fromJson(item.cast<String, dynamic>()),
    ];
  }

  /// `POST /api/auth/users` (solo admin).
  Future<AuthUser> createUser({
    required String username,
    required String password,
    bool isAdmin = false,
  }) async {
    final data = await _client.post(
      '/auth/users',
      body: {'username': username, 'password': password, 'is_admin': isAdmin},
    );
    return AuthUser.fromJson(_asMap(data));
  }

  /// `DELETE /api/auth/users/{id}` (solo admin).
  Future<void> deleteUser(int userId) async {
    await _client.delete('/auth/users/$userId');
  }

  /// `PUT /api/auth/users/{id}/reset-password` (solo admin).
  Future<void> resetUserPassword({
    required int userId,
    required String newPassword,
  }) async {
    await _client.put(
      '/auth/users/$userId/reset-password',
      body: {'new_password': newPassword},
    );
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map) {
    return data.cast<String, dynamic>();
  }
  throw ApiException('Risposta non valida dal server.');
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GuardianApi {
  static const storage = FlutterSecureStorage();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 9),
    receiveTimeout: const Duration(seconds: 14),
    headers: {'Accept': 'application/json'},
  ));
  String serverUrl = const String.fromEnvironment('GUARDIAN_API_URL');
  String? accessToken;
  String? refreshToken;
  Future<void>? _refreshing;

  Future<void> restore() async {
    serverUrl = (await storage.read(key: 'guardian.api.url')) ?? serverUrl;
    accessToken = await storage.read(key: 'guardian.access.token');
    refreshToken = await storage.read(key: 'guardian.refresh.token');
    if (serverUrl.isNotEmpty) _validateUrl(serverUrl);
  }

  void _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' &&
      !(kDebugMode && uri.scheme == 'http' &&
      ['localhost','127.0.0.1','10.0.2.2'].contains(uri.host)))) {
      throw StateError('Usa HTTPS. HTTP solo está permitido en desarrollo local.');
    }
  }

  Future<void> configure(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/$'), '');
    _validateUrl(normalized);
    if (serverUrl != normalized) await clearTokens();
    serverUrl = normalized;
    await storage.write(key: 'guardian.api.url', value: serverUrl);
  }

  Future<void> saveTokens(Map<String,dynamic> data) async {
    accessToken = data['accessToken'] as String;
    refreshToken = data['refreshToken'] as String;
    await storage.write(key:'guardian.access.token', value:accessToken);
    await storage.write(key:'guardian.refresh.token', value:refreshToken);
  }

  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
    await storage.delete(key:'guardian.access.token');
    await storage.delete(key:'guardian.refresh.token');
  }

  Future<dynamic> get(String path) => _call('GET', path, null);
  Future<dynamic> post(String path, [Object? body]) => _call('POST', path, body);
  Future<dynamic> patch(String path, Object body) => _call('PATCH', path, body);
  Future<dynamic> delete(String path) => _call('DELETE', path, null);

  Future<dynamic> _call(String method, String path, Object? body,
      {bool retry = true}) async {
    if (serverUrl.isEmpty) throw StateError('Configura la URL del servidor');
    try {
      final response = await _dio.request<dynamic>('$serverUrl/api/v1$path',
        data: body,
        options: Options(method: method, headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        }),
      );
      return response.data;
    } on DioException catch (ex) {
      final publicAuth = ['/auth/login','/auth/register','/auth/verify','/auth/refresh'];
      if (retry && ex.response?.statusCode == 401 && refreshToken != null
          && !publicAuth.contains(path)) {
        await _refreshAccess();
        return _call(method, path, body, retry: false);
      }
      throw ApiFailure.fromDio(ex);
    }
  }

  Future<void> _refreshAccess() async {
    if (_refreshing != null) {
      await _refreshing;
      return;
    }
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      final response = await _dio.post<dynamic>('$serverUrl/api/v1/auth/refresh',
        data:{'refreshToken':refreshToken});
      await saveTokens(Map<String,dynamic>.from(response.data as Map));
      completer.complete();
    } catch (e) {
      await clearTokens();
      completer.completeError(e);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }
}

class ApiFailure implements Exception {
  final String message;
  final int? status;
  const ApiFailure(this.message, [this.status]);
  factory ApiFailure.fromDio(DioException e) {
    final raw = e.response?.data;
    if (raw is Map) {
      final msg = raw['detail'] ?? raw['message'] ?? raw['error'];
      if (msg is String && msg.isNotEmpty) return ApiFailure(msg, e.response?.statusCode);
    }
    if (e.response?.statusCode == 401) {
      return const ApiFailure('Sesión vencida o credenciales incorrectas',401);
    }
    if (e.response?.statusCode == 429) {
      return const ApiFailure('Demasiadas solicitudes. Intenta más tarde.',429);
    }
    return ApiFailure(e.response?.statusCode == null ?
      'No hay conexión con el servidor Guardian.' :
      'Ocurrió un error de conexión con el servidor.',
      e.response?.statusCode);
  }
  @override
  String toString() => message;
}
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:guardian_app/core/api.dart';
import 'package:guardian_app/core/push_bridge.dart';

class GuardianController extends ChangeNotifier {
  final GuardianApi api = GuardianApi();
  final PushBridge push = PushBridge();
  bool initialized = false;
  bool working = false;
  String? error;
  Map<String,dynamic>? profile;
  List<Map<String,dynamic>> devices = [];
  List<Map<String,dynamic>> approvals = [];
  List<Map<String,dynamic>> notifications = [];
  List<Map<String,dynamic>> incidents = [];
  Timer? _poll;
  bool _loading = false;

  bool get authenticated => profile != null;
  int get unread => notifications.where((it)=>it['read'] == false).length;
  int get pending => approvals.where((it) {
    final expiry = DateTime.tryParse((it['expiresAt'] ?? '').toString());
    return it['state'] == 'PENDING' && (expiry?.isAfter(DateTime.now()) ?? false);
  }).length;

  Future<void> initialize() async {
    try {
      await api.restore();
      if (api.accessToken != null && api.serverUrl.isNotEmpty) {
        await _restoreSession();
      }
    } catch (e) {
      error = '$e';
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> _restoreSession() async {
    try {
      profile = Map<String,dynamic>.from(await api.get('/auth/me') as Map);
      await reload();
      startPolling();
      await push.start(api,reload);
    } catch (e) {
      profile = null;
      if (e is ApiFailure && e.status == 401) await api.clearTokens();
    }
  }

  Future<void> setServer(String server) async {
    await api.configure(server);
    profile = null;
    devices = []; approvals = []; notifications = []; incidents = [];
    notifyListeners();
  }

  Future<void> register(String name, String email, String password) async {
    await api.post('/auth/register',{'name':name,'email':email,'password':password});
  }
  Future<void> verify(String email, String code) async {
    await api.post('/auth/verify',{'email':email,'code':code});
  }
  Future<void> login(String email, String password) async {
    working = true; error = null; notifyListeners();
    try {
      final tokens = Map<String,dynamic>.from(await api.post('/auth/login',
        {'email':email,'password':password,'clientLabel':'Guardian Flutter'}) as Map);
      await api.saveTokens(tokens);
      profile = Map<String,dynamic>.from(await api.get('/auth/me') as Map);
      await reload();
      startPolling();
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      working = false; notifyListeners();
    }
  }

  Future<void> logout() async {
    _poll?.cancel();
    await push.stop(api);
    try { await api.post('/auth/logout'); } catch (_) { /* Local sign-out works offline. */ }
    await api.clearTokens();
    profile = null;
    devices = []; approvals = []; notifications = []; incidents = [];
    notifyListeners();
  }

  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => reload());
  }
  Future<void> reload() async {
    if (!authenticated || _loading) return;
    _loading = true;
    try {
      final responses = await Future.wait<dynamic>([
        api.get('/devices'), api.get('/approvals'),
        api.get('/notifications'), api.get('/incidents'),
      ]);
      devices = _maps(responses[0]); approvals = _maps(responses[1]);
      notifications = _maps(responses[2]); incidents = _maps(responses[3]);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
  List<Map<String,dynamic>> _maps(dynamic data) =>
      (data as List).map((v)=>Map<String,dynamic>.from(v as Map)).toList();

  Future<Map<String,dynamic>> addDevice(String name,String platform) async {
    final result = Map<String,dynamic>.from(await api.post('/devices',
      {'name':name,'platform':platform}) as Map);
    await reload();
    return result;
  }
  Future<void> updatePolicy(String id, {
      required bool lockOnAway, required int seconds, required bool remoteApproval}) async {
    await api.patch('/devices/$id/policy',{
      'lockOnAway':lockOnAway,'awayTimeoutSeconds':seconds,
      'allowRemoteApproval':remoteApproval,
    });
    await reload();
  }
  Future<void> revokeDevice(String id) async {
    await api.delete('/devices/$id'); await reload();
  }
  Future<void> markRead(String id) async {
    await api.post('/notifications/$id/read'); await reload();
  }
  @override void dispose() { _poll?.cancel(); push.dispose(); super.dispose(); }
}
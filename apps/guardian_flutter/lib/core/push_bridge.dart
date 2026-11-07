import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:guardian_app/core/api.dart';

/// Requires Android/iOS Firebase project setup via flutterfire configure and
/// server-side Firebase Admin credentials. The app works without it, but
/// background pushes cannot work until configured.
class PushBridge {
  StreamSubscription<String>? _rotations;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  bool ready = false;
  String? token;

  Future<void> start(GuardianApi api, Future<void> Function() reload) async {
    if (!(Platform.isAndroid || Platform.isIOS) || ready) return;
    try {
      await Firebase.initializeApp();
      final fcm = FirebaseMessaging.instance;
      final settings = await fcm.requestPermission(
        alert:true,badge:true,sound:true,provisional:false);
      if(settings.authorizationStatus==AuthorizationStatus.denied) return;
      if(Platform.isIOS && await fcm.getAPNSToken()==null) return;
      final newToken=await fcm.getToken(); // deprecated upstream; see FID migration
      if(newToken==null) return;
      await api.post('/push/register',{
        'token':newToken,'platform':Platform.isAndroid?'ANDROID':'IOS'});
      token=newToken;
      ready=true;
      _rotations=fcm.onTokenRefresh.listen((newToken)async{
        token=newToken;
        try { await api.post('/push/register',{
          'token':newToken,'platform':Platform.isAndroid?'ANDROID':'IOS'}); }
        catch (_) { /* Retry at next login/registration. */ }
      });
      _foreground=FirebaseMessaging.onMessage.listen((_){
        reload();
      });
      _opened=FirebaseMessaging.onMessageOpenedApp.listen((_){
        reload();
      });
    } catch (_) {
      // Missing Firebase configuration is not an authentication failure.
      ready=false;
    }
  }

  Future<void> stop(GuardianApi api) async {
    if(token!=null) {
      try { await api.post('/push/unregister',{'token':token}); }
      catch (_) { /* Offline sign-out still clears local account credentials. */ }
    }
    if(ready) { try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {} }
    await _rotations?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
    ready=false;
    token=null;
  }

  Future<void> dispose() async {
    await _rotations?.cancel();
    await _foreground?.cancel();
    await _opened?.cancel();
  }
}
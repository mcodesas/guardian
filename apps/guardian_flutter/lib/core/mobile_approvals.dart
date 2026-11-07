import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:guardian_app/core/api.dart';

/// The prototype stores an Ed25519 software key in OS encrypted storage.
/// Production high-assurance approvals must instead use hardware-backed,
/// non-exportable keys with biometric authorization bound to SIGNING.
class MobileApprovals {
  final GuardianApi api;
  final String accountId;
  final biometrics = LocalAuthentication();
  final algorithm = Ed25519();

  MobileApprovals(this.api, this.accountId);

  String get _seedKey => 'guardian.mobile.$accountId.seed';
  String get _credentialKey => 'guardian.mobile.$accountId.credential';

  bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<bool> isEnrolled() async {
    if (!supported) return false;
    return await GuardianApi.storage.read(key:_seedKey)!=null &&
           await GuardianApi.storage.read(key:_credentialKey)!=null;
  }

  Future<void> _authenticate() async {
    if (!supported) {
      throw StateError('Solo Android o iOS pueden aprobar accesos.');
    }
    if (!await biometrics.canCheckBiometrics) {
      throw StateError('Configura Face ID o huella en tu celular.');
    }
    final ok = await biometrics.authenticate(
      localizedReason:'Guardian necesita tu huella o Face ID para esta operación',
      biometricOnly:true,
      sensitiveTransaction:true,
      persistAcrossBackgrounding:true,
    );
    if (!ok) throw StateError('No se completó la verificación biométrica.');
  }

  /// Explicit first-time setup, before any request requiring quick response.
  /// The backend sends an OTP to the verified email, tied to this session.
  Future<void> sendEnrollmentCode() async {
    if (!supported) throw StateError('Este proceso requiere Android o iOS.');
    if (await isEnrolled()) throw StateError('Este teléfono ya está vinculado.');
    await api.post('/mobile/credentials/challenge');
  }

  Future<void> enroll(String code) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw StateError('Introduce el código de seis dígitos.');
    }
    if (await isEnrolled()) throw StateError('El teléfono ya está vinculado.');
    await _authenticate();
    final pair = await algorithm.newKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();
    final publicKey = await pair.extractPublicKey();
    final response = Map<String,dynamic>.from(
      await api.post('/mobile/credentials', {
        'publicKey':base64Encode(publicKey.bytes),
        'platform':Platform.isAndroid?'ANDROID':'IOS',
        'verificationCode':code,
      }) as Map);
    await GuardianApi.storage.write(
      key:_seedKey,value:base64Encode(privateBytes));
    await GuardianApi.storage.write(
      key:_credentialKey,value:response['credentialId'] as String);
  }

  Future<({SimpleKeyPair pair, String credentialId})> _credential() async {
    final seed = await GuardianApi.storage.read(key:_seedKey);
    final id = await GuardianApi.storage.read(key:_credentialKey);
    if (seed==null || id==null) {
      throw StateError(
        'Vincula primero tu teléfono desde Mi cuenta. '
        'Para tu seguridad, no se permiten registros durante una solicitud.');
    }
    return (pair:await algorithm.newKeyPairFromSeed(base64Decode(seed)),
            credentialId:id);
  }

  Future<void> decide(Map<String,dynamic> challenge, {
    required bool approve,
    required int minutes,
  }) async {
    if(challenge['state']!='PENDING') {
      throw StateError('La solicitud ya no está pendiente.');
    }
    final expires=DateTime.parse(challenge['expiresAt'] as String);
    if(!DateTime.now().isBefore(expires)) {
      throw StateError('La solicitud caducó. No se puede aprobar.');
    }
    if(approve && ![5,15,30].contains(minutes)) {
      throw StateError('Selecciona 5, 15 o 30 minutos.');
    }
    // Validate local registration before biometric prompt.
    final credentials=await _credential();
    await _authenticate();
    if(!DateTime.now().isBefore(expires)) {
      throw StateError('La solicitud venció durante la autenticación.');
    }
    final decision=approve?'APPROVED':'REJECTED';
    final duration=approve?minutes:0;
    final id=challenge['id'] as String;
    final nonce=challenge['nonce'] as String;
    final canonical='guardian:v1:$id:$nonce:$decision:$duration';
    final signed=await algorithm.sign(
      utf8.encode(canonical),keyPair:credentials.pair);
    await api.post('/approvals/$id/decision',{
      'credentialId':credentials.credentialId,
      'decision':decision,
      'trustMinutes':duration,
      'signature':base64Encode(signed.bytes),
    });
  }

  Future<Map<String,String>> registrationProof(String token) async {
    final credential=await _credential();
    final content='guardian:push:v1:${credential.credentialId}:$token';
    final sig=await algorithm.sign(utf8.encode(content),keyPair:credential.pair);
    return {
      'token':token,
      'platform':Platform.isAndroid?'ANDROID':'IOS',
      'credentialId':credential.credentialId,
      'signature':base64Encode(sig.bytes),
    };
  }

  /// Local-only logout must NOT delete the key: it is bound to this account
  /// and can be revoked from the server in a separate authenticated session.
}

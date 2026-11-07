import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:guardian_app/core/api.dart';

/// The software key is protected with OS encrypted storage, but is not
/// guaranteed to be hardware-backed. Native non-exportable keys are the
/// production hardening step for high-assurance approvals.
class MobileApprovals {
  final GuardianApi api;
  final String accountId;
  final biometrics = LocalAuthentication();
  final algorithm = Ed25519();

  MobileApprovals(this.api, this.accountId);

  String get _seedKey => 'guardian.mobile.$accountId.seed';
  String get _credentialKey => 'guardian.mobile.$accountId.credential';

  Future<void> _authenticate() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw StateError('Aprobaciones disponibles únicamente en Android o iOS.');
    }
    if (!await biometrics.canCheckBiometrics) {
      throw StateError('Configura huella o Face ID en tu teléfono.');
    }
    final ok = await biometrics.authenticate(
      localizedReason: 'Confirma tu identidad para responder a Guardian',
      biometricOnly: true,
      sensitiveTransaction: true,
      persistAcrossBackgrounding: true,
    );
    if (!ok) throw StateError('Autenticación biométrica cancelada.');
  }

  Future<({SimpleKeyPair pair, String credentialId})> _credential() async {
    final existingSeed = await GuardianApi.storage.read(key:_seedKey);
    final existingId = await GuardianApi.storage.read(key:_credentialKey);
    if (existingSeed != null && existingId != null) {
      return (pair:await algorithm.newKeyPairFromSeed(base64Decode(existingSeed)),
              credentialId:existingId);
    }
    final pair = existingSeed != null
      ? await algorithm.newKeyPairFromSeed(base64Decode(existingSeed))
      : await algorithm.newKeyPair();
    final seed = await pair.extractPrivateKeyBytes();
    final publicKey = await pair.extractPublicKey();
    final result = Map<String,dynamic>.from(await api.post('/mobile/credentials',{
      'publicKey':base64Encode(publicKey.bytes),
      'platform': Platform.isAndroid ? 'ANDROID' : 'IOS',
      'label':'Guardian Mobile',
    }) as Map);
    final id = result['credentialId'] as String;
    await GuardianApi.storage.write(key:_seedKey,value:base64Encode(seed));
    await GuardianApi.storage.write(key:_credentialKey,value:id);
    return (pair:pair,credentialId:id);
  }

  Future<void> decide(Map<String,dynamic> challenge, {
    required bool approve,
    required int minutes,
  }) async {
    if (challenge['state'] != 'PENDING') throw StateError('Solicitud no pendiente.');
    final expiry = DateTime.parse(challenge['expiresAt'] as String);
    if (!DateTime.now().isBefore(expiry)) throw StateError('La solicitud ya venció.');
    if (approve && ![5,15,30].contains(minutes)) throw StateError('Duración inválida');
    await _authenticate();
    final credential = await _credential();
    final decision = approve ? 'APPROVED' : 'REJECTED';
    final trust = approve ? minutes : 0;
    final id = challenge['id'] as String;
    final nonce = challenge['nonce'] as String;
    final payload = 'guardian:v1:$id:$nonce:$decision:$trust';
    final signed = await algorithm.sign(utf8.encode(payload),keyPair:credential.pair);
    await api.post('/approvals/$id/decision',{
      'credentialId':credential.credentialId,
      'decision':decision,
      'trustMinutes':trust,
      'signature':base64Encode(signed.bytes),
    });
  }
}
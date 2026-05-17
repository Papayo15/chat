import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;

class IdentityService {
  final FirebaseAuth _auth;

  IdentityService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  // ─── Phone Auth (SMS OTP) ────────────────────────────────────────────────

  /// Step 1: send OTP. Returns the ConfirmationResult needed for step 2.
  /// [recaptchaContainerId] must match the div id in index.html.
  Future<ConfirmationResult> sendPhoneOtp({
    required String phoneE164,
    required String recaptchaContainerId,
  }) async {
    final verifier = RecaptchaVerifier(
      container: recaptchaContainerId,
      size: RecaptchaVerifierSize.compact,
      theme: RecaptchaVerifierTheme.dark,
      auth: FirebaseAuthPlatform.instanceFor(
        app: _auth.app,
        pluginConstants: const {},
      ),
    );
    return await _auth.signInWithPhoneNumber(phoneE164, verifier);
  }

  /// Step 2: confirm OTP and sign in. Returns the signed-in User.
  Future<User> confirmPhoneOtp({
    required ConfirmationResult confirmationResult,
    required String smsCode,
  }) async {
    final credential = await confirmationResult.confirm(smsCode);
    return credential.user!;
  }

  // ─── Anonymous Auth ──────────────────────────────────────────────────────

  /// Sign in anonymously. Firebase assigns a persistent UID.
  Future<User> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  /// Generate the QR pairing code string for this user.
  String buildPairingCode(String uid) => 'SCHAT_PAIR:$uid';

  /// Parse a scanned/pasted pairing code. Returns the UID or null if invalid.
  String? parsePairingCode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('SCHAT_PAIR:')) return null;
    final uid = trimmed.substring('SCHAT_PAIR:'.length);
    return uid.isNotEmpty ? uid : null;
  }

  // ─── Contact Discovery ───────────────────────────────────────────────────

  /// Hash a phone number in E.164 format locally with SHA-256.
  /// Never send the raw number to Firestore.
  static String hashPhone(String phoneE164) {
    final bytes = utf8.encode(phoneE164.trim());
    return sha256.convert(bytes).toString();
  }

  /// Hash a list of phone numbers. Returns map of original → hash.
  static Map<String, String> hashPhoneList(List<String> phones) {
    return {for (final p in phones) p: hashPhone(p)};
  }
}

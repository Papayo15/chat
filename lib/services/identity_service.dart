import 'package:firebase_auth/firebase_auth.dart';

class IdentityService {
  final FirebaseAuth _auth;

  IdentityService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  // ─── Anonymous Auth ──────────────────────────────────────────────────────

  Future<User> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  // ─── QR Pairing ─────────────────────────────────────────────────────────

  String buildPairingCode(String uid) => 'SCHAT_PAIR:$uid';

  String? parsePairingCode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('SCHAT_PAIR:')) return null;
    final uid = trimmed.substring('SCHAT_PAIR:'.length);
    return uid.isNotEmpty ? uid : null;
  }
}

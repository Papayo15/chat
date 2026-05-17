import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../services/crypto_service.dart';

class UserRepository {
  final FirebaseFirestore _db;
  // ignore: unused_field
  final FirebaseAuth _auth;
  final CryptoService _crypto;

  UserRepository({
    required FirebaseFirestore db,
    required FirebaseAuth auth,
    required CryptoService crypto,
  })  : _db = db,
        _auth = auth,
        _crypto = crypto;

  Future<AppUser> registerOrLogin(User firebaseUser, {String? phoneHash}) async {
    final docRef = _db.collection('users').doc(firebaseUser.uid);
    final snap = await docRef.get();

    if (snap.exists) {
      final existing = AppUser.fromMap(snap.data()!);
      // Update phoneHash if newly provided and not yet stored
      if (phoneHash != null && existing.phoneHash == null) {
        await docRef.update({'phoneHash': phoneHash});
        return AppUser(
          uid: existing.uid,
          displayName: existing.displayName,
          email: existing.email,
          publicKey: existing.publicKey,
          phoneHash: phoneHash,
          createdAt: existing.createdAt,
        );
      }
      return existing;
    }

    await _crypto.generateAndStoreKeyPair();
    final publicKey = await _crypto.getPublicKeyBase64();

    final displayName = firebaseUser.displayName ??
        firebaseUser.phoneNumber ??
        'Anónimo-${firebaseUser.uid.substring(0, 6)}';

    final user = AppUser(
      uid: firebaseUser.uid,
      displayName: displayName,
      email: firebaseUser.email ?? '',
      publicKey: publicKey,
      phoneHash: phoneHash,
      createdAt: DateTime.now(),
    );

    await docRef.set(user.toMap());
    return user;
  }

  Future<AppUser?> getUserById(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    return AppUser.fromMap(snap.data()!);
  }

  Future<List<AppUser>> searchUsersByEmail(String email) async {
    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(5)
        .get();
    return snap.docs.map((d) => AppUser.fromMap(d.data())).toList();
  }

  /// Hash a phone number locally (SHA-256) and query Firestore by the hash.
  /// The raw phone number is NEVER sent to the server.
  Future<List<AppUser>> searchUsersByPhone(String phoneE164) async {
    final hash = _hashPhone(phoneE164);
    return searchUsersByPhoneHash(hash);
  }

  Future<List<AppUser>> searchUsersByPhoneHash(String phoneHash) async {
    final snap = await _db
        .collection('users')
        .where('phoneHash', isEqualTo: phoneHash)
        .limit(5)
        .get();
    return snap.docs.map((d) => AppUser.fromMap(d.data())).toList();
  }

  static String _hashPhone(String phoneE164) {
    final bytes = utf8.encode(phoneE164.trim());
    return sha256.convert(bytes).toString();
  }
}

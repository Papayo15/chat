import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String publicKey;
  final String? phoneHash; // SHA-256 hex of E.164 phone number, never the raw number
  final DateTime createdAt;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.publicKey,
    this.phoneHash,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'publicKey': publicKey,
      'createdAt': Timestamp.fromDate(createdAt),
    };
    if (phoneHash != null) map['phoneHash'] = phoneHash;
    return map;
  }

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        uid: map['uid'] as String,
        displayName: map['displayName'] as String,
        email: map['email'] as String? ?? '',
        publicKey: map['publicKey'] as String,
        phoneHash: map['phoneHash'] as String?,
        createdAt: (map['createdAt'] as Timestamp).toDate(),
      );
}

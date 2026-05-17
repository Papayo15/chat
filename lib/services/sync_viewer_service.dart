import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SyncViewerState {
  final String url;
  final double scrollY;
  final int page;
  final String updatedBy;
  final DateTime updatedAt;

  const SyncViewerState({
    required this.url,
    required this.scrollY,
    required this.page,
    required this.updatedBy,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'scrollY': scrollY,
        'page': page,
        'updatedBy': updatedBy,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory SyncViewerState.fromMap(Map<String, dynamic> map) => SyncViewerState(
        url: map['url'] as String,
        scrollY: (map['scrollY'] as num).toDouble(),
        page: map['page'] as int,
        updatedBy: map['updatedBy'] as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      );
}

class SyncViewerService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  SyncViewerService({
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  })  : _db = db,
        _auth = auth;

  Stream<SyncViewerState> stateStream(String chatId, String sessionId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('syncViewer')
        .doc(sessionId)
        .snapshots()
        .where((snap) => snap.exists)
        .map((snap) => SyncViewerState.fromMap(snap.data()!));
  }

  Future<void> updateState({
    required String chatId,
    required String sessionId,
    required String url,
    required double scrollY,
    required int page,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds < 500) return;
    _lastUpdate = now;

    final uid = _auth.currentUser!.uid;
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('syncViewer')
        .doc(sessionId)
        .set(SyncViewerState(
          url: url,
          scrollY: scrollY,
          page: page,
          updatedBy: uid,
          updatedAt: now,
        ).toMap());
  }

  Future<void> endSession(String chatId, String sessionId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('syncViewer')
        .doc(sessionId)
        .delete();
  }
}

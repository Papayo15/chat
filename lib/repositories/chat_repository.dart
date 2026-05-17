import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat.dart';

class ChatRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  ChatRepository({
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  })  : _db = db,
        _auth = auth;

  Stream<List<Chat>> chatsStream() {
    final uid = _auth.currentUser!.uid;
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Chat.fromDoc).toList());
  }

  Future<Chat> createOrFindChat(List<String> participantUids) async {
    final uid = _auth.currentUser!.uid;
    final allParticipants = ({...participantUids, uid}.toList())..sort();

    final existing = await _db
        .collection('chats')
        .where('participants', isEqualTo: allParticipants)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return Chat.fromDoc(existing.docs.first);
    }

    final ref = _db.collection('chats').doc();
    final chat = Chat(
      id: ref.id,
      participants: allParticipants,
      createdBy: uid,
      createdAt: DateTime.now(),
    );
    await ref.set(chat.toMap());
    return chat;
  }
}

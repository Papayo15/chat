// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/encrypted_message.dart';

const int kHistoryPageSize = 20;

class HistoryPage {
  final List<EncryptedMessage> messages;

  // Timestamps used as cursors for prev/next pagination.
  // Stored directly so rawDocs don't need to stay in memory.
  final Timestamp? oldestTs;
  final Timestamp? newestTs;

  final bool hasOlder;
  final bool hasNewer;
  final DateTime anchorDate;

  const HistoryPage({
    required this.messages,
    required this.oldestTs,
    required this.newestTs,
    required this.hasOlder,
    required this.hasNewer,
    required this.anchorDate,
  });

  bool get isEmpty => messages.isEmpty;
}

class HistoryRepository {
  final FirebaseFirestore _db;

  HistoryRepository({required FirebaseFirestore db}) : _db = db;

  CollectionReference<Map<String, dynamic>> _col(String chatId) =>
      _db.collection('chats').doc(chatId).collection('messages');

  /// Jump to a specific date. Returns first page (20 msgs) at or after [date].
  Future<HistoryPage> jumpToDate(String chatId, DateTime date) async {
    final snap = await _col(chatId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(date))
        .orderBy('timestamp')
        .limit(kHistoryPageSize + 1)
        .get();

    return _buildAscPage(snap, anchorDate: date, hasOlderDefault: true);
  }

  /// Load the next batch of messages after [afterTs].
  Future<HistoryPage> loadNewer({
    required String chatId,
    required Timestamp afterTs,
    required DateTime anchorDate,
  }) async {
    final snap = await _col(chatId)
        .where('timestamp', isGreaterThan: afterTs)
        .orderBy('timestamp')
        .limit(kHistoryPageSize + 1)
        .get();

    return _buildAscPage(snap, anchorDate: anchorDate, hasOlderDefault: true);
  }

  /// Load the previous batch of messages before [beforeTs].
  Future<HistoryPage> loadOlder({
    required String chatId,
    required Timestamp beforeTs,
    required DateTime anchorDate,
  }) async {
    // Query descending to get the nearest older messages, then flip.
    final snap = await _col(chatId)
        .where('timestamp', isLessThan: beforeTs)
        .orderBy('timestamp', descending: true)
        .limit(kHistoryPageSize)
        .get();

    if (snap.docs.isEmpty) {
      return HistoryPage(
        messages: const [],
        oldestTs: null,
        newestTs: null,
        hasOlder: false,
        hasNewer: true,
        anchorDate: anchorDate,
      );
    }

    // Reverse so messages appear oldest-first.
    final docs = snap.docs.reversed.toList();
    final oldestTs = docs.first.data()['timestamp'] as Timestamp;
    final newestTs = docs.last.data()['timestamp'] as Timestamp;

    return HistoryPage(
      messages: docs.map(EncryptedMessage.fromDoc).toList(),
      oldestTs: oldestTs,
      newestTs: newestTs,
      hasOlder: snap.docs.length == kHistoryPageSize,
      hasNewer: true,
      anchorDate: anchorDate,
    );
  }

  HistoryPage _buildAscPage(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required DateTime anchorDate,
    bool hasOlderDefault = false,
  }) {
    final all = snap.docs;
    final hasNewer = all.length > kHistoryPageSize;
    final docs = hasNewer ? all.sublist(0, kHistoryPageSize) : all;

    if (docs.isEmpty) {
      return HistoryPage(
        messages: const [],
        oldestTs: null,
        newestTs: null,
        hasOlder: false,
        hasNewer: false,
        anchorDate: anchorDate,
      );
    }

    return HistoryPage(
      messages: docs.map(EncryptedMessage.fromDoc).toList(),
      oldestTs: docs.first.data()['timestamp'] as Timestamp,
      newestTs: docs.last.data()['timestamp'] as Timestamp,
      hasOlder: hasOlderDefault,
      hasNewer: hasNewer,
      anchorDate: anchorDate,
    );
  }
}

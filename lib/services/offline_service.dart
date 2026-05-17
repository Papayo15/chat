import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'crypto_service.dart';

/// Queues text messages (and file messages with fileData already embedded)
/// in localStorage when offline, and flushes them to Firestore when
/// connectivity returns. No Firebase Storage required.
class OfflineService {
  final FirebaseFirestore _db;
  final CryptoService _crypto;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isFlushing = false;

  OfflineService({
    required FirebaseFirestore db,
    required CryptoService crypto,
  })  : _db = db,
        _crypto = crypto;

  void startListening() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _flushQueue();
      }
    });
  }

  Future<void> enqueue(String chatId, Map<String, dynamic> messageData) async {
    final queue = _crypto.getOfflineQueue();
    queue.add({
      'chatId': chatId,
      'data': messageData,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    _crypto.saveOfflineQueue(queue);
  }

  Future<void> _flushQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      final queue = _crypto.getOfflineQueue();
      if (queue.isEmpty) return;
      final failed = <Map<String, dynamic>>[];
      for (final item in queue) {
        try {
          await _db
              .collection('chats')
              .doc(item['chatId'] as String)
              .collection('messages')
              .add(Map<String, dynamic>.from(item['data'] as Map));
        } catch (_) {
          failed.add(item);
        }
      }
      _crypto.saveOfflineQueue(failed);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
  }
}

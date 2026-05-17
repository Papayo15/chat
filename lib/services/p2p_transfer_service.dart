import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stub — P2P file transfer via WebRTC DataChannels.
/// Files under 500 KB go through Firestore (already implemented).
/// Large-file P2P can be re-enabled by adding flutter_webrtc back.
class P2PTransferService {
  // ignore: unused_field
  final FirebaseFirestore _db;
  // ignore: unused_field
  final FirebaseAuth _auth;

  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
  Stream<double> get transferProgress => _progressController.stream;

  final StreamController<Uint8List> _receivedFileController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get receivedFile => _receivedFileController.stream;

  P2PTransferService({
    required FirebaseFirestore db,
    required FirebaseAuth auth,
  })  : _db = db,
        _auth = auth;

  Future<String> initiateSend({
    required String chatId,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    throw UnsupportedError(
      'Para archivos grandes usa la transferencia directa cuando ambos estén conectados.',
    );
  }

  Future<void> receiveFile({
    required String chatId,
    required String sessionId,
    required String senderUid,
  }) async {}

  Future<void> dispose() async {
    await _progressController.close();
    await _receivedFileController.close();
  }
}

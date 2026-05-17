import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/encrypted_message.dart';
import '../services/crypto_service.dart';
import '../services/data_saving_service.dart';
import '../services/offline_service.dart';

// Max file size: 500KB before encryption (~667KB base64 → fits in Firestore 1MB doc)
const int _maxFileSizeBytes = 524288;

class MessageRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final CryptoService _crypto;
  final DataSavingService _dataSaving;
  final OfflineService _offline;

  MessageRepository({
    required FirebaseFirestore db,
    required FirebaseAuth auth,
    required CryptoService crypto,
    required DataSavingService dataSaving,
    required OfflineService offline,
  })  : _db = db,
        _auth = auth,
        _crypto = crypto,
        _dataSaving = dataSaving,
        _offline = offline;

  Stream<List<EncryptedMessage>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(EncryptedMessage.fromDoc).toList());
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String plainText,
    required SecretKey sharedKey,
    bool ephemeral = false,
    bool isOffline = false,
  }) async {
    final uid = _auth.currentUser!.uid;
    final encrypted = await _crypto.encryptText(plainText, sharedKey);
    final msg = EncryptedMessage(
      id: '',
      chatId: chatId,
      senderId: uid,
      payload: encrypted,
      type: MessageType.text,
      ephemeral: ephemeral,
      read: false,
      timestamp: DateTime.now(),
    );
    if (isOffline) {
      await _offline.enqueue(chatId, msg.toMap());
    } else {
      await _db.collection('chats').doc(chatId).collection('messages').add(msg.toMap());
    }
  }

  /// Encrypt file and store it as base64 directly in the Firestore message document.
  /// No Firebase Storage needed — completely free.
  /// Limit: 500KB before encryption. Files above that must use P2P transfer.
  Future<void> sendFileMessage({
    required String chatId,
    required Uint8List fileBytes,
    required MessageType type,
    required SecretKey sharedKey,
    bool ephemeral = false,
    String? originalFileName,
    bool isOffline = false,
    String? recipientPhone,
  }) async {
    final uid = _auth.currentUser!.uid;

    // Compress images before size check
    Uint8List processedBytes = fileBytes;
    if (type == MessageType.image) {
      processedBytes = await _dataSaving.compressImageAdaptive(fileBytes);
    }

    if (processedBytes.length > _maxFileSizeBytes) {
      throw Exception(
        'Archivo demasiado grande (${(processedBytes.length / 1024).round()} KB). '
        'Máximo 500 KB. Para archivos grandes usa la transferencia P2P.',
      );
    }

    // Encrypt in memory
    final fileKey = await _crypto.generateFileKey();
    final encryptedBytes = await _crypto.encryptFile(processedBytes, fileKey);
    final encryptedFileKey = await _crypto.encryptFileKey(fileKey, sharedKey);
    final payloadEncrypted = await _crypto.encryptText(
      originalFileName ?? '[archivo adjunto]',
      sharedKey,
    );

    // Store encrypted file as base64 directly in Firestore document
    final fileDataB64 = base64.encode(encryptedBytes);

    final msg = EncryptedMessage(
      id: '',
      chatId: chatId,
      senderId: uid,
      payload: payloadEncrypted,
      type: type,
      fileData: fileDataB64,
      fileName: originalFileName,
      encryptedFileKey: encryptedFileKey,
      ephemeral: ephemeral,
      read: false,
      timestamp: DateTime.now(),
    );

    if (isOffline) {
      await _offline.enqueue(chatId, msg.toMap());
    } else {
      await _db.collection('chats').doc(chatId).collection('messages').add(msg.toMap());
    }
  }

  Future<void> sendCallInvite({
    required String chatId,
    required String roomId,
    required String roomPassword,
    required SecretKey sharedKey,
  }) async {
    final uid = _auth.currentUser!.uid;
    final inviteText = 'CALL_INVITE:$roomId:$roomPassword';
    final encrypted = await _crypto.encryptText(inviteText, sharedKey);
    final msg = EncryptedMessage(
      id: '',
      chatId: chatId,
      senderId: uid,
      payload: encrypted,
      type: MessageType.callInvite,
      ephemeral: false,
      read: false,
      timestamp: DateTime.now(),
    );
    await _db.collection('chats').doc(chatId).collection('messages').add(msg.toMap());
  }

  Future<void> sendSmsImport({
    required String chatId,
    required String decryptedText,
    required SecretKey sharedKey,
  }) async {
    final uid = _auth.currentUser!.uid;
    final encrypted = await _crypto.encryptText('[SMS] $decryptedText', sharedKey);
    final msg = EncryptedMessage(
      id: '',
      chatId: chatId,
      senderId: uid,
      payload: encrypted,
      type: MessageType.smsImport,
      ephemeral: false,
      read: true,
      timestamp: DateTime.now(),
    );
    await _db.collection('chats').doc(chatId).collection('messages').add(msg.toMap());
  }

  Future<void> deleteEphemeralMessage(String chatId, String messageId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  Future<void> markAsRead(String chatId, String messageId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'read': true});
  }
}

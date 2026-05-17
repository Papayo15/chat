import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/encrypted_message.dart';
import '../services/cloudinary_service.dart';
import '../services/crypto_service.dart';
import '../services/data_saving_service.dart';
import '../services/offline_service.dart';

// Files ≤ 500 KB go into Firestore as base64. Larger files go to Cloudinary.
const int _firestoreMaxBytes = 524288;

class MessageRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final CryptoService _crypto;
  final DataSavingService _dataSaving;
  final OfflineService _offline;
  final CloudinaryService _cloudinary = CloudinaryService();

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

  /// Encrypt and send a file.
  /// • Files ≤ 500 KB → stored as base64 in Firestore (free, instant).
  /// • Files > 500 KB → uploaded to Cloudinary (free, up to 25 GB/month).
  /// All files are AES-256-GCM encrypted before leaving the device.
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

    // Compress images adaptively
    Uint8List processedBytes = fileBytes;
    if (type == MessageType.image) {
      processedBytes = await _dataSaving.compressImageAdaptive(fileBytes);
    }

    // Encrypt in memory
    final fileKey = await _crypto.generateFileKey();
    final encryptedBytes = await _crypto.encryptFile(processedBytes, fileKey);
    final encryptedFileKey = await _crypto.encryptFileKey(fileKey, sharedKey);
    final payloadEncrypted = await _crypto.encryptText(
      originalFileName ?? '[archivo adjunto]',
      sharedKey,
    );

    String? fileDataB64;
    String? cloudinaryUrl;
    final fileId = '${chatId}_${DateTime.now().millisecondsSinceEpoch}';

    if (processedBytes.length <= _firestoreMaxBytes) {
      // Small file — store as base64 in Firestore document
      fileDataB64 = base64.encode(encryptedBytes);
    } else {
      // Large file — upload encrypted bytes to Cloudinary
      if (isOffline) {
        throw Exception(
          'Sin conexión. Los archivos grandes requieren internet para enviarse.',
        );
      }
      cloudinaryUrl = await _cloudinary.uploadEncryptedFile(encryptedBytes, fileId);
    }

    final msg = EncryptedMessage(
      id: '',
      chatId: chatId,
      senderId: uid,
      payload: payloadEncrypted,
      type: type,
      fileData: fileDataB64,
      cloudinaryUrl: cloudinaryUrl,
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

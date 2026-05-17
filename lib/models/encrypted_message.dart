import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, audio, file, callInvite, callEnded, smsImport }

class EncryptedPayload {
  final String ciphertext;
  final String nonce;
  final String mac;

  const EncryptedPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  Map<String, dynamic> toMap() => {
        'ciphertext': ciphertext,
        'nonce': nonce,
        'mac': mac,
      };

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) => EncryptedPayload(
        ciphertext: map['ciphertext'] as String,
        nonce: map['nonce'] as String,
        mac: map['mac'] as String,
      );
}

class EncryptedMessage {
  final String id;
  final String chatId;
  final String senderId;
  final EncryptedPayload payload;
  final MessageType type;
  final String? fileData;       // base64 encrypted file bytes stored in Firestore
  final String? fileName;       // original filename
  final EncryptedPayload? encryptedFileKey;
  final bool ephemeral;
  final bool read;
  final DateTime timestamp;

  const EncryptedMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.payload,
    required this.type,
    this.fileData,
    this.fileName,
    this.encryptedFileKey,
    required this.ephemeral,
    required this.read,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'senderId': senderId,
      'payload': payload.toMap(),
      'type': type.name,
      'ephemeral': ephemeral,
      'read': read,
      'timestamp': Timestamp.fromDate(timestamp),
    };
    if (fileData != null) map['fileData'] = fileData;
    if (fileName != null) map['fileName'] = fileName;
    if (encryptedFileKey != null) map['encryptedFileKey'] = encryptedFileKey!.toMap();
    return map;
  }

  factory EncryptedMessage.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EncryptedMessage(
      id: doc.id,
      chatId: '',
      senderId: data['senderId'] as String,
      payload: EncryptedPayload.fromMap(data['payload'] as Map<String, dynamic>),
      type: MessageType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MessageType.text,
      ),
      fileData: data['fileData'] as String?,
      fileName: data['fileName'] as String?,
      encryptedFileKey: data['encryptedFileKey'] != null
          ? EncryptedPayload.fromMap(data['encryptedFileKey'] as Map<String, dynamic>)
          : null,
      ephemeral: data['ephemeral'] as bool? ?? false,
      read: data['read'] as bool? ?? false,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}

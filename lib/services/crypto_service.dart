// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/encrypted_message.dart';

class CryptoService {
  static const _privateKeyEntry = 'sc_x25519_private';
  static const _publicKeyEntry = 'sc_x25519_public';
  static const _queueKey = 'sc_offline_queue';

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();

  // init() kept for API compatibility — no async setup needed with localStorage
  Future<void> init() async {}

  Future<SimpleKeyPair> generateAndStoreKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    html.window.localStorage[_privateKeyEntry] = base64.encode(privateBytes);
    html.window.localStorage[_publicKeyEntry] = base64.encode(publicKey.bytes);

    return keyPair;
  }

  Future<SimpleKeyPair?> loadStoredKeyPair() async {
    final privateB64 = html.window.localStorage[_privateKeyEntry];
    final publicB64 = html.window.localStorage[_publicKeyEntry];
    if (privateB64 == null || publicB64 == null) return null;

    return SimpleKeyPairData(
      base64.decode(privateB64),
      publicKey: SimplePublicKey(base64.decode(publicB64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  Future<String> getPublicKeyBase64() async {
    return html.window.localStorage[_publicKeyEntry] ??
        (throw StateError('No key pair stored. Call generateAndStoreKeyPair first.'));
  }

  Future<SecretKey> deriveSharedSecret(
    SimpleKeyPair myKeyPair,
    String theirPublicKeyBase64,
  ) async {
    final theirPublicBytes = base64.decode(theirPublicKeyBase64);
    final theirPublicKey = SimplePublicKey(theirPublicBytes, type: KeyPairType.x25519);
    return _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );
  }

  Future<EncryptedPayload> encryptText(String plainText, SecretKey key) async {
    final plainBytes = utf8.encode(plainText);
    final secretBox = await _aesGcm.encrypt(plainBytes, secretKey: key);
    return EncryptedPayload(
      ciphertext: base64.encode(secretBox.cipherText),
      nonce: base64.encode(secretBox.nonce),
      mac: base64.encode(secretBox.mac.bytes),
    );
  }

  Future<String> decryptText(EncryptedPayload payload, SecretKey key) async {
    final secretBox = SecretBox(
      base64.decode(payload.ciphertext),
      nonce: base64.decode(payload.nonce),
      mac: Mac(base64.decode(payload.mac)),
    );
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
  }

  Future<SecretKey> generateFileKey() => _aesGcm.newSecretKey();

  Future<Uint8List> encryptFile(Uint8List fileBytes, SecretKey fileKey) async {
    final secretBox = await _aesGcm.encrypt(fileBytes, secretKey: fileKey);
    final nonce = Uint8List.fromList(secretBox.nonce);
    final mac = Uint8List.fromList(secretBox.mac.bytes);
    final cipher = Uint8List.fromList(secretBox.cipherText);
    // Header: [nonceLen(1 byte), macLen(1 byte), reserved(2 bytes)]
    final header = Uint8List(4)
      ..[0] = nonce.length
      ..[1] = mac.length;
    return Uint8List.fromList([...header, ...nonce, ...mac, ...cipher]);
  }

  Future<Uint8List> decryptFile(Uint8List encryptedData, SecretKey fileKey) async {
    final nonceLen = encryptedData[0];
    final macLen = encryptedData[1];
    int offset = 4;
    final nonce = encryptedData.sublist(offset, offset + nonceLen);
    offset += nonceLen;
    final mac = encryptedData.sublist(offset, offset + macLen);
    offset += macLen;
    final cipher = encryptedData.sublist(offset);
    final secretBox = SecretBox(cipher, nonce: nonce, mac: Mac(mac));
    return Uint8List.fromList(await _aesGcm.decrypt(secretBox, secretKey: fileKey));
  }

  Future<EncryptedPayload> encryptFileKey(
    SecretKey fileKey,
    SecretKey sharedKey,
  ) async {
    final fileKeyBytes = await fileKey.extractBytes();
    final secretBox = await _aesGcm.encrypt(fileKeyBytes, secretKey: sharedKey);
    return EncryptedPayload(
      ciphertext: base64.encode(secretBox.cipherText),
      nonce: base64.encode(secretBox.nonce),
      mac: base64.encode(secretBox.mac.bytes),
    );
  }

  Future<SecretKey> decryptFileKey(
    EncryptedPayload payload,
    SecretKey sharedKey,
  ) async {
    final secretBox = SecretBox(
      base64.decode(payload.ciphertext),
      nonce: base64.decode(payload.nonce),
      mac: Mac(base64.decode(payload.mac)),
    );
    final fileKeyBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedKey);
    return SecretKey(fileKeyBytes);
  }

  // Encrypt plaintext to a single base64 blob (for SMS fallback)
  Future<String> encryptToBase64(String plainText, SecretKey key) async {
    final payload = await encryptText(plainText, key);
    return base64.encode(utf8.encode(jsonEncode({
      'c': payload.ciphertext,
      'n': payload.nonce,
      'm': payload.mac,
    })));
  }

  // Decrypt a base64 blob back to plaintext (SMS fallback import)
  Future<String> decryptFromBase64(String b64, SecretKey key) async {
    final decoded = jsonDecode(utf8.decode(base64.decode(b64))) as Map<String, dynamic>;
    final payload = EncryptedPayload(
      ciphertext: decoded['c'] as String,
      nonce: decoded['n'] as String,
      mac: decoded['m'] as String,
    );
    return decryptText(payload, key);
  }

  String generateRoomId(String chatId) {
    final rnd = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hashInput = [...utf8.encode(chatId), ...rnd];
    final hash = hashInput.fold<int>(0, (acc, b) => ((acc * 31) + b) & 0x7FFFFFFF);
    final uuidPart = _uuidV4().replaceAll('-', '');
    return '${hash.toRadixString(16).padLeft(8, '0')}$uuidPart'.substring(0, 32);
  }

  String generateRoomPassword() {
    final bytes = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).substring(0, 16);
  }

  // Offline message queue stored in localStorage
  List<Map<String, dynamic>> getOfflineQueue() {
    final raw = html.window.localStorage['sc_offline_queue'];
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  void saveOfflineQueue(List<Map<String, dynamic>> queue) {
    html.window.localStorage['sc_offline_queue'] = jsonEncode(queue);
  }

  String _uuidV4() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return [
      b.sublist(0, 4), b.sublist(4, 6), b.sublist(6, 8),
      b.sublist(8, 10), b.sublist(10, 16),
    ].map((g) => g.map((v) => v.toRadixString(16).padLeft(2, '0')).join()).join('-');
  }
}

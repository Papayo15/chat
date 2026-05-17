// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';

import '../services/crypto_service.dart';
import '../services/local_file_store.dart';

enum ConnectionStatus { online, offline }

class SmsImportResult {
  final String type; // 'text' | 'file_token'
  final String? decryptedText;
  // For file_token:
  final String? chatId;
  final String? fileId;
  final String? encryptedFileKeyB64;
  final String? messageType;
  final DateTime timestamp;

  const SmsImportResult({
    required this.type,
    this.decryptedText,
    this.chatId,
    this.fileId,
    this.encryptedFileKeyB64,
    this.messageType,
    required this.timestamp,
  });

  bool get isFileToken => type == 'file_token';
}

class SmsFallbackService {
  final CryptoService _crypto;
  final LocalFileStore _fileStore;

  final StreamController<ConnectionStatus> _statusCtrl =
      StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get connectionStatus => _statusCtrl.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SmsFallbackService({
    required CryptoService crypto,
    required LocalFileStore fileStore,
  })  : _crypto = crypto,
        _fileStore = fileStore;

  void startMonitoring() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.every((r) => r == ConnectivityResult.none);
      _statusCtrl.add(
        isOffline ? ConnectionStatus.offline : ConnectionStatus.online,
      );
    });
  }

  // ─── TEXT MESSAGE via SMS ─────────────────────────────────────────────────

  /// Encrypts a text message with AES-256 and opens the native SMS app.
  /// The SMS body is: SCHAT:<base64_encrypted_payload>
  Future<void> sendTextViaSms({
    required String plainText,
    required SecretKey sharedKey,
    required String recipientPhone,
  }) async {
    final encryptedBase64 = await _crypto.encryptToBase64(plainText, sharedKey);
    final smsBody = Uri.encodeComponent('SCHAT:$encryptedBase64');
    html.window.location.href = 'sms:$recipientPhone?body=$smsBody';
  }

  // ─── FILE TOKEN via SMS ───────────────────────────────────────────────────

  /// Stores a pending-upload file locally and sends an SMS with the file token.
  ///
  /// The token carries: chatId, fileId, encryptedFileKey (base64).
  /// The SMS body itself is also encrypted with the sharedKey.
  ///
  /// When the sender gets connectivity → [OfflineService] uploads the file
  /// and sends the full Firestore message.
  ///
  /// The receiver imports the token → schedules a download when online.
  Future<void> sendFileTokenViaSms({
    required String chatId,
    required String fileId,
    required String encryptedFileKeyB64,
    required String messageType,
    required SecretKey sharedKey,
    required String recipientPhone,
  }) async {
    final tokenPayload = jsonEncode({
      'type': 'file_token',
      'chatId': chatId,
      'fileId': fileId,
      'fileKey': encryptedFileKeyB64,
      'msgType': messageType,
    });
    final encryptedB64 = await _crypto.encryptToBase64(tokenPayload, sharedKey);
    final smsBody = Uri.encodeComponent('SCHAT:$encryptedB64');
    html.window.location.href = 'sms:$recipientPhone?body=$smsBody';
  }

  // ─── IMPORT FROM CLIPBOARD ────────────────────────────────────────────────

  /// Reads clipboard, extracts SCHAT: payload, decrypts it.
  /// Returns a text result or a file-token result depending on content.
  Future<SmsImportResult?> importFromClipboard(SecretKey sharedKey) async {
    try {
      final text = await html.window.navigator.clipboard!.readText();
      if (!text.contains('SCHAT:')) return null;

      final start = text.indexOf('SCHAT:') + 'SCHAT:'.length;
      final payload = text.substring(start).trim();

      final decrypted = await _crypto.decryptFromBase64(payload, sharedKey);

      // Try to parse as JSON (file token)
      try {
        final parsed = jsonDecode(decrypted) as Map<String, dynamic>;
        if (parsed['type'] == 'file_token') {
          final result = SmsImportResult(
            type: 'file_token',
            chatId: parsed['chatId'] as String,
            fileId: parsed['fileId'] as String,
            encryptedFileKeyB64: parsed['fileKey'] as String,
            messageType: parsed['msgType'] as String?,
            timestamp: DateTime.now(),
          );
          // Register in download queue automatically
          _fileStore.addToDownloadQueue({
            'fileId': parsed['fileId'],
            'chatId': parsed['chatId'],
            'encryptedFileKeyB64': parsed['fileKey'],
            'messageType': parsed['msgType'] ?? 'file',
          });
          return result;
        }
      } catch (_) {
        // Not JSON → plain text message
      }

      return SmsImportResult(
        type: 'text',
        decryptedText: decrypted,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Builds the SMS export string for manual sharing.
  Future<String> buildSmsExportString({
    required String plainText,
    required SecretKey sharedKey,
  }) async {
    final encryptedBase64 = await _crypto.encryptToBase64(plainText, sharedKey);
    return 'SCHAT:$encryptedBase64';
  }

  /// Copy a string to the system clipboard.
  Future<void> copyToClipboard(String text) async {
    await html.window.navigator.clipboard!.writeText(text);
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    await _statusCtrl.close();
  }
}

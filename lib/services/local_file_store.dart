// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Stores encrypted binary files in IndexedDB so they survive page refreshes
/// and can be uploaded to Firebase Storage when connectivity is restored.
/// Also manages the pending-upload queue in localStorage.
class LocalFileStore {
  // html.Database is the IndexedDB database type in dart:html
  // ignore: library_private_types_in_public_api
  dynamic _db;
  static const _dbName = 'SecureChatFilesDB';
  static const _filesStore = 'localFiles';
  static const _uploadQueueKey = 'sc_file_upload_queue';
  static const _downloadQueueKey = 'sc_file_download_queue';

  Future<void> init() async {
    _db = await html.window.indexedDB!.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (e) {
        final db = e.target.result as dynamic;
        if (!db.objectStoreNames!.contains(_filesStore)) {
          db.createObjectStore(_filesStore);
        }
      },
    );
  }

  /// Save encrypted file bytes locally (before upload).
  Future<void> storeFile(String fileId, Uint8List encryptedBytes) async {
    final txn = _db!.transaction(_filesStore, 'readwrite');
    await txn.objectStore(_filesStore).put(encryptedBytes.buffer, fileId);
    await txn.completed;
  }

  /// Read encrypted file bytes from local storage.
  Future<Uint8List?> readFile(String fileId) async {
    final txn = _db!.transaction(_filesStore, 'readonly');
    final result = await txn.objectStore(_filesStore).getObject(fileId);
    await txn.completed;
    if (result == null) return null;
    return Uint8List.view(result as ByteBuffer);
  }

  /// Delete a file after successful upload.
  Future<void> deleteFile(String fileId) async {
    final txn = _db!.transaction(_filesStore, 'readwrite');
    await txn.objectStore(_filesStore).delete(fileId);
    await txn.completed;
  }

  // ─── Upload queue (sender side) ───────────────────────────────────────────
  // Each entry: { fileId, chatId, encryptedFileKeyB64, messageType, senderId }

  List<Map<String, dynamic>> getUploadQueue() {
    final raw = html.window.localStorage[_uploadQueueKey];
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  void addToUploadQueue(Map<String, dynamic> entry) {
    final queue = getUploadQueue()..add(entry);
    html.window.localStorage[_uploadQueueKey] = jsonEncode(queue);
  }

  void removeFromUploadQueue(String fileId) {
    final queue = getUploadQueue()
      ..removeWhere((e) => e['fileId'] == fileId);
    html.window.localStorage[_uploadQueueKey] = jsonEncode(queue);
  }

  // ─── Download queue (receiver side) ──────────────────────────────────────
  // Each entry: { fileId, chatId, encryptedFileKeyB64, messageType, senderName }

  List<Map<String, dynamic>> getDownloadQueue() {
    final raw = html.window.localStorage[_downloadQueueKey];
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  void addToDownloadQueue(Map<String, dynamic> entry) {
    final queue = getDownloadQueue()..add(entry);
    html.window.localStorage[_downloadQueueKey] = jsonEncode(queue);
  }

  void removeFromDownloadQueue(String fileId) {
    final queue = getDownloadQueue()
      ..removeWhere((e) => e['fileId'] == fileId);
    html.window.localStorage[_downloadQueueKey] = jsonEncode(queue);
  }
}

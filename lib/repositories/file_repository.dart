// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Handles only in-browser blob URL management.
/// Files are stored encrypted in Firestore (no Firebase Storage needed).
class FileRepository {
  /// Create a temporary blob URL for in-browser media display.
  /// Caller must call [revokeBlobUrl] after display to free RAM.
  String createBlobUrl(Uint8List bytes, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    return html.Url.createObjectUrl(blob);
  }

  void revokeBlobUrl(String url) {
    html.Url.revokeObjectUrl(url);
  }
}

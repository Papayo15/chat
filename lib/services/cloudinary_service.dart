// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Uploads encrypted files to Cloudinary using an unsigned upload preset.
/// The API Secret is never needed — safe to use in the browser.
/// Files are stored as opaque binary blobs (.enc); only the app can decrypt them.
class CloudinaryService {
  static const _cloudName = 'dowfrkxfu';
  static const _uploadPreset = 'securechat';
  static const _uploadUrl =
      'https://api.cloudinary.com/v1_1/$_cloudName/raw/upload';

  /// Upload encrypted bytes to Cloudinary. Returns the secure download URL.
  Future<String> uploadEncryptedFile(
    Uint8List encryptedBytes,
    String fileId,
  ) async {
    final formData = html.FormData();
    final blob = html.Blob([encryptedBytes], 'application/octet-stream');
    formData.appendBlob('file', blob, '$fileId.enc');
    formData.append('upload_preset', _uploadPreset);
    formData.append('public_id', fileId);

    final request = await html.HttpRequest.request(
      _uploadUrl,
      method: 'POST',
      sendData: formData,
    );

    if (request.status != 200) {
      throw Exception('Cloudinary upload failed: ${request.status}');
    }

    final json = jsonDecode(request.responseText!) as Map<String, dynamic>;
    return json['secure_url'] as String;
  }

  /// Download encrypted bytes from a Cloudinary URL.
  Future<Uint8List> downloadEncryptedFile(String url) async {
    final request = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'arraybuffer',
    );

    if (request.status != 200) {
      throw Exception('Cloudinary download failed: ${request.status}');
    }

    return Uint8List.view(request.response as dynamic);
  }
}

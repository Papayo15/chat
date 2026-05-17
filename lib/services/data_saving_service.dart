// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum NetworkType { wifi, mobileData, offline }

class DataSavingService {
  static DataSavingService? _instance;
  static DataSavingService get instance => _instance ??= DataSavingService._();
  DataSavingService._();

  bool _dataSaverEnabled = false;
  bool get dataSaverEnabled => _dataSaverEnabled;

  void toggleDataSaver(bool enabled) => _dataSaverEnabled = enabled;

  NetworkType detectNetworkType() {
    final connection = _getNetworkInfo();
    if (connection == null) return NetworkType.wifi;
    final saveData = connection['saveData'] as bool? ?? false;
    final type = connection['type'] as String? ?? '';
    final effectiveType = connection['effectiveType'] as String? ?? '4g';

    if (type == 'wifi') return NetworkType.wifi;
    if (type == 'none' || effectiveType == 'slow-2g') return NetworkType.offline;
    if (saveData || type == 'cellular' || type == 'wimax') {
      return NetworkType.mobileData;
    }
    return NetworkType.wifi;
  }

  bool get shouldSaveData {
    if (_dataSaverEnabled) return true;
    return detectNetworkType() == NetworkType.mobileData;
  }

  bool get browserDataSaverOn {
    try {
      final conn = _getNetworkInfo();
      return (conn?['saveData'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic>? _getNetworkInfo() {
    try {
      final nav = html.window.navigator;
      // ignore: avoid_dynamic_calls
      final dynamic conn = (nav as dynamic).connection ??
          (nav as dynamic).mozConnection ??
          (nav as dynamic).webkitConnection;
      if (conn == null) return null;
      return {
        'saveData': conn.saveData as bool?,
        'type': conn.type as String?,
        'effectiveType': conn.effectiveType as String?,
      };
    } catch (_) {
      return null;
    }
  }

  /// Compress image to max 1080p at 70% JPEG quality before upload.
  Future<Uint8List> compressImage(Uint8List originalBytes) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    img.Image resized = decoded;
    const maxDimension = 1080;

    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDimension)
          : img.copyResize(decoded, height: maxDimension);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  }

  /// Compress image to max 360p at 50% quality (low bandwidth).
  Future<Uint8List> compressImageLow(Uint8List originalBytes) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) return originalBytes;

    img.Image resized = decoded;
    const maxDimension = 360;

    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDimension)
          : img.copyResize(decoded, height: maxDimension);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 50));
  }

  /// Adaptive compression: low-res on mobile data, high-res on WiFi.
  Future<Uint8List> compressImageAdaptive(Uint8List originalBytes) async {
    return shouldSaveData
        ? compressImageLow(originalBytes)
        : compressImage(originalBytes);
  }

  /// Max bitrate in bps for Jitsi video stream.
  int jitsiMaxBitrate() =>
      detectNetworkType() == NetworkType.wifi && !_dataSaverEnabled
          ? 1500000
          : 300000;

  /// Max height for Jitsi video stream.
  int jitsiMaxHeight() =>
      detectNetworkType() == NetworkType.wifi && !_dataSaverEnabled ? 720 : 360;

  /// Recommended voice note bitrate in kbps (max 16 kbps = < 120 KB/min).
  int voiceNoteBitrate() => shouldSaveData ? 16 : 64;

  /// Human-readable file size.
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}

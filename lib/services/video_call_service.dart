// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import '../services/crypto_service.dart';

enum VideoQuality { high, low, audioOnly }

class VideoCallService {
  final CryptoService _crypto;
  html.IFrameElement? _iframe;
  void Function()? _onEndedCallback;

  VideoCallService({required CryptoService crypto}) : _crypto = crypto;

  Map<String, String> generateCallCredentials(String chatId) => {
        'roomId': _crypto.generateRoomId(chatId),
        'password': _crypto.generateRoomPassword(),
      };

  void launchRoom({
    required String roomId,
    required String password,
    required String displayName,
    required bool isModerator,
    required html.Element container,
    required void Function() onCallEnded,
    VideoQuality quality = VideoQuality.high,
  }) {
    _onEndedCallback = onCallEnded;
    hangUp();

    final maxHeight = quality == VideoQuality.high ? 720 : 360;
    final startVideoMuted = quality == VideoQuality.audioOnly;

    // Config via Jitsi URL fragment — no JS interop needed
    final configParams = [
      'config.requireDisplayName=true',
      'config.prejoinPageEnabled=false',
      'config.disableDeepLinking=true',
      'config.startWithAudioMuted=false',
      'config.startWithVideoMuted=$startVideoMuted',
      'config.p2p.enabled=true',
      'config.enableLobbyChat=false',
      // Lobby mode: moderator must approve each joiner
      'config.securityUi.hideLobbyButton=false',
      if (quality != VideoQuality.high) 'config.constraints.video.height.ideal=$maxHeight',
      if (quality != VideoQuality.high) 'config.constraints.video.height.max=$maxHeight',
      // Reduce incoming video bitrate for data saving
      if (quality == VideoQuality.low) 'config.channelLastN=2',
      'userInfo.displayName=${Uri.encodeComponent(displayName)}',
    ].join('&');

    _iframe = html.IFrameElement()
      ..src = 'https://meet.jit.si/$roomId#$configParams'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.backgroundColor = '#000'
      ..setAttribute('allow', 'camera *; microphone *; fullscreen *; display-capture *; autoplay')
      ..setAttribute('allowfullscreen', 'true');

    container.children.clear();
    container.append(_iframe!);
  }

  void setQuality(VideoQuality quality) {
    // Quality changes require re-loading the iframe
    // The parent widget calls launchRoom again with the new quality
    // This method is kept for API compatibility
  }

  void hangUp() {
    _iframe?.remove();
    _iframe = null;
    _onEndedCallback?.call();
    _onEndedCallback = null;
  }
}

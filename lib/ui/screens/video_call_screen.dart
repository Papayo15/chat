// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

import '../../services/video_call_service.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String password;
  final String displayName;
  final bool isModerator;
  final VideoCallService videoService;
  final bool isDataSaver;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.password,
    required this.displayName,
    required this.isModerator,
    required this.videoService,
    this.isDataSaver = false,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late final html.DivElement _container;
  late final String _viewId;
  VideoQuality _currentQuality = VideoQuality.high;
  bool _jitsiReady = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'jitsi-${widget.roomId}';
    _currentQuality = widget.isDataSaver ? VideoQuality.low : VideoQuality.high;

    _container = html.DivElement()
      ..id = _viewId
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#000';

    ui.platformViewRegistry.registerViewFactory(_viewId, (_) => _container);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchRoom();
    });
  }

  void _launchRoom() {
    try {
      widget.videoService.launchRoom(
        roomId: widget.roomId,
        password: widget.password,
        displayName: widget.displayName,
        isModerator: widget.isModerator,
        container: _container,
        onCallEnded: () {
          if (mounted) Navigator.of(context).pop();
        },
        quality: _currentQuality,
      );
      if (mounted) setState(() => _jitsiReady = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error iniciando Jitsi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    widget.videoService.hangUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          HtmlElementView(viewType: _viewId),
          if (!_jitsiReady)
            const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Conectando sala cifrada...', style: TextStyle(color: Colors.white70)),
              ]),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'hangup',
                  backgroundColor: Colors.red,
                  onPressed: () {
                    widget.videoService.hangUp();
                    Navigator.of(context).pop();
                  },
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'quality',
                  backgroundColor: Colors.black54,
                  onPressed: _toggleQuality,
                  tooltip: 'Calidad de video',
                  child: Icon(
                    _currentQuality == VideoQuality.high
                        ? Icons.hd_outlined
                        : _currentQuality == VideoQuality.low
                            ? Icons.sd_outlined
                            : Icons.mic_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, size: 12, color: Color(0xFF42A5F5)),
                const SizedBox(width: 6),
                Text(
                  'Sala: ${widget.roomId.substring(0, 8)}... · Cifrada',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleQuality() {
    VideoQuality next;
    switch (_currentQuality) {
      case VideoQuality.high:
        next = VideoQuality.low;
      case VideoQuality.low:
        next = VideoQuality.audioOnly;
      case VideoQuality.audioOnly:
        next = VideoQuality.high;
    }
    setState(() => _currentQuality = next);
    widget.videoService.setQuality(next);

    final label = next == VideoQuality.high
        ? 'HD (720p)'
        : next == VideoQuality.low
            ? 'Bajo ancho de banda (360p)'
            : 'Solo audio';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calidad: $label'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.black87,
      ),
    );
  }
}

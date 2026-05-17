// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/chat.dart';
import '../../models/encrypted_message.dart';
import '../../repositories/file_repository.dart';
import '../../repositories/message_repository.dart';
import '../../services/cloudinary_service.dart';
import '../../repositories/user_repository.dart';
import '../../services/crypto_service.dart';
import '../../services/data_saving_service.dart';
import '../../services/local_file_store.dart';
import '../../services/p2p_transfer_service.dart';
import '../../services/sms_fallback_service.dart';
import '../../services/sync_viewer_service.dart';
import '../../services/video_call_service.dart';
import '../widgets/qr_pairing_widget.dart';
import 'video_call_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final String otherUserUid;
  final MessageRepository msgRepo;
  final UserRepository userRepo;
  final VideoCallService videoService;
  final P2PTransferService p2pService;
  final SyncViewerService syncService;
  final SmsFallbackService smsService;
  final CryptoService crypto;
  final DataSavingService dataSaving;
  final FileRepository fileRepo;
  final LocalFileStore localFiles;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.otherUserUid,
    required this.msgRepo,
    required this.userRepo,
    required this.videoService,
    required this.p2pService,
    required this.syncService,
    required this.smsService,
    required this.crypto,
    required this.dataSaving,
    required this.fileRepo,
    required this.localFiles,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  SecretKey? _sharedKey;
  AppUser? _otherUser;
  bool _ephemeralMode = false;
  bool _dataSaverMode = false;
  bool _loading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _initKeys();
    widget.smsService.connectionStatus.listen((status) {
      if (mounted) setState(() => _isOffline = status == ConnectionStatus.offline);
    });
  }

  Future<void> _initKeys() async {
    final myKeyPair = await widget.crypto.loadStoredKeyPair();
    final other = await widget.userRepo.getUserById(widget.otherUserUid);
    if (myKeyPair == null || other == null) {
      setState(() => _loading = false);
      return;
    }
    final shared = await widget.crypto.deriveSharedSecret(myKeyPair, other.publicKey);
    setState(() {
      _sharedKey = shared;
      _otherUser = other;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sharedKey == null) return;
    _textCtrl.clear();
    await widget.msgRepo.sendTextMessage(
      chatId: widget.chat.id,
      plainText: text,
      sharedKey: _sharedKey!,
      ephemeral: _ephemeralMode,
      isOffline: _isOffline,
    );
    _scrollToBottom();
  }

  Future<void> _sendViaSms() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sharedKey == null) return;
    // Phone numbers are never stored on server (privacy design); SMS requires manual entry
    const String? phone = null;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El contacto no tiene número de teléfono registrado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _textCtrl.clear();
    await widget.smsService.sendTextViaSms(
      plainText: text,
      sharedKey: _sharedKey!,
      recipientPhone: phone,
    );
  }

  Future<void> _importFromClipboard() async {
    if (_sharedKey == null) return;
    final result = await widget.smsService.importFromClipboard(_sharedKey!);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró un payload SCHAT en el portapapeles')),
      );
      return;
    }
    if (result.isFileToken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token de archivo recibido — se descargará cuando haya conexión'),
          backgroundColor: Colors.blue,
        ),
      );
    } else {
      await widget.msgRepo.sendSmsImport(
        chatId: widget.chat.id,
        decryptedText: result.decryptedText!,
        sharedKey: _sharedKey!,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje SMS importado y descifrado'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _sendFile() async {
    if (_sharedKey == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final ext = file.extension?.toLowerCase() ?? '';
    final msgType = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)
        ? MessageType.image
        : ['mp4', 'mov', 'webm'].contains(ext)
            ? MessageType.video
            : ['mp3', 'wav', 'ogg', 'opus', 'm4a'].contains(ext)
                ? MessageType.audio
                : MessageType.file;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isOffline
            ? 'Sin conexión — archivo cifrado y guardado localmente'
            : msgType == MessageType.image
                ? 'Comprimiendo y cifrando imagen...'
                : 'Cifrando y subiendo archivo...'),
        duration: const Duration(seconds: 2),
      ),
    );

    await widget.msgRepo.sendFileMessage(
      chatId: widget.chat.id,
      fileBytes: file.bytes!,
      type: msgType,
      sharedKey: _sharedKey!,
      ephemeral: _ephemeralMode,
      originalFileName: file.name,
      isOffline: _isOffline,
      recipientPhone: null, // phone numbers not stored on server (privacy design)
    );
  }

  Future<void> _startVideoCall() async {
    if (_sharedKey == null) return;
    final credentials = widget.videoService.generateCallCredentials(widget.chat.id);
    await widget.msgRepo.sendCallInvite(
      chatId: widget.chat.id,
      roomId: credentials['roomId']!,
      roomPassword: credentials['password']!,
      sharedKey: _sharedKey!,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          roomId: credentials['roomId']!,
          password: credentials['password']!,
          displayName: FirebaseAuth.instance.currentUser!.displayName ?? 'Usuario',
          isModerator: true,
          videoService: widget.videoService,
          isDataSaver: _dataSaverMode,
        ),
      ),
    );
  }

  Future<String> _decrypt(EncryptedMessage msg) async {
    if (_sharedKey == null) return '[clave no disponible]';
    try {
      return await widget.crypto.decryptText(msg.payload, _sharedKey!);
    } catch (_) {
      return '[error al descifrar]';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF1565C0),
            radius: 16,
            child: Text(
              (_otherUser?.displayName ?? '?').isNotEmpty
                  ? _otherUser!.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_otherUser?.displayName ?? '...',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Row(children: [
                const Icon(Icons.lock, size: 10, color: Color(0xFF42A5F5)),
                const SizedBox(width: 3),
                Text('E2EE · Cero huella local',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ]),
            ]),
          ),
        ]),
        actions: [
          // Data-saver switch
          IconButton(
            icon: Icon(
              _dataSaverMode ? Icons.data_saver_on : Icons.data_saver_off_outlined,
              color: _dataSaverMode ? Colors.amber : null,
            ),
            tooltip: _dataSaverMode ? 'Modo ahorro activo' : 'Activar modo ahorro',
            onPressed: () {
              setState(() => _dataSaverMode = !_dataSaverMode);
              widget.dataSaving.toggleDataSaver(_dataSaverMode);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_dataSaverMode ? 'Modo ahorro activado ☑' : 'Modo ahorro desactivado'),
                duration: const Duration(seconds: 1),
              ));
            },
          ),
          // Ephemeral toggle
          IconButton(
            icon: Icon(
              _ephemeralMode ? Icons.timer : Icons.timer_outlined,
              color: _ephemeralMode ? Colors.orange : null,
            ),
            tooltip: _ephemeralMode ? 'Mensajes efímeros activos' : 'Activar modo efímero',
            onPressed: () => setState(() => _ephemeralMode = !_ephemeralMode),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_outlined),
            tooltip: 'Mi código QR de emparejamiento',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: QrPairingWidget(
                  myUid: FirebaseAuth.instance.currentUser!.uid,
                  onPaired: (_) => Navigator.pop(context),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Videollamada privada',
            onPressed: _startVideoCall,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (_isOffline) _buildOfflineBanner(),
              if (_sharedKey == null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withAlpha(30),
                  child: const Text('Error derivando clave compartida',
                      style: TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ),
              Expanded(
                child: StreamBuilder<List<EncryptedMessage>>(
                  stream: widget.msgRepo.messagesStream(widget.chat.id),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final msgs = snap.data ?? [];
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    return ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: msgs.length,
                      itemBuilder: (ctx, i) {
                        final msg = msgs[i];
                        final isMe = msg.senderId == myUid;
                        return _MessageBubble(
                          key: ValueKey(msg.id),
                          message: msg,
                          isMe: isMe,
                          decryptFn: _decrypt,
                          sharedKey: _sharedKey,
                          crypto: widget.crypto,
                          fileRepo: widget.fileRepo,
                          onEphemeralSeen: msg.ephemeral && !isMe
                              ? () => widget.msgRepo.deleteEphemeralMessage(
                                  widget.chat.id, msg.id)
                              : null,
                          onCallAccepted: msg.type == MessageType.callInvite && !isMe
                              ? (roomId, password) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VideoCallScreen(
                                        roomId: roomId,
                                        password: password,
                                        displayName: FirebaseAuth.instance.currentUser!.displayName ?? 'Usuario',
                                        isModerator: false,
                                        videoService: widget.videoService,
                                        isDataSaver: _dataSaverMode,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
              _buildInputBar(),
            ]),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withAlpha(30),
      child: Row(children: [
        const Icon(Icons.wifi_off, size: 16, color: Colors.orange),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Sin conexión — mensajes en cola local',
            style: TextStyle(fontSize: 12, color: Colors.orange),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.sms_outlined, size: 14),
          label: const Text('Importar SMS', style: TextStyle(fontSize: 12)),
          onPressed: _importFromClipboard,
        ),
      ]),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          border: Border(top: BorderSide(color: Colors.grey[900]!, width: 1)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _sendFile,
            tooltip: 'Adjuntar archivo (cifrado E2EE)',
          ),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                hintText: _ephemeralMode
                    ? 'Mensaje efímero...'
                    : _isOffline
                        ? 'Sin red — en cola local...'
                        : 'Mensaje cifrado E2EE...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
            ),
          ),
          if (_isOffline)
            IconButton(
              icon: const Icon(Icons.sms_outlined, color: Colors.orange),
              tooltip: 'Enviar por SMS cifrado',
              onPressed: _sendViaSms,
            ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFF1565C0)),
            onPressed: _sendText,
          ),
        ]),
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  final EncryptedMessage message;
  final bool isMe;
  final Future<String> Function(EncryptedMessage) decryptFn;
  final SecretKey? sharedKey;
  final CryptoService crypto;
  final FileRepository fileRepo;
  final VoidCallback? onEphemeralSeen;
  final void Function(String roomId, String password)? onCallAccepted;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.decryptFn,
    required this.sharedKey,
    required this.crypto,
    required this.fileRepo,
    this.onEphemeralSeen,
    this.onCallAccepted,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  String? _decrypted;

  @override
  void initState() {
    super.initState();
    _doDecrypt();
  }

  Future<void> _doDecrypt() async {
    final text = await widget.decryptFn(widget.message);
    if (!mounted) return;
    setState(() => _decrypted = text);
    if (widget.message.ephemeral && !widget.isMe && widget.onEphemeralSeen != null) {
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) widget.onEphemeralSeen!();
    }
  }

  /// Decrypts and opens the file. Handles both Firestore base64 (≤500KB) and
  /// Cloudinary (>500KB). Zero-footprint: decrypted bytes stay in RAM only.
  Future<void> _openFile() async {
    final hasFile = widget.message.fileData != null || widget.message.cloudinaryUrl != null;
    if (!hasFile || widget.message.encryptedFileKey == null || widget.sharedKey == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(widget.message.cloudinaryUrl != null
              ? 'Descargando y descifrando...'
              : 'Descifrando archivo...'),
        ]),
      ),
    );

    try {
      final Uint8List encryptedBytes;
      if (widget.message.fileData != null) {
        encryptedBytes = base64.decode(widget.message.fileData!);
      } else {
        encryptedBytes = await CloudinaryService()
            .downloadEncryptedFile(widget.message.cloudinaryUrl!);
      }

      final fileKey = await widget.crypto.decryptFileKey(
        widget.message.encryptedFileKey!,
        widget.sharedKey!,
      );
      final decryptedBytes = await widget.crypto.decryptFile(encryptedBytes, fileKey);

      if (!mounted) return;
      Navigator.pop(context);

      final mimeType = _mimeForType(widget.message.type);
      final blobUrl = widget.fileRepo.createBlobUrl(decryptedBytes, mimeType);

      html.window.open(blobUrl, '_blank');

      await Future.delayed(const Duration(seconds: 3));
      widget.fileRepo.revokeBlobUrl(blobUrl);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir archivo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _mimeForType(MessageType type) {
    switch (type) {
      case MessageType.image: return 'image/jpeg';
      case MessageType.video: return 'video/mp4';
      case MessageType.audio: return 'audio/ogg';
      default: return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    final align = widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = widget.isMe ? const Color(0xFF1565C0) : const Color(0xFF1F2937);

    Widget content;
    if (_decrypted == null) {
      content = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (widget.message.type == MessageType.callInvite && !widget.isMe) {
      final parts = _decrypted!.replaceFirst('CALL_INVITE:', '').split(':');
      content = _CallInviteTile(
        onAccept: () => widget.onCallAccepted?.call(
          parts.isNotEmpty ? parts[0] : '',
          parts.length > 1 ? parts[1] : '',
        ),
      );
    } else if (widget.message.type == MessageType.callInvite && widget.isMe) {
      content = const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.videocam, size: 16, color: Colors.white70),
        SizedBox(width: 6),
        Text('Videollamada iniciada', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
      ]);
    } else if (widget.message.type == MessageType.smsImport) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sms, size: 14, color: Colors.amber),
        const SizedBox(width: 6),
        Flexible(child: Text(_decrypted!, style: const TextStyle(color: Colors.white))),
      ]);
    } else if (widget.message.fileData != null || widget.message.cloudinaryUrl != null) {
      // File message — tap to download, decrypt, and open (Zero-Footprint)
      content = InkWell(
        onTap: _openFile,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (widget.message.ephemeral)
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer, size: 11, color: Colors.orange),
              SizedBox(width: 4),
              Text('Efímero', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              widget.message.type == MessageType.image
                  ? Icons.image_outlined
                  : widget.message.type == MessageType.audio
                      ? Icons.audiotrack_outlined
                      : widget.message.type == MessageType.video
                          ? Icons.videocam_outlined
                          : Icons.attach_file,
              size: 20, color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(
              _decrypted ?? 'archivo adjunto',
              style: const TextStyle(color: Colors.white, decoration: TextDecoration.underline),
            )),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Toca para ver · Sin guardar en dispositivo',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ]),
      );
    } else {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (widget.message.ephemeral)
          const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer, size: 11, color: Colors.orange),
            SizedBox(width: 4),
            Text('Efímero · desaparece en 5s', style: TextStyle(fontSize: 10, color: Colors.orange)),
            SizedBox(height: 4),
          ]),
        Text(_decrypted!, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]);
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 3, bottom: 3,
        left: widget.isMe ? 40 : 0,
        right: widget.isMe ? 0 : 40,
      ),
      child: Column(crossAxisAlignment: align, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
              bottomRight: Radius.circular(widget.isMe ? 4 : 18),
            ),
          ),
          child: content,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
          child: Text(
            '${widget.message.timestamp.hour.toString().padLeft(2, '0')}:${widget.message.timestamp.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ),
      ]),
    );
  }
}

class _CallInviteTile extends StatelessWidget {
  final VoidCallback? onAccept;
  const _CallInviteTile({this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.videocam, color: Colors.greenAccent),
      const SizedBox(width: 8),
      const Text('Videollamada entrante', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      const SizedBox(width: 12),
      ElevatedButton.icon(
        onPressed: onAccept,
        icon: const Icon(Icons.call, size: 14),
        label: const Text('Unirse', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
        ),
      ),
    ]);
  }
}

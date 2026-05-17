import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/chat.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/history_repository.dart';
import '../../repositories/message_repository.dart';
import '../../repositories/user_repository.dart';
import '../../services/crypto_service.dart';
import '../../services/data_saving_service.dart';
import '../../services/p2p_transfer_service.dart';
import '../../services/sms_fallback_service.dart';
import '../../services/sync_viewer_service.dart';
import '../../services/local_file_store.dart';
import '../../services/video_call_service.dart';
import '../../repositories/file_repository.dart';
import '../widgets/qr_pairing_widget.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatelessWidget {
  final ChatRepository chatRepo;
  final MessageRepository msgRepo;
  final UserRepository userRepo;
  final HistoryRepository historyRepo;
  final VideoCallService videoService;
  final P2PTransferService p2pService;
  final SyncViewerService syncService;
  final SmsFallbackService smsService;
  final CryptoService crypto;
  final DataSavingService dataSaving;
  final FileRepository fileRepo;
  final LocalFileStore localFiles;

  const ChatsScreen({
    super.key,
    required this.chatRepo,
    required this.msgRepo,
    required this.userRepo,
    required this.historyRepo,
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.lock, size: 18, color: Color(0xFF42A5F5)),
          SizedBox(width: 8),
          Text('SecureChat'),
        ]),
        actions: [
          StreamBuilder<ConnectionStatus>(
            stream: smsService.connectionStatus,
            builder: (ctx, snap) {
              final isOffline = snap.data == ConnectionStatus.offline;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: Text(
                    isOffline ? 'Sin red' : 'En línea',
                    style: const TextStyle(fontSize: 11),
                  ),
                  avatar: Icon(
                    isOffline ? Icons.wifi_off : Icons.wifi,
                    size: 14,
                    color: isOffline ? Colors.orange : Colors.green,
                  ),
                  backgroundColor: isOffline
                      ? Colors.orange.withAlpha(30)
                      : Colors.green.withAlpha(30),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Chat>>(
        stream: chatRepo.chatsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final chats = snap.data ?? [];
          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text('No hay chats', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  Text('Toca + para iniciar una conversación',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => Divider(
              color: Colors.grey[900],
              indent: 72,
              height: 1,
            ),
            itemBuilder: (ctx, i) {
              final chat = chats[i];
              final myUid = FirebaseAuth.instance.currentUser!.uid;
              final otherUid = chat.participants.firstWhere(
                (p) => p != myUid,
                orElse: () => chat.participants.first,
              );
              return FutureBuilder(
                future: userRepo.getUserById(otherUid),
                builder: (ctx, userSnap) {
                  final name = userSnap.data?.displayName ?? '...';
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1565C0),
                      radius: 24,
                      child: Text(initial,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Row(children: [
                      const Icon(Icons.lock, size: 11, color: Color(0xFF42A5F5)),
                      const SizedBox(width: 4),
                      Text('Cifrado E2EE',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    ]),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chat: chat,
                          otherUserUid: otherUid,
                          msgRepo: msgRepo,
                          userRepo: userRepo,
                          historyRepo: historyRepo,
                          videoService: videoService,
                          p2pService: p2pService,
                          syncService: syncService,
                          smsService: smsService,
                          crypto: crypto,
                          dataSaving: dataSaving,
                          fileRepo: fileRepo,
                          localFiles: localFiles,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewChatDialog(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Nuevo chat'),
      ),
    );
  }

  void _showQrPairingSheet(BuildContext context) {
    showModalBottomSheet(
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
          onPaired: (otherUid) async {
            Navigator.pop(context);
            final chat = await chatRepo.createOrFindChat([otherUid]);
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chat: chat,
                    otherUserUid: otherUid,
                    msgRepo: msgRepo,
                    userRepo: userRepo,
                    historyRepo: historyRepo,
                    videoService: videoService,
                    p2pService: p2pService,
                    syncService: syncService,
                    smsService: smsService,
                    crypto: crypto,
                    dataSaving: dataSaving,
                    fileRepo: fileRepo,
                    localFiles: localFiles,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _showNewChatDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nuevo chat seguro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Email del contacto',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton.icon(
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text('QR'),
              onPressed: () {
                Navigator.pop(ctx);
                _showQrPairingSheet(context);
              },
            ),
            FilledButton(
              onPressed: () async {
                final users = await userRepo.searchUsersByEmail(emailCtrl.text.trim());
                if (users.isEmpty) {
                  setDialogState(() => error = 'Usuario no encontrado');
                  return;
                }
                final chat = await chatRepo.createOrFindChat([users.first.uid]);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chat: chat,
                        otherUserUid: users.first.uid,
                        msgRepo: msgRepo,
                        userRepo: userRepo,
                        historyRepo: historyRepo,
                        videoService: videoService,
                        p2pService: p2pService,
                        syncService: syncService,
                        smsService: smsService,
                        crypto: crypto,
                        dataSaving: dataSaving,
                        fileRepo: fileRepo,
                        localFiles: localFiles,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Buscar e iniciar'),
            ),
          ],
        ),
      ),
    );
  }
}

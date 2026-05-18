import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'repositories/chat_repository.dart';
import 'repositories/file_repository.dart';
import 'repositories/history_repository.dart';
import 'repositories/message_repository.dart';
import 'repositories/user_repository.dart';
import 'services/crypto_service.dart';
import 'services/data_saving_service.dart';
import 'services/local_file_store.dart';
import 'services/offline_service.dart';
import 'services/p2p_transfer_service.dart';
import 'services/sms_fallback_service.dart';
import 'services/sync_viewer_service.dart';
import 'services/video_call_service.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/chats_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disable Firestore offline persistence — its IndexedDB usage causes
  // unhandled promise rejections in Safari that freeze Dart's async loop.
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  } catch (_) {}

  final crypto = CryptoService();
  try { await crypto.init(); } catch (_) {}

  // LocalFileStore uses IndexedDB; in Safari Private mode IndexedDB is
  // completely blocked and init() throws. Catch and continue — the app
  // works without local file caching.
  final localFiles = LocalFileStore();
  try { await localFiles.init(); } catch (_) {}

  final offline = OfflineService(db: FirebaseFirestore.instance, crypto: crypto);
  try { offline.startListening(); } catch (_) {}

  final smsService = SmsFallbackService(crypto: crypto, fileStore: localFiles);
  try { smsService.startMonitoring(); } catch (_) {}

  runApp(SecureChatApp(
    crypto: crypto,
    offline: offline,
    smsService: smsService,
    localFiles: localFiles,
  ));
}

class SecureChatApp extends StatelessWidget {
  final CryptoService crypto;
  final OfflineService offline;
  final SmsFallbackService smsService;
  final LocalFileStore localFiles;

  const SecureChatApp({
    super.key,
    required this.crypto,
    required this.offline,
    required this.smsService,
    required this.localFiles,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final dataSaving = DataSavingService.instance;
    final fileRepo = FileRepository();

    final msgRepo = MessageRepository(
      db: db,
      auth: auth,
      crypto: crypto,
      dataSaving: dataSaving,
      offline: offline,
    );
    final userRepo = UserRepository(db: db, auth: auth, crypto: crypto);
    final chatRepo = ChatRepository(db: db, auth: auth);
    final historyRepo = HistoryRepository(db: db);
    final videoService = VideoCallService(crypto: crypto);
    final p2pService = P2PTransferService(db: db, auth: auth);
    final syncService = SyncViewerService(db: db, auth: auth);

    return MaterialApp(
      title: 'SecureChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0d0d0d),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data == null) {
            return AuthScreen(userRepo: userRepo);
          }
          return ChatsScreen(
            chatRepo: chatRepo,
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
          );
        },
      ),
    );
  }
}

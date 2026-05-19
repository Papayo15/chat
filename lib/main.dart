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

bool _isFirebaseTransportError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('long polling') ||
      s.contains('timeout: null') ||
      s.contains('invalid-argument') ||
      s.contains('log poll');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress Firebase Firestore transport errors (long polling timeout: null)
  // at the Flutter error level so they never replace the widget tree.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isFirebaseTransportError(details.exception)) return;
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Firebase transport errors must not replace the widget with a red screen.
    if (_isFirebaseTransportError(details.exception)) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d0d),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            details.exception.toString(),
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ),
    );
  };

  // Show UI immediately — never block runApp() on service init.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    runApp(_ErrorApp('Firebase init failed: $e'));
    return;
  }

  runApp(const _AppBootstrap());
}

/// Thin bootstrap widget that initializes all services in initState() so
/// Flutter's rendering pipeline starts immediately after Firebase init.
/// No service failure can prevent the UI from appearing.
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  late CryptoService _crypto;
  late OfflineService _offline;
  late SmsFallbackService _smsService;
  late LocalFileStore _localFiles;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      _crypto = CryptoService();
      try { await _crypto.init(); } catch (_) {}

      // Disable offline persistence AND long-polling transport.
      // The Firebase JS SDK throws "invalid long polling timeout: null" when
      // long-polling initialises with null defaults in some browsers.
      // webExperimentalForceLongPolling: false forces WebSocket-only transport.
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
          webExperimentalForceLongPolling: false,
          webExperimentalAutoDetectLongPolling: false,
        );
      } catch (_) {}

      // LocalFileStore uses IndexedDB. Safari Private mode may never resolve
      // the open() call, so we timeout after 3 s and degrade gracefully.
      _localFiles = LocalFileStore();
      try {
        await _localFiles.init().timeout(const Duration(seconds: 3));
      } catch (_) {}

      _offline = OfflineService(
          db: FirebaseFirestore.instance, crypto: _crypto);
      try { _offline.startListening(); } catch (_) {}

      _smsService = SmsFallbackService(crypto: _crypto, fileStore: _localFiles);
      try { _smsService.startMonitoring(); } catch (_) {}
    } catch (e) {
      // Fatal init error — still transition to app (shows auth screen).
      _crypto = CryptoService();
      _localFiles = LocalFileStore();
      _offline = OfflineService(db: FirebaseFirestore.instance, crypto: _crypto);
      _smsService = SmsFallbackService(crypto: _crypto, fileStore: _localFiles);
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF0d0d0d),
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return SecureChatApp(
      crypto: _crypto,
      offline: _offline,
      smsService: _smsService,
      localFiles: _localFiles,
    );
  }
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

/// Shown only when Firebase.initializeApp() itself fails.
class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0d0d0d),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text('SecureChat — Error de inicio',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SelectableText(message,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

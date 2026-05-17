// INSTRUCCIÓN: Este archivo es generado automáticamente por FlutterFire CLI.
// Ejecuta en la terminal: flutterfire configure
// Selecciona tu proyecto Firebase y marca la plataforma "Web".
// El comando reemplazará este archivo con tus credenciales reales.
//
// Si aún no tienes proyecto Firebase:
//   1. Ve a https://console.firebase.google.com
//   2. Crea un proyecto nuevo
//   3. Activa Authentication (Email/Password), Firestore y Storage
//   4. Instala FlutterFire CLI: dart pub global activate flutterfire_cli
//   5. Ejecuta: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform. '
      'Run: flutterfire configure',
    );
  }

  // REEMPLAZA estos valores con los de tu proyecto Firebase

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAYso6vqOsZTusldxhxdX35ovBBZ0lNm54',
    appId: '1:355103356286:web:0360b3b65cf0ce872b2f2f',
    messagingSenderId: '355103356286',
    projectId: 'chat-fb379',
    authDomain: 'chat-fb379.firebaseapp.com',
    storageBucket: 'chat-fb379.firebasestorage.app',
  );

  // (disponibles en Firebase Console → Configuración del proyecto → Tus apps → Web)
}
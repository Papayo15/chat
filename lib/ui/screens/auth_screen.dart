// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../repositories/user_repository.dart';
import '../../services/identity_service.dart';

class AuthScreen extends StatefulWidget {
  final UserRepository userRepo;
  const AuthScreen({super.key, required this.userRepo});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isRegister = false;

  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  ConfirmationResult? _confirmation;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // Shows error in an AlertDialog — impossible to miss regardless of scroll.
  void _showError(String msg) {
    setState(() => _loading = false);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 36),
        title: const Text('Error de autenticación'),
        content: Text(msg, style: const TextStyle(fontSize: 14)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':        return 'No existe una cuenta con ese email.';
      case 'wrong-password':        return 'Contraseña incorrecta.';
      case 'email-already-in-use':  return 'Ese email ya está registrado.';
      case 'weak-password':         return 'La contraseña debe tener al menos 6 caracteres.';
      case 'invalid-email':         return 'Email con formato inválido.';
      case 'invalid-phone-number':  return 'Número inválido. Usa formato E.164: +521234567890';
      case 'too-many-requests':     return 'Demasiados intentos. Espera unos minutos.';
      case 'operation-not-allowed': return 'Este método de login no está habilitado en Firebase.\n\nVe a Firebase Console → Authentication → Sign-in method y actívalo.';
      case 'unauthorized-domain':   return 'El dominio no está autorizado en Firebase.\n\nVe a Firebase Console → Authentication → Settings → Authorized domains y agrega: ${html.window.location.hostname}';
      default:
        return '${e.code}: ${e.message ?? "sin detalle"}';
    }
  }

  // ── Email ────────────────────────────────────────────────────────────────

  Future<void> _emailAction() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final name  = _nameCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _showError('Completa email y contraseña.'); return;
    }
    if (_isRegister && name.isEmpty) {
      _showError('Ingresa tu nombre.'); return;
    }

    setState(() => _loading = true);
    try {
      UserCredential cred;
      if (_isRegister) {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: pass);
        await cred.user!.updateDisplayName(name);
      } else {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: pass);
      }
      await widget.userRepo.registerOrLogin(cred.user!);
    } on FirebaseAuthException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      // Firebase may throw internal SDK errors (e.g. log polling timeout)
      // even when auth succeeded. Check if user is actually signed in.
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        try { await widget.userRepo.registerOrLogin(current); } catch (_) {}
        return;
      }
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _showError('Ingresa el número en formato E.164.\nEjemplo: +521234567890'); return;
    }
    setState(() => _loading = true);
    try {
      final svc = IdentityService();
      _confirmation = await svc.sendPhoneOtp(
        phoneE164: phone,
        recaptchaContainerId: 'recaptcha-container',
      );
      if (mounted) setState(() { _otpSent = true; _loading = false; });
    } on FirebaseAuthException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _confirmOtp() async {
    if (_confirmation == null) return;
    final code = _otpCtrl.text.trim();
    if (code.length != 6) { _showError('El código OTP debe tener 6 dígitos.'); return; }
    setState(() => _loading = true);
    try {
      final svc  = IdentityService();
      final user = await svc.confirmPhoneOtp(
        confirmationResult: _confirmation!, smsCode: code);
      final hash = IdentityService.hashPhone(_phoneCtrl.text.trim());
      await widget.userRepo.registerOrLogin(user, phoneHash: hash);
    } on FirebaseAuthException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        final hash = IdentityService.hashPhone(_phoneCtrl.text.trim());
        try { await widget.userRepo.registerOrLogin(current, phoneHash: hash); } catch (_) {}
        return;
      }
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Anonymous ─────────────────────────────────────────────────────────────

  Future<void> _signInAnonymously() async {
    setState(() => _loading = true);
    try {
      final svc  = IdentityService();
      final user = await svc.signInAnonymously();
      await widget.userRepo.registerOrLogin(user);
    } on FirebaseAuthException catch (e) {
      _showError(_friendly(e));
    } catch (e) {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        try { await widget.userRepo.registerOrLogin(current); } catch (_) {}
        return;
      }
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 72, color: Color(0xFF1565C0)),
                const SizedBox(height: 12),
                const Text('SecureChat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Privacidad Radical · Cifrado E2EE',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 32),

                // Invisible reCAPTCHA anchor for Firebase Phone Auth
                const SizedBox(key: ValueKey('recaptcha-container'), height: 0),

                TabBar(
                  controller: _tabs,
                  labelStyle: const TextStyle(fontSize: 11),
                  tabs: const [
                    Tab(icon: Icon(Icons.email_outlined),  text: 'Email'),
                    Tab(icon: Icon(Icons.phone_outlined),  text: 'SMS OTP'),
                    Tab(icon: Icon(Icons.shield_outlined), text: 'Anónimo'),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  height: 310,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildEmailTab(),
                      _buildPhoneTab(),
                      _buildAnonTab(),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Divider(color: Colors.grey[800])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Los errores se muestran en un diálogo',
                        style: TextStyle(color: Colors.grey[700], fontSize: 10)),
                  ),
                  Expanded(child: Divider(color: Colors.grey[800])),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailTab() {
    return Column(children: [
      if (_isRegister) ...[
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _emailCtrl,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.email_outlined),
        ),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passCtrl,
        decoration: const InputDecoration(
          labelText: 'Contraseña (mín. 6 caracteres)',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.lock_outlined),
        ),
        obscureText: true,
        onSubmitted: (_) => _emailAction(),
      ),
      const SizedBox(height: 16),
      _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                onPressed: _emailAction,
                icon: Icon(_isRegister ? Icons.person_add_outlined : Icons.login),
                label: Text(_isRegister ? 'Crear cuenta' : 'Iniciar sesión'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _isRegister = !_isRegister;
                }),
                child: Text(_isRegister
                    ? '¿Ya tienes cuenta? Iniciar sesión'
                    : '¿No tienes cuenta? Registrarse'),
              ),
            ]),
    ]);
  }

  Widget _buildPhoneTab() {
    if (!_otpSent) {
      return Column(children: [
        TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(
            labelText: 'Número con código de país',
            hintText: '+521234567890',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 8),
        Text(
          'Formato E.164: + código país + número\nMéxico: +52 · USA: +1 · España: +34',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : FilledButton.icon(
                onPressed: _sendOtp,
                icon: const Icon(Icons.send),
                label: const Text('Enviar código SMS'),
              ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Código enviado a ${_phoneCtrl.text}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      const SizedBox(height: 14),
      TextField(
        controller: _otpCtrl,
        decoration: const InputDecoration(
          labelText: 'Código de 6 dígitos',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.dialpad),
        ),
        keyboardType: TextInputType.number,
        maxLength: 6,
        onSubmitted: (_) => _confirmOtp(),
      ),
      const SizedBox(height: 4),
      _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(children: [
              TextButton(
                onPressed: () =>
                    setState(() { _otpSent = false; _confirmation = null; }),
                child: const Text('Cambiar número'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _confirmOtp,
                child: const Text('Verificar'),
              ),
            ]),
    ]);
  }

  Widget _buildAnonTab() {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.shield_outlined, size: 56, color: Color(0xFF42A5F5)),
      const SizedBox(height: 14),
      const Text(
        'Entra sin email ni teléfono.\nSe genera un ID criptográfico único\nvinculado solo a este navegador.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 20),
      _loading
          ? const Center(child: CircularProgressIndicator())
          : FilledButton.icon(
              onPressed: _signInAnonymously,
              icon: const Icon(Icons.shield),
              label: const Text('Entrar de forma anónima'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
      const SizedBox(height: 10),
      Text(
        'Tu clave E2EE se guarda solo en este navegador.',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

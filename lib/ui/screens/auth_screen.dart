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
  String? _error;

  // ── Email tab ──
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isRegister = false;

  // ── Phone tab ──
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  ConfirmationResult? _confirmation;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
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

  void _setError(String? e) {
    setState(() { _error = e; _loading = false; });
    if (e != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found': return 'Usuario no encontrado';
      case 'wrong-password': return 'Contraseña incorrecta';
      case 'email-already-in-use': return 'El email ya está registrado';
      case 'weak-password': return 'La contraseña debe tener al menos 6 caracteres';
      case 'invalid-email': return 'Email inválido';
      case 'invalid-verification-code': return 'Código OTP incorrecto';
      case 'invalid-phone-number': return 'Número de teléfono inválido (usa formato E.164)';
      case 'too-many-requests': return 'Demasiados intentos. Intenta más tarde.';
      default: return 'Error de autenticación: $code';
    }
  }

  // ── Email ─────────────────────────────────────────────────────────────────

  Future<void> _emailSignIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await widget.userRepo.registerOrLogin(cred.user!);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e.code));
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailRegister() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _setError('Ingresa tu nombre');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());
      await widget.userRepo.registerOrLogin(cred.user!);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e.code));
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _setError('Ingresa un número en formato E.164 (ejemplo: +521234567890)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = IdentityService();
      _confirmation = await svc.sendPhoneOtp(
        phoneE164: phone,
        recaptchaContainerId: 'recaptcha-container',
      );
      if (mounted) setState(() { _otpSent = true; _loading = false; });
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e.code));
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _confirmOtp() async {
    if (_confirmation == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final svc = IdentityService();
      final user = await svc.confirmPhoneOtp(
        confirmationResult: _confirmation!,
        smsCode: _otpCtrl.text.trim(),
      );
      final phoneHash = IdentityService.hashPhone(_phoneCtrl.text.trim());
      await widget.userRepo.registerOrLogin(user, phoneHash: phoneHash);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e.code));
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Anonymous ─────────────────────────────────────────────────────────────

  Future<void> _signInAnonymously() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = IdentityService();
      final user = await svc.signInAnonymously();
      await widget.userRepo.registerOrLogin(user);
    } on FirebaseAuthException catch (e) {
      _setError(_friendlyError(e.code));
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 72,
                    color: Color(0xFF1565C0)),
                const SizedBox(height: 16),
                const Text('SecureChat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                const Text('Identidad Híbrida · Privacidad Radical',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),

                // Error banner — shown at top so it's always visible
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withAlpha(80)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                        onPressed: () => setState(() => _error = null),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                  ),

                // Invisible reCAPTCHA anchor for Firebase Phone Auth
                const SizedBox(
                    key: ValueKey('recaptcha-container'), height: 0),

                TabBar(
                  controller: _tabs,
                  labelStyle: const TextStyle(fontSize: 11),
                  tabs: const [
                    Tab(icon: Icon(Icons.email_outlined), text: 'Email'),
                    Tab(icon: Icon(Icons.phone_outlined), text: 'SMS OTP'),
                    Tab(icon: Icon(Icons.shield_outlined), text: 'Anónimo'),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 280,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildEmailTab(),
                      _buildPhoneTab(),
                      _buildAnonTab(),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: Divider(color: Colors.grey[800])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Cifrado E2EE',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 11)),
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
    return Column(
      children: [
        if (_isRegister) ...[
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
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
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outlined),
          ),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _isRegister ? _emailRegister() : _emailSignIn(),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          FilledButton.icon(
            onPressed: _isRegister ? _emailRegister : _emailSignIn,
            icon: Icon(_isRegister
                ? Icons.person_add_outlined
                : Icons.login),
            label: Text(_isRegister ? 'Crear cuenta' : 'Iniciar sesión'),
          ),
          TextButton(
            onPressed: () =>
                setState(() { _isRegister = !_isRegister; _error = null; }),
            child: Text(_isRegister
                ? '¿Ya tienes cuenta? Inicia sesión'
                : '¿No tienes cuenta? Regístrate'),
          ),
        ],
      ],
    );
  }

  Widget _buildPhoneTab() {
    if (!_otpSent) {
      return Column(
        children: [
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Número E.164 (+521234567890)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 8),
          const Text(
            'El número se hashea con SHA-256 antes de guardarse.\nEl número real nunca se almacena.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Enviar código SMS'),
              onPressed: _sendOtp,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Código enviado a ${_phoneCtrl.text}',
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextField(
          controller: _otpCtrl,
          decoration: const InputDecoration(
            labelText: 'Código OTP de 6 dígitos',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.dialpad),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          onSubmitted: (_) => _confirmOtp(),
        ),
        const SizedBox(height: 4),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
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
      ],
    );
  }

  Widget _buildAnonTab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.shield_outlined, size: 48,
            color: Color(0xFF42A5F5)),
        const SizedBox(height: 12),
        const Text(
          'Entra sin revelar ningún dato personal.\nSe genera un ID criptográfico único en este dispositivo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          FilledButton.icon(
            icon: const Icon(Icons.shield),
            label: const Text('Entrar de forma anónima'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            onPressed: _signInAnonymously,
          ),
        const SizedBox(height: 8),
        const Text(
          'Tu clave E2EE se guarda solo en este navegador.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

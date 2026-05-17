import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shows the user's own QR pairing code and allows pasting
/// another user's code to initiate a chat.
class QrPairingWidget extends StatefulWidget {
  final String myUid;
  final void Function(String otherUid) onPaired;

  const QrPairingWidget({
    super.key,
    required this.myUid,
    required this.onPaired,
  });

  @override
  State<QrPairingWidget> createState() => _QrPairingWidgetState();
}

class _QrPairingWidgetState extends State<QrPairingWidget> {
  final _codeCtrl = TextEditingController();
  String? _error;

  String get _pairingCode => 'SCHAT_PAIR:${widget.myUid}';

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _codeCtrl.text = data!.text!);
    }
  }

  void _submit() {
    final raw = _codeCtrl.text.trim();
    if (!raw.startsWith('SCHAT_PAIR:')) {
      setState(() => _error = 'Código inválido. Debe comenzar con SCHAT_PAIR:');
      return;
    }
    final uid = raw.substring('SCHAT_PAIR:'.length);
    if (uid.isEmpty) {
      setState(() => _error = 'Código vacío');
      return;
    }
    if (uid == widget.myUid) {
      setState(() => _error = 'No puedes emparejarte contigo mismo');
      return;
    }
    widget.onPaired(uid);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tu código de emparejamiento',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: _pairingCode,
              version: QrVersions.auto,
              size: 180,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _pairingCode,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copiar código', style: TextStyle(fontSize: 12)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _pairingCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Código copiado al portapapeles')),
              );
            },
          ),
          const Divider(height: 32),
          const Text('Conectar con otro usuario',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: 'Pega el código SCHAT_PAIR: aquí',
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: _handlePaste,
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Conectar'),
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }
}

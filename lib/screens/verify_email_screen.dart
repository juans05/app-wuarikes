import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../state/auth_provider.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final TextEditingController _emailCtrl = TextEditingController(text: widget.email);
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().verifyEmail(_emailCtrl.text.trim(), _codeCtrl.text.trim());
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = 'Código inválido o expirado');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await ApiClient().resendCode(_emailCtrl.text.trim());
      setState(() => _info = 'Te enviamos un nuevo código a tu correo.');
    } catch (e) {
      setState(() => _error = 'No se pudo reenviar el código');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'Te enviamos un código de 6 dígitos a tu correo. Ingrésalo para activar tu cuenta.',
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
              ),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_info != null) Text(_info!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_loading ? 'Verificando...' : 'Verificar'),
              ),
              TextButton(onPressed: _resend, child: const Text('Reenviar código')),
            ],
          ),
        ),
      ),
    );
  }
}

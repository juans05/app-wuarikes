import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _api = ApiClient();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresa tu correo electrónico.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.forgotPassword(email);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: email)),
        );
      }
    } catch (e) {
      setState(() => _error = e is ApiException ? e.message : 'No se pudo enviar el código. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'Ingresa tu correo y te enviaremos un código de 6 dígitos para restablecer tu contraseña.',
                style: AppText.bodyMd,
              ),
              const SizedBox(height: 20),
              Text('Correo electrónico', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'tu@correo.com'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Enviando...' : 'Enviar código'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

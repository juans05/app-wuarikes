import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _api = ApiClient();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _submit() async {
    if (_codeCtrl.text.trim().length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos.');
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.resetPassword(widget.email, _codeCtrl.text.trim(), _passwordCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada. Ya puedes iniciar sesión.')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() => _error = e is ApiException ? e.message : 'No se pudo actualizar la contraseña.');
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
      await _api.forgotPassword(widget.email);
      setState(() => _info = 'Te enviamos un nuevo código a tu correo.');
    } catch (e) {
      setState(() => _error = 'No se pudo reenviar el código.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Restablecer contraseña')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('Te enviamos un código de 6 dígitos a ${widget.email}.', style: AppText.bodyMd),
              const SizedBox(height: 20),
              Text('Código', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 8),
              Text('Nueva contraseña', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded)),
              ),
              const SizedBox(height: 14),
              Text('Confirmar contraseña', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_reset_rounded)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_info != null) ...[
                const SizedBox(height: 10),
                Text(_info!, style: const TextStyle(color: Colors.green)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Guardando...' : 'Cambiar contraseña'),
              ),
              TextButton(onPressed: _loading ? null : _resend, child: const Text('Reenviar código')),
            ],
          ),
        ),
      ),
    );
  }
}

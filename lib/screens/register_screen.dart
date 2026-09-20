import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../state/auth_provider.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().register(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
            _nameCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: _emailCtrl.text.trim())),
        );
      }
    } catch (e) {
      setState(() => _error = 'No se pudo crear la cuenta. Revisa los datos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final success = await context.read<AuthProvider>().loginWithGoogle();
      if (success && mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = 'No se pudo registrar con Google');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _facebookSignUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final success = await context.read<AuthProvider>().loginWithFacebook();
      if (success && mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = 'No se pudo registrar con Facebook');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              Text('Crea tu cuenta', textAlign: TextAlign.center, style: AppText.headlineMobile),
              const SizedBox(height: 6),
              Text('Únete a la comunidad de exploradores culinarios de Lima',
                  textAlign: TextAlign.center, style: AppText.bodyMd),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.xl)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nombre completo', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded), hintText: 'Ej. Juan Pérez'),
                    ),
                    const SizedBox(height: 14),
                    Text('Correo electrónico', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'tu@correo.com'),
                    ),
                    const SizedBox(height: 14),
                    Text('Contraseña', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline_rounded)),
                    ),
                    const SizedBox(height: 14),
                    Text('Confirmar', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
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
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading ? null : const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(_loading ? 'Creando cuenta...' : 'Registrarse'),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      const Expanded(child: Divider(color: AppColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('o continúa con', style: AppText.bodyMd),
                      ),
                      const Expanded(child: Divider(color: AppColors.border)),
                    ]),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _googleSignUp,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                      label: const Text('Registrarse con Google'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _facebookSignUp,
                      icon: const Icon(Icons.facebook_rounded, size: 22, color: Color(0xFF1877F2)),
                      label: const Text('Registrarse con Facebook'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: RichText(
                    text: TextSpan(
                      style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                      children: const [
                        TextSpan(text: '¿Ya tienes una cuenta? '),
                        TextSpan(text: 'Inicia sesión', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

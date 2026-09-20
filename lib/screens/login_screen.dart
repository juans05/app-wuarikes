import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../state/auth_provider.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().login(_emailCtrl.text.trim(), _passwordCtrl.text);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (e.status == 403 && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: _emailCtrl.text.trim())),
        );
        return;
      }
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar sesión');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final success = await context.read<AuthProvider>().loginWithGoogle();
      if (success && mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[GOOGLE_LOGIN_DEBUG] ${e.runtimeType}: $e'
          '${e is ApiException ? ' (status ${e.status})' : ''}');
      setState(() => _error = 'No se pudo ingresar con Google');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _facebookLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final success = await context.read<AuthProvider>().loginWithFacebook();
      if (success && mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'No se pudo ingresar con Facebook');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Wuarikes', textAlign: TextAlign.center, style: AppText.titleLg.copyWith(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Explora el sabor de Lima', textAlign: TextAlign.center, style: AppText.bodyMd),
                  const SizedBox(height: 28),
                  Text('Correo electrónico', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_outline_rounded), hintText: 'tu@correo.com'),
                  ),
                  const SizedBox(height: 16),
                  Text('Contraseña', style: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? 'Ingresando...' : 'Iniciar Sesión'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: Text(
                        '¿Olvidaste tu contraseña?',
                        style: AppText.bodyMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('o continúa con', style: AppText.bodyMd),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _googleLogin,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                    label: const Text('Ingresar con Google'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _facebookLogin,
                    icon: const Icon(Icons.facebook_rounded, size: 22, color: Color(0xFF1877F2)),
                    label: const Text('Ingresar con Facebook'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                          children: const [
                            TextSpan(text: '¿No tienes una cuenta? '),
                            TextSpan(
                              text: 'Regístrate ahora',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

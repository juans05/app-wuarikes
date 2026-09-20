import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../screens/login_screen.dart';

/// Shown in place of a screen's content when the user isn't logged in.
class LoginRequiredView extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onLoggedIn;

  const LoginRequiredView({super.key, required this.icon, required this.message, required this.onLoggedIn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppText.bodyMd),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
                onLoggedIn();
              },
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}

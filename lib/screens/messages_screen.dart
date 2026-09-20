import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../state/auth_provider.dart';
import '../widgets/login_required_view.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mensajes')),
      body: SafeArea(
        child: !auth.isLoggedIn
            ? LoginRequiredView(
                icon: Icons.chat_bubble_outline_rounded,
                message: 'Inicia sesión para consultar tus mensajes con huariques y anfitriones.',
                onLoggedIn: () {},
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text('Aún no tienes mensajes.', textAlign: TextAlign.center, style: AppText.bodyMd),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

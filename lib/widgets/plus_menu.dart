import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../screens/register_place_screen.dart';

enum _PlusAction { publish, suggest }

/// Menú del botón ＋ de la barra: fondo oscurecido, dos opciones apiladas
/// sobre el botón central, que se vuelve ×.
Future<void> showPlusMenu(BuildContext context) async {
  final action = await showGeneralDialog<_PlusAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar menú',
    barrierColor: AppColors.onSurface.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const _PlusMenu(),
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PlusAction.publish:
      showPublishNowSheet(context);
    case _PlusAction.suggest:
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterPlaceScreen()),
      );
  }
}

// TODO(Task 9): reemplazar por la hoja de publicar
void showPublishNowSheet(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Muy pronto')));
}

class _PlusMenu extends StatelessWidget {
  const _PlusMenu();

  // El centro del botón de la barra queda a medio FAB (28) sobre el borde
  // inferior de la barra segura, así que el × se dibuja en el mismo lugar.
  static const _fabSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + _fabSize / 2;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + _fabSize + 16,
            child: Center(
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlusMenuItem(
                      icon: Icons.bolt_rounded,
                      label: 'Publicar lo que pasa aquí',
                      onTap: () => Navigator.of(context).pop(_PlusAction.publish),
                    ),
                    const SizedBox(height: 8),
                    _PlusMenuItem(
                      icon: Icons.add_location_alt_outlined,
                      label: 'Sugerir un lugar nuevo',
                      onTap: () => Navigator.of(context).pop(_PlusAction.suggest),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: Center(
              child: FloatingActionButton(
                heroTag: null,
                tooltip: 'Cerrar',
                backgroundColor: AppColors.primary,
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlusMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PlusMenuItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: AppText.bodyMd.copyWith(
                      color: AppColors.onSurface, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

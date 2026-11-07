import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../screens/register_place_screen.dart';

enum _PlusAction { publish, suggest }

/// Menú del botón ＋ de la barra: fondo oscurecido, dos opciones apiladas
/// sobre el botón central, que se vuelve ×.
///
/// [anchor] es el contexto del botón ＋ de la barra: el × se dibuja en su
/// centro real. Sin él se usa una fórmula aproximada (ver [_PlusMenu]).
Future<void> showPlusMenu(BuildContext context, {BuildContext? anchor}) async {
  Offset? center;
  final box = anchor?.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    center = box.localToGlobal(box.size.center(Offset.zero));
  }
  final action = await showGeneralDialog<_PlusAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar menú',
    barrierColor: AppColors.onSurface.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _PlusMenu(center: center),
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
  /// Centro del ＋ en coordenadas de pantalla; null si no se pudo medir.
  final Offset? center;
  const _PlusMenu({this.center});

  static const _fabSize = 56.0;
  static const _menuWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      // ponytail: asume que el diálogo ocupa la pantalla entera (así es en la
      // app); con un Navigator anidado o recortado habría que convertir el centro.
      child: LayoutBuilder(builder: (context, box) {
        // Sin ancla: a medio FAB sobre el borde inferior seguro.
        final c = center ??
            Offset(
                box.maxWidth / 2,
                box.maxHeight -
                    MediaQuery.paddingOf(context).bottom -
                    _fabSize / 2);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: c.dx - _menuWidth / 2,
              width: _menuWidth,
              bottom: box.maxHeight - (c.dy - _fabSize / 2) + 16,
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
            Positioned(
              left: c.dx - _fabSize / 2,
              top: c.dy - _fabSize / 2,
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
          ],
        );
      }),
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

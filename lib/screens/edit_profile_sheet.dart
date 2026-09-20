import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';

Future<bool?> showEditProfileSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (context) => _EditProfileSheet(user: user),
  );
}

class _EditProfileSheet extends StatefulWidget {
  final AppUser user;
  const _EditProfileSheet({required this.user});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _fullNameController = TextEditingController(text: widget.user.fullName);
  late final _bioController = TextEditingController(text: widget.user.bio ?? '');
  final _api = ApiClient();
  bool _isSaving = false;
  String? _error;

  Future<void> _save() async {
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _api.updateProfile(fullName: fullName, bio: _bioController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Editar perfil', style: AppText.titleLg),
          const SizedBox(height: 16),
          Text('Nombre', style: AppText.labelMd),
          const SizedBox(height: 4),
          TextField(controller: _fullNameController, decoration: const InputDecoration(hintText: 'Tu nombre')),
          const SizedBox(height: 16),
          Text('Bio', style: AppText.labelMd),
          const SizedBox(height: 4),
          TextField(
            controller: _bioController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Cuéntanos algo sobre ti'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: AppText.labelMd.copyWith(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isSaving ? 'Guardando...' : 'Guardar cambios'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/external_actions.dart';
import '../state/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient();
  Map<String, dynamic>? _profile;
  List<dynamic> _sessions = [];
  bool _busy = false;
  String? _error;
  static const _privacy = {
    'isProfilePublic': 'Perfil público',
    'areFavoritesPublic': 'Favoritos visibles',
    'allowBusinessMessages': 'Mensajes de negocios',
    'isDiscoverable': 'Aparecer en búsqueda de amigos'
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _api.get('/users/me/profile');
      final sessions = await _api
          .post('/auth/sessions', {'refreshToken': await _api.refreshToken});
      if (mounted)
        setState(() {
          _profile = Map<String, dynamic>.from(profile);
          _sessions = sessions as List;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(Future<dynamic> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _busy = false;
        });
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
            'Esta acción es permanente: se elimina tu perfil y ya no podrás iniciar sesión con esta cuenta. ¿Deseas continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.delete('/users/me');
      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Ajustes de la cuenta')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
              onPressed: _busy ? null : _load, child: const Text('Reintentar'))
        ],
        Text('Privacidad', style: Theme.of(context).textTheme.titleLarge),
        if (_profile != null)
          for (final item in _privacy.entries)
            SwitchListTile(
                title: Text(item.value),
                value: _profile![item.key] == true,
                onChanged: _busy
                    ? null
                    : (v) => _change(
                        () => _api.patch('/users/me/privacy', {item.key: v}))),
        const Divider(),
        Text('Sesiones activas', style: Theme.of(context).textTheme.titleLarge),
        for (final s in _sessions)
          ListTile(
              title: Text('${s['deviceLabel']}'),
              subtitle: Text('${s['createdAt']}'),
              trailing: s['isCurrent'] == true
                  ? const Text('Actual')
                  : IconButton(
                      tooltip: 'Cerrar sesión',
                      icon: const Icon(Icons.logout),
                      onPressed: _busy
                          ? null
                          : () => _change(() =>
                              _api.post('/auth/sessions/${s['id']}/revoke')))),
        OutlinedButton(
            onPressed: _busy || _sessions.length < 2
                ? null
                : () => _change(() async => _api.post(
                    '/auth/sessions/revoke-others',
                    {'refreshToken': await _api.refreshToken})),
            child: const Text('Cerrar las otras sesiones')),
        const Divider(),
        for (final link in {
          'terminos-y-condiciones': 'Términos y condiciones',
          'politica-de-privacidad': 'Política de privacidad',
          'libro-de-reclamaciones': 'Libro de reclamaciones'
        }.entries)
          ListTile(
              dense: true,
              title: Text(link.value,
                  style: Theme.of(context).textTheme.bodySmall),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () => openExternal(context, '$webBaseUrl/${link.key}')),
        const Divider(),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _confirmDeleteAccount,
            child: Text('Eliminar cuenta',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red)),
          ),
        ),
      ]));
}

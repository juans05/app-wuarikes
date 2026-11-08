import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/now_api.dart';

/// Mis amigos de "Ahora": mis seguidores, cada uno con un interruptor
/// "En mis Amigos". Solo se ve nombre y foto (lo público). Quien está en la
/// lista ve mis publicaciones marcadas "solo Amigos".
class FriendsScreen extends StatefulWidget {
  /// Solo para pruebas: API de mentira.
  final ApiClient? api;
  const FriendsScreen({super.key, this.api});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _followers = <Map<String, dynamic>>[];
  final _friendIds = <String>{};

  /// Seguidores con un cambio en camino: su interruptor espera la respuesta.
  final _changing = <String>{};
  int _page = 0, _total = 0;
  bool _loading = true, _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait<dynamic>([
        _api.get('/users/me/followers', query: {'page': '1', 'limit': '20'}),
        _api.getFriends(),
      ]);
      if (!mounted) return;
      final page = r[0] as Map<String, dynamic>;
      setState(() {
        _followers
          ..clear()
          ..addAll((page['data'] as List).cast<Map<String, dynamic>>());
        _total = (page['total'] as num?)?.toInt() ?? _followers.length;
        _page = 1;
        _friendIds
          ..clear()
          ..addAll((r[1] as List<Map<String, dynamic>>)
              .map((f) => f['id'] as String));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await _api.get('/users/me/followers',
          query: {'page': '${_page + 1}', 'limit': '20'});
      if (!mounted) return;
      setState(() {
        _followers.addAll((page['data'] as List).cast<Map<String, dynamic>>());
        _page++;
      });
    } catch (_) {
      _snack('No se pudieron cargar más. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Cambia el interruptor al instante y lo devuelve si el servidor falla.
  Future<void> _toggle(String id, bool on) async {
    setState(() {
      _changing.add(id);
      on ? _friendIds.add(id) : _friendIds.remove(id);
    });
    try {
      on ? await _api.addFriend(id) : await _api.removeFriend(id);
    } catch (_) {
      if (mounted) {
        setState(() => on ? _friendIds.remove(id) : _friendIds.add(id));
      }
      _snack(on
          ? 'No se pudo agregar a Amigos. Intenta de nuevo.'
          : 'No se pudo quitar de Amigos. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _changing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mis amigos')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    TextButton(
                        onPressed: _load, child: const Text('Reintentar'))
                  ]))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                              'Tus Amigos ven lo que publicas solo para Amigos.',
                              style: AppText.bodyMd
                                  .copyWith(color: AppColors.onSurface)),
                        ),
                        const SizedBox(height: 8),
                        if (_followers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                'Todavía no tienes seguidores. Cuando alguien te siga, podrás agregarlo a tus Amigos.',
                                textAlign: TextAlign.center,
                                style: AppText.bodyMd),
                          ),
                        for (final f in _followers)
                          _FollowerTile(
                            follower: f,
                            isFriend: _friendIds.contains(f['id']),
                            busy: _changing.contains(f['id']),
                            onChanged: (on) => _toggle(f['id'] as String, on),
                          ),
                        if (_followers.length < _total)
                          TextButton(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: const Text('Cargar más')),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _FollowerTile extends StatelessWidget {
  final Map<String, dynamic> follower;
  final bool isFriend;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _FollowerTile({
    required this.follower,
    required this.isFriend,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = follower['avatarUrl'] as String?;
    return SwitchListTile(
      value: isFriend,
      onChanged: busy ? null : onChanged,
      activeThumbColor: AppColors.primary,
      secondary: CircleAvatar(
        backgroundColor: AppColors.primaryContainer,
        backgroundImage:
            avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
        child: avatar == null || avatar.isEmpty
            ? const Icon(Icons.person, color: AppColors.primary)
            : null,
      ),
      title: Text('${follower['fullName'] ?? ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('En mis Amigos'),
    );
  }
}

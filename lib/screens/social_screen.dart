import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/external_actions.dart';
import '../state/auth_provider.dart';
import 'login_screen.dart';

class SocialScreen extends StatefulWidget {
  final String? userId;
  final bool followers;
  const SocialScreen({super.key, this.userId, this.followers = true});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

/// Paginated follow-list state, one instance per tab (followers / following).
class _PeopleList {
  final people = <dynamic>[];
  int page = 0;
  bool more = true, busy = false;
  String? error;
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  Map<String, dynamic>? _profile, _status;
  bool _busy = false;
  String? _error;

  // ---- List mode (widget.userId == null): tabs + search ----
  late final TabController _tabController;
  final _followersList = _PeopleList();
  final _followingList = _PeopleList();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _searchResults; // null = not searching
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId == null) {
      _tabController = TabController(
          length: 2, vsync: this, initialIndex: widget.followers ? 0 : 1);
      _loadList(_followersList, true);
      _loadList(_followingList, false);
    }
    _load();
  }

  @override
  void dispose() {
    if (widget.userId == null) _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await _api.get('/users/${widget.userId}');
      final status = await _api.get('/users/${widget.userId}/follow');
      if (!mounted) return;
      setState(() {
        _profile = Map<String, dynamic>.from(profile);
        _status = Map<String, dynamic>.from(status);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadList(_PeopleList l, bool followers) async {
    if (l.busy || !l.more) return;
    setState(() => l.busy = true);
    try {
      final result = await _api.get(
          '/users/me/${followers ? 'followers' : 'following'}',
          query: {'page': '${l.page + 1}', 'limit': '20'});
      if (!mounted) return;
      setState(() {
        l.page++;
        l.people.addAll(result['data']);
        l.more = l.people.length < (result['total'] as num);
      });
    } catch (e) {
      if (mounted) setState(() => l.error = '$e');
    } finally {
      if (mounted) setState(() => l.busy = false);
    }
  }

  Future<void> _follow() async {
    setState(() => _busy = true);
    try {
      if (_status?['isFollowing'] == true) {
        await _api.delete('/users/${widget.userId}/follow');
      } else {
        await _api.post('/users/${widget.userId}/follow');
      }
      await _load();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _busy = false;
        });
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final results = await _api.searchUsers(query);
        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      } catch (_) {
        if (mounted)
          setState(() {
            _searchResults = [];
            _searching = false;
          });
      }
    });
  }

  void _openProfile(dynamic p) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SocialScreen(userId: p['id'])));

  Widget _personTile(dynamic p) => ListTile(
        title: Text('${p['fullName']}'),
        leading: CircleAvatar(
            backgroundImage:
                p['avatarUrl'] == null ? null : NetworkImage(p['avatarUrl']),
            child: p['avatarUrl'] == null
                ? const Icon(Icons.person)
                : null),
        onTap: () => _openProfile(p),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.userId != null) return _buildProfileView(context);
    return _buildListMode(context);
  }

  Widget _buildProfileView(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (!auth.isLoggedIn)
            FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()));
                  if (mounted) _load();
                },
                child: const Text('Iniciar sesión')),
          if (_profile != null) ...[
            if (_profile!['avatarUrl'] != null)
              CircleAvatar(
                  radius: 48,
                  backgroundImage: NetworkImage(_profile!['avatarUrl'])),
            Text('${_profile!['fullName']}',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('Nivel ${_profile!['currentLevel'] ?? 1}'),
            Text(
                '${_status?['followers'] ?? 0} seguidores · ${_status?['following'] ?? 0} siguiendo'),
            if (auth.user?.id != widget.userId)
              FilledButton(
                  onPressed: _busy ? null : _follow,
                  child: Text(_status?['isFollowing'] == true
                      ? 'Dejar de seguir'
                      : 'Seguir')),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
        ]));
  }

  Widget _buildListMode(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguidores y seguidos'),
        bottom: TabBar(controller: _tabController, tabs: [
          Tab(text: '${_followersList.people.length} Seguidores'),
          Tab(text: '${_followingList.people.length} Seguidos'),
        ]),
      ),
      body: !auth.isLoggedIn
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LoginScreen()));
                    if (mounted) setState(() {});
                  },
                  child: const Text('Iniciar sesión')),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar en Wuarikes...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(
                  child: _searchResults == null
                      ? TabBarView(controller: _tabController, children: [
                          _buildPeopleList(_followersList, true),
                          _buildPeopleList(_followingList, false),
                        ])
                      : _buildSearchResults(),
                ),
              ],
            ),
    );
  }

  Widget _buildPeopleList(_PeopleList l, bool followers) {
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      for (final p in l.people) _personTile(p),
      if (l.busy) const Center(child: Padding(
          padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      if (l.error != null)
        Padding(
            padding: const EdgeInsets.all(16), child: Text(l.error!)),
      if (!l.busy && (l.error != null || l.more))
        TextButton(
            onPressed: () => _loadList(l, followers),
            child: Text(l.error != null ? 'Reintentar' : 'Cargar más')),
      if (!l.busy && l.people.isEmpty && l.error == null)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              followers
                  ? 'Todavía no tienes seguidores.'
                  : 'Todavía no sigues a nadie.',
              style: AppText.bodyMd),
        ),
    ]);
  }

  Widget _buildSearchResults() {
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_searchResults!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_search_outlined,
                size: 40, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No encontramos a nadie con ese nombre en Wuarikes.',
                textAlign: TextAlign.center, style: AppText.bodyMd),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => inviteFriends(context),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Invitar amigos'),
            ),
          ]),
        ),
      );
    }
    return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [for (final p in _searchResults!) _personTile(p)]);
  }
}

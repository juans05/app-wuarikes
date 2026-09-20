import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/models.dart';
import '../state/auth_provider.dart';
import '../core/external_actions.dart';
import 'place_detail_screen.dart';
import 'social_screen.dart';
import 'login_screen.dart';

class FeedScreen extends StatefulWidget {
  final String? placeId;
  final bool history;
  const FeedScreen({super.key, this.placeId, this.history = false});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _api = ApiClient();
  final _items = <CheckinItem>[];
  final _liking = <String>{};
  int _page = 0;
  bool _more = true, _loading = false, _following = false;
  String _sort = 'recent';
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = widget.history
          ? await _api.getMyCheckins(page: page)
          : await _api.getFeed(
              page: page,
              following: _following,
              placeId: widget.placeId,
              sort: _sort == 'photos' ? 'recent' : _sort,
              hasPhotos: _sort == 'photos');
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(result.data);
        _page = page;
        _more = page < result.totalPages;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _like(CheckinItem item) async {
    if (!context.read<AuthProvider>().isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    setState(() => _liking.add(item.id));
    try {
      if (item.isLikedByMe) {
        await _api.unlikeCheckin(item.id);
      } else {
        await _api.likeCheckin(item.id);
      }
      await _load(reset: true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _liking.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.history
                ? 'Historial completo'
                : widget.placeId != null
                    ? 'Reseñas'
                    : 'Actividad reciente')),
        body: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (!widget.history &&
                  widget.placeId == null &&
                  context.watch<AuthProvider>().isLoggedIn)
                SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Todos')),
                      ButtonSegment(value: true, label: Text('Siguiendo'))
                    ],
                    selected: {
                      _following
                    },
                    onSelectionChanged: _loading
                        ? null
                        : (s) {
                            setState(() => _following = s.first);
                            _load(reset: true);
                          }),
              if (widget.placeId != null)
                DropdownButton<String>(
                    value: _sort,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'recent', child: Text('Más recientes')),
                      DropdownMenuItem(
                          value: 'top_rated', child: Text('Mayor puntuación')),
                      DropdownMenuItem(
                          value: 'low_rated', child: Text('Menor puntuación')),
                      DropdownMenuItem(
                          value: 'photos', child: Text('Con fotos'))
                    ],
                    onChanged: _loading
                        ? null
                        : (v) {
                            setState(() => _sort = v!);
                            _load(reset: true);
                          }),
              for (final item in _items)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (item.userId != null)
                                TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => SocialScreen(
                                                userId: item.userId))),
                                    child:
                                        Text(item.userFullName ?? 'Usuario')),
                              if (item.place != null)
                                TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => PlaceDetailScreen(
                                                placeId: item.place!.id))),
                                    child: Text(item.place!.name)),
                              if (item.rating != null)
                                Text('${item.rating} / 5 ★'),
                              if (item.comment != null) Text(item.comment!),
                              if (item.dishName != null)
                                Text(
                                    '${item.dishName}${item.dishPrice == null ? '' : ' · S/ ${item.dishPrice}'}'),
                              if (item.photoUrl != null)
                                Image.network(item.photoUrl!,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image)),
                              Text(item.createdAt.split('T').first),
                              Row(children: [
                                TextButton.icon(
                                    onPressed: widget.history ||
                                            _liking.contains(item.id) ||
                                            _loading
                                        ? null
                                        : () => _like(item),
                                    icon: Icon(item.isLikedByMe
                                        ? Icons.favorite
                                        : Icons.favorite_border),
                                    label: Text('${item.likesCount}')),
                                const Spacer(),
                                IconButton(
                                    tooltip: 'Compartir',
                                    onPressed: () => sharePlace(
                                        context,
                                        item.place?.id ?? item.placeId,
                                        item.place?.name ?? 'Wuarikes'),
                                    icon: const Icon(Icons.share))
                              ]),
                            ]))),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_loading) const LinearProgressIndicator(),
              if (!_loading && _items.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Todavía no hay publicaciones.')),
              if (!_loading && (_more || _error != null))
                TextButton(
                    onPressed: () => _load(reset: _error != null),
                    child: Text(_error != null ? 'Reintentar' : 'Cargar más')),
            ])),
      );
}

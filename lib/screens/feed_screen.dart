import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../core/now_api.dart';
import '../core/now_location.dart';
import '../core/now_models.dart';
import '../state/auth_provider.dart';
import '../core/external_actions.dart';
import 'now/now_post_screen.dart';
import 'place_detail_screen.dart';
import 'social_screen.dart';
import 'login_screen.dart';

/// Una fila de Actividad: un check-in o una publicación de Ahora.
sealed class FeedEntry {
  /// Cuándo se hizo; con esto [mergeFeed] las ordena.
  DateTime get at;
}

class CheckinEntry extends FeedEntry {
  final CheckinItem item;
  CheckinEntry(this.item)
      : at = DateTime.tryParse(item.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  @override
  final DateTime at;
}

class PostEntry extends FeedEntry {
  final NowPost post;
  PostEntry(this.post) : at = post.createdAt;
  @override
  final DateTime at;
}

/// Intercala check-ins y publicaciones de la más nueva a la más vieja. A igual
/// fecha manda el orden de entrada (check-ins antes que publicaciones, cada
/// lista como vino): `List.sort` no es estable, por eso el índice desempata.
List<FeedEntry> mergeFeed(List<CheckinItem> checkins, List<NowPost> posts) {
  final all = <FeedEntry>[
    for (final c in checkins) CheckinEntry(c),
    for (final p in posts) PostEntry(p),
  ];
  final order = List<int>.generate(all.length, (i) => i)
    ..sort((a, b) {
      final byDate = all[b].at.compareTo(all[a].at);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  return [for (final i in order) all[i]];
}

/// Filtro de la pestaña Actividad. [all] es el feed de siempre (solo
/// check-ins); los otros tres suman o usan solo las publicaciones de Ahora
/// (`GET /now/feed?scope=` toma el [name] tal cual).
enum _Scope {
  all('Todos'),
  following('Siguiendo'),
  nearby('Cerca de mí'),
  friends('Amigos');

  const _Scope(this.label);
  final String label;
  bool get hasCheckins => this == all || this == following;
  bool get hasPosts => this != all;
}

class FeedScreen extends StatefulWidget {
  final String? placeId;
  final bool history;

  /// Solo para pruebas: API y GPS de mentira.
  final ApiClient? api;
  final NowLocator? locate;
  const FeedScreen(
      {super.key, this.placeId, this.history = false, this.api, this.locate});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _checkins = <CheckinItem>[];
  final _posts = <NowPost>[];
  final _liking = <String>{};

  // Cada fuente pagina aparte. En Siguiendo se piden las dos juntas (página N
  // de cada una) y se mezclan; "Cargar más" pide la página siguiente de las que
  // todavía tienen más. ponytail: el orden global solo es exacto dentro de lo
  // ya cargado; si una fuente va más atrás en el tiempo que la otra, sus
  // elementos nuevos se intercalan donde les toca, no al final.
  int _ckPage = 0, _postPage = 0;
  bool _ckMore = true, _postMore = true;

  bool _loading = false;
  _Scope _scope = _Scope.all;
  String _sort = 'recent';
  String? _error;

  /// Cerca de mí: sin GPS no se llama a la API, se avisa.
  bool _noLocation = false;
  Position? _pos;

  /// Sube al cambiar de filtro: lo que venga en vuelo del anterior se descarta.
  int _gen = 0;

  /// Historial y reseñas de un local no llevan filtros de Ahora.
  bool get _hasTabs => !widget.history && widget.placeId == null;

  bool get _more =>
      (_scope.hasCheckins && _ckMore) || (_scope.hasPosts && _postMore);

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<Paginated<CheckinItem>> _fetchCheckins(int page, _Scope scope) async =>
      widget.history
          ? await _api.getMyCheckins(page: page)
          : await _api.getFeed(
              page: page,
              following: scope == _Scope.following,
              placeId: widget.placeId,
              sort: _sort == 'photos' ? 'recent' : _sort,
              hasPhotos: _sort == 'photos');

  Future<Paginated<NowPost>> _fetchPosts(int page, _Scope scope) async =>
      _api.getNowFeed(scope.name,
          page: page,
          lat: scope == _Scope.nearby ? _pos?.latitude : null,
          lng: scope == _Scope.nearby ? _pos?.longitude : null);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final scope = _scope;
    final gen = _gen;
    // Las pestañas de Ahora piden sesión; el invitado ve el aviso, sin llamadas.
    if (scope != _Scope.all && !context.read<AuthProvider>().isLoggedIn) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _noLocation = false;
    });
    try {
      if (scope == _Scope.nearby && (reset || _pos == null)) {
        Position? p;
        try {
          p = await (widget.locate ?? currentNowPosition)();
        } catch (_) {}
        if (!mounted || gen != _gen) return;
        if (p == null) {
          setState(() {
            _noLocation = true;
            _pos = null;
            _posts.clear();
          });
          return;
        }
        _pos = p;
      }

      final ckPage = reset ? 1 : _ckPage + 1;
      final postPage = reset ? 1 : _postPage + 1;
      final wantCk = scope.hasCheckins && (reset || _ckMore);
      final wantPosts = scope.hasPosts && (reset || _postMore);

      // Una fuente que falla no tumba a la otra.
      Object? firstError;
      Future<Paginated<T>?> guard<T>(Future<Paginated<T>> f) async {
        try {
          return await f;
        } catch (e) {
          firstError ??= e;
          return null;
        }
      }

      final ckFuture = wantCk ? guard(_fetchCheckins(ckPage, scope)) : null;
      final postFuture = wantPosts ? guard(_fetchPosts(postPage, scope)) : null;
      final ck = await ckFuture;
      final posts = await postFuture;
      if (!mounted || gen != _gen) return;

      final failed = (wantCk && ck == null) || (wantPosts && posts == null);
      final allFailed = (wantCk || wantPosts) &&
          (!wantCk || ck == null) &&
          (!wantPosts || posts == null);
      setState(() {
        if (ck != null) {
          if (reset) _checkins.clear();
          _append(_checkins, ck.data, (c) => c.id);
          _ckPage = ckPage;
          _ckMore = ckPage < ck.totalPages;
        }
        if (posts != null) {
          if (reset) _posts.clear();
          _append(_posts, posts.data, (p) => p.id);
          _postPage = postPage;
          _postMore = postPage < posts.totalPages;
        }
        if (allFailed) _error = '$firstError';
      });
      if (failed && !allFailed) _snack('No se pudo cargar todo');
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  /// Agrega [more] a [list] sin repetir ids: si entre una página y la siguiente
  /// entra algo nuevo, el servidor corre los límites y repite elementos.
  void _append<T>(List<T> list, Iterable<T> more, String Function(T) id) {
    final seen = {for (final e in list) id(e)};
    list.addAll(more.where((e) => seen.add(id(e))));
  }

  void _select(_Scope scope) {
    if (scope == _scope) return;
    _gen++;
    setState(() {
      _scope = scope;
      _checkins.clear();
      _posts.clear();
      _ckPage = _postPage = 0;
      _ckMore = _postMore = true;
      _loading = false;
      _error = null;
      _noLocation = false;
      _pos = null;
    });
    _load(reset: true);
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (mounted && context.read<AuthProvider>().isLoggedIn) {
      _load(reset: true);
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _liking.remove(item.id));
    }
  }

  String get _emptyText => switch (_scope) {
        _Scope.nearby => 'No hay publicaciones cerca por ahora.',
        _Scope.friends => 'Tus amigos no han publicado nada por ahora.',
        _ => 'Todavía no hay publicaciones.',
      };

  String get _loginText => switch (_scope) {
        _Scope.following =>
          'Inicia sesión para ver lo que publican quienes sigues',
        _Scope.nearby => 'Inicia sesión para ver lo que pasa cerca de ti',
        _ => 'Inicia sesión para ver lo que publican tus amigos',
      };

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthProvider>().isLoggedIn;
    final locked = _scope != _Scope.all && !loggedIn;
    // Siguiendo mezcla por fecha; el resto va como lo ordena el servidor
    // (Todos y reseñas de un local traen su propio orden: más reciente, mejor
    // puntuación...).
    // Una publicación que venció mientras la pantalla estaba abierta ya no se
    // muestra (el servidor tampoco la mandaría al refrescar).
    final now = DateTime.now();
    final live = [
      for (final p in _posts)
        if (p.expiresAt.isAfter(now)) p
    ];
    final entries = _scope == _Scope.following
        ? mergeFeed(_checkins, live)
        : <FeedEntry>[
            for (final c in _checkins) CheckinEntry(c),
            for (final p in live) PostEntry(p),
          ];
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.history
              ? 'Historial completo'
              : widget.placeId != null
                  ? 'Reseñas'
                  : 'Actividad reciente')),
      body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_hasTabs)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in _Scope.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: s == _scope,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.primaryContainer,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                            color: s == _scope
                                ? AppColors.primary
                                : AppColors.border),
                        labelStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s == _scope
                                ? AppColors.primary
                                : AppColors.onSurface),
                        onSelected: (_) => _select(s),
                      ),
                    ),
                ]),
              ),
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
                    DropdownMenuItem(value: 'photos', child: Text('Con fotos'))
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          setState(() => _sort = v!);
                          _load(reset: true);
                        }),
            if (locked)
              _Notice(
                  icon: Icons.lock_outline,
                  text: _loginText,
                  action: 'Iniciar sesión',
                  onAction: _login)
            else ...[
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: switch (entry) {
                    CheckinEntry(:final item) => _CheckinCard(
                        item: item,
                        canLike: !widget.history &&
                            !_liking.contains(item.id) &&
                            !_loading,
                        onLike: () => _like(item),
                      ),
                    PostEntry(:final post) => _NowCard(
                        post: post,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => NowPostScreen(
                                    postId: post.id,
                                    api: widget.api,
                                    locate: widget.locate))),
                      ),
                  },
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_loading) const LinearProgressIndicator(),
              if (!_loading && _noLocation)
                _Notice(
                    icon: Icons.location_off_outlined,
                    text: 'Activa tu ubicación para ver lo que pasa cerca',
                    action: 'Reintentar',
                    onAction: () => _load(reset: true)),
              if (!_loading && !_noLocation && entries.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24), child: Text(_emptyText)),
              if (!_loading && !_noLocation && (_more || _error != null))
                TextButton(
                    // Con la lista vacía se empieza de cero; con elementos se reintenta
                    // la página que falló, sin tirar lo que ya se ve.
                    onPressed: () =>
                        _load(reset: _error != null && entries.isEmpty),
                    child: Text(_error != null ? 'Reintentar' : 'Cargar más')),
            ],
          ])),
    );
  }
}

/// Aviso con un botón: pide iniciar sesión o activar la ubicación.
class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Notice(
      {required this.icon,
      required this.text,
      required this.action,
      required this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
        child: Column(children: [
          Icon(icon, size: 40, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: AppText.bodyMd),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(action)),
        ]),
      );
}

/// Publicación de Ahora en el feed: autor, "⚡ quedan X h", texto y miniatura.
/// Tocarla abre la publicación (ahí se reacciona y se reporta).
class _NowCard extends StatelessWidget {
  final NowPost post;
  final VoidCallback onTap;
  const _NowCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final author = post.authorName.trim();
    final avatar = post.authorAvatar;
    final text = (post.text ?? '').trim();
    final media = post.mediaUrl;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.secondary,
                  backgroundImage: avatar != null && avatar.isNotEmpty
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar == null || avatar.isEmpty
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(author.isEmpty ? 'Usuario' : '@$author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.bodyLg.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      '⚡ ${timeLeftLabel(post.timeLeft(DateTime.now()))}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
              ]),
              if (media != null && media.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: post.kind == 'video'
                        // La miniatura de un video no se puede pintar como imagen.
                        ? Container(
                            color: AppColors.primaryContainer,
                            child: const Icon(Icons.play_circle_outline_rounded,
                                size: 44, color: AppColors.primary))
                        : Image.network(media,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surface,
                                child: const Icon(Icons.broken_image,
                                    color: AppColors.onSurfaceVariant))),
                  ),
                ),
              ],
              if (text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyLg),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _CheckinCard extends StatelessWidget {
  final CheckinItem item;
  final bool canLike;
  final VoidCallback onLike;
  const _CheckinCard(
      {required this.item, required this.canLike, required this.onLike});

  @override
  Widget build(BuildContext context) {
    final rawName = item.userFullName?.trim() ?? '';
    final name = rawName.isEmpty ? 'Usuario' : rawName;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryContainer,
            child: Text(name[0].toUpperCase(),
                style: AppText.bodyLg.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: item.userId == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SocialScreen(userId: item.userId))),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.bodyLg.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (item.place != null)
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PlaceDetailScreen(placeId: item.place!.id))),
                  child: Row(children: [
                    const Icon(Icons.place_outlined,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(item.place!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.labelMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
            ]),
          ),
          if (item.rating != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded,
                    size: 14, color: AppColors.amber),
                const SizedBox(width: 2),
                Text('${item.rating}',
                    style: AppText.labelMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        if (item.comment != null && item.comment!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(item.comment!, style: AppText.bodyLg),
        ],
        if (item.dishName != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
                '${item.dishName}${item.dishPrice == null ? '' : ' · S/ ${item.dishPrice}'}',
                style: AppText.labelMd.copyWith(color: AppColors.onSurface)),
          ),
        ],
        if (item.photoUrl != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(item.photoUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: AppColors.surface,
                    child: const Icon(Icons.broken_image,
                        color: AppColors.onSurfaceVariant))),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: AppColors.border),
        ),
        Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: canLike ? onLike : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(item.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: item.isLikedByMe
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant),
                const SizedBox(width: 5),
                Text('${item.likesCount}', style: AppText.labelMd),
              ]),
            ),
          ),
          const Spacer(),
          Text(item.createdAt.split('T').first, style: AppText.labelMd),
          const SizedBox(width: 4),
          IconButton(
              tooltip: 'Compartir',
              visualDensity: VisualDensity.compact,
              onPressed: () => sharePlace(
                  context,
                  item.place?.id ?? item.placeId,
                  item.place?.name ?? 'Wuarikes'),
              icon: const Icon(Icons.share_outlined,
                  size: 18, color: AppColors.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _CheckinCard(
                    item: item,
                    canLike: !widget.history &&
                        !_liking.contains(item.id) &&
                        !_loading,
                    onLike: () => _like(item),
                  ),
                ),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: item.userId == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SocialScreen(userId: item.userId))),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w600)),
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
                const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
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
                style: AppText.labelMd
                    .copyWith(color: AppColors.onSurface)),
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
                Icon(
                    item.isLikedByMe
                        ? Icons.favorite
                        : Icons.favorite_border,
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
              onPressed: () => sharePlace(context,
                  item.place?.id ?? item.placeId, item.place?.name ?? 'Wuarikes'),
              icon: const Icon(Icons.share_outlined,
                  size: 18, color: AppColors.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}

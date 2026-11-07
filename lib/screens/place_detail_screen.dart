import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/map_config.dart';
import '../core/marker_builder.dart';
import '../core/models.dart';
import '../core/place_image.dart';
import '../state/auth_provider.dart';
import 'edit_account_screen.dart';
import 'login_screen.dart';
import 'new_checkin_screen.dart';
import 'place_extras.dart';
import '../core/external_actions.dart';

const amenityIcons = {
  'wifi': Icons.wifi_rounded,
  'estacionamiento': Icons.local_parking_rounded,
  'cochera': Icons.local_parking_rounded,
  'terraza': Icons.deck_outlined,
  'bar': Icons.local_bar_outlined,
  'pet friendly': Icons.pets_rounded,
  'acepta tarjeta': Icons.credit_card_rounded,
  'música en vivo': Icons.music_note_rounded,
};

class PlaceDetailScreen extends StatefulWidget {
  final String placeId;
  const PlaceDetailScreen({super.key, required this.placeId});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final ApiClient _api = ApiClient();
  Place? _place;
  List<CheckinItem> _reviews = [];
  bool _favorited = false;
  bool _loading = true;
  String? _error;
  LoyaltyProgram? _loyaltyProgram;
  LoyaltyCard? _loyaltyCard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Place place;
    try {
      place = await _api.getPlace(widget.placeId);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el lugar');
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Reviews and favorite status are secondary: if either fails (e.g. the
    // feed endpoint erroring out), still show the place details we already have.
    List<CheckinItem> reviews = [];
    try {
      reviews = (await _api.getFeed(placeId: widget.placeId, size: 10)).data;
    } catch (_) {}

    bool favorited = false;
    if (!mounted) return;
    try {
      if (context.read<AuthProvider>().isLoggedIn) {
        favorited = await _api.isFavorite(widget.placeId);
      }
    } catch (_) {}

    LoyaltyProgram? loyaltyProgram;
    LoyaltyCard? loyaltyCard;
    if (!mounted) return;
    try {
      final phone =
          context.read<AuthProvider>().user?.details['phone'] as String?;
      if (phone != null && phone.isNotEmpty) {
        loyaltyCard = await _api.getLoyaltyCard(widget.placeId, phone);
        loyaltyProgram = loyaltyCard?.program;
      } else {
        loyaltyProgram = await _api.getLoyaltyProgram(widget.placeId);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _place = place;
        _reviews = reviews;
        _favorited = favorited;
        _loyaltyProgram = loyaltyProgram;
        _loyaltyCard = loyaltyCard;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (!context.read<AuthProvider>().isLoggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    try {
      if (_favorited) {
        await _api.removeFavorite(widget.placeId);
      } else {
        await _api.addFavorite(widget.placeId);
      }
      setState(() => _favorited = !_favorited);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _place == null) {
      return Scaffold(
          body: Center(child: Text(_error ?? 'Lugar no encontrado')));
    }

    final place = _place!;
    final priceLabel = place.priceMax == null
        ? null
        : place.priceMax! >= 80
            ? r'$$$'
            : place.priceMax! >= 40
                ? r'$$'
                : r'$';

    final reviewTiles = <Widget>[
      ..._reviews.map((r) => _ReviewTile(
            source: 'Wuarikes',
            authorName: r.userFullName ?? 'Usuario',
            authorPhotoUrl: null,
            timeLabel: timeAgo(r.createdAt),
            rating: r.rating,
            text: r.comment,
            photoUrl: r.photoUrl,
          )),
      ...place.googleReviews.map((r) => _ReviewTile(
            source: 'Google',
            authorName: r.authorName,
            authorPhotoUrl: r.authorPhotoUrl,
            timeLabel: r.relativeTimeDescription,
            rating: r.rating,
            text: r.text,
            photoUrl: null,
          )),
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            surfaceTintColor: Colors.transparent,
            iconTheme: const IconThemeData(color: AppColors.primary),
            titleSpacing: 0,
            title: const Text('Wuarikes'),
            centerTitle: false,
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: AppColors.border),
            ),
            actions: [
              IconButton(
                  tooltip: 'Compartir',
                  icon: const Icon(Icons.share_outlined,
                      color: AppColors.primary),
                  onPressed: () => sharePlace(context, place.id, place.name)),
              IconButton(
                icon: Icon(
                    _favorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _favorited ? Colors.redAccent : AppColors.primary),
                onPressed: _toggleFavorite,
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 309,
              width: double.infinity,
              child: PlaceImage(imageUrl: place.coverImageUrl, logoPadding: 40),
            ),
          ),
          SliverToBoxAdapter(
            // The -24 overlap leaves 24px below the card, which doubles as
            // the gap before the next section.
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: _gutter),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(
                                    child: Text(place.name,
                                        style: AppText.headlineMobile)),
                                if (place.isVerified)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(Icons.verified_rounded,
                                        size: 20, color: Color(0xFF2196F3)),
                                  ),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  place.category?.name ?? 'Restaurante',
                                  place.district?.district
                                ].whereType<String>().join(' • '),
                                style: AppText.bodyMd,
                              ),
                            ],
                          ),
                        ),
                        if (priceLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(priceLabel,
                                style: AppText.bodyLg.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.amber, size: 24),
                      const SizedBox(width: 4),
                      Text(place.rating.toStringAsFixed(1),
                          style: AppText.bodyLg
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      Text('(${place.totalReviews} reseñas)',
                          style: AppText.bodyMd),
                    ]),
                    if (place.amenities.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(
                          height: 1, thickness: 1, color: AppColors.border),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (var i = 0; i < place.amenities.length; i++) ...[
                            if (i > 0) const SizedBox(width: 16),
                            _AmenityIcon(name: place.amenities[i]),
                          ],
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (place.description != null) ...[
                  _pad(Text(place.description!, style: AppText.bodyLg)),
                  const SizedBox(height: 24),
                ],
                if (_loyaltyProgram != null) ...[
                  _pad(_LoyaltySection(
                    program: _loyaltyProgram!,
                    card: _loyaltyCard,
                    onAddPhone: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const EditAccountScreen()));
                      if (mounted) _load();
                    },
                  )),
                  const SizedBox(height: 24),
                ],
                _pad(Text('Ubicación', style: AppText.titleLg)),
                const SizedBox(height: 16),
                _pad(Container(
                  height: 192,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: place.latitude != null && place.longitude != null
                      ? IgnorePointer(
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter:
                                  LatLng(place.latitude!, place.longitude!),
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none),
                            ),
                            children: [
                              buildMapboxTileLayer(),
                              MarkerLayer(markers: [
                                Marker(
                                  point:
                                      LatLng(place.latitude!, place.longitude!),
                                  alignment: Alignment.topCenter,
                                  width: 52,
                                  height: 60,
                                  child: MapPin(
                                      imageUrl: place.coverImageUrl, size: 48),
                                ),
                              ]),
                            ],
                          ),
                        )
                      : Container(color: AppColors.primaryContainer),
                )),
                if (place.address != null) ...[
                  const SizedBox(height: 8),
                  _pad(Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 18, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(place.address!, style: AppText.bodyMd)),
                  ])),
                ],
                if (place.dishes.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _pad(Text('Platos Destacados', style: AppText.titleLg)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 192,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: _gutter),
                      itemCount: place.dishes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, i) =>
                          _DishCard(dish: place.dishes[i]),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                _pad(Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reseñas recientes', style: AppText.titleLg),
                      if (place.googleTotalReviews > 0)
                        Row(children: [
                          const Icon(Icons.public_rounded,
                              size: 14, color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                              'Google ${place.googleRating?.toStringAsFixed(1) ?? '–'} · ${place.googleTotalReviews}',
                              style: AppText.labelMd),
                        ]),
                    ])),
                const SizedBox(height: 16),
                if (reviewTiles.isEmpty)
                  _pad(Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.rate_review_outlined,
                          size: 18, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No se ha registrado una reseña.',
                                  style: AppText.bodyLg
                                      .copyWith(fontWeight: FontWeight.w600)),
                              Text('Sé el primero en dejar la tuya.',
                                  style: AppText.bodyMd),
                            ]),
                      ),
                    ]),
                  )),
                for (var i = 0; i < reviewTiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 24),
                  _pad(reviewTiles[i]),
                ],
                const SizedBox(height: 24),
                _pad(PlaceExtras(key: ValueKey(place.id), place: place)),
                // Room for the floating check-in button.
                const SizedBox(height: 110),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: AppText.bodyLg.copyWith(fontWeight: FontWeight.w700),
              ),
              onPressed: () => _checkin(place),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Hacer check-in'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkin(Place place) async {
    if (!context.read<AuthProvider>().isLoggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NewCheckinScreen(place: place)));
    if (mounted) _load();
  }
}

/// Horizontal page gutter from the design (20px).
const _gutter = 20.0;

Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _gutter), child: child);

/// "Hace 2 días"-style label for an ISO timestamp; null if unparseable.
String? timeAgo(String iso, {DateTime? now}) {
  final t = DateTime.tryParse(iso);
  if (t == null) return null;
  final d = (now ?? DateTime.now()).difference(t);
  String plural(int n, String one, String many) =>
      'Hace $n ${n == 1 ? one : many}';
  if (d.inDays >= 30) return plural(d.inDays ~/ 30, 'mes', 'meses');
  if (d.inDays >= 7) return plural(d.inDays ~/ 7, 'semana', 'semanas');
  if (d.inDays >= 1) return plural(d.inDays, 'día', 'días');
  if (d.inHours >= 1) return plural(d.inHours, 'hora', 'horas');
  return 'Hace un momento';
}

class _AmenityIcon extends StatelessWidget {
  final String name;
  const _AmenityIcon({required this.name});

  @override
  Widget build(BuildContext context) {
    final icon =
        amenityIcons[name.toLowerCase()] ?? Icons.check_circle_outline_rounded;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 60),
      child: Column(
        children: [
          CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.border.withValues(alpha: 0.5),
              child: Icon(icon, color: AppColors.primary, size: 24)),
          const SizedBox(height: 4),
          Text(name, style: AppText.labelMd),
        ],
      ),
    );
  }
}

class _DishCard extends StatelessWidget {
  final Dish dish;
  const _DishCard({required this.dish});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 192,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 128,
            width: double.infinity,
            child: dish.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: dish.imageUrl!, fit: BoxFit.cover)
                : Container(color: AppColors.primaryContainer),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dish.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (dish.price != null)
                  Text('S/ ${dish.price}',
                      style: AppText.bodyMd.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One review row, shared by Wuarikes check-ins and Google reviews. The
/// source is spelled out in the subtitle (never color alone) so both stay
/// distinguishable.
class _ReviewTile extends StatelessWidget {
  final String source; // 'Wuarikes' | 'Google'
  final String authorName;
  final String? authorPhotoUrl;
  final String? timeLabel;
  final int? rating;
  final String? text;
  final String? photoUrl;
  const _ReviewTile({
    required this.source,
    required this.authorName,
    this.authorPhotoUrl,
    this.timeLabel,
    this.rating,
    this.text,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryContainer,
              backgroundImage:
                  authorPhotoUrl != null ? NetworkImage(authorPhotoUrl!) : null,
              child: authorPhotoUrl == null
                  ? const Icon(Icons.person, size: 20, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyMd.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700)),
                  Text([timeLabel, source].whereType<String>().join(' · '),
                      style: AppText.labelMd),
                ],
              ),
            ),
            if (rating != null)
              Row(
                  children: List.generate(
                      5,
                      (i) => Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(Icons.star_rounded,
                                size: 16,
                                color: i < rating!
                                    ? AppColors.amber
                                    : AppColors.border),
                          ))),
          ],
        ),
        if (text != null && text!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('"$text"',
              style: AppText.bodyMd.copyWith(fontStyle: FontStyle.italic)),
        ],
        if (photoUrl != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
                imageUrl: photoUrl!, width: 96, height: 96, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }
}

/// Shows whether this restaurant runs a loyalty (stamps/points) program and,
/// when the signed-in user has a phone on file, their card status there.
class _LoyaltySection extends StatelessWidget {
  final LoyaltyProgram program;
  final LoyaltyCard? card;
  final VoidCallback onAddPhone;
  const _LoyaltySection(
      {required this.program, this.card, required this.onAddPhone});

  @override
  Widget build(BuildContext context) {
    final isStamps = program.type == 'stamps';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.card_giftcard_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Fidelización', style: AppText.titleLg),
          ]),
          if (program.rewardDescription != null) ...[
            const SizedBox(height: 6),
            Text(program.rewardDescription!, style: AppText.bodyMd),
          ],
          const SizedBox(height: 10),
          if (card == null)
            Row(children: [
              Expanded(
                child: Text(
                    'Agrega tu teléfono en tu perfil para ver tu tarjeta aquí.',
                    style: AppText.labelMd),
              ),
              TextButton(onPressed: onAddPhone, child: const Text('Agregar')),
            ])
          else if (card!.isNew)
            Text(
                'Aún no tienes tarjeta aquí. Haz tu primer check-in para empezar a sumar.',
                style: AppText.bodyMd)
          else
            Row(children: [
              Icon(
                  isStamps
                      ? Icons.local_fire_department_rounded
                      : Icons.star_rounded,
                  size: 18,
                  color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                  isStamps
                      ? '${card!.stamps ?? 0}/${program.stampsToReward} sellos'
                      : '${card!.points ?? 0} puntos',
                  style: AppText.bodyMd.copyWith(fontWeight: FontWeight.w700)),
              if (card!.level != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border)),
                  child: Text(card!.level!, style: AppText.labelMd),
                ),
              ],
            ]),
        ],
      ),
    );
  }
}

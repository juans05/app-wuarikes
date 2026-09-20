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
      final phone = context.read<AuthProvider>().user?.details['phone'] as String?;
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            title: const Text('Wuarikes'),
            centerTitle: false,
            actions: [
              IconButton(
                  tooltip: 'Compartir',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => sharePlace(context, place.id, place.name)),
              IconButton(
                icon: Icon(
                    _favorited
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _favorited ? Colors.redAccent : AppColors.onSurface),
                onPressed: _toggleFavorite,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: place.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: place.coverImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.primaryContainer,
                      child: const Icon(Icons.restaurant, size: 48)),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(children: [
                            Flexible(
                                child: Text(place.name,
                                    style: AppText.headlineMobile)),
                            if (place.isVerified)
                              const Padding(
                                padding: EdgeInsets.only(left: 4, top: 4),
                                child: Icon(Icons.verified_rounded,
                                    size: 18, color: Colors.blue),
                              ),
                          ]),
                        ),
                        if (priceLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text(priceLabel,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    Text(
                      [
                        place.category?.name ?? 'Restaurante',
                        place.district?.district
                      ].whereType<String>().join(' · '),
                      style: AppText.bodyMd,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.amber, size: 18),
                      Text(' ${place.rating.toStringAsFixed(1)} ',
                          style: AppText.bodyMd.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600)),
                      Text('(${place.totalReviews} reseñas)',
                          style: AppText.labelMd),
                    ]),
                    if (place.amenities.isNotEmpty) ...[
                      const Divider(height: 24, color: AppColors.border),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: place.amenities
                            .take(4)
                            .map((a) => _AmenityIcon(name: a))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (place.description != null) ...[
                    Text(place.description!, style: AppText.bodyLg),
                    const SizedBox(height: 20),
                  ],
                  if (_loyaltyProgram != null) ...[
                    _LoyaltySection(
                      program: _loyaltyProgram!,
                      card: _loyaltyCard,
                      onAddPhone: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const EditAccountScreen()));
                        if (mounted) _load();
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text('Ubicación', style: AppText.titleLg),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: SizedBox(
                      height: 140,
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
                                      point: LatLng(
                                          place.latitude!, place.longitude!),
                                      alignment: Alignment.topCenter,
                                      width: 36,
                                      height: 46,
                                      child: MapPin(
                                          imageUrl: place.coverImageUrl,
                                          size: 32),
                                    ),
                                  ]),
                                ],
                              ),
                            )
                          : Container(color: AppColors.primaryContainer),
                    ),
                  ),
                  if (place.address != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: AppColors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(place.address!, style: AppText.bodyMd)),
                    ]),
                  ],
                  if (place.dishes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Platos Destacados', style: AppText.titleLg),
                        ]),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: place.dishes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final d = place.dishes[i];
                          return Container(
                            width: 130,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 90,
                                  width: double.infinity,
                                  child: d.imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: d.imageUrl!,
                                          fit: BoxFit.cover)
                                      : Container(
                                          color: AppColors.primaryContainer),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(d.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.bodyMd.copyWith(
                                              color: AppColors.onSurface,
                                              fontWeight: FontWeight.w600)),
                                      if (d.price != null)
                                        Text('S/ ${d.price}',
                                            style: AppText.bodyMd.copyWith(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Reseñas', style: AppText.titleLg),
                    if (place.googleTotalReviews > 0)
                      Row(children: [
                        const Icon(Icons.public_rounded,
                            size: 14, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                            'Google ${place.googleRating?.toStringAsFixed(1) ?? '–'} · ${place.googleTotalReviews}',
                            style: AppText.labelMd),
                      ]),
                  ]),
                  const SizedBox(height: 8),
                  if (_reviews.isEmpty && place.googleReviews.isEmpty)
                    Text('Sé el primero en dejar una reseña.',
                        style: AppText.bodyMd),
                  ..._reviews.map((r) => _ReviewTile(
                        source: 'Wuarikes',
                        authorName: r.userFullName ?? 'Usuario',
                        authorPhotoUrl: null,
                        rating: r.rating,
                        text: r.comment,
                        photoUrl: r.photoUrl,
                      )),
                  ...place.googleReviews.map((r) => _ReviewTile(
                        source: 'Google',
                        authorName: r.authorName,
                        authorPhotoUrl: r.authorPhotoUrl,
                        rating: r.rating,
                        text: r.text,
                        photoUrl: null,
                      )),
                  PlaceExtras(key: ValueKey(place.id), place: place),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () async {
          if (!context.read<AuthProvider>().isLoggedIn) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NewCheckinScreen(place: place)));
          if (mounted) _load();
        },
        icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
        label:
            const Text('Hacer check-in', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _AmenityIcon extends StatelessWidget {
  final String name;
  const _AmenityIcon({required this.name});

  @override
  Widget build(BuildContext context) {
    final icon =
        amenityIcons[name.toLowerCase()] ?? Icons.check_circle_outline_rounded;
    return Column(
      children: [
        CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surface,
            child: Icon(icon, color: AppColors.onSurfaceVariant, size: 20)),
        const SizedBox(height: 4),
        Text(name, style: AppText.labelMd),
      ],
    );
  }
}

/// One review row, shared by Wuarikes check-ins and Google reviews. A text
/// chip (never color alone) marks the source so both stay distinguishable.
class _ReviewTile extends StatelessWidget {
  final String source; // 'Wuarikes' | 'Google'
  final String authorName;
  final String? authorPhotoUrl;
  final int? rating;
  final String? text;
  final String? photoUrl;
  const _ReviewTile({
    required this.source,
    required this.authorName,
    this.authorPhotoUrl,
    this.rating,
    this.text,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isGoogle = source == 'Google';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primaryContainer,
                backgroundImage:
                    authorPhotoUrl != null ? NetworkImage(authorPhotoUrl!) : null,
                child: authorPhotoUrl == null
                    ? const Icon(Icons.person, size: 16, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMd.copyWith(
                        color: AppColors.onSurface, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isGoogle ? AppColors.surface : AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(source,
                    style: AppText.labelMd.copyWith(
                        color: isGoogle
                            ? AppColors.onSurfaceVariant
                            : AppColors.primary)),
              ),
            ],
          ),
          if (rating != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                  children: List.generate(
                      5,
                      (i) => Icon(
                            i < rating! ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 14,
                            color: AppColors.amber,
                          ))),
            ),
          if (text != null && text!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('"$text"',
                    style:
                        AppText.bodyMd.copyWith(fontStyle: FontStyle.italic))),
          if (photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                    imageUrl: photoUrl!,
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover),
              ),
            ),
        ],
      ),
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

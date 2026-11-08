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
import '../core/now_models.dart' show promoEndsLabel;
import '../core/place_image.dart';
import '../state/auth_provider.dart';
import 'edit_account_screen.dart';
import 'feed_screen.dart';
import 'login_screen.dart';
import 'media_screen.dart';
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

  /// Solo para pruebas: el cliente con el que se pide todo (por defecto, el real).
  final ApiClient? api;
  const PlaceDetailScreen({super.key, required this.placeId, this.api});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

enum _PlaceTab { resumen, carta, fotos, resenas }

const _tabLabels = {
  _PlaceTab.resumen: 'Resumen',
  _PlaceTab.carta: 'Carta',
  _PlaceTab.fotos: 'Fotos',
  _PlaceTab.resenas: 'Reseñas',
};

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  Place? _place;
  List<CheckinItem> _reviews = [];
  bool _favorited = false;
  bool _loading = true;
  String? _error;
  LoyaltyProgram? _loyaltyProgram;
  LoyaltyCard? _loyaltyCard;
  List<String> _photos = [];
  List<Map> _promos = [];
  Map<String, dynamic> _actions = {};
  _PlaceTab _tab = _PlaceTab.resumen;

  /// Pestañas ya abiertas: se arman la primera vez que se tocan y se quedan
  /// (con su estado) al cambiar de pestaña.
  final _visited = <_PlaceTab>{_PlaceTab.resumen};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _optional(String path, {Map<String, String>? query}) async {
    try {
      return await _api.get(path, query: query);
    } catch (_) {
      return null;
    }
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

    // Fotos (carrusel y pestaña), promociones (caja) y acciones públicas
    // (WhatsApp de pedidos, reservar) son extras: si fallan, la ficha sigue.
    final id = widget.placeId;
    final extras = await Future.wait([
      _optional('/places/$id/photos', query: {'page': '1', 'limit': '9'}),
      _optional('/places/$id/promotions'),
      _optional('/public/places/$id/actions'),
    ]);

    if (mounted) {
      setState(() {
        _place = place;
        _reviews = reviews;
        _favorited = favorited;
        _loyaltyProgram = loyaltyProgram;
        _loyaltyCard = loyaltyCard;
        _photos = _photoUrls(extras[0]);
        _promos = _activePromos(extras[1]);
        _actions = extras[2] is Map<String, dynamic>
            ? extras[2] as Map<String, dynamic>
            : {};
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

  /// La tarjeta resumida (arriba) solo sale si el usuario ya tiene tarjeta aquí;
  /// si no, la sección "Fidelización" del Resumen conserva el "agregar teléfono"
  /// y el aviso de tarjeta nueva.
  bool get _showsCardBox =>
      _loyaltyCard != null && !_loyaltyCard!.isNew && _loyaltyProgram != null;

  void _openMedia(Place place) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaScreen(
          placeId: place.id,
          ownerId: place.details['claimedByUserId'] as String?)));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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

    // La carta solo la publica el dueño: sin reclamar, no hay pestaña Carta
    // (misma regla que la web).
    final claimed = place.details['claimedByUserId'] != null;
    final tabs = [
      _PlaceTab.resumen,
      if (claimed) _PlaceTab.carta,
      _PlaceTab.fotos,
      _PlaceTab.resenas,
    ];
    final tab = tabs.contains(_tab) ? _tab : _PlaceTab.resumen;
    final cover = place.coverImageUrl;
    final heroImages = [
      if (cover != null && cover.isNotEmpty) cover,
      ..._photos.where((u) => u != cover),
    ];
    final quick = placeQuickActions(place, _actions);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: _HeroButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Volver',
                onPressed: () => Navigator.of(context).maybePop()),
            actions: [
              _HeroButton(
                  icon: _favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _favorited ? Colors.redAccent : AppColors.primary,
                  tooltip: _favorited ? 'Quitar de favoritos' : 'Guardar',
                  onPressed: _toggleFavorite),
              _HeroButton(
                  icon: Icons.share_outlined,
                  tooltip: 'Compartir',
                  onPressed: () => sharePlace(context, place.id, place.name)),
              const SizedBox(width: 8),
            ],
            flexibleSpace:
                FlexibleSpaceBar(background: _HeroCarousel(images: heroImages)),
            // La esquina redondeada de la ficha, montada sobre la foto.
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(20),
              child: Container(
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pad(_header(place, priceLabel)),
                if (quick.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _pad(_QuickActionsRow(actions: quick)),
                ],
                if (_promos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _pad(_PromoBox(promo: _promos.first)),
                ],
                if (_showsCardBox) ...[
                  const SizedBox(height: 12),
                  _pad(_LoyaltyCardBox(
                      program: _loyaltyProgram!, card: _loyaltyCard!)),
                ],
                const SizedBox(height: 16),
                _pad(_PlaceTabs(
                  tabs: tabs,
                  selected: tab,
                  onSelect: (t) => setState(() {
                    _tab = t;
                    _visited.add(t);
                  }),
                )),
                const SizedBox(height: 16),
                for (final t in tabs)
                  if (_visited.contains(t))
                    Offstage(offstage: t != tab, child: _tabBody(t, place)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 10),
            child: Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle:
                        AppText.bodyLg.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _checkin(place),
                  child: const Text('📍 Estoy aquí · check-in'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Fotos y videos',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(56, 48),
                    padding: EdgeInsets.zero,
                    side:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  onPressed: () => _openMedia(place),
                  child: const Text('📷', style: TextStyle(fontSize: 20)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(Place place, String? priceLabel) {
    final openUntil = openUntilLabel(place.details['openingHours']);
    return Column(
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
                        child: Text(place.name, style: AppText.headlineMobile)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(priceLabel,
                    style: AppText.bodyLg.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.star_rounded, color: AppColors.amber, size: 24),
          const SizedBox(width: 4),
          Text(place.rating.toStringAsFixed(1),
              style: AppText.bodyLg.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('(${place.totalReviews} reseñas)', style: AppText.bodyMd),
        ]),
        if (openUntil != null) ...[
          const SizedBox(height: 4),
          Text(openUntil,
              style: AppText.bodyMd.copyWith(
                  color: AppColors.accent, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }

  Widget _tabBody(_PlaceTab t, Place place) => switch (t) {
        _PlaceTab.resumen => _resumen(place),
        _PlaceTab.carta => _pad(PlaceMenu(placeId: place.id, api: _api)),
        _PlaceTab.fotos => _fotos(place),
        _PlaceTab.resenas => _resenas(place),
      };

  Widget _resumen(Place place) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (place.description != null) ...[
          _pad(Text(place.description!, style: AppText.bodyLg)),
          const SizedBox(height: 24),
        ],
        if (_loyaltyProgram != null && !_showsCardBox) ...[
          _pad(_LoyaltySection(
            program: _loyaltyProgram!,
            card: _loyaltyCard,
            onAddPhone: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditAccountScreen()));
              if (mounted) _load();
            },
          )),
          const SizedBox(height: 24),
        ],
        if (place.amenities.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _gutter),
            child: Row(children: [
              for (var i = 0; i < place.amenities.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                _AmenityIcon(name: place.amenities[i]),
              ],
            ]),
          ),
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
                      initialCenter: LatLng(place.latitude!, place.longitude!),
                      initialZoom: 15,
                      interactionOptions:
                          const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      buildMapboxTileLayer(),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(place.latitude!, place.longitude!),
                          alignment: Alignment.topCenter,
                          width: 52,
                          height: 60,
                          child:
                              MapPin(imageUrl: place.coverImageUrl, size: 48),
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
            Expanded(child: Text(place.address!, style: AppText.bodyMd)),
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
              itemBuilder: (context, i) => _DishCard(dish: place.dishes[i]),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _pad(PlaceExtras(
            key: ValueKey(place.id),
            place: place,
            api: _api,
            morePromos: _promos.skip(1).toList())),
      ],
    );
  }

  Widget _fotos(Place place) {
    return _pad(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_photos.isEmpty)
          Text('Todavía no hay fotos de este local.', style: AppText.bodyMd)
        else
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final url in _photos)
                GestureDetector(
                  onTap: () => _openMedia(place),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PlaceImage(imageUrl: url)),
                ),
            ],
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: () => _openMedia(place),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Ver fotos y videos')),
      ],
    ));
  }

  Widget _resenas(Place place) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pad(PlaceRatings(placeId: place.id, api: _api)),
        const SizedBox(height: 16),
        _pad(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text('Reseñas recientes', style: AppText.titleLg)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
        const SizedBox(height: 16),
        _pad(OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FeedScreen(placeId: place.id))),
            icon: const Icon(Icons.reviews_outlined, size: 18),
            label: const Text('Ver todas las reseñas'))),
      ],
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

/// URLs de `GET /places/:id/photos` (`{data: [{url}]}`); vacío si no llegó nada.
List<String> _photoUrls(dynamic page) => [
      for (final p in (page is Map ? page['data'] : null) as List? ?? const [])
        if (p is Map && p['url'] is String) p['url'] as String,
    ];

/// Promociones vigentes de `GET /places/:id/promotions` (la primera es la más
/// nueva); se descartan las que no traen título.
List<Map> _activePromos(dynamic list) => [
      for (final p in list is List ? list : const [])
        if (p is Map && '${p['title'] ?? ''}'.trim().isNotEmpty) p,
    ];

/// Una acción rápida de la ficha: ícono, rótulo y el enlace que abre.
class PlaceQuickAction {
  final IconData icon;
  final String label;
  final String url;
  const PlaceQuickAction(this.icon, this.label, this.url);
}

/// Las acciones rápidas que el local puede ofrecer, en este orden: Cómo llegar
/// (coordenadas o, si no, dirección), WhatsApp, Reservar y Llamar. Solo salen
/// las que tienen dato. [publicActions] es `GET /public/places/:id/actions`
/// (`orderWhatsapp`, `bookingUrl`), que puede venir vacío.
List<PlaceQuickAction> placeQuickActions(
    Place place, Map<String, dynamic> publicActions) {
  final address = place.address?.trim() ?? '';
  final phone = place.phone?.trim() ?? '';
  final orderWhatsapp = '${publicActions['orderWhatsapp'] ?? ''}';
  final whatsapp =
      orderWhatsapp.isNotEmpty ? orderWhatsapp : whatsappNumber(place.phone);
  final booking = '${publicActions['bookingUrl'] ?? ''}';
  return [
    if (place.latitude != null && place.longitude != null)
      PlaceQuickAction(Icons.directions_rounded, 'Cómo llegar',
          'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}')
    else if (address.isNotEmpty)
      PlaceQuickAction(Icons.directions_rounded, 'Cómo llegar',
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
    if (whatsapp != null)
      PlaceQuickAction(Icons.chat_rounded, 'WhatsApp',
          'https://wa.me/$whatsapp?text=${Uri.encodeComponent('Hola, vi su ficha en Wuarikes.')}'),
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(booking))
      PlaceQuickAction(Icons.event_available_rounded, 'Reservar', booking),
    if (phone.isNotEmpty)
      PlaceQuickAction(Icons.call_rounded, 'Llamar', 'tel:${place.phone}'),
  ];
}

/// Número para `wa.me` (solo dígitos, con código de país) si [phone] parece de
/// WhatsApp: con `+`, o celular peruano (9 dígitos que empiezan en 9, con o
/// sin 51). Un fijo no tiene WhatsApp, así que devuelve null.
String? whatsappNumber(String? phone) {
  final raw = phone?.trim() ?? '';
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (raw.startsWith('+') && digits.length >= 8) return digits;
  if (digits.length == 9 && digits.startsWith('9')) return '51$digits';
  if (digits.length == 11 && digits.startsWith('519')) return digits;
  return null;
}

/// "Abierto hasta 17:00" si, según el horario por día del local, está abierto
/// ahora en Lima; null si no hay horario por día o no está abierto (nunca
/// afirma "cerrado"). Mismo cálculo que el filtro "abierto ahora" del backend:
/// hora de Lima (UTC-5, sin horario de verano) y el horario de hoy.
String? openUntilLabel(Object? openingHours, {DateTime? now}) {
  if (openingHours is! List) return null;
  final lima =
      (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 5));
  const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final today = days[lima.weekday - 1];
  final minutes = lima.hour * 60 + lima.minute;
  int? toMinutes(Object? hhmm) {
    final parts = '$hhmm'.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  String two(int n) => n.toString().padLeft(2, '0');
  for (final slot in openingHours) {
    if (slot is! Map || '${slot['day']}'.toLowerCase() != today) continue;
    final open = toMinutes(slot['open']);
    final close = toMinutes(slot['close']);
    if (open == null || close == null) continue;
    final isOpen = open <= close
        ? minutes >= open && minutes <= close
        : minutes >= open || minutes < close;
    if (isOpen) {
      return 'Abierto hasta ${two((close ~/ 60) % 24)}:${two(close % 60)}';
    }
  }
  return null;
}

/// "🎁 Tu tarjeta: 6/8 sellos · ¡Te faltan 2 para tu premio!" (sellos) o
/// "🎁 Tu tarjeta: 120 puntos".
String loyaltyCardLabel(LoyaltyProgram program, LoyaltyCard card) {
  if (program.type != 'stamps') {
    return '🎁 Tu tarjeta: ${card.points ?? 0} puntos';
  }
  final have = card.stamps ?? 0;
  final left = program.stampsToReward - have;
  final tail = left <= 0
      ? '¡Ya puedes canjear tu premio!'
      : left == 1
          ? '¡Te falta 1 para tu premio!'
          : '¡Te faltan $left para tu premio!';
  return '🎁 Tu tarjeta: $have/${program.stampsToReward} sellos · $tail';
}

/// Botón redondo blanco sobre la foto (volver, guardar, compartir).
class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;
  const _HeroButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.white.withValues(alpha: 0.9),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: tooltip,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(icon, color: color),
              onPressed: onPressed,
            ),
          ),
        ),
      );
}

/// Foto grande de arriba: la portada y las fotos del local, deslizables, con
/// puntitos. Con una sola (o ninguna) se ve como antes.
class _HeroCarousel extends StatefulWidget {
  final List<String> images;
  const _HeroCarousel({required this.images});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    if (images.length < 2) {
      return PlaceImage(
          imageUrl: images.isEmpty ? null : images.first, logoPadding: 40);
    }
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        itemCount: images.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => PlaceImage(imageUrl: images[i], logoPadding: 40),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 30,
        child: IgnorePointer(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < images.length; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: i == _page ? 1 : 0.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 2)
                  ],
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// Cómo llegar · WhatsApp · Reservar · Llamar: solo las que tienen dato.
class _QuickActionsRow extends StatelessWidget {
  final List<PlaceQuickAction> actions;
  const _QuickActionsRow({required this.actions});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              key: ValueKey('quick-${a.label}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openExternal(context, a.url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primaryContainer,
                    child: Icon(a.icon, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.labelMd),
                ]),
              ),
            ),
          ),
      ]);
}

/// La promo del día: la vigente más nueva de `GET /places/:id/promotions`.
class _PromoBox extends StatelessWidget {
  final Map promo;
  const _PromoBox({required this.promo});

  @override
  Widget build(BuildContext context) {
    final end = DateTime.tryParse('${promo['endsAt'] ?? ''}');
    final description = '${promo['description'] ?? ''}';
    return Container(
      key: const ValueKey('promo-box'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: '🔥 '),
            TextSpan(
                text: '${promo['title']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (end != null)
              TextSpan(text: ' · ${promoEndsLabel(end, DateTime.now())}'),
          ]),
          style: AppText.bodyLg,
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyMd),
        ],
      ]),
    );
  }
}

/// "Tu tarjeta: X/Y sellos": solo para quien ya tiene tarjeta en este local.
class _LoyaltyCardBox extends StatelessWidget {
  final LoyaltyProgram program;
  final LoyaltyCard card;
  const _LoyaltyCardBox({required this.program, required this.card});

  @override
  Widget build(BuildContext context) {
    final detail = [
      program.rewardDescription ?? program.rewardTitle,
      card.level
    ].whereType<String>().where((t) => t.isNotEmpty).join(' · ');
    return Container(
      key: const ValueKey('loyalty-card-box'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.onSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(loyaltyCardLabel(program, card),
            style: AppText.bodyMd
                .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(detail,
              style: AppText.labelMd
                  .copyWith(color: Colors.white.withValues(alpha: 0.75))),
        ],
      ]),
    );
  }
}

/// Resumen · Carta · Fotos · Reseñas (Carta solo si el local está reclamado).
class _PlaceTabs extends StatelessWidget {
  final List<_PlaceTab> tabs;
  final _PlaceTab selected;
  final ValueChanged<_PlaceTab> onSelect;
  const _PlaceTabs(
      {required this.tabs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          for (final t in tabs)
            Expanded(
              child: Semantics(
                selected: t == selected,
                button: true,
                child: InkWell(
                  key: ValueKey('tab-${t.name}'),
                  onTap: () => onSelect(t),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              width: 2,
                              color: t == selected
                                  ? AppColors.primary
                                  : Colors.transparent)),
                    ),
                    child: Text(_tabLabels[t]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t == selected
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant)),
                  ),
                ),
              ),
            ),
        ]),
      );
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

/// Shows that this restaurant runs a loyalty (stamps/points) program and what
/// is missing for the user to see their card: a phone on file, or a first
/// check-in. Once the card exists, `_LoyaltyCardBox` takes over.
class _LoyaltySection extends StatelessWidget {
  final LoyaltyProgram program;
  final LoyaltyCard? card;
  final VoidCallback onAddPhone;
  const _LoyaltySection(
      {required this.program, this.card, required this.onAddPhone});

  @override
  Widget build(BuildContext context) {
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
          else
            // Tarjeta nueva: con sellos o puntos, la ficha muestra
            // _LoyaltyCardBox arriba y esta sección ni sale.
            Text(
                'Aún no tienes tarjeta aquí. Haz tu primer check-in para empezar a sumar.',
                style: AppText.bodyMd),
        ],
      ),
    );
  }
}

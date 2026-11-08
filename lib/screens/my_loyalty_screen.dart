import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/geofence_sync_service.dart';
import '../core/models.dart';
import '../core/now_location.dart' show NowLocator;
import '../core/place_image.dart';
import '../state/auth_provider.dart';
import '../widgets/login_required_view.dart';
import '../widgets/place_list_tile.dart' show formatDistance;
import '../widgets/proximity_alerts.dart';
import 'place_detail_screen.dart';

/// "📍 a X" solo sale si el local está a esta distancia o menos.
const _nearMeters = 5000.0;

class MyLoyaltyScreen extends StatefulWidget {
  /// Solo para pruebas: API y GPS de mentira.
  final ApiClient? api;
  final NowLocator? locate;
  const MyLoyaltyScreen({super.key, this.api, this.locate});

  @override
  State<MyLoyaltyScreen> createState() => _MyLoyaltyScreenState();
}

class _MyLoyaltyScreenState extends State<MyLoyaltyScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  List<MyLoyaltyCard> _cards = [];
  Position? _position;
  bool _loading = true;
  String? _error;
  bool? _alertsOn; // null mientras se lee la preferencia

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!context.read<AuthProvider>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cards = await _api.getMyLoyaltyCards();
      if (mounted) setState(() => _cards = cards);
      _readAlerts();
      // Sin esperar: las tarjetas se ven ya y la distancia llega después.
      if (mounted && cards.any((c) => c.hasLocation)) _findMe();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readAlerts() async {
    try {
      final on = (await SharedPreferences.getInstance())
              .getBool(geofencingPrefKey) ??
          false;
      if (mounted) setState(() => _alertsOn = on);
      // Con los avisos prendidos, la tarjeta guardada para el aviso se pone al día.
      if (on) GeofenceSyncService().start();
    } catch (_) {}
  }

  Future<void> _turnOnAlerts() async {
    final ok = await enableProximityAlerts(context);
    if (mounted) setState(() => _alertsOn = ok);
  }

  Future<void> _findMe() async {
    try {
      final p = await (widget.locate ?? _quietPosition)();
      if (mounted && p != null) setState(() => _position = p);
    } catch (_) {}
  }

  /// Metros de la persona al local; null si no se sabe o está lejos.
  double? _distanceTo(MyLoyaltyCard card) {
    final p = _position;
    if (p == null || !card.hasLocation) return null;
    final m = Geolocator.distanceBetween(
        p.latitude, p.longitude, card.latitude!, card.longitude!);
    return m <= _nearMeters ? m : null;
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mis premios')),
      body: SafeArea(
        child: !isLoggedIn
            ? LoginRequiredView(
                icon: Icons.loyalty_outlined,
                message:
                    'Inicia sesión para ver todas tus tarjetas de fidelización en un solo lugar.',
                onLoggedIn: _load,
              )
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            Text(_error!),
                            TextButton(
                                onPressed: _load,
                                child: const Text('Reintentar'))
                          ]))
                    : _cards.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  'Aún no tienes tarjetas de fidelización. Escanea el código QR de un huarique cuando lo visites para empezar a acumular.',
                                  textAlign: TextAlign.center,
                                  style: AppText.bodyMd),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Text('Tus tarjetas de fidelización en un solo lugar',
                                    style: AppText.bodyMd),
                                if (_alertsOn == false &&
                                    _cards.any((c) => c.hasLocation)) ...[
                                  const SizedBox(height: 12),
                                  _AlertsBanner(onTurnOn: _turnOnAlerts),
                                ],
                                for (var i = 0; i < _cards.length; i++) ...[
                                  const SizedBox(height: 12),
                                  _PrizeCard(
                                    card: _cards[i],
                                    gradient: _gradients[i % _gradients.length],
                                    meters: _distanceTo(_cards[i]),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => PlaceDetailScreen(
                                                  placeId: _cards[i].placeId)));
                                      if (mounted) _load();
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
      ),
    );
  }
}

/// Posición sin pedir permiso ni esperar al GPS: la última conocida, o una
/// lectura rápida si el permiso ya estaba dado. Null en cualquier otro caso.
Future<Position?> _quietPosition() async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    return await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 5)));
  } catch (_) {
    return null;
  }
}

/// Colores de las tarjetas, rotando de a uno por local.
final _gradients = <List<Color>>[
  [AppColors.primary, AppColors.primaryLight],
  [AppColors.onSurface, AppColors.onSurfaceVariant],
  [
    AppColors.accent,
    Color.lerp(AppColors.accent, AppColors.surfaceContainerLowest, 0.3)!
  ],
];

/// ¿Ya juntó los sellos del premio? La tarjeta va de 0 a la meta y se queda
/// ahí hasta que canjea.
bool _isReady(MyLoyaltyCard c) {
  final goal = c.stampsToReward ?? 0;
  return c.programType == 'stamps' && goal > 0 && c.stamps >= goal;
}

class _PrizeCard extends StatelessWidget {
  final MyLoyaltyCard card;
  final List<Color> gradient;
  final double? meters;
  final VoidCallback onTap;
  const _PrizeCard({
    required this.card,
    required this.gradient,
    required this.meters,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isStamps = card.programType == 'stamps';
    final goal = card.stampsToReward ?? 0;
    final ready = _isReady(card);
    final filled = card.stamps.clamp(0, goal);
    final remaining = goal - filled;
    final reward = card.rewardTitle ?? 'tu premio';
    const onColor = AppColors.surfaceContainerLowest;

    final subtitle = ready
        ? 'Muestra esta tarjeta en el local para canjear: $reward'
        : isStamps
            ? 'Te falta${remaining == 1 ? '' : 'n'} $remaining sello${remaining == 1 ? '' : 's'} para "$reward"'
            : '${card.points} puntos acumulados';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: PlaceImage(
                            imageUrl: card.placeCoverImageUrl, logoPadding: 4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(card.placeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyLg.copyWith(
                              color: onColor, fontWeight: FontWeight.w700)),
                    ),
                    if (meters != null) ...[
                      const SizedBox(width: 8),
                      _Tag('📍 a ${formatDistance(meters!)}',
                          background: onColor, foreground: AppColors.primary),
                    ],
                  ],
                ),
                if (isStamps && goal > 0) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$filled',
                          key: const Key('stamp-count'),
                          style: const TextStyle(
                              fontSize: 34,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: onColor)),
                      Flexible(
                        child: Text(' / $goal sellos',
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyMd.copyWith(
                                color: onColor.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (ready) ...[
                    const SizedBox(height: 8),
                    const _Tag('🎁 ¡Tienes para canjear!',
                        background: AppColors.secondary,
                        foreground: AppColors.onSurface),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < goal; i++)
                        _Stamp(
                          key: Key('stamp-${i < filled ? 'full' : 'empty'}-$i'),
                          number: i + 1,
                          full: i < filled,
                          isPrize: i == goal - 1,
                          ink: gradient.first,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyMd.copyWith(
                        color: onColor.withValues(alpha: 0.95),
                        fontWeight: ready ? FontWeight.w700 : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un casillero de la tarjeta: ✓ si ya está, su número si falta, y 🎁 en el
/// último (el que da el premio).
class _Stamp extends StatelessWidget {
  final int number;
  final bool full;
  final bool isPrize;
  final Color ink;
  const _Stamp({
    super.key,
    required this.number,
    required this.full,
    required this.isPrize,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    const onColor = AppColors.surfaceContainerLowest;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: full ? onColor : Colors.transparent,
        border: Border.all(
            color: onColor.withValues(alpha: full ? 1 : 0.55), width: 2),
      ),
      child: full
          ? Icon(Icons.check_rounded, size: 20, color: ink)
          : isPrize
              ? const Text('🎁', style: TextStyle(fontSize: 15))
              : Text('$number',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: onColor.withValues(alpha: 0.8))),
    );
  }
}

/// Invita a prender los avisos de cercanía desde Mis premios.
class _AlertsBanner extends StatelessWidget {
  final VoidCallback onTurnOn;
  const _AlertsBanner({required this.onTurnOn});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Text('🔔', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  'Avísame cuando pase cerca de mis huariques: cuántos sellos me faltan o si tengo premio.',
                  style: AppText.bodyMd),
            ),
            TextButton(
                key: const Key('alerts-turn-on'),
                onPressed: onTurnOn,
                child: const Text('Activar')),
          ],
        ),
      );
}

class _Tag extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const _Tag(this.text, {required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/external_actions.dart';
import '../core/map_config.dart';
import '../core/marker_builder.dart';
import '../core/models.dart';
import '../state/auth_provider.dart';
import 'edit_account_screen.dart';
import 'favorites_screen.dart';
import 'settings_screen.dart';
import 'social_screen.dart';
import 'feed_screen.dart';
import 'login_screen.dart';
import 'my_loyalty_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// ponytail: level thresholds are a placeholder guess pending real tiers from product/backend.
const _rankTiers = [
  (1, 'Bronce'),
  (4, 'Plata'),
  (8, 'Oro'),
  (13, 'Platino'),
  (18, 'Diamante')
];

String _rankName(int level) {
  var tier = _rankTiers.first.$2;
  for (final t in _rankTiers) {
    if (level >= t.$1) tier = t.$2;
  }
  return 'Explorador $tier';
}

String? _nextRankTier(int level) {
  for (final t in _rankTiers) {
    if (level < t.$1) return t.$2;
  }
  return null;
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiClient _api = ApiClient();
  GamificationStats? _stats;
  AppUser? _profile;
  List<AppBadge> _badges = [];
  List<CheckinItem> _checkins = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AuthProvider>().isLoggedIn) return;
    try {
      final stats = await _api.getMyStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
    try {
      final profile = await _api.getMyProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
    try {
      final badges = await _api.getBadges();
      if (mounted) setState(() => _badges = badges);
    } catch (_) {}
    try {
      final checkins = await _api.getMyCheckins(limit: 20);
      if (mounted) setState(() => _checkins = checkins.data);
    } catch (_) {}
  }

  Future<void> _editProfile() async {
    final user = _profile;
    if (user == null) return;
    final saved = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EditAccountScreen()));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = _profile ?? auth.user;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_food_beverage_outlined,
                      size: 44, color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(
                      'Inicia sesión para ver tu perfil, tus puntos y tus check-ins.',
                      textAlign: TextAlign.center,
                      style: AppText.bodyMd),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const LoginScreen()));
                      _load();
                    },
                    child: const Text('Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final level = _stats?.level ?? 1;
    final xp = _stats?.xp ?? 0;
    final nextLevelXp = _stats?.nextLevelXp ?? 1000;
    final progress =
        nextLevelXp == 0 ? 0.0 : (xp / nextLevelXp).clamp(0.0, 1.0);

    final placeMarkers = <Marker>[];
    for (final c in _checkins) {
      final p = c.place;
      if (p?.latitude != null && p?.longitude != null) {
        placeMarkers.add(Marker(
          point: LatLng(p!.latitude!, p.longitude!),
          alignment: Alignment.topCenter,
          width: 36,
          height: 46,
          child: MapPin(imageUrl: p.coverImageUrl, size: 32),
        ));
      }
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Wuarikes'),
        actions: [
          IconButton(
              tooltip: 'Ajustes',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(Icons.person, size: 18, color: AppColors.primary)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user.details['coverImageUrl'] != null)
              ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(user.details['coverImageUrl'],
                      height: 150, fit: BoxFit.cover)),
            Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                            BorderSide(color: AppColors.primary, width: 2))),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primaryContainer,
                      backgroundImage: user.avatarUrl != null
                          ? NetworkImage(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? const Icon(Icons.person,
                              size: 36, color: AppColors.primary)
                          : null,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: AppColors.amber, shape: BoxShape.circle),
                      child: const Icon(Icons.star_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(user.fullName,
                textAlign: TextAlign.center,
                style: AppText.titleLg
                    .copyWith(color: AppColors.primary, fontSize: 20)),
            Text('${user.details['levelName'] ?? _rankName(level)}',
                textAlign: TextAlign.center, style: AppText.bodyMd),
            const SizedBox(height: 8),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _FollowStat(
                  count: (user.details['followersCount'] as num?)?.toInt() ?? 0,
                  label: 'Seguidores',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SocialScreen())),
                ),
                const SizedBox(width: 20),
                _FollowStat(
                  count: (user.details['followingCount'] as num?)?.toInt() ?? 0,
                  label: 'Seguidos',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SocialScreen(followers: false))),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            for (final key in ['city', 'hometown', 'pronouns'])
              if ((user.details[key] as String? ?? '').isNotEmpty)
                Text('${user.details[key]}', textAlign: TextAlign.center),
            if ((_profile?.bio ?? '').isNotEmpty)
              Text(_profile!.bio!,
                  textAlign: TextAlign.center, style: AppText.bodyMd)
            else
              Center(
                child: TextButton(
                  onPressed: _editProfile,
                  child: Text('Agrega una bio',
                      style: AppText.bodyMd.copyWith(color: AppColors.primary)),
                ),
              ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.outlined(
                tooltip: 'Editar perfil',
                onPressed: _editProfile,
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 16),
              IconButton.outlined(
                tooltip: 'Invitar amigos',
                onPressed: () => inviteFriends(context),
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
              const SizedBox(width: 16),
              IconButton.outlined(
                tooltip: 'Mis Fidelizaciones',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyLoyaltyScreen())),
                icon: const Icon(Icons.loyalty_outlined),
              ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _nextRankTier(level) != null
                    ? '$xp / $nextLevelXp XP para Nivel ${_nextRankTier(level)}'
                    : '$xp / $nextLevelXp XP · nivel máximo',
                style: AppText.labelMd,
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _StatBox(label: 'Nivel', value: '$level'),
              const SizedBox(width: 8),
              _StatBox(label: 'Puntos', value: '$xp'),
              const SizedBox(width: 8),
              _StatBox(
                  label: 'Check-ins',
                  value: '${_stats?.checkinsCount ?? _checkins.length}'),
            ]),
            const SizedBox(height: 12),
            _ProfileLinkRow(
              icon: Icons.favorite_border_rounded,
              label: 'Guardados',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Insignias', style: AppText.titleLg),
              Text('Ver todas',
                  style: AppText.bodyMd.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final earned = _badges.where((b) => b.unlocked).toList();
              return SizedBox(
                height: 86,
                child: earned.isEmpty
                    ? Center(
                        child: Text('Aún no ganaste insignias.',
                            style: AppText.bodyMd))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: earned.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final b = earned[i];
                          return SizedBox(
                            width: 70,
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AppColors.primaryContainer,
                                  child: Text(b.icon,
                                      style: const TextStyle(fontSize: 22)),
                                ),
                                const SizedBox(height: 4),
                                Text(b.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: AppText.labelMd),
                              ],
                            ),
                          );
                        },
                      ),
              );
            }),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                  child: Text('Mi Mapa de Wuarikes', style: AppText.titleLg)),
              Text('${_checkins.length} lugares visitados',
                  style: AppText.labelMd),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: SizedBox(
                height: 160,
                child: placeMarkers.isEmpty
                    ? Container(
                        color: AppColors.primaryContainer,
                        child: Center(
                            child: Text(
                                'Haz tu primer check-in para ver tu mapa',
                                style: AppText.bodyMd)))
                    : IgnorePointer(
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: placeMarkers.first.point,
                            initialZoom: 12,
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none),
                          ),
                          children: [
                            buildMapboxTileLayer(),
                            MarkerLayer(markers: placeMarkers)
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 22),
            Text('Check-ins Recientes', style: AppText.titleLg),
            const SizedBox(height: 8),
            if (_checkins.isEmpty)
              Text('Todavía no tienes check-ins.', style: AppText.bodyMd),
            ..._checkins.take(5).map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: c.place?.coverImageUrl != null
                          ? Image.network(c.place!.coverImageUrl!,
                              width: 48, height: 48, fit: BoxFit.cover)
                          : Container(
                              width: 48,
                              height: 48,
                              color: AppColors.primaryContainer),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.place?.name ?? 'Lugar',
                              style: AppText.bodyMd.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600)),
                          if (c.comment != null)
                            Text('"${c.comment}"',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.labelMd),
                        ],
                      ),
                    ),
                    if (c.rating != null)
                      Row(children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppColors.amber),
                        Text(' ${c.rating}', style: AppText.bodyMd),
                      ]),
                  ]),
                )),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FeedScreen(history: true))),
                child: const Text('Ver historial completo')),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => context.read<AuthProvider>().logout(),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowStat extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;
  const _FollowStat(
      {required this.count, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$count ',
              style: AppText.bodyMd.copyWith(
                  color: AppColors.onSurface, fontWeight: FontWeight.w700)),
          TextSpan(text: label, style: AppText.bodyMd),
        ])),
      ),
    );
  }
}

class _ProfileLinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProfileLinkRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label,
            style: AppText.bodyMd.copyWith(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.onSurfaceVariant),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(value,
              style: AppText.titleLg
                  .copyWith(color: AppColors.primary, fontSize: 20)),
          Text(label, style: AppText.labelMd),
        ]),
      ),
    );
  }
}

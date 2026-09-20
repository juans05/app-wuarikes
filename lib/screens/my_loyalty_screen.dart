import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../state/auth_provider.dart';
import '../widgets/login_required_view.dart';
import 'place_detail_screen.dart';

class MyLoyaltyScreen extends StatefulWidget {
  const MyLoyaltyScreen({super.key});

  @override
  State<MyLoyaltyScreen> createState() => _MyLoyaltyScreenState();
}

class _MyLoyaltyScreenState extends State<MyLoyaltyScreen> {
  final ApiClient _api = ApiClient();
  List<MyLoyaltyCard> _cards = [];
  bool _loading = true;
  String? _error;

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
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Mis Fidelizaciones')),
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
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _cards.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final card = _cards[i];
                                return _LoyaltyCardTile(
                                  card: card,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => PlaceDetailScreen(
                                                placeId: card.placeId)));
                                    if (mounted) _load();
                                  },
                                );
                              },
                            ),
                          ),
      ),
    );
  }
}

class _LoyaltyCardTile extends StatelessWidget {
  final MyLoyaltyCard card;
  final VoidCallback onTap;
  const _LoyaltyCardTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isStamps = card.programType == 'stamps';
    final progress = isStamps && (card.stampsToReward ?? 0) > 0
        ? (card.stamps % card.stampsToReward!) / card.stampsToReward!
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: card.rewardReady ? AppColors.primary : AppColors.border,
              width: card.rewardReady ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: card.placeCoverImageUrl != null
                  ? Image.network(card.placeCoverImageUrl!,
                      width: 56, height: 56, fit: BoxFit.cover)
                  : Container(
                      width: 56,
                      height: 56,
                      color: AppColors.primaryContainer,
                      child: const Icon(Icons.storefront_outlined,
                          color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.placeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyLg
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (card.rewardReady)
                    Text('🎁 ¡Premio listo para canjear!',
                        style: AppText.bodyMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600))
                  else if (isStamps)
                    Text(
                        '${card.stampsRemaining ?? 0} sello${(card.stampsRemaining ?? 0) == 1 ? '' : 's'} para "${card.rewardTitle ?? 'tu premio'}"',
                        style: AppText.bodyMd)
                  else
                    Text('${card.points} puntos acumulados',
                        style: AppText.bodyMd),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: AppColors.border,
                          color: AppColors.primary),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

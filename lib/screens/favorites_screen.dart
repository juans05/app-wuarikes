import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../state/auth_provider.dart';
import '../widgets/login_required_view.dart';
import '../widgets/place_card.dart';
import 'place_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ApiClient _api = ApiClient();
  List<Place> _favorites = [];
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
      final favorites = await _api.getMyFavorites();
      if (mounted) setState(() => _favorites = favorites);
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
      appBar: AppBar(title: const Text('Favoritos')),
      body: SafeArea(
        child: !isLoggedIn
            ? LoginRequiredView(
                icon: Icons.favorite_border_rounded,
                message:
                    'Inicia sesión para crear, consultar o editar tus huariques favoritos.',
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
                    : _favorites.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  'Aún no tienes favoritos. Toca el ♡ en un huarique para guardarlo aquí.',
                                  textAlign: TextAlign.center,
                                  style: AppText.bodyMd),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _favorites.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final place = _favorites[i];
                                return PlaceCard(
                                  place: place,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => PlaceDetailScreen(
                                                placeId: place.id)));
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

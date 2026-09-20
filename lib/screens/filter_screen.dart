import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../widgets/place_card.dart';
import 'place_detail_screen.dart';

/// Full-screen category filter — picking a category updates the results
/// list live, right here, instead of a bottom sheet over the map.
class FilterScreen extends StatefulWidget {
  final List<Category> categories;
  final String? initialCategory;

  const FilterScreen({super.key, required this.categories, this.initialCategory});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final ApiClient _api = ApiClient();
  late String? _selectedCategory = widget.initialCategory;
  List<Place> _places = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _api.getPlaces(category: _selectedCategory);
      if (mounted) setState(() => _places = result.data);
    } catch (_) {
      if (mounted) setState(() => _places = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCategory(String? slug) {
    setState(() => _selectedCategory = slug);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_selectedCategory);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Filtrar por categoría'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(_selectedCategory),
          ),
        ),
        body: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  _CategoryChip(
                    label: 'Todas',
                    selected: _selectedCategory == null,
                    onTap: () => _selectCategory(null),
                  ),
                  const SizedBox(width: 8),
                  for (final c in widget.categories) ...[
                    _CategoryChip(
                      label: c.name,
                      selected: _selectedCategory == c.slug,
                      onTap: () => _selectCategory(c.slug),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _places.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No hay huariques en esta categoría todavía.', textAlign: TextAlign.center, style: AppText.bodyMd),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _places.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final place = _places[i];
                            return PlaceCard(
                              place: place,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PlaceDetailScreen(placeId: place.id)),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Text(label, style: AppText.labelMd.copyWith(color: selected ? Colors.white : AppColors.onSurfaceVariant)),
      ),
    );
  }
}

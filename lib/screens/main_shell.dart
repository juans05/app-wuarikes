import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../core/app_theme.dart';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';
import 'register_place_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    ExploreScreen(),
    FavoritesScreen(),
    FeedScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: KeyedSubtree(
          key: ValueKey('${context.watch<AuthProvider>().user?.id}-$_index'),
          child: _screens[_index]),
      floatingActionButton: FloatingActionButton(
        heroTag: 'newPlace',
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RegisterPlaceScreen()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        height: 56 + MediaQuery.of(context).padding.bottom,
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: 'Explorar',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
              _NavItem(
                icon: Icons.favorite_border_rounded,
                selectedIcon: Icons.favorite_rounded,
                label: 'Favoritos',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
              const SizedBox(width: 56), // reserved for the notch/FAB
              _NavItem(
                icon: Icons.dynamic_feed_outlined,
                selectedIcon: Icons.dynamic_feed,
                label: 'Actividad',
                selected: _index == 2,
                onTap: () => setState(() => _index = 2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Perfil',
                selected: _index == 3,
                onTap: () => setState(() => _index = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(selected ? selectedIcon : icon, color: color),
        ),
      ),
    );
  }
}

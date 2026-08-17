import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/create/domain/captured_media.dart';
import '../../features/create/presentation/camera_capture_screen.dart';
import '../../features/create/presentation/create_screen.dart';
import '../../features/create/presentation/gallery_picker_screen.dart';
import '../../features/editor/presentation/editor_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/templates/presentation/template_list_screen.dart';
import '../../features/templates/presentation/template_preview_screen.dart';
import '../../shared/widgets/tap_scale.dart';
import '../theme/app_colors.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/categories',
                builder: (context, state) => const CategoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/create',
                builder: (context, state) => const CreateScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (context, state) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // Task-focused full-screen flows registered outside the shell (per the
      // Stitch mockups: these hide the persistent bottom nav bar).
      GoRoute(
        path: '/categories/:slug',
        builder: (context, state) => TemplateListScreen(
          categorySlug: state.pathParameters['slug']!,
          categoryName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/templates/:id',
        builder: (context, state) => TemplatePreviewScreen(
          templateId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/create/camera',
        builder: (context, state) => const CameraCaptureScreen(),
      ),
      GoRoute(
        path: '/create/gallery',
        builder: (context, state) => const GalleryPickerScreen(),
      ),
      GoRoute(
        path: '/editor',
        builder: (context, state) =>
            EditorScreen(media: state.extra as CapturedMedia),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
    ],
  );
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _CreatorBottomBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

// TikTok-style bottom bar: 5 slots, Create dead-center as a raised,
// gradient-filled button rather than just another flat icon, so it reads as
// the app's single most important action at a glance.
class _CreatorBottomBar extends StatelessWidget {
  const _CreatorBottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _barHeight = 62.0;
  static const _fabSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: _barHeight + bottomInset + (_fabSize / 2 - 8),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Container(
                height: _barHeight + bottomInset,
                padding: EdgeInsets.only(bottom: bottomInset),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  border: const Border(
                    top: BorderSide(color: AppColors.outlineVariant),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _NavIcon(
                            icon: Icons.home_outlined,
                            activeIcon: Icons.home,
                            label: 'Home',
                            selected: currentIndex == 0,
                            onTap: () => onTap(0),
                          ),
                          _NavIcon(
                            icon: Icons.grid_view_outlined,
                            activeIcon: Icons.grid_view,
                            label: 'Categories',
                            selected: currentIndex == 1,
                            onTap: () => onTap(1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: _fabSize + 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _NavIcon(
                            icon: Icons.favorite_border,
                            activeIcon: Icons.favorite,
                            label: 'Favorites',
                            selected: currentIndex == 3,
                            onTap: () => onTap(3),
                          ),
                          _NavIcon(
                            icon: Icons.person_outline,
                            activeIcon: Icons.person,
                            label: 'Profile',
                            selected: currentIndex == 4,
                            onTap: () => onTap(4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: TapScale(
              scale: 0.9,
              onTap: () => onTap(2),
              child: Container(
                width: _fabSize,
                height: _fabSize,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryContainer, AppColors.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.surfaceElevated,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryContainer.withValues(alpha: 0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: AppColors.onPrimaryContainer,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primaryContainer
        : AppColors.onSurfaceVariant;
    return TapScale(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppColors.primaryContainer.withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
            child: Icon(selected ? activeIcon : icon, color: color, size: 22),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/tap_scale.dart';
import '../../auth/data/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile', style: AppTypography.headlineLgMobile),
      ),
      body: auth.isAuthenticated
          ? _SignedInView(auth: auth)
          : const _SignedOutView(),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.containerPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.asset(
              'assets/branding/logo.png',
              height: 96,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: AppSpacing.stackLg),
          Text('You\'re not logged in', style: AppTypography.headlineLgMobile),
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            'Log in to save your favorites and creations across devices.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.stackLg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/login'),
              child: const Text('Log In'),
            ),
          ),
          const SizedBox(height: AppSpacing.stackMd),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.push('/signup'),
              child: const Text('Sign Up'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedInView extends ConsumerWidget {
  const _SignedInView({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = auth.user;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.containerPadding),
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryContainer,
              ),
              child: Center(
                child: Text(
                  (user?.name.isNotEmpty ?? false)
                      ? user!.name[0].toUpperCase()
                      : '?',
                  style: AppTypography.headlineLgMobile.copyWith(
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.stackMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? 'Loading…',
                    style: AppTypography.headlineLgMobile.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (user?.isPro ?? false) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.stackSm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusPro,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        'PRO',
                        style: AppTypography.labelCaps.copyWith(
                          fontSize: 10,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.stackLg),
        const Divider(color: AppColors.outlineVariant),
        const SizedBox(height: AppSpacing.stackSm),
        TapScale(
          onTap: () => ref.read(authControllerProvider.notifier).logout(),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.stackMd,
              vertical: AppSpacing.stackMd,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Icons.logout, color: AppColors.error, size: 20),
                const SizedBox(width: AppSpacing.stackSm),
                Text(
                  'Log Out',
                  style: AppTypography.bodyMd.copyWith(color: AppColors.error),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

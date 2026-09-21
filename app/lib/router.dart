import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/database.dart';
import 'data/queries.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/create_club_screen.dart';
import 'features/onboarding/join_club_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/pending_screen.dart';
import 'features/splash_screen.dart';

/// Où en est l'utilisateur. Le routeur en déduit l'écran ; aucune navigation manuelle
/// n'est nécessaire après une connexion, une création de club ou une approbation.
enum AppPhase { signedOut, syncing, noClub, pending, ready }

final appPhaseProvider = Provider<AppPhase>((ref) {
  if (ref.watch(userProvider) == null) return AppPhase.signedOut;

  final memberships = ref.watch(myMembershipsProvider).value;
  if (memberships == null) return AppPhase.syncing;
  if (memberships.any((m) => m.isActive)) return AppPhase.ready;
  if (memberships.isNotEmpty) return AppPhase.pending;

  // Liste vide : soit l'utilisateur n'a pas de club, soit (nouvel appareil) les données ne
  // sont pas encore arrivées. Seule la première synchronisation terminée permet de trancher.
  final synced = ref.watch(hasSyncedProvider).value ?? false;
  return synced ? AppPhase.noClub : AppPhase.syncing;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AppPhase>(appPhaseProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final phase = ref.read(appPhaseProvider);
      final location = state.matchedLocation;
      // Les sous-écrans "créer" et "rejoindre" restent accessibles tant qu'on n'a pas de club.
      if (phase == AppPhase.noClub && location.startsWith('/onboarding')) return null;
      final target = switch (phase) {
        AppPhase.signedOut => '/auth',
        AppPhase.syncing => '/splash',
        AppPhase.noClub => '/onboarding',
        AppPhase.pending => '/pending',
        AppPhase.ready => '/home',
      };
      return location == target ? null : target;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingScreen(),
        routes: [
          GoRoute(path: 'create', builder: (_, _) => const CreateClubScreen()),
          GoRoute(path: 'join', builder: (_, _) => const JoinClubScreen()),
        ],
      ),
      GoRoute(path: '/pending', builder: (_, _) => const PendingScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
    ],
  );
});

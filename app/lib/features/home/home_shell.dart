import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../club/club_screen.dart';
import '../club/profile_screen.dart';
import '../library/library_screen.dart';
import '../planning/week_screen.dart';
import '../season/season_screen.dart';
import 'overview_screen.dart';

/// Navigation principale. Coach : Accueil, Semaine, Saison, Bibliothèque, Club. Athlète :
/// Accueil, Semaine, Saison, Profil. Accueil est l'onglet par défaut, donc le premier écran
/// après connexion.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isCoach = ref.watch(isCoachProvider);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const OverviewScreen(),
          const WeekScreen(),
          const SeasonScreen(),
          if (isCoach) const LibraryScreen(),
          isCoach ? const ClubScreen() : const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: 'Semaine',
          ),
          const NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Saison',
          ),
          if (isCoach)
            const NavigationDestination(
              icon: Icon(Icons.library_books_outlined),
              selectedIcon: Icon(Icons.library_books),
              label: 'Bibliothèque',
            ),
          NavigationDestination(
            icon: Icon(isCoach ? Icons.groups_outlined : Icons.person_outline),
            selectedIcon: Icon(isCoach ? Icons.groups : Icons.person),
            label: isCoach ? 'Club' : 'Profil',
          ),
        ],
      ),
    );
  }
}

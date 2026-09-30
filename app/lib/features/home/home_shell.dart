import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../club/club_screen.dart';
import '../club/profile_screen.dart';
import '../library/library_screen.dart';
import '../planning/week_screen.dart';
import '../resources/resources_screen.dart';
import '../season/season_screen.dart';
import 'overview_screen.dart';

/// Navigation principale. Coach : Accueil, Semaine, Saison, Modèles (bibliothèque), Club.
/// Athlète : Accueil, Semaine, Saison, Ressources, Profil. Accueil est l'onglet par défaut,
/// donc le premier écran après connexion.
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
    // Garde-fou si les onglets changent avec le rôle (déconnexion, rôle modifié à distance) :
    // l'index mémorisé ne doit jamais sortir des bornes.
    const tabCount = 5;
    final index = _index < tabCount ? _index : tabCount - 1;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          const OverviewScreen(),
          const WeekScreen(),
          const SeasonScreen(),
          // Athlète : la bibliothèque se limite aux ressources du club, en lecture seule.
          isCoach ? const LibraryScreen() : const ResourcesScreen(),
          isCoach ? const ClubScreen() : const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
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
          NavigationDestination(
            icon: Icon(isCoach ? Icons.library_books_outlined : Icons.video_library_outlined),
            selectedIcon: Icon(isCoach ? Icons.library_books : Icons.video_library),
            // « Bibliothèque » (titre de l'écran) ne tient pas sur une ligne dans la barre du
            // bas (5 onglets, peu de place chacun).
            label: isCoach ? 'Modèles' : 'Ressources',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../club/club_screen.dart';
import '../club/profile_screen.dart';
import '../library/library_screen.dart';
import '../planning/week_screen.dart';

/// Navigation principale. Coach : Semaine, Bibliothèque, Club. Athlète : Semaine, Profil.
/// (Saison s'ajoutera ici quand elle existera.)
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
          const WeekScreen(),
          if (isCoach) const LibraryScreen(),
          isCoach ? const ClubScreen() : const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: 'Semaine',
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

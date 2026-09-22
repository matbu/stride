import 'package:flutter/material.dart';

/// Les types de séance stockent une clé d'icône (modifiable par club) ; l'app la traduit.
/// Couleur + icône + libellé : la couleur seule ne suffit pas (daltonisme, plein soleil).
const sessionIconKeys = <String, IconData>{
  'run': Icons.directions_run,
  'bolt': Icons.bolt,
  'speed': Icons.speed,
  'sprint': Icons.rocket_launch_outlined,
  'hill': Icons.terrain,
  'dumbbell': Icons.fitness_center,
  'technique': Icons.sports,
  'recovery': Icons.self_improvement,
  'competition': Icons.emoji_events,
};

IconData sessionIcon(String key) => sessionIconKeys[key] ?? Icons.circle_outlined;

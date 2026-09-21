import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

/// Écran d'attente pendant la première synchronisation d'un appareil.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Synchronisation…', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            // Sortie de secours si le réseau est indisponible à la première connexion.
            TextButton(
              onPressed: () => confirmSignOut(context, ref),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}

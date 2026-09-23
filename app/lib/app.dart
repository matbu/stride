import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/database.dart';
import 'data/notification_scheduler.dart';
import 'router.dart';

const _localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class CoachApp extends ConsumerWidget {
  const CoachApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncLifecycleProvider);
    ref.watch(notificationSchedulerProvider);
    return MaterialApp.router(
      title: 'TrackClub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: _localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Affiché à la place de l'app quand les variables de compilation manquent, pour éviter un
/// plantage obscur au premier lancement.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuration manquante',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                SizedBox(height: 12),
                Text('Lance l’app avec :'),
                SizedBox(height: 8),
                SelectableText(
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=… \\\n'
                  '  --dart-define=SUPABASE_PUBLISHABLE_KEY=… \\\n'
                  '  --dart-define=POWERSYNC_URL=…',
                  style: TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

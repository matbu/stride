import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');

  if (!Config.isComplete) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabasePublishableKey);
  final db = await openLocalDatabase();

  runApp(ProviderScope(
    overrides: [powerSyncProvider.overrideWithValue(db)],
    child: const CoachApp(),
  ));
}

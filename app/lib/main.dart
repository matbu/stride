import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'core/notifications.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  await initNotifications();

  if (!Config.isComplete) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabasePublishableKey);
  _keepStorageAuthenticated(Supabase.instance.client);
  final db = await openLocalDatabase();

  runApp(ProviderScope(
    overrides: [powerSyncProvider.overrideWithValue(db)],
    child: const CoachApp(),
  ));
}

/// `_client.from(...)` (donc PowerSync) obtient toujours un jeton à jour car il passe par un
/// client HTTP qui le relit à chaque requête ; `_client.storage`, lui, garde l'en-tête
/// `Authorization` figé à sa valeur de construction (avant toute connexion) et ne le
/// rafraîchit jamais tout seul — l'upload d'une photo échoue alors avec une erreur RLS
/// (« new row violates row-level security policy »), signée en fait par la clé publique et
/// non par l'utilisateur. On republie donc nous-mêmes le jeton courant sur tous les
/// sous-clients (dont `storage`) à chaque connexion/déconnexion/renouvellement.
void _keepStorageAuthenticated(SupabaseClient client) {
  client.auth.onAuthStateChange.listen((data) {
    final token = data.session?.accessToken ?? Config.supabasePublishableKey;
    client.headers = {...client.headers, 'Authorization': 'Bearer $token'};
  });
}

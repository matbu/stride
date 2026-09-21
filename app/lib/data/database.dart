import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connector.dart';
import 'schema.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Fournie au démarrage (voir main.dart) : la base doit être ouverte avant `runApp`.
final powerSyncProvider = Provider<PowerSyncDatabase>(
  (ref) => throw UnimplementedError('powerSyncProvider doit être surchargé au démarrage'),
);

Future<PowerSyncDatabase> openLocalDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final db = PowerSyncDatabase(schema: schema, path: p.join(dir.path, 'coach.db'));
  await db.initialize();
  return db;
}

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Utilisateur connecté (null si déconnecté). Se recalcule à chaque changement d'auth.
final userProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Connecte la synchronisation à la connexion de l'utilisateur, la coupe et vide la base
/// locale à la déconnexion. À observer une fois, à la racine de l'app.
final syncLifecycleProvider = Provider<void>((ref) {
  final db = ref.watch(powerSyncProvider);
  final client = ref.watch(supabaseProvider);

  Future<void> apply(User? user) => user == null
      ? db.disconnectAndClear()
      : db.connect(connector: SupabaseConnector(client));

  apply(ref.read(userProvider));
  ref.listen<User?>(userProvider, (prev, next) {
    if (prev?.id != next?.id) apply(next);
  });
});

/// Vrai une fois la première synchronisation terminée sur cet appareil. Sert à distinguer
/// "pas de club" de "les données ne sont pas encore arrivées".
final hasSyncedProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(powerSyncProvider);
  return db.statusStream.map((s) => s.hasSynced ?? false);
});

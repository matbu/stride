/// Configuration injectée à la compilation :
///
///     flutter run \
///       --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///       --dart-define=SUPABASE_PUBLISHABLE_KEY=... \
///       --dart-define=POWERSYNC_URL=https://xxxx.powersync.journeyapps.com
///
/// La clé publiable (ancienne clé "anon") est publique par conception : la sécurité repose
/// sur la RLS.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const powersyncUrl = String.fromEnvironment('POWERSYNC_URL');

  static bool get isComplete =>
      supabaseUrl.isNotEmpty &&
      supabasePublishableKey.isNotEmpty &&
      powersyncUrl.isNotEmpty;
}

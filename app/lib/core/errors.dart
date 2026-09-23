import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit les erreurs techniques (codes des RPC, erreurs d'auth) en messages pour l'utilisateur.
String humanError(Object error) {
  if (error is AuthException) return _authMessage(error);
  if (error is PostgrestException) {
    return _rpcMessages[error.message] ?? 'Une erreur est survenue (${error.message}).';
  }
  if (error is StorageException) return 'Envoi impossible (${error.message}).';
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'Pas de connexion. Cette action nécessite du réseau.';
  }
  return 'Une erreur est survenue.';
}

String _authMessage(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login')) return 'Email ou mot de passe incorrect.';
  if (m.contains('already registered')) return 'Un compte existe déjà avec cet email.';
  if (m.contains('email not confirmed')) return 'Confirme ton email avant de te connecter.';
  if (m.contains('password')) return 'Mot de passe trop court ou invalide.';
  if (m.contains('rate limit')) return 'Trop de tentatives, réessaie dans quelques minutes.';
  return 'Connexion impossible : ${e.message}';
}

const _rpcMessages = {
  'club_name_taken': 'Ce nom de club est déjà pris.',
  'invalid_club_name': 'Le nom doit faire entre 2 et 80 caractères.',
  'club_not_found': 'Club introuvable.',
  'already_member': 'Tu fais déjà partie de ce club.',
  'already_requested': 'Ta demande est déjà en attente.',
  'invitation_not_found': 'Code introuvable. Vérifie-le et réessaie.',
  'invitation_invalid': 'Ce code a expiré ou a déjà été utilisé.',
  'forbidden': "Tu n'as pas les droits pour faire cela.",
  'owner_must_transfer': 'Passe d’abord le rôle de super coach à un autre coach.',
  'new_owner_must_be_active_coach': 'Le nouveau super coach doit être un coach du club.',
  'request_not_found': 'Cette demande n’existe plus.',
  'not_authenticated': 'Session expirée, reconnecte-toi.',
};

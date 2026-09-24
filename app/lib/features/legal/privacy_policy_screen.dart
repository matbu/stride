import 'package:flutter/material.dart';

/// Politique de confidentialité, en dur dans l'app (pas de dépendance réseau pour la lire).
/// Le même texte existe en HTML autonome (`legal/privacy-policy.html`) pour l'URL exigée par
/// l'App Store / Play Store dans les métadonnées de la fiche — à héberger quelque part (ex.
/// GitHub Pages) et à tenir à jour en même temps que cet écran si le texte change.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Dernière mise à jour : 24 septembre 2026',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final s in _sections) _Section(title: s.$1, body: s.$2),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

const _sections = <(String, String)>[
  (
    'Qui gère tes données',
    'TrackClub est l’application d’un club d’athlétisme pour organiser ses entraînements. '
        'Le responsable du traitement est le club auquel tu appartiens (ses coachs, pour les '
        'données qu’ils gèrent) ainsi que l’éditeur de l’application pour son fonctionnement '
        'technique. Pour toute question, contacte ton club ou écris à [email de contact à '
        'compléter].',
  ),
  (
    'Données collectées',
    'Compte : email, nom affiché. Club : ton rôle, tes groupes d’entraînement. Entraînement : '
        'séances, contenu des séances, statut « fait / non fait » que tu renseignes toi-même, '
        'présences prises par un coach. Profil libre-service (facultatif) : photo, description, '
        'lien vers ta fiche athle.fr, records personnels. Ces derniers ne sont visibles que par '
        'les coachs de ton club et toi-même.',
  ),
  (
    'Pourquoi ces données',
    'Uniquement pour faire fonctionner le club : planifier et suivre les séances '
        'd’entraînement, gérer les groupes et les adhésions, permettre aux coachs de suivre la '
        'présence et l’assiduité. Aucune donnée n’est utilisée à des fins publicitaires, et '
        'aucune donnée n’est vendue ou partagée avec un tiers en dehors des prestataires '
        'techniques nécessaires au fonctionnement du service (hébergement de la base de '
        'données et des photos).',
  ),
  (
    'Où sont hébergées les données',
    'Les données sont hébergées chez notre prestataire technique (Supabase). L’application '
        'fonctionne aussi hors ligne : une copie locale des données de ton club est conservée '
        'sur ton appareil pour permettre de consulter et modifier tes séances sans connexion, '
        'puis synchronisée dès que le réseau revient.',
  ),
  (
    'Combien de temps',
    'Tes données sont conservées tant que ton compte existe et que tu es membre d’un club. Si '
        'tu quittes un club, ta fiche athlète reste dans son historique (séances passées, '
        'présences) mais n’est plus liée à ton compte. Tu peux supprimer ton compte à tout '
        'moment (voir ci-dessous), ce qui supprime définitivement ton compte, ton profil et tes '
        'données personnelles.',
  ),
  (
    'Tes droits',
    'Tu peux à tout moment consulter et modifier ton profil (photo, description, records, lien '
        'FFA) directement dans l’application. Tu peux supprimer ton compte toi-même, depuis '
        'l’écran Club ou Profil (« Supprimer mon compte ») : cette action est définitive et '
        'supprime ton profil, tes adhésions et tes données personnelles. Pour toute autre '
        'demande (accès, rectification, export), contacte ton club ou [email de contact à '
        'compléter].',
  ),
  (
    'Mineurs',
    'Certains athlètes suivis dans l’application sont mineurs. Leur fiche est créée et gérée '
        'par un coach du club ; elle peut exister sans qu’un compte y soit rattaché. Si un '
        'compte est associé à la fiche d’un mineur, il revient au responsable légal ou au club '
        'de s’assurer du consentement nécessaire, conformément à sa propre politique interne.',
  ),
  (
    'Cookies et traçage',
    'L’application ne contient ni publicité ni traceur publicitaire, et n’utilise pas de '
        'cookies au sens web (application mobile native).',
  ),
  (
    'Modifications',
    'Cette politique peut évoluer si l’application change. La date de dernière mise à jour en '
        'haut de cette page permet de suivre les changements.',
  ),
];

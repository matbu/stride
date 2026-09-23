# TrackClub

App iPhone et Android pour organiser les séances d'entraînement d'athlétisme d'un club :
plusieurs coachs, plusieurs groupes, séances créées en amont puis placées dans la semaine,
fonctionnement hors ligne avec synchronisation.

## Architecture

```
app/        Flutter (Dart) : l'application mobile
supabase/   Postgres : schéma, RLS, fonctions serveur (migrations) + tests SQL
powersync/  Règles de synchronisation (qui reçoit quelles données)
```

- **Supabase** : authentification, Postgres, sécurité par ligne (RLS).
- **PowerSync** : SQLite local sur le téléphone, synchronisé avec Postgres. L'app lit et écrit
  en local, donc tout fonctionne hors ligne ; les écritures partent au retour du réseau.
- **Deux chemins d'écriture** :
  - *Planification* (séances, groupes, fiches athlètes) : écriture locale via PowerSync, possible
    hors ligne.
  - *Administration du club* (créer un club, invitations, rôles, approbations) : fonctions
    serveur (RPC) qui valident les droits, en ligne uniquement. Voir `supabase/migrations/0003_functions.sql`.
- **Rôles** : `owner` (super coach, un seul par club, transférable), `coach`, `athlete`.
  Un athlète ne reçoit que les séances des groupes dont il fait partie.

## Mise en route

### 1. Supabase
1. Crée un projet sur supabase.com (région proche de tes utilisateurs, ex. Paris ou Francfort) et
   note le mot de passe de la base.
2. Installe la CLI (`supabase --version`). Sur macOS ancien où Homebrew échoue, télécharge le binaire
   de la release GitHub `supabase/cli` (`supabase_<version>_darwin_<amd64|arm64>.tar.gz`), vérifie
   son SHA-256 avec `checksums.txt`, et place-le dans un dossier de ton PATH.
3. Depuis la racine du repo :
   ```sh
   supabase login                          # ouvre le navigateur
   supabase link --project-ref <ref>       # <ref> : l'identifiant dans l'URL du projet
   supabase db push --dry-run              # liste ce qui serait appliqué
   supabase db push                        # applique supabase/migrations/ dans l'ordre
   ```
   Sans la CLI : colle chaque fichier de `supabase/migrations/` dans l'éditeur SQL, dans l'ordre.
4. Authentication → Providers → Email : pour la bêta, désactive « Confirm email » afin que
   l'inscription connecte directement. Longueur minimale du mot de passe : 8 (comme dans l'app).

`supabase/config.toml` sert à la config locale (`supabase start`, qui exige Docker) ; le flux
ci-dessus ne nécessite pas Docker.

### 2. PowerSync
À faire **après** `supabase db push` (les tables et la publication `powersync` doivent exister).

1. Dans l'éditeur SQL de Supabase, crée le rôle de réplication (choisis un mot de passe long et
   aléatoire, sans le committer nulle part) :
   ```sql
   create role powersync_role with replication bypassrls login password 'CHOISIS_UN_MOT_DE_PASSE';
   grant select on all tables in schema public to powersync_role;
   alter default privileges in schema public grant select on tables to powersync_role;
   ```
   Ne recrée pas la publication : `0004_powersync.sql` l'a déjà créée (`powersync`, limitée aux tables
   synchronisées). Le rôle contourne la RLS : ce sont les règles de sync qui décident qui reçoit quoi.
2. Crée un projet puis une instance sur powersync.com.
3. Instance → *Database Connection* → onglet *Postgres* : colle l'URI « Direct connection » de Supabase
   (Supabase → *Connect*), puis remplace l'utilisateur et le mot de passe par `powersync_role` et son mot
   de passe (à encoder en URL s'il contient des caractères spéciaux). SSL : `verify-full` convient.
   *Test Connection*, puis *Save Connection* et attends 1 à 2 minutes.
4. *Client Auth* : coche « Use Supabase Auth », puis *Save and Deploy*. (Nouvelles clés de signature JWT :
   laisse le secret vide. Anciennes clés : colle le « JWT Secret » de Supabase.)
5. Colle `powersync/sync-rules.yaml` dans les règles de synchronisation, valide, déploie. Le format
   `bucket_definitions` est l'ancien format : toujours supporté, avec un outil de migration vers les
   Sync Streams si tu veux plus tard.
6. Note l'URL de l'instance : c'est `POWERSYNC_URL` pour l'app.

Supabase limite à 4 les slots de réplication logique : supprimer et recréer des instances PowerSync
peut les épuiser (erreur « All replication slots are in use »).

### 3. Lancer l'app
```sh
cd app
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=... \
  --dart-define=POWERSYNC_URL=https://xxxx.powersync.journeyapps.com
```
Sans ces variables, l'app affiche un écran « Configuration manquante ».

Il faut Xcode (iOS) et/ou le SDK Android : voir `flutter doctor`.

## Tests

```sh
cd app && flutter analyze && flutter test        # logique de routage, écrans avec données simulées

# SQL : schéma, RLS, RPC sur un Postgres jetable (aucun Supabase requis)
pip install psycopg2-binary
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres python supabase/tests/run_tests.py
```
Le test SQL recrée la base `coach_test` à chaque exécution : ne le pointe pas sur une base qui compte.

## Synchroniser et builder

`scripts/sync-and-build.sh` : `supabase db push`, rappel si `powersync/sync-rules.yaml` a changé
(pas d'API pour l'automatiser, à coller à la main dans le tableau de bord), puis
`flutter build apk` et `flutter build ipa`. Lit ses variables dans `env` (non versionné). Options :
`--db-only`, `--skip-db`, `--android-only`, `--ios-only`.

Pas nécessaire après chaque modification : seulement quand `supabase/migrations/` a changé (schéma,
RLS, fonctions) avant de builder, et pour les builds seulement quand tu veux redistribuer aux testeurs
(le code Dart seul se teste avec `flutter run`, sans rebuild ni sync).

## Distribution aux testeurs

- **Android** : `flutter build apk`, envoyer le fichier (lien, Drive, WhatsApp). Les testeurs
  autorisent l'installation d'applications inconnues. Gratuit.
- **iPhone** : Apple Developer Program (~99 $/an) puis TestFlight. Pour 2 ou 3 testeurs, le test
  **interne** suffit : chacun est ajouté à l'équipe App Store Connect et reçoit l'app sans revue Apple.
- **Identifiant d'application** : `com.trackclub.app` (`android/app/build.gradle.kts` et
  `ios/Runner.xcodeproj/project.pbxproj`). Choisi le 2026-09-22, avant toute publication — à ne
  plus changer une fois envoyé sur TestFlight ou le Play Store (très difficile ensuite).
- **Icône de l'app** : générée depuis `app/assets/icon/icon.png` (recadré depuis le logo fourni —
  le logo original a de la marge autour du rond noir, retirée pour que l'icône remplisse bien le
  cadre que iOS/Android appliquent). Pour la changer : remplacer ce fichier (carré, sans coins
  arrondis ni marge — le système les ajoute) puis `cd app && dart run flutter_launcher_icons`.
  `app/assets/images/logo.png` (le logo tel quel) sert à l'écran de connexion.

## Saisie rapide d'un exercice

Dans un bloc de séance, on tape l'exercice, l'aperçu montre comment il est compris, puis « + » l'ajoute.
On peut en saisir plusieurs d'un coup (sur une ligne, séparés par un retour à la ligne ou `;`).

| Saisie | Compris comme |
|---|---|
| `10x400 r1'` | 10 × 400 m, récupération 1' |
| `10x400 r1' 3x300 r1'` | deux exercices |
| `6x400 r1'30 @5k` | 6 × 400 m, récup 1'30, allure 5k |
| `6 x 1'30 r 45"` | 6 × 1'30 d'effort, récup 45" |
| `4x2km` · `3 x 1,5 km` | distances en km |
| `5x200 r200m` | récupération en distance (trot) |
| `1h @endurance` · `20 min` | effort en durée |
| `Footing en côte` | texte libre, gardé comme note |

Règles : un nombre seul est une distance en mètres (≥ 30) ; durées `1h`, `1h30`, `10min`, `2'`, `1'30`,
`30"`, `45s` (minutes/secondes sur deux chiffres : `1'05`) ; dans `r…`, un nombre seul est en secondes.
Le code est dans `app/lib/core/notation.dart`, avec ses tests (`app/test/notation_test.dart`).

## Import CSV

Une ligne = une séance. Sans date, la ligne devient un modèle de la bibliothèque. Séparateur `;`, `,` ou
tabulation (détecté), UTF-8 ou Windows-1252. Colonnes (ordre libre, accents et casse tolérés) :

`date ; heure ; duree_min ; groupes ; type ; titre ; echauffement ; corps ; retour_au_calme ; notes`

`groupes` : plusieurs noms séparés par `|`. Colonnes de contenu : exercices en saisie rapide séparés par `|`.
`type` et `groupes` doivent exister dans le club. L'écran d'import affiche un aperçu ligne par ligne
(lignes invalides signalées avec la raison, puis ignorées) et propose un fichier modèle
(`importTemplateCsv` dans `app/lib/data/import_csv.dart`).

## État actuel

Fait, et vérifié par les tests (voir ci-dessus) :
- Schéma, RLS, invitations, demandes d'adhésion, transfert de propriété (112 contrôles SQL).
- Connexion / inscription, création ou adhésion à un club, écran d'attente.
- **Accueil** (premier onglet, écran après connexion) : la séance du jour (les siennes pour un
  athlète, toutes celles du club pour un coach), sinon « Repos ». Pour un coach en plus : la
  présence à l'entraînement, par groupe (menu déroulant → liste d'athlètes → coche), prise le jour
  même. Stockée en base (`attendances`), consultable ensuite depuis la fiche de chaque athlète
  (écran Club) même s'il n'a pas encore de compte — c'est un coach qui la prend, pas l'athlète.
- **Vue semaine** : téléphone (bande des jours + agenda) et **tablette / paysage (≥ 720 px) : 7 colonnes**,
  avec glisser-déposer d'une séance vers un autre jour (appui long) dans les deux dispositions, et
  suppression en la glissant vers la gauche (confirmation demandée).
- **Vue mois** (bouton calendrier dans l'AppBar) : grille façon Google Calendar avec pastilles de
  couleur par type ; toucher un jour revient à l'agenda de ce jour.
- **Filtre coach** (vue semaine et mois) : Tous, ou un groupe. Chaque chip de groupe a un menu
  déroulant vers ses athlètes (pas de liste plate — invivable à 150 athlètes) pour afficher le
  statut **fait / non fait** d'un seul, par séance (façon Pronote — seul l'athlète le marque, un
  coach consulte en lecture seule). L'athlète le marque depuis sa vue semaine ou la fiche détail.
- **Saisie rapide du titre** : si le titre ressemble à de la notation (« 10x400 r1' »), une
  suggestion propose de remplir le corps de séance — jamais automatique, pour ne pas écraser un
  titre qui contient juste des chiffres.
- **Éditeur de séance par blocs** (échauffement / corps / retour au calme / autre) avec saisie rapide,
  aperçu en direct, exercices réordonnables, volume d'effort, enregistrement en une transaction locale.
  Échauffement et retour au calme ont un contenu par défaut (20' et Étirements), modifiable ou
  effaçable librement.
- **Bibliothèque de modèles** : créer, modifier, supprimer, placer sur un jour pour un ou plusieurs
  groupes (chaque groupe reçoit sa propre copie), « enregistrer comme modèle » depuis une séance.
  Toute séance créée à la main (pas placée depuis un modèle existant) y est aussi ajoutée
  automatiquement, une seule fois même si posée pour plusieurs groupes d'un coup.
- **Import CSV** avec aperçu.
- Fiche de séance en lecture seule pour les athlètes ; écran Club.
- **Profil athlète** : photo (Supabase Storage, bucket `avatars`), description, lien vers la fiche
  athle.fr (juste un lien — pas de récupération automatique, athle.fr n'a pas d'API publique),
  records personnels (entraînement / compétition non officielle, distincts des records FFA). Géré
  par l'athlète seul ; un coach le consulte en lecture seule depuis la fiche de l'athlète dans
  l'écran Club. Déconnexion.

**Non vérifié** (aucune instance ni appareil disponibles pendant le développement) :
- La synchronisation PowerSync de bout en bout : `sync-rules.yaml` et `connector.dart` sont écrits
  d'après la documentation mais jamais exécutés contre une instance. Le connecteur décode la colonne
  JSON `items` avant l'envoi (sinon Postgres la refuse : voir `supabase/tests/run_tests.py`).
- L'app sur simulateur ou appareil réel (rendu vérifié uniquement via des tests de widgets).
- Le sélecteur de fichier et le partage du fichier modèle (`import_screen.dart`) : plugins natifs non testables ici.
- Le glisser-déposer au doigt sur une vraie tablette (testé par gestes simulés).

À faire ensuite :
- Calendrier de saison (compétitions, échéances) : les tables existent, pas l'écran.
- Poser un modèle par glisser-déposer depuis la bibliothèque sur la vue 7 colonnes.
- Séries imbriquées (`2 x (5x200 r30") r3'`), non gérées par la saisie rapide.
- Signaler à l'utilisateur les modifications hors ligne rejetées par le serveur (`connector.dart`).
- Conflits : deux coachs qui modifient le même bloc hors ligne, la dernière écriture gagne.
- Suppression de compte (obligatoire pour l'App Store), politique de confidentialité.
- Intégration Strava : tables prêtes (`integrations`, `activities`), profil athlète prêt à l'accueillir.
  D'abord vérifier les conditions de l'API Strava, créer une appli sur developers.strava.com et
  décider comment stocker les tokens OAuth, avant de brancher l'intégration réelle. Objectif : que
  les séances Strava d'un athlète apparaissent dans un calendrier perso, visible uniquement quand
  un coach consulte son profil.
- Garmin / Coros : idem, non commencé.

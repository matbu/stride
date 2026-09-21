"""Tests de bout en bout du schéma, des RPC et de la RLS sur un Postgres jetable.

Usage :
    pip install psycopg2-binary
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres python supabase/tests/run_tests.py

La base `coach_test` est recréée à chaque exécution. On y applique stubs.sql (émulation de
Supabase) puis les migrations, puis on rejoue un scénario en changeant de rôle et
d'utilisateur comme le fait PostgREST (`set local role authenticated` + `request.jwt.claim.sub`).
"""
import os
import pathlib
import sys
import uuid

import psycopg2

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = "coach_test"
CONN = dict(
    host=os.environ.get("PGHOST", "127.0.0.1"),
    port=os.environ.get("PGPORT", "5432"),
    user=os.environ.get("PGUSER", "postgres"),
)

# --- préparation de la base ----------------------------------------------------------------

admin = psycopg2.connect(dbname="postgres", **CONN)
admin.autocommit = True
with admin.cursor() as c:
    c.execute(f"drop database if exists {DB} with (force)")
    c.execute(f"create database {DB}")
admin.close()

db = psycopg2.connect(dbname=DB, **CONN)
db.autocommit = True
cur = db.cursor()

for name in ["tests/stubs.sql"] + sorted(p.name for p in (ROOT / "migrations").glob("*.sql")):
    path = ROOT / name if name.startswith("tests/") else ROOT / "migrations" / name
    cur.execute(path.read_text())
print("migrations appliquées")

# --- outils ---------------------------------------------------------------------------------

passed = failed = 0


def user(name):
    uid = str(uuid.uuid4())
    cur.execute(
        "insert into auth.users (id, email, raw_user_meta_data) values (%s, %s, %s::jsonb)",
        (uid, f"{name}@example.com", f'{{"display_name": "{name.capitalize()}"}}'),
    )
    return uid


def run(uid, sql, params=None, role="authenticated"):
    """Exécute `sql` comme l'utilisateur `uid` (ou anonyme si None) et renvoie les lignes."""
    cur.execute("begin")
    try:
        cur.execute(f"set local role {role}")
        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
        cur.execute(sql, params)
        rows = cur.fetchall() if cur.description else []
        cur.execute("commit")
        return rows
    except Exception:
        cur.execute("rollback")
        raise


def check(label, cond):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print(f"  ÉCHEC : {label}")


def fails(label, uid, sql, params=None, contains="", role="authenticated"):
    """L'instruction doit échouer, avec `contains` dans le message d'erreur."""
    try:
        run(uid, sql, params, role)
    except psycopg2.Error as e:
        check(f"{label} (message: {str(e).strip()[:120]!r})", contains in str(e))
        return
    check(f"{label} (devait échouer)", False)


def one(uid, sql, params=None):
    rows = run(uid, sql, params)
    return rows[0][0] if rows else None


def count(uid, table, where="true", params=None):
    return one(uid, f"select count(*) from public.{table} where {where}", params)


def su(sql, params=None):
    """Lecture en superutilisateur, pour vérifier l'état réel de la base."""
    cur.execute(sql, params)
    return cur.fetchall() if cur.description else []


# --- scénario -------------------------------------------------------------------------------

julie, marc, lea, tom, eve, zoe, nina = (user(n) for n in ["julie", "marc", "lea", "tom", "eve", "zoe", "nina"])

print("club et adhésions")
club = one(julie, "select public.create_club(%s)", ("AC Test",))
check("create_club renvoie un id", club is not None)
fails("nom de club unique, insensible à la casse", zoe, "select public.create_club(%s)", ("ac TEST",), "club_name_taken")
check("8 types de séance par défaut", count(julie, "session_types", "club_id = %s", (club,)) == 8)
check("julie est owner", su("select role from public.memberships where user_id=%s", (julie,))[0][0] == "owner")
check("find_club insensible à la casse", len(run(lea, "select * from public.find_club(%s)", ("  ac test ",))) == 1)
check("find_club n'expose pas de club au hasard", len(run(lea, "select * from public.find_club(%s)", ("ac",))) == 0)

# Léa demande à rejoindre comme athlète : en attente, elle ne voit rien du club.
run(lea, "select public.request_join(%s, 'athlete')", (club,))
fails("demande en double refusée", lea, "select public.request_join(%s, 'athlete')", (club,), "already_requested")
check("athlète en attente voit le nom du club", count(lea, "clubs") == 1)
check("athlète en attente ne voit pas les groupes", count(lea, "training_groups") == 0)
fails("on ne peut pas demander à être owner", tom, "select public.request_join(%s, 'owner')", (club,), "invalid_role")

# Marc et Zoé demandent à être coach.
run(marc, "select public.request_join(%s, 'coach')", (club,))
run(zoe, "select public.request_join(%s, 'coach')", (club,))
mid = lambda u: su("select id from public.memberships where user_id=%s and club_id=%s", (u, club))[0][0]

check("un coach en attente ne voit pas la file des demandes", count(marc, "memberships") == 1)
fails("un simple athlète en attente ne peut pas approuver", lea, "select public.approve_membership(%s)", (mid(marc),), "forbidden")
check("le propriétaire voit les demandes en attente", count(julie, "memberships", "status = 'pending'") == 3)

run(julie, "select public.approve_membership(%s)", (mid(lea),))
run(julie, "select public.approve_membership(%s)", (mid(marc),))
run(julie, "select public.reject_membership(%s)", (mid(zoe),))
check("refus = demande supprimée", len(su("select 1 from public.memberships where user_id=%s", (zoe,))) == 0)
check("approbation d'un athlète crée sa fiche", len(su("select 1 from public.athletes where user_id=%s", (lea,))) == 1)
check("l'athlète approuvé voit maintenant le club", count(lea, "training_groups") == 0 and count(lea, "memberships") >= 2)

# Un coach ne peut pas valider un autre coach, seulement un athlète.
run(zoe, "select public.request_join(%s, 'coach')", (club,))
fails("un coach ne valide pas un coach", marc, "select public.approve_membership(%s)", (mid(zoe),), "forbidden")
run(julie, "select public.reject_membership(%s)", (mid(zoe),))
run(tom, "select public.request_join(%s, 'athlete')", (club,))
run(marc, "select public.approve_membership(%s)", (mid(tom),))
check("un coach valide un athlète", su("select status from public.memberships where user_id=%s", (tom,))[0][0] == "active")

print("invitations")
fails("un coach n'invite pas de coach", marc, "select public.create_invitation(%s, 'coach')", (club,), "forbidden")
fails("un athlète n'invite personne", lea, "select public.create_invitation(%s, 'athlete')", (club,), "forbidden")
code = one(marc, "select public.create_invitation(%s, 'athlete')", (club,))
check("code de 12 caractères", len(code) == 12)
prev = run(eve, "select club_name, role, valid from public.preview_invitation(%s)", (f"{code[:4]}-{code[4:8]} {code[8:].lower()}",))
check("aperçu tolère tirets, espaces et casse", prev == [("AC Test", "athlete", True)])
run(eve, "select public.accept_invitation(%s)", (code,))
check("invitation acceptée = membre actif", su("select status, role from public.memberships where user_id=%s", (eve,)) == [("active", "athlete")])
check("invitation acceptée crée la fiche athlète", len(su("select 1 from public.athletes where user_id=%s", (eve,))) == 1)
fails("code à usage unique déjà utilisé", zoe, "select public.accept_invitation(%s)", (code,), "invitation_invalid")
fails("code inconnu", zoe, "select public.accept_invitation(%s)", ("ZZZZZZZZZZZZ",), "invitation_not_found")
fails("déjà membre", lea, "select public.accept_invitation(%s)",
      (one(marc, "select public.create_invitation(%s, 'athlete')", (club,)),), "already_member")

# Fiche créée à l'avance, puis rattachée par l'invitation.
pre = str(uuid.uuid4())
run(marc, "insert into public.athletes (id, club_id, full_name) values (%s, %s, 'Zoé Dupont')", (pre, club))
code2 = one(marc, "select public.create_invitation(%s, 'athlete', %s)", (club, pre))
run(zoe, "select public.accept_invitation(%s)", (code2,))
check("l'invitation rattache la fiche existante", su("select user_id from public.athletes where id=%s", (pre,))[0][0] == zoe)
check("pas de doublon de fiche", len(su("select 1 from public.athletes where user_id=%s", (zoe,))) == 1)
codec = one(julie, "select public.create_invitation(%s, 'coach', null, 1, null)", (club,))
check("invitation coach par le propriétaire", codec is not None)
run(julie, "select public.revoke_invitation(id) from public.invitations where code=%s", (codec,))
fails("invitation révoquée", tom, "select public.accept_invitation(%s)", (codec,), "invitation_invalid")

print("groupes et athlètes")
sprint = str(uuid.uuid4())
run(marc, "insert into public.training_groups (id, club_id, name) values (%s, %s, 'Sprint')", (sprint, club))
fails("un athlète ne crée pas de groupe", lea, "insert into public.training_groups (club_id, name) values (%s, 'X')", (club,), "row-level security")
check("un athlète voit les groupes pour choisir", count(lea, "training_groups") == 1)
lea_ath = su("select id from public.athletes where user_id=%s", (lea,))[0][0]
tom_ath = su("select id from public.athletes where user_id=%s", (tom,))[0][0]
run(lea, "insert into public.group_athletes (group_id, athlete_id) values (%s, %s)", (sprint, lea_ath))
check("un athlète rejoint un groupe librement", len(su("select 1 from public.group_athletes where athlete_id=%s", (lea_ath,))) == 1)
check("club_id et user_id remplis par trigger",
      su("select club_id, user_id from public.group_athletes where athlete_id=%s", (lea_ath,)) == [(club, lea)])
fails("un athlète n'inscrit pas un autre athlète", lea, "insert into public.group_athletes (group_id, athlete_id) values (%s, %s)", (sprint, tom_ath), "row-level security")
check("un athlète ne voit que sa fiche", count(lea, "athletes") == 1)
check("un coach voit toutes les fiches", count(marc, "athletes") == 4)

print("séances")
type_id = su("select id from public.session_types where club_id=%s and name='Fractionné'", (club,))[0][0]
tpl, planned, blk_t, blk_p = (str(uuid.uuid4()) for _ in range(4))
run(marc, "insert into public.sessions (id, club_id, type_id, title, is_template) values (%s, %s, %s, '6x400', true)", (tpl, club, type_id))
run(marc, """insert into public.session_blocks (id, session_id, kind, position, title, items)
             values (%s, %s, 'main', 1, 'Corps de séance', '[{"reps":6,"distance_m":400,"recovery_s":90}]')""", (blk_t, tpl))
check("bloc : club_id hérité de la séance", su("select club_id from public.session_blocks where id=%s", (blk_t,))[0][0] == club)
check("l'athlète ne voit pas la bibliothèque", count(lea, "sessions") == 0)

run(marc, """insert into public.sessions (id, club_id, type_id, title, group_id, scheduled_date, template_id)
             values (%s, %s, %s, '6x400', %s, '2026-09-24', %s)""", (planned, club, type_id, sprint, tpl))
run(marc, "insert into public.session_blocks (id, session_id, kind, title, items) values (%s, %s, 'main', 'Corps', '[]')", (blk_p, planned))
check("bloc : group_id hérité de la séance placée", su("select group_id from public.session_blocks where id=%s", (blk_p,))[0][0] == sprint)
fails("items doit être un tableau JSON : une chaîne est refusée (d'où le décodage dans le connecteur)", marc,
      "insert into public.session_blocks (session_id, items) values (%s, %s::jsonb)", (planned, '"[]"'), "violates check constraint")
run(marc, "insert into public.session_blocks (session_id, items, position) values (%s, %s::jsonb, 5)", (planned, '[{"reps":10,"distance_m":400,"recovery_s":60}]'))
check("items : un tableau d'exercices est accepté", su("select jsonb_array_length(items) from public.session_blocks where session_id=%s and position=5", (planned,))[0][0] == 1)
check("l'athlète du groupe voit la séance placée et ses 2 blocs", count(lea, "sessions") == 1 and count(lea, "session_blocks") == 2)
check("l'athlète hors groupe ne voit rien", count(tom, "sessions") == 0 and count(tom, "session_blocks") == 0)
fails("séance placée sans date", marc, "insert into public.sessions (club_id, type_id, title, group_id) values (%s, %s, 'x', %s)", (club, type_id, sprint), "violates check constraint")
fails("modèle avec une date", marc, "insert into public.sessions (club_id, type_id, title, is_template, scheduled_date) values (%s, %s, 'x', true, '2026-09-24')", (club, type_id), "violates check constraint")
run(lea, "update public.sessions set title = 'piraté' where id = %s", (planned,))
check("un athlète ne modifie pas une séance", su("select title from public.sessions where id=%s", (planned,))[0][0] == "6x400")
run(lea, "delete from public.sessions where id = %s", (planned,))
check("un athlète ne supprime pas une séance", len(su("select 1 from public.sessions where id=%s", (planned,))) == 1)

# Déplacer la séance dans un autre groupe met à jour les blocs, donc la visibilité.
demi = str(uuid.uuid4())
run(marc, "insert into public.training_groups (id, club_id, name) values (%s, %s, 'Demi-fond')", (demi, club))
run(marc, "update public.sessions set group_id = %s where id = %s", (demi, planned))
check("déplacement : les blocs suivent", su("select group_id from public.session_blocks where id=%s", (blk_p,))[0][0] == demi)
check("déplacement : Léa ne la voit plus", count(lea, "sessions") == 0 and count(lea, "session_blocks") == 0)
run(marc, "update public.sessions set group_id = %s where id = %s", (sprint, planned))

# Groupe vide : autorisé.
run(marc, "insert into public.sessions (club_id, type_id, title, group_id, scheduled_date) values (%s, %s, 'Footing', %s, '2026-09-25')", (club, type_id, demi))
check("séance sur un groupe vide autorisée", count(marc, "sessions", "group_id = %s", (demi,)) == 1)

print("isolation entre clubs")
other = one(nina, "select public.create_club(%s)", ("Autre Club",))
check("club B invisible depuis A", count(marc, "clubs") == 1 and count(nina, "clubs") == 1)
check("séances du club A invisibles depuis B", count(nina, "sessions") == 0)
fails("insérer dans le club A depuis B", nina, "insert into public.training_groups (club_id, name) values (%s, 'pirate')", (club,), "row-level security")
fails("séance de B avec un type de A", nina, "insert into public.sessions (club_id, type_id, title, is_template) values (%s, %s, 'x', true)", (other, type_id), "type_not_in_club")
fails("séance de B sur un groupe de A", nina,
      "insert into public.sessions (club_id, type_id, title, group_id, scheduled_date) values (%s, (select id from public.session_types where club_id=%s limit 1), 'x', %s, '2026-09-24')",
      (other, other, sprint), "group_not_in_club")
fails("groupe et athlète du club A depuis le club B", nina, "insert into public.group_athletes (group_id, athlete_id) values (%s, %s)", (sprint, lea_ath), "row-level security")
fails("club_id d'un bloc ne peut pas être forgé", marc, "update public.session_blocks set club_id = %s where id = %s", (other, blk_p), "row-level security")
check("… et le bloc est inchangé", su("select club_id from public.session_blocks where id=%s", (blk_p,))[0][0] == club)
forged = str(uuid.uuid4())
run(marc, "insert into public.session_blocks (id, session_id, club_id, title) values (%s, %s, %s, 'x')", (forged, planned, other))
check("insert avec un club_id forgé : écrasé par le trigger", su("select club_id from public.session_blocks where id=%s", (forged,))[0][0] == club)

print("événements")
ev = str(uuid.uuid4())
run(marc, "insert into public.events (id, club_id, kind, title, start_date, end_date, priority) values (%s, %s, 'competition', 'Régionaux', '2026-10-10', '2026-10-11', 'A')", (ev, club))
run(marc, "insert into public.event_groups (event_id, group_id) values (%s, %s)", (ev, sprint))
check("un athlète voit les événements du club", count(lea, "events") == 1 and count(lea, "event_groups") == 1)
fails("fin avant début", marc, "insert into public.events (club_id, kind, title, start_date, end_date) values (%s, 'deadline', 'x', '2026-10-10', '2026-10-09')", (club,), "violates check constraint")
fails("un athlète ne crée pas d'événement", lea, "insert into public.events (club_id, kind, title, start_date, end_date) values (%s, 'other', 'x', '2026-10-10', '2026-10-10')", (club,), "row-level security")

print("écritures directes interdites, droits")
fails("insert direct dans memberships", lea, "insert into public.memberships (club_id, user_id, role, status) values (%s, %s, 'owner', 'active')", (club, lea), "row-level security")
run(lea, "update public.memberships set role = 'owner', status = 'active' where user_id = %s", (lea,))
check("update direct de memberships sans effet", su("select role from public.memberships where user_id=%s", (lea,))[0][0] == "athlete")
fails("insert direct dans clubs", lea, "insert into public.clubs (name, created_by) values ('Pirate', %s)", (lea,), "row-level security")
fails("anonyme : RPC refusée", None, "select public.create_club('Anon')", None, "permission denied", role="anon")
check("anonyme : lecture vide", (lambda: (run(None, "select 1 from public.clubs", role="anon") == []))())
check("tokens OAuth illisibles", count(lea, "integration_secrets") == 0)
fails("tokens OAuth non insérables", lea, "insert into public.integration_secrets (integration_id, access_token) values (gen_random_uuid(), 'x')", None, "")

print("propriété et départ")
fails("un coach ne passe pas la main", marc, "select public.transfer_ownership(%s, %s)", (club, marc), "forbidden")
fails("cible = athlète refusée", julie, "select public.transfer_ownership(%s, %s)", (club, lea), "new_owner_must_be_active_coach")
fails("le propriétaire ne peut pas partir sans transférer", julie, "select public.leave_club(%s)", (club,), "owner_must_transfer")
fails("un coach ne retire pas un coach", marc, "select public.remove_member(%s, %s)", (club, julie), "")
run(julie, "select public.transfer_ownership(%s, %s)", (club, marc))
check("marc est owner, julie coach",
      su("select role from public.memberships where user_id=%s", (marc,))[0][0] == "owner"
      and su("select role from public.memberships where user_id=%s", (julie,))[0][0] == "coach")
check("un seul owner", su("select count(*) from public.memberships where club_id=%s and role='owner'", (club,))[0][0] == 1)
fails("l'ex-propriétaire n'a plus les droits", julie, "select public.transfer_ownership(%s, %s)", (club, julie), "forbidden")
fails("l'ex-propriétaire n'invite plus de coach", julie, "select public.create_invitation(%s, 'coach')", (club,), "forbidden")

run(lea, "select public.leave_club(%s)", (club,))
check("départ : adhésion supprimée", len(su("select 1 from public.memberships where user_id=%s and club_id=%s", (lea, club))) == 0)
check("départ : fiche conservée mais détachée", su("select user_id from public.athletes where id=%s", (lea_ath,))[0][0] is None)
check("départ : lien de groupe détaché", su("select user_id from public.group_athletes where athlete_id=%s", (lea_ath,))[0][0] is None)
check("départ : plus d'accès aux séances", count(lea, "sessions") == 0)
run(marc, "select public.remove_member(%s, %s)", (club, tom))
check("un coach retire un athlète", len(su("select 1 from public.memberships where user_id=%s and club_id=%s", (tom, club))) == 0)

print("profil")
run(eve, "update public.profiles set display_name = 'Eve Martin' where id = %s", (eve,))
check("le nom se propage aux adhésions", su("select display_name from public.memberships where user_id=%s", (eve,))[0][0] == "Eve Martin")
check("on ne voit que son propre profil", count(eve, "profiles") == 1)

print(f"\n{passed} contrôles réussis, {failed} échecs")
sys.exit(1 if failed else 0)

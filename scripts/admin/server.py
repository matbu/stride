#!/usr/bin/env python3
"""Petit outil d'admin local pour superviser/déboguer les clubs TrackClub.

Se connecte directement à Postgres (via `DIRECT_URL`/`DATABASE_URL` du fichier `env` à la
racine du repo, jamais commité) avec le rôle `postgres` : ça contourne les RLS, donc on voit
tout le club, pas seulement ce qu'un coach du club verrait. N'écoute que sur 127.0.0.1 — jamais
exposé au réseau. Aucune valeur du fichier `env` n'est journalisée.

Clubs, groupes et comptes (adhésions) : lecture, création, modification, suppression. Volontairement
absent : la création d'un compte (mot de passe) — ça exige de reproduire correctement le hachage
bcrypt de GoTrue, risqué à la main ; passer par l'inscription normale de l'app, ou par le script
de création de compte démo si besoin d'un compte tout fait.

Les opérations qui touchent au rôle « owner » (créer un club, promouvoir quelqu'un owner) passent
par les vrais RPC de l'app (`create_club`, `transfer_ownership`) en simulant l'identité de
l'utilisateur concerné (`request.jwt.claims`) — jamais de logique dupliquée à la main pour cette
règle métier (un seul owner par club).

Lancer via `scripts/admin/run.sh` (gère l'environnement Python), pas directement.
"""
from __future__ import annotations

import json
import re
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

import psycopg2
import psycopg2.extras

HOST = "127.0.0.1"
PORT = 8787
REPO_ROOT = Path(__file__).resolve().parents[2]
STATIC_DIR = Path(__file__).resolve().parent / "static"
UUID_RE = re.compile(r"^[0-9a-fA-F-]{36}$")


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m:
            continue  # ex. une URL Postgres restée sans variable dans `env` : ignorée
        key, val = m.group(1), m.group(2)
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        values[key] = val
    return values


env_path = REPO_ROOT / "env"
if not env_path.is_file():
    sys.exit(f"Fichier 'env' introuvable : {env_path}")
env = load_env(env_path)
DSN = env.get("DIRECT_URL") or env.get("DATABASE_URL")
if not DSN:
    sys.exit("Ni DIRECT_URL ni DATABASE_URL trouvé dans 'env'.")


def get_conn():
    return psycopg2.connect(DSN, cursor_factory=psycopg2.extras.RealDictCursor)


# --- Requêtes ---------------------------------------------------------------------------

def list_clubs():
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            """
            select
              c.id, c.name, c.created_at,
              (select m.display_name from public.memberships m
                 where m.club_id = c.id and m.role = 'owner') as owner_name,
              (select u.email from public.memberships m
                 join auth.users u on u.id = m.user_id
                 where m.club_id = c.id and m.role = 'owner') as owner_email,
              (select count(*) from public.memberships m
                 where m.club_id = c.id and m.status = 'active') as members_count,
              (select count(*) from public.memberships m
                 where m.club_id = c.id and m.status = 'pending') as pending_count,
              (select count(*) from public.athletes a where a.club_id = c.id) as athletes_count,
              (select count(*) from public.training_groups g
                 where g.club_id = c.id and not g.archived) as groups_count,
              (select count(*) from public.sessions s
                 where s.club_id = c.id and not s.is_template) as sessions_count
            from public.clubs c
            order by c.created_at desc
            """
        )
        return cur.fetchall()


def club_detail(club_id: str):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "select id, name, created_at from public.clubs where id = %s", (club_id,)
        )
        club = cur.fetchone()
        if club is None:
            return None
        cur.execute(
            """
            select m.id, m.user_id, m.display_name, m.role, m.status, m.created_at, u.email
            from public.memberships m
            left join auth.users u on u.id = m.user_id
            where m.club_id = %s
            order by (m.role = 'owner') desc, m.status, m.display_name
            """,
            (club_id,),
        )
        members = cur.fetchall()
        cur.execute(
            """
            select g.id, g.name, g.archived,
              (select count(*) from public.group_athletes ga where ga.group_id = g.id) as athletes_count
            from public.training_groups g
            where g.club_id = %s
            order by g.sort_order, g.name
            """,
            (club_id,),
        )
        groups = cur.fetchall()
        cur.execute(
            """
            select a.id, a.full_name, (a.user_id is not null) as has_account
            from public.athletes a
            where a.club_id = %s
            order by a.full_name
            """,
            (club_id,),
        )
        athletes = cur.fetchall()
        cur.execute(
            """
            select s.id, s.title, s.scheduled_date, t.name as type_name, g.name as group_name
            from public.sessions s
            join public.session_types t on t.id = s.type_id
            left join public.training_groups g on g.id = s.group_id
            where s.club_id = %s and not s.is_template
            order by s.scheduled_date desc
            limit 20
            """,
            (club_id,),
        )
        recent_sessions = cur.fetchall()
        return {
            "club": club,
            "members": members,
            "groups": groups,
            "athletes": athletes,
            "recentSessions": recent_sessions,
        }


def search_by_email(email: str):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            """
            select m.club_id, c.name as club_name, m.role, m.status, m.display_name, u.email
            from public.memberships m
            join public.clubs c on c.id = m.club_id
            join auth.users u on u.id = m.user_id
            where u.email ilike %s
            order by c.name
            """,
            (f"%{email}%",),
        )
        return cur.fetchall()


def delete_club(club_id: str, confirm_name: str):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("select name from public.clubs where id = %s", (club_id,))
        row = cur.fetchone()
        if row is None:
            return False, "club introuvable"
        if row["name"] != confirm_name:
            return False, "le nom de confirmation ne correspond pas"
        cur.execute("delete from public.clubs where id = %s", (club_id,))
        conn.commit()
        return True, None


def delete_membership(membership_id: str):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("select role from public.memberships where id = %s", (membership_id,))
        row = cur.fetchone()
        if row is None:
            return False, "adhésion introuvable"
        if row["role"] == "owner":
            return False, "impossible de retirer le propriétaire — supprime plutôt le club entier"
        cur.execute("delete from public.memberships where id = %s", (membership_id,))
        conn.commit()
        return True, None


def _pg_message(e: Exception) -> str:
    """Le message métier d'un `raise exception 'code'` (ex. club_name_taken), sans le bruit
    psycopg2 autour, ou à défaut le message brut."""
    diag = getattr(e, "diag", None)
    return (diag.message_primary if diag and diag.message_primary else str(e)).strip()


def create_club(name: str, owner_email: str):
    """Passe par le vrai RPC `create_club` (types de séance par défaut, adhésion owner...), en
    se faisant passer pour le compte propriétaire — un club a toujours un propriétaire dès sa
    création dans l'app réelle, pas de raccourci ici."""
    name = name.strip()
    owner_email = owner_email.strip()
    if not owner_email:
        return None, "email du propriétaire requis — un club a toujours un propriétaire"
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("select id from auth.users where email = %s", (owner_email,))
        u = cur.fetchone()
        if u is None:
            return None, f"aucun compte avec l'email {owner_email!r}"
        try:
            cur.execute("set local role authenticated")
            cur.execute(
                "select set_config('request.jwt.claims', %s, true)",
                (json.dumps({"sub": u["id"], "role": "authenticated"}),),
            )
            cur.execute("select public.create_club(%s) as id", (name,))
            club_id = cur.fetchone()["id"]
        except Exception as e:
            conn.rollback()
            return None, _pg_message(e)
        conn.commit()
        return {"id": club_id}, None


def rename_club(club_id: str, name: str):
    name = name.strip()
    with get_conn() as conn, conn.cursor() as cur:
        try:
            cur.execute("update public.clubs set name = %s where id = %s", (name, club_id))
        except Exception as e:
            conn.rollback()
            return False, _pg_message(e)
        if cur.rowcount == 0:
            return False, "club introuvable"
        conn.commit()
        return True, None


def create_group(club_id: str, name: str):
    with get_conn() as conn, conn.cursor() as cur:
        try:
            cur.execute(
                "insert into public.training_groups (club_id, name) values (%s, %s) returning id",
                (club_id, name.strip()),
            )
        except Exception as e:
            conn.rollback()
            return None, _pg_message(e)
        group_id = cur.fetchone()["id"]
        conn.commit()
        return {"id": group_id}, None


def update_group(group_id: str, name: str | None, archived: bool | None):
    fields, params = [], []
    if name is not None:
        fields.append("name = %s")
        params.append(name.strip())
    if archived is not None:
        fields.append("archived = %s")
        params.append(archived)
    if not fields:
        return True, None
    params.append(group_id)
    with get_conn() as conn, conn.cursor() as cur:
        try:
            cur.execute(f"update public.training_groups set {', '.join(fields)} where id = %s", params)
        except Exception as e:
            conn.rollback()
            return False, _pg_message(e)
        if cur.rowcount == 0:
            return False, "groupe introuvable"
        conn.commit()
        return True, None


def delete_group(group_id: str):
    with get_conn() as conn, conn.cursor() as cur:
        try:
            cur.execute("delete from public.training_groups where id = %s", (group_id,))
        except Exception as e:
            conn.rollback()
            # Le plus probable : des séances existent encore pour ce groupe (pas de cascade
            # voulue ici, contrairement à `group_athletes`) — l'app elle-même n'archive que.
            return False, "impossible : des séances (ou une autre donnée) référencent encore ce groupe — archive-le plutôt"
        if cur.rowcount == 0:
            return False, "groupe introuvable"
        conn.commit()
        return True, None


def update_membership(membership_id: str, role: str | None, display_name: str | None):
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(
            "select club_id, user_id, role as current_role from public.memberships where id = %s",
            (membership_id,),
        )
        m = cur.fetchone()
        if m is None:
            return False, "adhésion introuvable"

        if display_name is not None and display_name.strip():
            # `profiles.display_name` est la source de vérité (un trigger la recopie sur
            # toutes les adhésions de la personne) — jamais `memberships.display_name` direct.
            cur.execute(
                "update public.profiles set display_name = %s where id = %s",
                (display_name.strip(), m["user_id"]),
            )

        if role is not None and role != m["current_role"]:
            if role not in ("owner", "coach", "athlete"):
                conn.rollback()
                return False, "rôle invalide"
            if role == "owner":
                cur.execute(
                    "select user_id from public.memberships where club_id = %s and role = 'owner'",
                    (m["club_id"],),
                )
                current_owner = cur.fetchone()
                if current_owner is None:
                    conn.rollback()
                    return False, "aucun propriétaire actuel trouvé pour ce club"
                try:
                    cur.execute("set local role authenticated")
                    cur.execute(
                        "select set_config('request.jwt.claims', %s, true)",
                        (json.dumps({"sub": str(current_owner["user_id"]), "role": "authenticated"}),),
                    )
                    cur.execute(
                        "select public.transfer_ownership(%s, %s)",
                        (m["club_id"], m["user_id"]),
                    )
                except Exception as e:
                    conn.rollback()
                    return False, _pg_message(e)
            elif m["current_role"] == "owner":
                conn.rollback()
                return False, "attribue d'abord le rôle de propriétaire à quelqu'un d'autre avant de rétrograder celui-ci"
            else:
                cur.execute("update public.memberships set role = %s where id = %s", (role, membership_id))

        conn.commit()
        return True, None


def delete_account(user_id: str, confirm_email: str):
    """Supprime le compte entier (`auth.users`), pas juste une adhésion : cascade sur profil,
    adhésions de tous les clubs, profil/records athlète, etc. Les `created_by` historiques
    (club, séance, événement...) passent à NULL plutôt que de bloquer (voir la migration
    `delete_account`)."""
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("select email from auth.users where id = %s", (user_id,))
        row = cur.fetchone()
        if row is None:
            return False, "compte introuvable"
        if row["email"] != confirm_email:
            return False, "l'email de confirmation ne correspond pas"
        cur.execute("delete from auth.users where id = %s", (user_id,))
        conn.commit()
        return True, None


# --- Serveur HTTP ------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "TrackClubAdmin/1"

    def log_message(self, fmt, *args):  # discret : jamais de secret à journaliser de toute façon
        sys.stderr.write(f"{self.address_string()} - {fmt % args}\n")

    def _json(self, status: int, payload):
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str):
        self._json(status, {"error": message})

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length) or b"{}")

    def _serve_static(self, path: str):
        if path == "/":
            path = "/index.html"
        file_path = (STATIC_DIR / path.lstrip("/")).resolve()
        if STATIC_DIR not in file_path.parents or not file_path.is_file():
            return self._error(404, "introuvable")
        content_type = {
            ".html": "text/html; charset=utf-8",
            ".js": "application/javascript; charset=utf-8",
            ".css": "text/css; charset=utf-8",
        }.get(file_path.suffix, "application/octet-stream")
        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        try:
            if parts == ["api", "clubs"]:
                return self._json(200, list_clubs())
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "clubs":
                club_id = parts[2]
                if not UUID_RE.match(club_id):
                    return self._error(400, "id invalide")
                detail = club_detail(club_id)
                if detail is None:
                    return self._error(404, "club introuvable")
                return self._json(200, detail)
            if parts == ["api", "search"]:
                qs = parse_qs(parsed.query)
                email = (qs.get("email") or [""])[0].strip()
                if len(email) < 2:
                    return self._json(200, [])
                return self._json(200, search_by_email(email))
            return self._serve_static(unquote(parsed.path))
        except Exception as e:  # outil local mono-utilisateur : autant voir l'erreur telle quelle
            return self._error(500, str(e))

    def do_DELETE(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        try:
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "clubs":
                club_id = parts[2]
                if not UUID_RE.match(club_id):
                    return self._error(400, "id invalide")
                qs = parse_qs(parsed.query)
                confirm_name = (qs.get("confirm_name") or [""])[0]
                ok, message = delete_club(club_id, confirm_name)
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"deleted": True})
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "memberships":
                ok, message = delete_membership(parts[2])
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"deleted": True})
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "groups":
                ok, message = delete_group(parts[2])
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"deleted": True})
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "accounts":
                user_id = parts[2]
                if not UUID_RE.match(user_id):
                    return self._error(400, "id invalide")
                qs = parse_qs(parsed.query)
                confirm_email = (qs.get("confirm_email") or [""])[0]
                ok, message = delete_account(user_id, confirm_email)
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"deleted": True})
            return self._error(404, "route inconnue")
        except Exception as e:
            return self._error(500, str(e))

    def do_POST(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        try:
            body = self._read_json()
            if parts == ["api", "clubs"]:
                name = str(body.get("name", ""))
                owner_email = str(body.get("owner_email", ""))
                result, message = create_club(name, owner_email)
                if result is None:
                    return self._error(409, message)
                return self._json(201, result)
            if parts == ["api", "groups"]:
                club_id = str(body.get("club_id", ""))
                name = str(body.get("name", ""))
                if not UUID_RE.match(club_id):
                    return self._error(400, "club_id invalide")
                result, message = create_group(club_id, name)
                if result is None:
                    return self._error(409, message)
                return self._json(201, result)
            return self._error(404, "route inconnue")
        except Exception as e:
            return self._error(500, str(e))

    def do_PATCH(self):
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        try:
            body = self._read_json()
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "clubs":
                club_id = parts[2]
                if not UUID_RE.match(club_id):
                    return self._error(400, "id invalide")
                name = body.get("name")
                if not name:
                    return self._error(400, "name requis")
                ok, message = rename_club(club_id, str(name))
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"updated": True})
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "groups":
                group_id = parts[2]
                if not UUID_RE.match(group_id):
                    return self._error(400, "id invalide")
                name = body.get("name")
                archived = body.get("archived")
                ok, message = update_group(
                    group_id,
                    str(name) if name is not None else None,
                    bool(archived) if archived is not None else None,
                )
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"updated": True})
            if len(parts) == 3 and parts[0] == "api" and parts[1] == "memberships":
                membership_id = parts[2]
                if not UUID_RE.match(membership_id):
                    return self._error(400, "id invalide")
                role = body.get("role")
                display_name = body.get("display_name")
                ok, message = update_membership(
                    membership_id,
                    str(role) if role is not None else None,
                    str(display_name) if display_name is not None else None,
                )
                if not ok:
                    return self._error(409, message)
                return self._json(200, {"updated": True})
            return self._error(404, "route inconnue")
        except Exception as e:
            return self._error(500, str(e))


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    url = f"http://{HOST}:{PORT}/"
    host_only = DSN.split("@")[-1].split("/")[0] if "@" in DSN else "?"
    print(f"Admin TrackClub sur {url}  (base : {host_only})")
    print("Ctrl+C pour arrêter.")
    try:
        webbrowser.open(url)
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

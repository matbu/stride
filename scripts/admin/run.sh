#!/usr/bin/env bash
# Lance l'outil d'admin local (voir server.py). Crée un venv Python dédié au premier lancement
# (le Python système est "externally managed", voir supabase/tests/run_tests.py pour le même souci).
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f ../../env ]]; then
  echo "Fichier 'env' introuvable à la racine du repo." >&2
  exit 1
fi

if [[ ! -d venv ]]; then
  echo "Première utilisation : installation de psycopg2 dans un venv local..."
  python3 -m venv venv
  venv/bin/pip install -q --upgrade pip
  venv/bin/pip install -q psycopg2-binary
fi

exec venv/bin/python server.py

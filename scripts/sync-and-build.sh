#!/usr/bin/env bash
# Syncs Supabase (SQL migrations) + reminds about PowerSync if needed, then builds the apps.
#
# Usage:
#   scripts/sync-and-build.sh                  # everything: db push, powersync reminder, build android + ios
#   scripts/sync-and-build.sh --db-only         # only supabase db push
#   scripts/sync-and-build.sh --skip-db         # only the builds
#   scripts/sync-and-build.sh --android-only    # build Android only (no iOS)
#   scripts/sync-and-build.sh --ios-only        # build iOS only (no Android)
#
# Requirements: `supabase link` already done once (supabase/.temp/), the `env` file at the repo
# root filled in (see README), Xcode for the iOS build, the Android SDK for the Android build.
set -euo pipefail
cd "$(dirname "$0")/.."

DO_DB=1
DO_ANDROID=1
DO_IOS=1
for arg in "$@"; do
  case "$arg" in
    --db-only) DO_ANDROID=0; DO_IOS=0 ;;
    --skip-db) DO_DB=0 ;;
    --android-only) DO_IOS=0 ;;
    --ios-only) DO_ANDROID=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -f env ]]; then
  echo "'env' file not found at the repo root (see README)." >&2
  exit 1
fi
set -a
source ./env
set +a
for v in SUPABASE_URL SUPABASE_PUBLISHABLE_KEY POWERSYNC_URL; do
  if [[ -z "${!v:-}" ]]; then
    echo "Missing variable $v in 'env'." >&2
    exit 1
  fi
done

if (( DO_DB )); then
  echo "==> Supabase: migrations"
  if ! command -v supabase >/dev/null; then
    echo "supabase CLI not found (see README)." >&2
    exit 1
  fi
  supabase db push
  echo

  echo "==> PowerSync: sync rules"
  if ! git diff --quiet -- powersync/sync-rules.yaml 2>/dev/null || \
     ! git diff --quiet --cached -- powersync/sync-rules.yaml 2>/dev/null; then
    cat <<EOF
powersync/sync-rules.yaml has changed and isn't synced yet.
No public API to automate this: paste the file into the instance's dashboard
(Sync Rules → Validate → Deploy).
  Instance: ${POWERSYNC_URL}
EOF
  else
    echo "No local change in sync-rules.yaml."
  fi
  echo
fi

DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"
  --dart-define=POWERSYNC_URL="$POWERSYNC_URL"
)

if (( DO_ANDROID )); then
  echo "==> Build Android (release APK)"
  (cd app && flutter build apk --release "${DEFINES[@]}")
  echo "APK: app/build/app/outputs/flutter-apk/app-release.apk"
  echo
fi

if (( DO_IOS )); then
  echo "==> Build iOS (release IPA — requires Xcode and a configured Apple Developer account)"
  (cd app && flutter build ipa --release "${DEFINES[@]}")
  echo "IPA: app/build/ios/ipa/"
  echo
fi

echo "Done."

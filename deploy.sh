#!/usr/bin/env bash
#
# Baut die Seite und synchronisiert _site per SFTP auf den Webserver.
#
#   ./deploy.sh            bauen und hochladen
#   ./deploy.sh --dry-run  bauen und nur anzeigen, was sich ändern würde
#
# Zugangsdaten stehen in deploy.env (Vorlage: deploy.env.example).
# Ohne SFTP_PASSWORD wird per SSH-Key angemeldet (empfohlen).

set -euo pipefail
cd "$(dirname "$0")"

DRY_RUN=""
case "${1:-}" in
  "") ;;
  -n|--dry-run) DRY_RUN="--dry-run" ;;
  *) echo "Unbekannte Option: $1" >&2; exit 1 ;;
esac

if [[ ! -f deploy.env ]]; then
  echo "deploy.env fehlt. Lege sie aus deploy.env.example an." >&2
  exit 1
fi
# shellcheck source=/dev/null
source deploy.env

: "${SFTP_HOST:?SFTP_HOST fehlt in deploy.env}"
: "${SFTP_USER:?SFTP_USER fehlt in deploy.env}"
: "${SFTP_PATH:=}"   # leer: Verzeichnis, in dem der Login landet
SFTP_PORT="${SFTP_PORT:-22}"

if [[ "$SFTP_PATH" == "/html/soulism.de" ]]; then
  echo "SFTP_PATH ist noch der Beispielwert aus deploy.env.example, bitte anpassen." >&2
  exit 1
fi

command -v lftp >/dev/null || { echo "lftp fehlt: brew install lftp" >&2; exit 1; }

echo "==> Baue Seite"
rm -rf _site
JEKYLL_ENV=production bundle exec jekyll build

if [[ -n "${SFTP_PASSWORD:-}" ]]; then
  export LFTP_PASSWORD="$SFTP_PASSWORD"
  LOGIN=(-u "$SFTP_USER" --env-password)
else
  LOGIN=(-u "$SFTP_USER,")   # leeres Passwort: Anmeldung per SSH-Key
fi

CD_TARGET=""
[[ -n "$SFTP_PATH" ]] && CD_TARGET="cd \"$SFTP_PATH\""   # bricht ab, falls nicht vorhanden

echo "==> Synchronisiere _site nach sftp://$SFTP_HOST:$SFTP_PORT/${SFTP_PATH#/} ${DRY_RUN:+(Probelauf)}"
lftp -p "$SFTP_PORT" "${LOGIN[@]}" "sftp://$SFTP_HOST" <<LFTP
set cmd:fail-exit yes
set net:max-retries 2
set net:timeout 20
$CD_TARGET
mirror --reverse --delete --verbose --parallel=4 \
  --exclude-glob .DS_Store \
  $DRY_RUN _site/ .
LFTP

echo "==> Fertig"

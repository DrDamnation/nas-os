#!/bin/bash
# Lo scanner deve bloccare i casi veri e lasciar passare le letture da variabile.
set -u
cd "$(dirname "$0")/.."
source tests/lib.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
blocca() { mkdir -p "$t/$1"; printf '%s\n' "$3" > "$t/$1/$2"; check "blocca: $3 ($2)" ! bash tests/secrets-scan.sh "$t/$1"; }
passa()  { mkdir -p "$t/$1"; printf '%s\n' "$3" > "$t/$1/$2"; check "passa: $3 ($2)" bash tests/secrets-scan.sh "$t/$1"; }

section "Blocca"
blocca 1 a.py 'PW="Segreto9"'
blocca 2 b.yml 'ROUTER_PASS: valore12'
blocca 3 c.js "const API_KEY = 'abcd1234'"
blocca 4 d.env 'MARIADB_ROOT_PASSWORD=xyz987'
blocca 5 e.sh 'export HA_TOKEN="abcdefgh"'
blocca 6 token 'qualcosa'
blocca 7 f.py '{"password": "lunga1234"}'

section "Passa"
passa 11 a.py 'PW = os.environ["ROUTER_PASS"]'
passa 12 b.yml 'DB_PASSWD: ${ROMM_DB_PASSWORD:?manca}'
passa 13 c.js 'const HA_TOKEN = process.env.HA_TOKEN;'
passa 14 d.py 'data = {"password": pw}'
passa 15 e.js "loadConfig({ TELEGRAM_BOT_TOKEN: 'tok' })"
passa 16 f.sh 'PASS=$(cat /run/secret)'

finish

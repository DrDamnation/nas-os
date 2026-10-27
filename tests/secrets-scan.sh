#!/usr/bin/env bash
# Blocca segreti e dati personali nei file del repo.
# Cerca per FORMA del valore, non per nome della variabile.
# Uso: tests/secrets-scan.sh [file o cartelle...]   (senza argomenti: tutti i file tracciati da git)
# Eccezioni puntuali: a fine riga il commento "secrets-scan: ok" (solo per falsi positivi verificati).
set -u
top=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$top"

if (( $# )); then mapfile -t files < <(find "$@" -type f 2>/dev/null)
else mapfile -t files < <(git ls-files); fi
(( ${#files[@]} )) || { echo "Nessun file da controllare"; exit 0; }

declare -A regole=(
  # valore tra virgolette (ovunque): "pass": "abcd", TOKEN='xyz1'
  [password_scritta]='(^|[^A-Za-z0-9-])([A-Za-z0-9]+_)*(psk|pw|pass|passw|password|passwd|pwd|secret|token|api[_-]?key)(_[A-Za-z0-9]+)*["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'$<{[:space:]]{4,}'
  # valore senza virgolette: solo nei file di configurazione (in codice e' una variabile)
  [password_config]='(^|[^A-Za-z0-9-])([A-Za-z0-9]+_)*(psk|pw|pass|passw|password|passwd|pwd|secret|token|api[_-]?key)(_[A-Za-z0-9]+)*["'"'"']?[[:space:]]*[=:][[:space:]]*[^"'"'"'$<{?[:space:]][^[:space:]]{3,}'
  [chiave_privata]='BEGIN [A-Z ]*PRIVATE KEY'
  [token_github]='github_pat_|gh[pousr]_[A-Za-z0-9]{20,}'
  [token_tailscale]='tskey-[a-z]+-[A-Za-z0-9]'
  [jwt]='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'
  [token_generico]='(sk-|sk_live_|xox[bap]-|AKIA)[A-Za-z0-9]{12,}'
  [bearer]='Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  [email]='[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook|live|yahoo|libero|icloud|datamasters|convertini)\.[a-z.]+'
  [codice_fiscale]='\b[A-Z]{6}[0-9]{2}[A-EHLMPR-T][0-9]{2}[A-Z][0-9]{3}[A-Z]\b'
  [iban]='\bIT[0-9]{2}[A-Z][0-9]{10}[0-9A-Z]{12}\b'
  [telefono]='(\+39|0039)[[:space:]]?3[0-9]{2}[[:space:]]?[0-9]{6,7}'
  [rete_tailscale]='[a-z]+-[a-z]+\.ts\.net'
)

# Valori personali da cercare (IP pubblico, nomi...): MAI nel repo.
# In locale: file .secrets-scan-extra (escluso da git), una regex per riga.
# In CI: segreto del repo SECRETS_SCAN_EXTRA, stesso formato.
extra="${SECRETS_SCAN_EXTRA:-}"
[[ -f .secrets-scan-extra ]] && extra+=$'
'"$(cat .secrets-scan-extra)"
n=0
while IFS= read -r r; do [[ -n $r ]] && regole[personale_$((++n))]="$r"; done <<<"$extra"

# Regole senza distinzione maiuscole/minuscole (ROUTER_PASS=, API_KEY=...)
declare -A senza_maiuscole=([password_scritta]=1 [password_config]=1)
# File di configurazione: unici dove vale password_config
config_re='(\.(ya?ml|env|conf|cfg|ini|toml|properties|sh)|(^|/)[^./]+)$'

trovati=0
# File che per nome sono credenziali o stato di un servizio
nomi=$(printf '%s\n' "${files[@]}" | grep -E '(^|/)(secret|token|state\.json|[^/]*\.state|id_(rsa|ed25519|ecdsa))$')
if [[ -n $nomi ]]; then
  trovati=1; echo "[file_credenziali]"; sed 's/^/  /' <<<"$nomi"
fi
for nome in "${!regole[@]}"; do
  opz=-HInE; [[ -n ${senza_maiuscole[$nome]:-} ]] && opz=-HIinE
  lista=("${files[@]}")
  if [[ $nome == password_config ]]; then mapfile -t lista < <(printf '%s\n' "${files[@]}" | grep -E "$config_re"); fi
  (( ${#lista[@]} )) || continue
  hits=$(grep $opz "${regole[$nome]}" -- "${lista[@]}" 2>/dev/null | grep -v 'secrets-scan: ok' | grep -Ev '^tests/secrets-scan(-test)?.sh:')
  if [[ -n $hits ]]; then
    trovati=1
    echo "[$nome]"
    cut -d: -f1,2 <<<"$hits" | sed 's/^/  /'   # solo file:riga, mai il valore
  fi
done

if (( trovati )); then
  echo "BLOCCATO: possibili segreti o dati personali. Spostali fuori dal repo: i segreti vivono solo sul dispositivo."
  exit 1
fi
echo "OK: nessun segreto o dato personale in ${#files[@]} file"

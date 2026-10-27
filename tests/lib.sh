#!/usr/bin/env bash
# Mini libreria di test: check "<descrizione>" [!] <comando...>; finish
# Stampa PASS/FAIL per riga; finish esce 1 se almeno un check è fallito.
_AIR_PASS=0
_AIR_FAIL=0

check() {
    local desc="$1"; shift
    local negate=0
    if [[ "${1:-}" == "!" ]]; then negate=1; shift; fi
    if "$@" >/dev/null 2>&1; then local rc=0; else local rc=1; fi
    if (( negate )); then rc=$(( 1 - rc )); fi
    if (( rc == 0 )); then
        _AIR_PASS=$((_AIR_PASS + 1)); echo "PASS  $desc"
    else
        _AIR_FAIL=$((_AIR_FAIL + 1)); echo "FAIL  $desc"
    fi
}

section() { echo; echo "== $*"; }

finish() {
    echo
    echo "Risultato: $_AIR_PASS PASS, $_AIR_FAIL FAIL"
    (( _AIR_FAIL == 0 ))
}

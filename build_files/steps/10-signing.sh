#!/bin/bash
# Le immagini nas-os si accettano solo se firmate con la nostra chiave cosign.
source "$(dirname "$0")/vars.sh"

policy=/etc/containers/policy.json
tmp=$(mktemp)
jq '.transports.docker["ghcr.io/drdamnation/nas-os"] = [{
      "type": "sigstoreSigned",
      "keyPath": "/etc/pki/containers/nas-os.pub",
      "signedIdentity": {"type": "matchRepository"}
    }]' "$policy" > "$tmp"
mv "$tmp" "$policy"
chmod 644 "$policy"

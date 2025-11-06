#!/usr/bin/env bash
# helpers/crtsh_fallback.sh
# Query crt.sh for subdomains and output unique list
# Usage: ./helpers/crtsh_fallback.sh example.com /path/to/output

DOMAIN="$1"
OUTFILE="$2"

if [[ -z "$DOMAIN" || -z "$OUTFILE" ]]; then
  echo "Usage: $0 <domain> <outputfile>" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "[!] curl and jq are required for crt.sh fallback" >&2
  exit 2
fi

curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" | jq -r '.[].name_value' | sed 's/*\.//g' | sort -u > "$OUTFILE"

echo "[+] crt.sh results written to $OUTFILE"

#!/usr/bin/env bash
# helpers/403_bypass.sh
# Simple wrapper to run 403bypasser on a given URL and append results.
# Usage: ./helpers/403_bypass.sh "https://sub.example.com/secret" /path/to/outputfile

URL="$1"
OUTFILE="$2"

if [[ -z "$URL" || -z "$OUTFILE" ]]; then
  echo "Usage: $0 <url> <outputfile>" >&2
  exit 1
fi

if ! command -v 403bypasser >/dev/null 2>&1; then
  echo "[!] 403bypasser not found in PATH. Install it or adjust this script." >&2
  exit 2
fi

echo "[+] Running 403 bypass on: $URL"
403bypasser -u "$URL" -o /tmp/403bypass_tmp.txt || true
# Tailor parsing if needed; here we append full output
cat /tmp/403bypass_tmp.txt >> "$OUTFILE"

# basic cleanup
rm -f /tmp/403bypass_tmp.txt

echo "[+] Results appended to $OUTFILE"

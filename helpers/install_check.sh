#!/usr/bin/env bash
# helpers/install_check.sh
# Quick checks and printout of missing tools to help newcomers

REQUIRED=(amass subfinder findomain httpx katana paramspider 403bypasser subjack dalfox sqlmap jq)
MISSING=()
for t in "${REQUIRED[@]}"; do
  if ! command -v "$t" >/dev/null 2>&1; then
    MISSING+=("$t")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "[+] All recommended tools detected in PATH"
else
  echo "[!] Missing tools: ${MISSING[*]}"
  echo "Install the missing tools or run the main script with --skip-* flags as needed."
fi

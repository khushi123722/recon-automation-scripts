# Recon Automation Scripts — Khushi Mistry

> **Solo project** — Automation scripts for Vulnerability Assessment (Recon phase)

---

## Project summary

Bash-based toolkit to automate reconnaissance tasks during VAPT engagements. It orchestrates multiple open-source tools to discover subdomains, check liveliness, enumerate endpoints/parameters, discover directories, attempt 403 bypasses, detect subdomain takeover candidates, and scan for XSS/SQLi — then aggregates findings into concise output reports.

**Repo name suggestion:** `recon-automation-scripts` (solo)

---

## Polished README.md

````
# Recon Automation Scripts

**Owner:** Khushi Mistry
**Type:** Solo project — Recon & vulnerability discovery automation (recon phase)

## TL;DR
A Bash automation toolkit that runs common recon tools (amass, subfinder, findomain, httpx, katana, paramspider, dalfox, sqlmap, etc.) in a safe, auditable workflow and aggregates final results into `final_vuln.txt`.

## Features
- Multi-tool subdomain discovery (active + passive)
- Live-host detection and normalization (httpx)
- Endpoint & parameter extraction (katana, paramspider)
- Directory discovery with 403/404 classification
- 403 bypass attempts and subdomain takeover checks
- XSS / SQLi quick checks and aggregation
- CLI flags to skip tools or run in limited mode (for smaller environments or missing tooling)

## Files & Structure
- `recon_automation.sh` — main orchestrator script (CLI-friendly)
- `helpers/` — small helper wrappers (e.g., `403_bypass.sh`)
- `README.md` — this file
- `LICENSE` — MIT by default
- `.gitignore`

## Prerequisites
Install the tools you plan to use and ensure they are in your PATH. Recommended:
- amass, subfinder, findomain, sublist3r
- httpx, katana, paramspider
- 403bypasser, subjack (or alternative takeover checker)
- dalfox, xssstrike
- sqlmap, ghauri
- jq, parallel, sort, uniq

If a tool is missing, the script will either skip the step or use a fallback when possible. You can also pass CLI flags to explicitly skip certain steps.

## Usage

```bash
# make it executable
chmod +x recon_automation.sh

# basic run
./recon_automation.sh -d example.com -o outputs/example.com

# skip httpx and sqlmap (faster / less intrusive)
./recon_automation.sh -d example.com -o outputs/example.com --skip-httpx --skip-sqlmap

# run only subdomain discovery + live-check
./recon_automation.sh -d example.com --mode=light
````

## Outputs (per-run directory)

* `totalsub.txt` — merged unique subdomains
* `live.txt` — live hosts
* `param.txt` — endpoints + parameters discovered
* `dir.txt` — discovered directories with HTTP status markers
* `403_bypass_results.txt` — 403 bypass attempts output
* `takeover_candidates.txt` — potential takeover domains
* `xss_vuln.txt`, `sql_vuln.txt`, `end_vuln.txt`, `final_vuln.txt`

## Legal & Ethics

Only run these scripts against targets you own or have explicit written authorization to test. The author and repository **do not** endorse unauthorized scanning.

## Credits

Inspired by community recon workflows and public automation scripts. Tools used are third-party projects—see individual tool documentation for usage details.

````

---

## Improved `recon_automation.sh` (CLI flags + graceful fallbacks)

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'
	'

# recon_automation.sh
# Usage: recon_automation.sh -d example.com -o outputs/example.com [--skip-httpx] [--skip-katana] [--mode=light]

show_help(){
  cat <<'HELP'
Usage: $0 -d <domain> [-o <output_dir>] [--skip-httpx] [--skip-katana] [--skip-sqlmap] [--mode=light]

Options:
  -d  domain to scan (required)
  -o  output directory (optional, default: ./outputs/<domain>)
  --skip-httpx   skip httpx live-check (useful if httpx not installed)
  --skip-katana  skip katana endpoint discovery
  --skip-sqlmap  skip sqlmap checks
  --mode=light    run only subdomain discovery and live-check (fast)
  -h             show help
HELP
}

# Parse args (simple approach)
DOMAIN=""
OUTDIR=""
SKIP_HTTPX=false
SKIP_KATANA=false
SKIP_SQLMAP=false
MODE="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DOMAIN="$2"; shift 2;;
    -o) OUTDIR="$2"; shift 2;;
    --skip-httpx) SKIP_HTTPX=true; shift;;
    --skip-katana) SKIP_KATANA=true; shift;;
    --skip-sqlmap) SKIP_SQLMAP=true; shift;;
    --mode=light) MODE="light"; shift;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 1;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Error: domain not provided. Use -d <domain>" >&2
  show_help
  exit 1
fi

if [[ -z "$OUTDIR" ]]; then
  OUTDIR="./outputs/${DOMAIN}"
fi
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# Filenames
RAW_SUBS="raw_subs.txt"
TOTAL_SUBS="totalsub.txt"
LIVE="live.txt"
PARAMS="param.txt"
DIRS="dir.txt"
BYPASS_403="403_bypass_results.txt"
TAKEOVER="takeover_candidates.txt"
XSS_VULN="xss_vuln.txt"
SQL_VULN="sql_vuln.txt"
END_VULN="end_vuln.txt"
FINAL_VULN="final_vuln.txt"

# helper
exists(){ command -v "$1" >/dev/null 2>&1; }

# 1) Subdomain enumeration
> "$RAW_SUBS"
if exists amass; then amass enum -d "$DOMAIN" -o amass_out.txt || true; cat amass_out.txt >> "$RAW_SUBS" || true; else echo "[!] amass not found"; fi
if exists subfinder; then subfinder -d "$DOMAIN" -silent -o subfinder_out.txt || true; cat subfinder_out.txt >> "$RAW_SUBS" || true; else echo "[!] subfinder not found"; fi
if exists findomain; then findomain -t "$DOMAIN" -q -o findomain_out.txt || true; cat findomain_out.txt >> "$RAW_SUBS" || true; fi
if exists sublist3r; then sublist3r -d "$DOMAIN" -o sublist3r_out.txt || true; cat sublist3r_out.txt >> "$RAW_SUBS" || true; fi

# fallback: crt.sh scraping (curl + jq) if none of the above
if ! exists amass && ! exists subfinder && ! exists findomain && ! exists sublist3r; then
  echo "[*] No major subdomain tools found. Attempting crt.sh fallback..."
  curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" | jq -r '.[].name_value' | sed 's/*\.//g' | sort -u >> "$RAW_SUBS" || true
fi

sort -u "$RAW_SUBS" -o "$TOTAL_SUBS" || true

# If mode=light, stop after live-check
if [[ "$MODE" == "light" ]]; then
  # live-check using httpx if available
  if [[ "$SKIP_HTTPX" == false && $(exists httpx && echo yes || echo no) == yes ]]; then
    cat "$TOTAL_SUBS" | httpx -silent -o httpx_out.txt || true
    awk '{print $1}' httpx_out.txt | sed 's/https\?:\/\///' | sed 's/:.*//' | sort -u > "$LIVE" || true
  else
    cp "$TOTAL_SUBS" "$LIVE" || true
  fi
  echo "Light mode finished. Check $OUTDIR for totalsub.txt and live.txt"
  exit 0
fi

# 2) Live check (httpx or fallback to curl)
> "$LIVE"
if [[ "$SKIP_HTTPX" == false && $(exists httpx && echo yes || echo no) == yes ]]; then
  cat "$TOTAL_SUBS" | httpx -silent -o httpx_out.txt || true
  awk '{print $1}' httpx_out.txt | sed 's/https\?:\/\///' | sed 's/:.*//' | sort -u > "$LIVE" || true
else
  echo "[!] httpx skipped or not found — using totalsub as live list"
  cp "$TOTAL_SUBS" "$LIVE" || true
fi

# 3) Endpoint & parameters discovery
> "$PARAMS"
if [[ "$SKIP_KATANA" == false && $(exists katana && echo yes || echo no) == yes ]]; then
  cat "$LIVE" | while read -r host; do
    katana -u "https://$host" -silent -o katana_${host}.txt || true
    cat katana_${host}.txt >> "$PARAMS" || true
  done
else
  echo "[!] katana skipped or not found — attempting simple approach using httpx + common paths"
  # naive fallback: probe common paths
  COMMON_PATHS=("/" "/login" "/admin" "/api" "/index.php")
  while read -r host; do
    for p in "${COMMON_PATHS[@]}"; do
      echo "https://$host$p" >> "$PARAMS"
    done
  done < "$LIVE"
fi

# paramspider (parameters)
if exists paramspider; then
  cat "$LIVE" | while read -r host; do
    paramspider -d "$host" -o paramspider_${host}.txt || true
    cat paramspider_${host}.txt >> "$PARAMS" || true
  done
fi

sort -u "$PARAMS" -o "$PARAMS" || true

# 4) Directory enumeration (try httpx output or simple fallbacks)
> "$DIRS"
if exists httpx; then
  cat "$PARAMS" | httpx -silent -status-code -o dirs_status_raw.txt || true
  awk '{print $1" "$(NF)}' dirs_status_raw.txt | awk '$2==403{print $1" 403"} $2==404{print $1" 404"}' | sort -u > "$DIRS" || true
else
  echo "[!] httpx not available — storing params as dirs fallback"
  cp "$PARAMS" "$DIRS" || true
fi

# 5) 403 bypass
> "$BYPASS_403"
if exists 403bypasser; then
  awk '$2==403{print $1}' "$DIRS" | while read -r url; do
    403bypasser -u "$url" -o /tmp/403byp_${DOMAIN}.txt || true
    tail -n +1 /tmp/403byp_${DOMAIN}.txt >> "$BYPASS_403" || true
  done
else
  echo "[!] 403bypasser not installed — skipping 403 bypass step"
fi

# 6) Subdomain takeover (try subjack or skip)
> "$TAKEOVER"
if exists subjack; then
  subjack -w "$TOTAL_SUBS" -t 50 -timeout 30 -o subjack_out.json -silent || true
  if [[ -f subjack_out.json ]]; then
    jq -r '.[] | select(.vulnerable==true) | .domain' subjack_out.json | sort -u > "$TAKEOVER" || true
  fi
else
  echo "[!] subjack not found — skipping takeover checks"
fi

# 7) XSS scanning
> "$XSS_VULN"
if exists dalfox; then
  cat "$PARAMS" | xargs -n1 -P10 -I{} sh -c 'dalfox url "{}" -b 2>/dev/null | grep -E "Vulnerable|XSS" && echo "{}"' >> "$XSS_VULN" || true
else
  echo "[!] dalfox not found — skipping XSS checks"
fi

# 8) SQLi scanning
> "$SQL_VULN"
if [[ "$SKIP_SQLMAP" == false && $(exists sqlmap && echo yes || echo no) == yes ]]; then
  cat "$PARAMS" | while read -r target; do
    # light sqlmap run
    sqlmap -u "$target" --batch --level=1 --risk=1 --output-dir=sqlmap_output-"$DOMAIN" >/dev/null 2>&1 || true
    if [[ -d "sqlmap_output-${DOMAIN}" ]]; then
      echo "$target" >> "$SQL_VULN" || true
    fi
  done
else
  echo "[!] sqlmap skipped or not found — skipping SQLi checks"
fi

# 9) Aggregate
> "$END_VULN"
cat "$XSS_VULN" "$SQL_VULN" "$TAKEOVER" "$BYPASS_403" | sed '/^$/d' | sort -u > "$END_VULN" || true
cp "$END_VULN" "$FINAL_VULN" || true

echo "
[*] Run finished. Outputs saved in: $OUTDIR"
echo "Files created:"
ls -1

exit 0
````

---

## .gitignore (suggested)

```
outputs/
sqlmap_output-*/
*.log
*.tmp
```

---

## LICENSE

MIT by default — add your name and year in the file.

---

## Next steps I prepared for you

1. Git push steps & example commit messages (see chat message accompanying this canvas file).
2. A short resume bullet and repo tagline (see chat message).
3. If you want, I can also produce a zipped repo structure you can download (tell me and I will create files locally and give commands).

---

*This canvas contains a polished README and a CLI-friendly script that gracefully skips missing tools and provides light-mode.*

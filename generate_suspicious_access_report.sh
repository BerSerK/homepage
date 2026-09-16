#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE="${OUTPUT_FILE:-/var/www/html/suspicious-access-report.txt}"
LOG_FILE="${LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-/var/log/nginx}"
LOG_GLOB="${LOG_GLOB:-access.log*}"
IONICE_CLASS="${IONICE_CLASS:-3}"
NICE_LEVEL="${NICE_LEVEL:-15}"
MAX_SAMPLE_LINES="${MAX_SAMPLE_LINES:-5}"

if ! [[ "$MAX_SAMPLE_LINES" =~ ^[0-9]+$ ]] || (( MAX_SAMPLE_LINES < 1 )); then
  echo "ERROR: MAX_SAMPLE_LINES must be a positive integer." >&2
  exit 1
fi

input_files=()

if [[ -n "$LOG_FILE" ]]; then
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "ERROR: LOG_FILE does not exist: $LOG_FILE" >&2
    exit 1
  fi
  input_files=("$LOG_FILE")
else
  mapfile -t input_files < <(find "$LOG_DIR" -maxdepth 1 -type f -name "$LOG_GLOB" | sort -V)
  if [[ ${#input_files[@]} -eq 0 ]]; then
    echo "ERROR: could not find any nginx access logs under $LOG_DIR" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

tmpdir="$(mktemp -d)"
raw_tsv="$tmpdir/suspicious.tsv"
trap 'rm -rf "$tmpdir"' EXIT

stream_logs() {
  if command -v ionice >/dev/null 2>&1; then
    ionice -c "$IONICE_CLASS" nice -n "$NICE_LEVEL" gzip -cdf -- "${input_files[@]}" 2>/dev/null
  else
    nice -n "$NICE_LEVEL" gzip -cdf -- "${input_files[@]}" 2>/dev/null
  fi
}

stream_logs | awk '
function add_hit(severity, category, detail) {
  print severity "\t" category "\t" ip "\t" timestamp "\t" status "\t" method "\t" path "\t" ua "\t" detail;
}

{
  ip = $1;

  if (match($0, /\[([^]]+)\]/, m)) {
    timestamp = m[1];
  } else {
    timestamp = "unknown";
  }

  request = "";
  status = "-";
  ua = "-";

  first_quote = index($0, "\"");
  if (first_quote > 0) {
    rest = substr($0, first_quote + 1);
    second_quote = index(rest, "\"");
    if (second_quote > 0) {
      request = substr(rest, 1, second_quote - 1);
      tail = substr(rest, second_quote + 2);
      split(tail, tail_parts, " ");
      if (tail_parts[1] ~ /^[0-9][0-9][0-9]$/) {
        status = tail_parts[1];
      }
    }
  }

  if (match($0, /"[^"]*" "([^"]*)"$/, ua_match)) {
    ua = ua_match[1];
  }

  split(request, req_parts, " ");
  method = req_parts[1];
  path = req_parts[2];

  if (request == "") {
    next;
  }

  if (request ~ /\\x[0-9A-Fa-f]{2}/ || request ~ /^SSH-2\.0-/ || request ~ /^PRI \* HTTP\/2\.0$/) {
    add_hit("HIGH", "non_http_payload", request);
    next;
  }

  if (path ~ /\/(\.env([._-][^ ?"]*)?|\.git(\/|$)|\.svn(\/|$)|id_rsa|composer\.(json|lock)|\.DS_Store)(\?|$)/) {
    add_hit("HIGH", "secret_or_repo_disclosure", path);
    next;
  }

  if (path ~ /eval-stdin\.php/ || path ~ /invokefunction/ || path ~ /pearcmd/ || request ~ /allow_url_include/ || request ~ /auto_prepend_file/ || request ~ /php:\/\/input/ || path ~ /\/cgi-bin\// && request ~ /(\.\.\/|%2e%2e)/) {
    add_hit("HIGH", "rce_or_traversal", request);
    next;
  }

  if (path ~ /wp_filemanager\.php/ || path ~ /wp-admin\/setup-config\.php/ || path ~ /wp-login\.php/ || path ~ /xmlrpc\.php/ || path ~ /HNAP1(\/)?$/ || path ~ /actuator\/(health|env)(\?|$)/ || path ~ /server-status(\?|$)/ || path ~ /geoserver\/web(\/|\?|$)/ || path ~ /webui(\/|\?|$)/ || path ~ /v1\/(models|completions|embeddings)(\?|$)/ || path ~ /containers\/json(\?|$)/ || path ~ /_profiler\/phpinfo(\?|$)/) {
    add_hit("MEDIUM", "admin_or_vuln_probe", path);
    next;
  }

  if (method ~ /^(CONNECT|PROPFIND)$/) {
    add_hit("MEDIUM", "protocol_abuse", request);
    next;
  }
}
' > "$raw_tsv"

{
  echo "Suspicious Access Report"
  echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "Log files scanned: ${#input_files[@]}"
  echo "Output file: $OUTPUT_FILE"
  echo

  if [[ ! -s "$raw_tsv" ]]; then
    echo "No suspicious access patterns matched the current rules."
    exit 0
  fi

  total_hits="$(wc -l < "$raw_tsv" | tr -d ' ')"
  echo "Total suspicious hits: $total_hits"
  echo

  echo "By severity"
  cut -f1 "$raw_tsv" | sort | uniq -c | sort -nr | sed "s/^ *//"
  echo

  echo "By category"
  cut -f1-2 "$raw_tsv" | sort | uniq -c | sort -nr | sed "s/^ *//"
  echo

  echo "Top source IPs"
  cut -f3 "$raw_tsv" | sort | uniq -c | sort -nr | head -n 20 | sed "s/^ *//"
  echo

  echo "Top target paths"
  cut -f7 "$raw_tsv" | sort | uniq -c | sort -nr | head -n 20 | sed "s/^ *//"
  echo

  echo "Date range of suspicious hits"
  cut -f4 "$raw_tsv" | awk -F: '{print $1}' | sort | uniq -c | sed "s/^ *//"
  echo

  for category in $(cut -f2 "$raw_tsv" | sort -u); do
    echo "Sample hits: $category"
    awk -F'\t' -v category="$category" -v limit="$MAX_SAMPLE_LINES" '
      $2 == category {
        printf("- [%s] ip=%s status=%s method=%s path=%s ua=%s\n", $4, $3, $5, $6, $7, $8);
        count++;
        if (count >= limit) exit;
      }
    ' "$raw_tsv"
    echo
  done
} > "$OUTPUT_FILE"

echo "Generated $OUTPUT_FILE from ${#input_files[@]} log file(s)"
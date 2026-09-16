#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE="${OUTPUT_FILE:-/var/www/html/nginx-report.html}"
LOG_FILE="${LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-/var/log/nginx}"
LOG_FORMAT="${LOG_FORMAT:-COMBINED}"
DATE_FORMAT="${DATE_FORMAT:-%d/%b/%Y}"
TIME_FORMAT="${TIME_FORMAT:-%T}"
REPORT_TITLE="${REPORT_TITLE:-Nginx Access Report}"
REAL_TIME_HTML="${REAL_TIME_HTML:-false}"
LOG_GLOB="${LOG_GLOB:-access.log*}"
DECOMPRESS_NICE_LEVEL="${DECOMPRESS_NICE_LEVEL:-15}"
IONICE_CLASS="${IONICE_CLASS:-3}"
GOACCESS_NICE_LEVEL="${GOACCESS_NICE_LEVEL:-10}"
GOACCESS_IONICE_CLASS="${GOACCESS_IONICE_CLASS:-3}"
NO_GLOBAL_CONFIG="${NO_GLOBAL_CONFIG:-true}"
MAX_COMPRESSED_FILES="${MAX_COMPRESSED_FILES:-}"
RUN_WITH_NOHUP="${RUN_WITH_NOHUP:-auto}"
NOHUP_LOG_FILE="${NOHUP_LOG_FILE:-/tmp/generate_nginx_report.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/generate_nginx_report.lock}"

if ! command -v flock >/dev/null 2>&1; then
  echo "ERROR: flock is not installed or not in PATH." >&2
  exit 1
fi

if [[ -z "${GENERATE_NGINX_REPORT_NOHUP:-}" ]] && command -v nohup >/dev/null 2>&1; then
  if [[ "$RUN_WITH_NOHUP" == "always" || ( "$RUN_WITH_NOHUP" == "auto" && -t 1 ) ]]; then
    if ! flock -n "$LOCK_FILE" true; then
      echo "Another generate_nginx_report.sh process is already running. Lock: $LOCK_FILE"
      exit 0
    fi

    mkdir -p "$(dirname "$NOHUP_LOG_FILE")"
    nohup flock -n "$LOCK_FILE" env GENERATE_NGINX_REPORT_NOHUP=1 GENERATE_NGINX_REPORT_LOCKED=1 "$0" "$@" >> "$NOHUP_LOG_FILE" 2>&1 &
    echo "Started in background (PID $!), log: $NOHUP_LOG_FILE"
    exit 0
  fi
fi

if [[ -z "${GENERATE_NGINX_REPORT_LOCKED:-}" ]]; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "Another generate_nginx_report.sh process is already running. Lock: $LOCK_FILE"
    exit 0
  fi
fi

if ! command -v goaccess >/dev/null 2>&1; then
  echo "ERROR: goaccess is not installed or not in PATH." >&2
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

if [[ -n "$MAX_COMPRESSED_FILES" ]]; then
  if ! [[ "$MAX_COMPRESSED_FILES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: MAX_COMPRESSED_FILES must be a non-negative integer." >&2
    exit 1
  fi

  plain_candidates=()
  compressed_candidates=()

  for input_file in "${input_files[@]}"; do
    case "$input_file" in
      *.gz)
        compressed_candidates+=("$input_file")
        ;;
      *)
        plain_candidates+=("$input_file")
        ;;
    esac
  done

  if (( MAX_COMPRESSED_FILES == 0 )); then
    input_files=("${plain_candidates[@]}")
  elif (( ${#compressed_candidates[@]} > MAX_COMPRESSED_FILES )); then
    input_files=("${plain_candidates[@]}" "${compressed_candidates[@]: -MAX_COMPRESSED_FILES}")
  fi
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

decompress_cmd=(gzip -cdf --)
goaccess_cmd=(
  goaccess -
  --log-format="$LOG_FORMAT"
  --date-format="$DATE_FORMAT"
  --time-format="$TIME_FORMAT"
  --html-report-title="$REPORT_TITLE"
  --ignore-crawlers
  -o "$OUTPUT_FILE"
)

if [[ "$NO_GLOBAL_CONFIG" == "true" ]]; then
  goaccess_cmd+=(--no-global-config)
fi

if [[ "$REAL_TIME_HTML" == "true" ]]; then
  goaccess_cmd+=(--real-time-html)
fi

run_decompress() {
  if command -v ionice >/dev/null 2>&1; then
    ionice -c "$IONICE_CLASS" nice -n "$DECOMPRESS_NICE_LEVEL" "${decompress_cmd[@]}" "$@"
  else
    nice -n "$DECOMPRESS_NICE_LEVEL" "${decompress_cmd[@]}" "$@"
  fi
}

run_goaccess() {
  if command -v ionice >/dev/null 2>&1; then
    ionice -c "$GOACCESS_IONICE_CLASS" nice -n "$GOACCESS_NICE_LEVEL" "${goaccess_cmd[@]}"
  else
    nice -n "$GOACCESS_NICE_LEVEL" "${goaccess_cmd[@]}"
  fi
}

run_decompress "${input_files[@]}" | run_goaccess

echo "Generated $OUTPUT_FILE from ${#input_files[@]} log file(s)"
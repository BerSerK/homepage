#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE="${OUTPUT_FILE:-/var/www/html/nginx-report.html}"
LOG_FILE="${LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-/var/log/nginx}"
LOG_FORMAT="${LOG_FORMAT:-COMBINED}"
DATE_FORMAT="${DATE_FORMAT:-%d/%b/%Y}"
TIME_FORMAT="${TIME_FORMAT:-%T}"
REPORT_TITLE="${REPORT_TITLE:-Nginx Access Report}"
REAL_TIME_HTML="${REAL_TIME_HTML:-true}"
LOG_GLOB="${LOG_GLOB:-access.log*}"
DECOMPRESS_NICE_LEVEL="${DECOMPRESS_NICE_LEVEL:-15}"
IONICE_CLASS="${IONICE_CLASS:-3}"
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
plain_files=()
compressed_files=()

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

for input_file in "${input_files[@]}"; do
  case "$input_file" in
    *.gz)
      compressed_files+=("$input_file")
      ;;
    *)
      plain_files+=("$input_file")
      ;;
  esac
done

if [[ -n "$MAX_COMPRESSED_FILES" ]]; then
  if ! [[ "$MAX_COMPRESSED_FILES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: MAX_COMPRESSED_FILES must be a non-negative integer." >&2
    exit 1
  fi

  if (( MAX_COMPRESSED_FILES == 0 )); then
    compressed_files=()
  elif (( ${#compressed_files[@]} > MAX_COMPRESSED_FILES )); then
    compressed_files=("${compressed_files[@]: -MAX_COMPRESSED_FILES}")
  fi
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

stream_logs() {
  local input_file

  for input_file in "${plain_files[@]}"; do
    cat "$input_file"
  done

  for input_file in "${compressed_files[@]}"; do
    if command -v ionice >/dev/null 2>&1; then
      ionice -c "$IONICE_CLASS" nice -n "$DECOMPRESS_NICE_LEVEL" gzip -dc "$input_file"
    else
      nice -n "$DECOMPRESS_NICE_LEVEL" gzip -dc "$input_file"
    fi
  done
}

if [[ "$REAL_TIME_HTML" == "true" ]]; then
  stream_logs | goaccess - \
    --log-format="$LOG_FORMAT" \
    --date-format="$DATE_FORMAT" \
    --time-format="$TIME_FORMAT" \
    --html-report-title="$REPORT_TITLE" \
    --ignore-crawlers \
    --real-time-html \
    -o "$OUTPUT_FILE"
else
  stream_logs | goaccess - \
    --log-format="$LOG_FORMAT" \
    --date-format="$DATE_FORMAT" \
    --time-format="$TIME_FORMAT" \
    --html-report-title="$REPORT_TITLE" \
    --ignore-crawlers \
    -o "$OUTPUT_FILE"
fi

echo "Generated $OUTPUT_FILE from $((${#plain_files[@]} + ${#compressed_files[@]})) log file(s)"
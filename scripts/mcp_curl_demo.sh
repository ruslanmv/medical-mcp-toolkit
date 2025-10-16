#!/usr/bin/env bash
# ==============================================================================
# mcp_curl_demo.sh — Production-ready curl demo for medical-mcp-toolkit
#
# Cross-platform: Linux/macOS + Windows (Git Bash).
#
# Demonstrates BOTH:
#   1) SSE JSON-RPC flow (MCP)   → MODE=sse  (default)
#   2) HTTP REST smoke tests      → MODE=http
#
# Environment variables (optional):
#   MODE=sse|http                 # which demo to run (default: sse)
#   BASE=http://localhost:9090    # server base
#   TOKEN=dev-token               # bearer token (if your server enforces auth)
#
#   # Tool call customization
#   CALL_TOOL=triageSymptoms|calcClinicalScores|getPatient|getPatient360|getDrugInfo|none
#   PATIENT_KEY=demo-001
#   DRUG_NAME=Lisinopril
#
#   # SSE (MCP) options
#   SSE_PATH=/sse
#   SSE_TIMEOUT=30                # not heavily used now (we keep reader open)
#   PROTOCOL_VERSION=2024-11-05
#   DEBUG=0                       # 1 = curl -v
#   RETRY_TOGGLE_TRAILING_SLASH=1 # toggle trailing / on 404
#   RETRY_BASE_MESSAGES=1         # retry /messages if /sse/messages 404s
#   KEEP_OPEN=1                   # keep SSE reader alive at end (Ctrl+C to exit)
#
# Usage:
#   ./scripts/mcp_curl_demo.sh
#   MODE=http ./scripts/mcp_curl_demo.sh
#   CALL_TOOL=getPatient PATIENT_KEY=demo-002 ./scripts/mcp_curl_demo.sh
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ---------------------------
# Global defaults / settings
# ---------------------------
MODE="${MODE:-sse}"                 # sse | http
BASE="${BASE:-http://localhost:9090}"
TOKEN="${TOKEN:-}"

# Tool call params
CALL_TOOL="${CALL_TOOL:-triageSymptoms}"
PATIENT_KEY="${PATIENT_KEY:-demo-001}"
DRUG_NAME="${DRUG_NAME:-Lisinopril}"

# SSE / JSON-RPC params
SSE_PATH="${SSE_PATH:-/sse}"
SSE_TIMEOUT="${SSE_TIMEOUT:-30}"
PROTOCOL_VERSION="${PROTOCOL_VERSION:-2024-11-05}"
DEBUG="${DEBUG:-0}"
RETRY_TOGGLE_TRAILING_SLASH="${RETRY_TOGGLE_TRAILING_SLASH:-1}"
RETRY_BASE_MESSAGES="${RETRY_BASE_MESSAGES:-1}"
KEEP_OPEN="${KEEP_OPEN:-1}"

# ---------------------------
# Helpers
# ---------------------------
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

pretty(){
  # Pretty-print JSON if jq or python is available; otherwise just cat.
  if have_cmd jq; then
    local buf; buf="$(cat || true)"
    if printf '%s' "$buf" | jq . >/dev/null 2>&1; then
      printf '%s' "$buf" | jq .
    else
      printf '%s' "$buf"
    fi
  elif have_cmd python3; then
    local buf; buf="$(cat || true)"
    if printf '%s' "$buf" | python3 -m json.tool >/dev/null 2>&1; then
      printf '%s' "$buf" | python3 -m json.tool
    else
      printf '%s' "$buf"
    fi
  else
    cat
  fi
}

say(){ printf '%s\n' "$*"; }
hr(){ printf '%s\n' "----------------------------------------------------------------"; }

usage(){
  cat <<'USAGE'
Usage:
  ./scripts/mcp_curl_demo.sh                # Default MODE=sse
  MODE=http ./scripts/mcp_curl_demo.sh      # Use HTTP smoke tests

Env Vars:
  MODE=sse|http
  BASE=http://localhost:9090
  TOKEN=dev-token

Tool call customization:
  CALL_TOOL=triageSymptoms|calcClinicalScores|getPatient|getPatient360|getDrugInfo|none
  PATIENT_KEY=demo-001
  DRUG_NAME=Lisinopril

SSE-specific:
  SSE_PATH=/sse
  SSE_TIMEOUT=30
  PROTOCOL_VERSION=2024-11-05
  DEBUG=0
  RETRY_TOGGLE_TRAILING_SLASH=1
  RETRY_BASE_MESSAGES=1
  KEEP_OPEN=1   # keep the SSE reader running at the end (Ctrl+C to stop)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# -----------------------------------------
# HTTP REST mode (simple smoke test suite)
# -----------------------------------------
http_smoke(){
  local base_url token payload
  base_url="${BASE%/}"
  token="${TOKEN:-}"

  say "HTTP SMOKE TESTS against ${base_url}"
  hr

  say "→ GET /health"
  if have_cmd jq; then
    curl -sS "${base_url}/health" | jq -R .
  else
    curl -sS "${base_url}/health"
    echo ""
  fi
  hr

  say "→ GET /tools"
  if [[ -n "$token" ]]; then
    curl -sS -H "Authorization: Bearer ${token}" "${base_url}/tools" | pretty
  else
    say "⚠️  TOKEN not set; /tools may fail if auth is enforced."
    curl -sS "${base_url}/tools" | pretty || true
  fi
  hr

  say "→ GET /schema"
  if [[ -n "$token" ]]; then
    curl -sS -H "Authorization: Bearer ${token}" "${base_url}/schema" | pretty
  else
    say "⚠️  TOKEN not set; /schema may fail if auth is enforced."
    curl -sS "${base_url}/schema" | pretty || true
  fi
  hr

  say "→ POST /invoke ${CALL_TOOL}"
  case "${CALL_TOOL}" in
    triageSymptoms)
      payload='{"tool":"triageSymptoms","args":{"age":45,"sex":"male","symptoms":["chest pain","sweating"],"duration_text":"2 hours"}}'
      ;;
    getPatient)
      payload="{\"tool\":\"getPatient\",\"args\":{\"patient_key\":\"${PATIENT_KEY}\"}}"
      ;;
    getPatient360)
      payload="{\"tool\":\"getPatient360\",\"args\":{\"patient_key\":\"${PATIENT_KEY}\"}}"
      ;;
    getDrugInfo)
      payload="{\"tool\":\"getDrugInfo\",\"args\":{\"drug_name\":\"${DRUG_NAME}\"}}"
      ;;
    *)
      say "⚠️  CALL_TOOL='${CALL_TOOL}' not configured for HTTP mode in this script. Skipping /invoke test."
      payload=""
      ;;
  esac

  if [[ -n "$payload" ]]; then
    if [[ -n "$token" ]]; then
      curl -sS -X POST "${base_url}/invoke" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${payload}" | pretty
    else
      say "⚠️  TOKEN not set; /invoke may fail if auth is enforced."
      curl -sS -X POST "${base_url}/invoke" \
        -H "Content-Type: application/json" \
        -d "${payload}" | pretty || true
    fi
  fi
  hr

  say "✅ HTTP smoke tests complete."
}

# -----------------------------------------
# SSE JSON-RPC mode (keeps reader open)
# -----------------------------------------
sse_jsonrpc(){
  local BASE_URL HDR_AUTH CURL_V SSE_LOG SESSION_PATH_OR_URL SESSION_URL SSE_PID LISTENER_PID

  BASE_URL="${BASE%/}${SSE_PATH}"
  HDR_AUTH=()
  [[ -n "$TOKEN" ]] && HDR_AUTH=(-H "Authorization: Bearer ${TOKEN}")
  CURL_V=()
  [[ "$DEBUG" == "1" ]] && CURL_V=(-v)

  # Utilities for POST retries
  toggle_trailing_slash(){
    local url="$1" base qs
    if [[ "$url" == *\?* ]]; then
      base="${url%%\?*}"; qs="${url#*\?}"
      if [[ "$base" == */ ]]; then base="${base%/}"; else base="${base}/"; fi
      printf '%s?%s' "$base" "$qs"
    else
      if [[ "$url" == */ ]]; then printf '%s' "${url%/}"; else printf '%s/' "$url"; fi
    fi
  }
  swap_to_root_messages(){
    local url="$1" base qs
    if [[ "$url" == *\?* ]]; then base="${url%%\?*}"; qs="${url#*\?}"; else base="$url"; qs=""; fi
    base="${base%/}"
    base="${base/\/sse\/messages/\/messages}"
    if [[ -n "$qs" ]]; then printf '%s?%s' "$base" "$qs"; else printf '%s' "$base"; fi
  }

  # Start long-lived SSE reader to a growing log file
  SSE_LOG="$(mktemp 2>/dev/null || printf '.mcp_sse_%s.log' "$$")"
  say "→ Opening SSE at ${BASE_URL} (reader stays open; results will appear below)..."
  ( curl "${CURL_V[@]}" -s -N --no-buffer \
        -H 'Accept: text/event-stream' "${HDR_AUTH[@]}" "${BASE_URL}" \
      || true ) > "${SSE_LOG}" &
  SSE_PID=$!

  cleanup(){
    # stop background processes and remove temp files
    [[ -n "${LISTENER_PID-}" ]] && kill "${LISTENER_PID}" >/dev/null 2>&1 || true
    [[ -n "${SSE_PID-}" ]] && kill "${SSE_PID}" >/dev/null 2>&1 || true
    [[ -f "${SSE_LOG-}" ]] && rm -f -- "${SSE_LOG}" || true
  }
  trap cleanup EXIT INT TERM

  # Wait for the first data: line (writer URL)
  for _ in $(seq 1 300); do
    if grep -q '^data: ' "${SSE_LOG}" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  # Extract writer URL
  SESSION_PATH_OR_URL="$(awk -F': ' '/^data: /{ sub(/^data: /,""); gsub(/\r$/,""); print; exit }' "${SSE_LOG}" || true)"
  if [[ -z "${SESSION_PATH_OR_URL}" ]]; then
    say "❌ No writer URL received from SSE."
    exit 1
  fi

  # Normalize to absolute URL
  if [[ "${SESSION_PATH_OR_URL}" =~ ^https?:// ]]; then
    SESSION_URL="${SESSION_PATH_OR_URL}"
  elif [[ "${SESSION_PATH_OR_URL}" == /* ]]; then
    SESSION_URL="${BASE%/}${SESSION_PATH_OR_URL}"
  else
    SESSION_URL="${BASE%/}/${SESSION_PATH_OR_URL}"
  fi

  say "✅ SSE writer URL: ${SESSION_URL}"
  hr

  # Live listener: follow SSE_LOG and print each subsequent "data: ..." line payload
  (
    tail -n +1 -F "${SSE_LOG}" 2>/dev/null \
    | awk '/^data: /{ sub(/^data: /,""); gsub(/\r$/,""); print; fflush(); }' \
    | while IFS= read -r payload; do
        # Pretty print entire event if possible
        if have_cmd jq && printf '%s' "$payload" | jq . >/dev/null 2>&1; then
          printf '%s\n' "$payload" | jq .
          # If this is tools/list reply (id==1), print just tool names
          printf '%s\n' "$payload" \
            | jq -r 'select(.id==1 and .result and .result.tools) | .result.tools[]?.name' 2>/dev/null \
            | awk 'NF{print "• " $0}'
        else
          printf '%s\n' "$payload"
        fi
      done
  ) &
  LISTENER_PID=$!

  # POST JSON with retries and slash toggles (SSE writer returns typically 202)
  curl_post_json(){
    local url="$1" json="$2"
    local body used_url code
    body="$(mktemp 2>/dev/null || printf '.mcp_curl_body_%s' "$$")"
    trap '[[ -n "${body-}" && -f "${body-}" ]] && rm -f -- "${body}" || true' RETURN

    used_url="$url"
    code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                -X POST "$used_url" -H 'Content-Type: application/json' \
                "${HDR_AUTH[@]}" -d "$json")"

    if [[ "$code" == "404" && "$RETRY_TOGGLE_TRAILING_SLASH" == "1" ]]; then
      local alt; alt="$(toggle_trailing_slash "$used_url")"
      say "↻ 404 from $used_url — retrying $alt"
      used_url="$alt"
      code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                  -X POST "$used_url" -H 'Content-Type: application/json' \
                  "${HDR_AUTH[@]}" -d "$json")"
    fi

    if [[ "$code" == "404" && "$RETRY_BASE_MESSAGES" == "1" ]]; then
      local alt2; alt2="$(swap_to_root_messages "$url")"
      if [[ "$alt2" != "$url" ]]; then
        say "↻ 404 from $used_url — retrying base-path $alt2"
        used_url="$alt2"
        code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                    -X POST "$used_url" -H 'Content-Type: application/json' \
                    "${HDR_AUTH[@]}" -d "$json")"
        if [[ "$code" == "404" ]]; then
          local alt2b; alt2b="$(toggle_trailing_slash "$used_url")"
          say "↻ 404 from $used_url — retrying $alt2b"
          used_url="$alt2b"
          code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                      -X POST "$used_url" -H 'Content-Type: application/json' \
                      "${HDR_AUTH[@]}" -d "$json")"
        fi
      fi
    fi

    if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
      SESSION_URL="$used_url"
    fi

    say "↪ HTTP ${code} ${used_url}" >&2
    cat "$body"
  }

  rpc(){ curl_post_json "${SESSION_URL}" "$1"; }

  # Initialize session
  say "→ JSON-RPC: initialize"
  rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"${PROTOCOL_VERSION}\",\"capabilities\":{},\"clientInfo\":{\"name\":\"curl\",\"version\":\"8\"}}}" >/dev/null
  sleep 0.2
  hr

  # List tools
  # FIX #1: Changed params from {} to null, as some servers are strict.
  say "→ JSON-RPC: tools/list"
  rpc '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":null}' >/dev/null
  sleep 0.2
  hr

  # Optional example tool call
  # FIX #2: Changed "arguments" key to "args" to match server expectation.
  case "${CALL_TOOL}" in
    triageSymptoms)
      say "→ JSON-RPC: tools/call triageSymptoms"
      rpc '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"triageSymptoms","args":{"age":45,"sex":"male","symptoms":["chest pain","sweating"],"duration_text":"2 hours"}}}' >/dev/null
      ;;
    calcClinicalScores)
      say "→ JSON-RPC: tools/call calcClinicalScores"
      rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"calcClinicalScores","args":{"age":40,"sex":"male","weight_kg":80,"height_cm":180,"serum_creatinine_mg_dl":1.0}}}' >/dev/null
      ;;
    getPatient)
      say "→ JSON-RPC: tools/call getPatient (key=${PATIENT_KEY})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"getPatient\",\"args\":{\"patient_key\":\"${PATIENT_KEY}\"}}}" >/dev/null
      ;;
    getPatient360)
      say "→ JSON-RPC: tools/call getPatient360 (key=${PATIENT_KEY})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"getPatient360\",\"args\":{\"patient_key\":\"${PATIENT_KEY}\"}}}" >/dev/null
      ;;
    getDrugInfo)
      say "→ JSON-RPC: tools/call getDrugInfo (drug=${DRUG_NAME})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"getDrugInfo\",\"args\":{\"drug_name\":\"${DRUG_NAME}\"}}}" >/dev/null
      ;;
    none|"")
      say "Skipping tools/call (CALL_TOOL is 'none' or unset)."
      ;;
    *)
      say "⚠️  CALL_TOOL '${CALL_TOOL}' is not a built-in example in this script; skipping extra tools/call."
      ;;
  esac
  hr

  say "✅ SSE JSON-RPC flow started. Results are streaming above."
  if [[ "${KEEP_OPEN}" == "1" ]]; then
    say "ℹ️  Press Ctrl+C to stop the SSE listener."
    # Wait indefinitely for background listener; the trap will handle cleanup.
    wait
  else
    # Give a brief window for results to print, then exit cleanly
    sleep 2
  fi
}

# ---------------------------
# Main
# ---------------------------
case "${MODE}" in
  http) http_smoke ;;
  sse)  sse_jsonrpc ;;
  *)
    say "❌ Unknown MODE='${MODE}'. Use MODE=sse or MODE=http."
    usage
    exit 1
    ;;
esac
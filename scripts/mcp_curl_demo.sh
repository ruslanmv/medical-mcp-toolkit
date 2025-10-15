#!/usr/bin/env bash
# ==============================================================================
# mcp_curl_demo.sh — Production-ready curl demo for medical-mcp-toolkit
#
# Cross-platform: works on Linux/macOS and Windows (Git Bash).
# Demonstrates BOTH:
#   1) SSE JSON-RPC flow (MCP)   → MODE=sse  (default)
#   2) HTTP REST smoke tests      → MODE=http
#
# Customize via environment variables (all optional):
#   MODE=sse|http
#   BASE=http://localhost:9090
#   TOKEN=dev-token
#
#   # Tool call customization
#   CALL_TOOL=triageSymptoms|calcClinicalScores|getPatient|getPatient360|getDrugInfo|none
#   PATIENT_KEY=demo-001
#   DRUG_NAME=Lisinopril
#
#   # SSE (MCP) options
#   SSE_PATH=/sse
#   SSE_TIMEOUT=30
#   PROTOCOL_VERSION=2024-11-05
#   DEBUG=0                       # 1 = curl -v
#   RETRY_TOGGLE_TRAILING_SLASH=1 # Try toggling trailing slash on 404
#   RETRY_BASE_MESSAGES=1         # Try /messages if /sse/messages 404s
#
# Usage:
#   # Run default SSE triage demo
#   ./scripts/mcp_curl_demo.sh
#
#   # Run SSE demo to fetch a patient record
#   CALL_TOOL=getPatient PATIENT_KEY=demo-002 ./scripts/mcp_curl_demo.sh
#
#   # Run HTTP smoke test, invoking the getDrugInfo tool
#   MODE=http CALL_TOOL=getDrugInfo DRUG_NAME=Aspirin ./scripts/mcp_curl_demo.sh
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

# ---------------------------
# Helpers
# ---------------------------
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

# Pretty-print JSON if jq or python is available; otherwise just cat.
pretty(){
  if have_cmd jq; then
    local buf; buf="$(cat || true)"
    # If it's JSON, pretty print; else output raw.
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
      payload='{
        "tool": "triageSymptoms",
        "args": { "age": 45, "sex": "male", "symptoms": ["chest pain","sweating"], "duration_text": "2 hours" }
      }'
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
# SSE JSON-RPC mode
# -----------------------------------------
sse_jsonrpc(){
  local BASE_URL HDR_AUTH CURL_V

  BASE_URL="${BASE%/}${SSE_PATH}"
  HDR_AUTH=()
  [[ -n "$TOKEN" ]] && HDR_AUTH=(-H "Authorization: Bearer ${TOKEN}")
  CURL_V=()
  [[ "$DEBUG" == "1" ]] && CURL_V=(-v)

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

  # Replace '/sse/messages' base with '/messages' (preserve query string).
  swap_to_root_messages(){
    local url="$1" base qs
    if [[ "$url" == *\?* ]]; then
      base="${url%%\?*}"; qs="${url#*\?}"
    else
      base="$url"; qs=""
    fi
    base="${base%/}"  # strip trailing /
    base="${base/\/sse\/messages/\/messages}"
    if [[ -n "$qs" ]]; then printf '%s?%s' "$base" "$qs"; else printf '%s' "$base"; fi
  }

  get_session_url(){
    local endpoint
    set +o pipefail
    endpoint="$(
      curl "${CURL_V[@]}" -s -N --no-buffer --max-time "${SSE_TIMEOUT}" \
           -H 'Accept: text/event-stream' "${HDR_AUTH[@]}" "${BASE_URL}" 2>/dev/null \
      | awk -F': ' '/^data: /{sub(/^data: /,"");gsub(/\r$/,"");print;exit;}'
    )"
    local curl_status=${PIPESTATUS[0]}
    set -o pipefail
    [[ ${curl_status} -ne 0 && -z "${endpoint}" ]] && return ${curl_status}
    printf '%s' "${endpoint}"
  }

  say "→ Opening SSE at ${BASE_URL} to get session writer URL..."
  local SESSION_PATH_OR_URL
  SESSION_PATH_OR_URL="$(get_session_url || true)"
  [[ -z "${SESSION_PATH_OR_URL}" ]] && { say "❌ No SSE endpoint returned a writer URL"; exit 1; }

  # Normalize to absolute URL
  local SESSION_URL
  if [[ "${SESSION_PATH_OR_URL}" =~ ^https?:// ]]; then
    SESSION_URL="${SESSION_PATH_OR_URL}"
  elif [[ "${SESSION_PATH_OR_URL}" == /* ]]; then
    SESSION_URL="${BASE%/}${SESSION_PATH_OR_URL}"
  else
    SESSION_URL="${BASE%/}/${SESSION_PATH_OR_URL}"
  fi

  say "✅ SSE writer URL: ${SESSION_URL}"
  hr

  # POST JSON with retries and slash toggles
  curl_post_json(){
    local url="$1" json="$2"
    local body used_url code
    body="$(mktemp 2>/dev/null || printf '%s' ".mcp_curl_body.$$")"
    trap '[[ -n "${body-}" && -f "${body-}" ]] && rm -f -- "${body}" || true' RETURN

    used_url="$url"
    # -L follows 307/308 so we land on /messages/ if server redirects
    code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                -X POST "$used_url" -H 'Content-Type: application/json' \
                "${HDR_AUTH[@]}" -d "$json")"

    # 1) trailing-slash retry (only if still 404 after following redirects)
    if [[ "$code" == "404" && "$RETRY_TOGGLE_TRAILING_SLASH" == "1" ]]; then
      local alt; alt="$(toggle_trailing_slash "$used_url")"
      say "↻ 404 from $used_url — retrying $alt"
      used_url="$alt"
      code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                  -X POST "$used_url" -H 'Content-Type: application/json' \
                  "${HDR_AUTH[@]}" -d "$json")"
    fi

    # 2) base-path retry: /sse/messages → /messages (preserve qs)
    if [[ "$code" == "404" && "$RETRY_BASE_MESSAGES" == "1" ]]; then
      local alt2; alt2="$(swap_to_root_messages "$url")"
      if [[ "$alt2" != "$url" ]]; then
        say "↻ 404 from $used_url — retrying base-path $alt2"
        used_url="$alt2"
        code="$(curl "${CURL_V[@]}" -sS -L -o "$body" -w "%{http_code}" \
                    -X POST "$used_url" -H 'Content-Type: application/json' \
                    "${HDR_AUTH[@]}" -d "$json")"
        # If that ALSO 404s, try toggling slash on the /messages variant
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

    # If we finally succeeded, persist the working URL for subsequent calls
    if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
      SESSION_URL="$used_url"
    fi

    say "↪ HTTP ${code} ${used_url}" >&2
    cat "$body"
  }

  rpc(){ curl_post_json "${SESSION_URL}" "$1"; }

  say "→ JSON-RPC: initialize"
  rpc "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"${PROTOCOL_VERSION}\",\"capabilities\":{},\"clientInfo\":{\"name\":\"curl\",\"version\":\"8\"}}}" | pretty
  
  # ✅ FIX: Add a delay to allow the server to process initialization.
  sleep 1
  hr

  say "→ JSON-RPC: tools/list"
  local TOOLS_JSON
  TOOLS_JSON="$(rpc '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')"
  printf '%s' "$TOOLS_JSON" | pretty

  # ✅ FIX: Add a small delay before the next call.
  sleep 1
  hr

  if have_cmd jq; then
    say "Tools available:"
    printf '%s' "$TOOLS_JSON" | jq -r '.result.tools[]?.name' 2>/dev/null || say "(Could not parse tools list)"
    hr
  fi

  case "${CALL_TOOL}" in
    triageSymptoms)
      say "→ JSON-RPC: tools/call triageSymptoms"
      rpc '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"triageSymptoms","arguments":{"age":45,"sex":"male","symptoms":["chest pain","sweating"],"duration_text":"2 hours"}}}' | pretty
      ;;
    calcClinicalScores)
      say "→ JSON-RPC: tools/call calcClinicalScores"
      rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"calcClinicalScores","arguments":{"age":40,"sex":"male","weight_kg":80,"height_cm":180,"serum_creatinine_mg_dl":1.0}}}' | pretty
      ;;
    getPatient)
      say "→ JSON-RPC: tools/call getPatient (key=${PATIENT_KEY})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"getPatient\",\"arguments\":{\"patient_key\":\"${PATIENT_KEY}\"}}}" | pretty
      ;;
    getPatient360)
      say "→ JSON-RPC: tools/call getPatient360 (key=${PATIENT_KEY})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"getPatient360\",\"arguments\":{\"patient_key\":\"${PATIENT_KEY}\"}}}" | pretty
      ;;
    getDrugInfo)
      say "→ JSON-RPC: tools/call getDrugInfo (drug=${DRUG_NAME})"
      rpc "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"getDrugInfo\",\"arguments\":{\"drug_name\":\"${DRUG_NAME}\"}}}" | pretty
      ;;
    none|"")
      say "Skipping tools/call (CALL_TOOL is 'none' or unset)."
      ;;
    *)
      say "⚠️  CALL_TOOL '${CALL_TOOL}' is not a built-in example in this script."
      say "    The script will not attempt a tools/call RPC."
      ;;
  esac
  hr

  say "✅ SSE JSON-RPC flow complete."
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
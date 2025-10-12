#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

BASE="${BASE:-http://localhost:9090}"
SSE_PATH="${SSE_PATH:-/sse}"
TOKEN="${TOKEN:-}"
CALL_TOOL="${CALL_TOOL:-triageSymptoms}"
SSE_TIMEOUT="${SSE_TIMEOUT:-30}"
PROTOCOL_VERSION="${PROTOCOL_VERSION:-2024-11-05}"
RETRY_TOGGLE_TRAILING_SLASH="${RETRY_TOGGLE_TRAILING_SLASH:-1}"
RETRY_BASE_MESSAGES="${RETRY_BASE_MESSAGES:-1}"     # try /messages if /sse/messages fails
DEBUG="${DEBUG:-0}"  # 1 = curl -v

case "${CALL_TOOL}" in
  triageSymptoms|calcClinicalScores|none|"") ;; *) echo "⚠️  Unknown CALL_TOOL"; CALL_TOOL="none" ;; esac

BASE_URL="${BASE%/}${SSE_PATH}"
HDR_AUTH=()
[[ -n "$TOKEN" ]] && HDR_AUTH=(-H "Authorization: Bearer ${TOKEN}")
CURL_V=()
[[ "$DEBUG" == "1" ]] && CURL_V=(-v)

jq_ok(){ command -v jq >/dev/null 2>&1; }
pretty(){
  if jq_ok; then
    local buf; buf="$(cat || true)"; local lead
    lead="$(printf '%s' "$buf" | sed -E 's/^[[:space:]]+//')"
    if [[ -z "$lead" ]]; then printf '%s' "$buf"
    elif [[ "$lead" =~ ^[\{\[] ]]; then printf '%s' "$buf" | jq
    else printf '%s' "$buf"; fi
  else cat; fi
}
say(){ printf '%s\n' "$*"; }
hr(){ printf '%s\n' "----------------------------------------------------------------"; }

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
SESSION_PATH_OR_URL="$(get_session_url || true)"
[[ -z "${SESSION_PATH_OR_URL}" ]] && { say "❌ No SSE endpoint"; exit 1; }

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

curl_post_json(){
  local url="$1" json="$2"
  local body used_url code
  body="$(mktemp)"
  trap '[[ -n "${body-}" ]] && rm -f -- "${body}" || true' RETURN

  used_url="$url"
  # IMPORTANT: -L follows 307/308 so we land on /messages/ if server redirects
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
hr

say "→ JSON-RPC: tools/list"
TOOLS_JSON="$(rpc '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')"
printf '%s' "$TOOLS_JSON" | pretty
hr

if jq_ok; then
  say "Tools available:"
  printf '%s' "$TOOLS_JSON" | jq -r '.result.tools[]?.name' 2>/dev/null || true
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
  none|"")
    say "Skipping tools/call (CALL_TOOL=none)."
    ;;
esac

say "✅ Done."

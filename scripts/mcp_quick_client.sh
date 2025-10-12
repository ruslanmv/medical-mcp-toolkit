#!/usr/bin/env bash
set -euo pipefail

# Minimal sanity test for the MCP SSE server:
#  - Always spin up a temp server on a free port (9091+)
#  - Wait until TCP is accepting connections
#  - Run the Python MCP client: list-tools
#  - Print tail of logs on failure, then clean up

CLIENT_TIMEOUT_RAW="${CLIENT_TIMEOUT:-30}"
LOG_FILE="${LOG_FILE:-.run/server.log}"
PID_FILE="${PID_FILE:-.run/server.pid}"

RUN_DIR="$(dirname "${LOG_FILE}")"
mkdir -p "${RUN_DIR}"

# sanitize timeout to integer seconds
CLIENT_TIMEOUT="${CLIENT_TIMEOUT_RAW%%[!0-9]*}"
[ -z "${CLIENT_TIMEOUT}" ] && CLIENT_TIMEOUT="30"

pick_python() {
  if command -v uv >/dev/null 2>&1; then echo "uv run python"; return; fi
  [ -x ".venv/bin/python" ] && { echo ".venv/bin/python"; return; }
  echo "python3"
}
PYTHON_CMD="$(pick_python)"
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"

is_port_open_py() {
  local port="$1"
  ${PYTHON_CMD} - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", port))
    print("open")
except Exception:
    print("closed")
finally:
    s.close()
PY
}

find_free_port() {
  for p in $(seq 9091 9110); do
    if [ "$(is_port_open_py "$p")" = "closed" ]; then
      echo "$p"
      return
    fi
  done
  echo "9191"
}

PORT="$(find_free_port)"
BASE_URL="http://localhost:${PORT}/sse"

echo "[client] Starting temporary SSE server on 0.0.0.0:${PORT} ..."
PYTHONUNBUFFERED=1 \
${PYTHON_CMD} -c "import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
print('[mcp] background SSE...'); \
asyncio.run(run_mcp_async('sse', host='0.0.0.0', port=${PORT}))" \
  >"${LOG_FILE}" 2>&1 & echo $! >"${PID_FILE}"

echo "[mcp] Waiting for 0.0.0.0:${PORT} to become ready..."
READY=0
for _ in $(seq 1 60); do  # ~12s
  if [ "$(is_port_open_py "$PORT")" = "open" ]; then READY=1; break; fi
  sleep 0.2
done
if [ "${READY}" -ne 1 ]; then
  echo "✗ Timed out waiting for server. See ${LOG_FILE}"
  kill "$(cat "${PID_FILE}")" >/dev/null 2>&1 || true
  exit 1
fi
echo "✓ Server is up."
sleep 0.2

echo "[client] Using URL: ${BASE_URL}"
STATUS=0
if [ -n "${TIMEOUT_BIN}" ]; then
  echo "[client] Running client with ${CLIENT_TIMEOUT}s timeout..."
  PYTHONUNBUFFERED=1 ${TIMEOUT_BIN} "${CLIENT_TIMEOUT}" \
    ${PYTHON_CMD} scripts/mcp_sse_client.py \
      --url "${BASE_URL}" \
      list-tools || STATUS=$?
else
  echo "[client] Running client (no timeout command available)..."
  PYTHONUNBUFFERED=1 \
    ${PYTHON_CMD} scripts/mcp_sse_client.py \
      --url "${BASE_URL}" \
      list-tools || STATUS=$?
fi

if [ "${STATUS}" -ne 0 ]; then
  echo "✗ Client failed (exit ${STATUS}). Last 200 lines of server log:"
  tail -n 200 "${LOG_FILE}" || true
fi

echo "[mcp] Stopping temporary server (PID $(cat "${PID_FILE}"))..."
kill "$(cat "${PID_FILE}")" >/dev/null 2>&1 || true
rm -f "${PID_FILE}"

exit "${STATUS}"

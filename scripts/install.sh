#!/usr/bin/env bash
# install.sh — Cross-platform Python-only installer dispatcher (Ubuntu, macOS, Windows/Git-Bash)
# - Detects OS and invokes the correct platform installer.
# - On Windows, uses the launcher "py -3.11" and writes .python_cmd for the Makefile.
# - Allows overriding with --install-dir/-d and --python.
# - Prints a logo on start.

set -euo pipefail
IFS=$'\n\t'

# ── RuslanMV logo ─────────────────────────────────────────────────────────────
print_logo() {
  local BLUE="\033[1;34m"; local NC="\033[0m"
  echo -e "${BLUE}"
  cat <<'EOF'
██████╗ ██╗   ██╗███████╗██╗      █████╗ ███╗   ███╗███╗   ███╗██╗   ██╗
██╔══██╗██║   ██║██╔════╝██║     ██╔══██╗████╗ ████║████╗ ████║╚██╗ ██╔╝
██████╔╝██║   ██║█████╗  ██║     ███████║██╔████╔██║██╔████╔██║ ╚████╔╝ 
██╔══██╗██║   ██║██╔══╝  ██║     ██╔══██║██║╚██╔╝██║██║╚██╔╝██║  ╚██╔╝  
██║  ██║╚██████╔╝███████╗███████╗██║  ██║██║ ╚═╝ ██║██║ ╚═╝ ██║   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝   ╚═╝   
                           r u s l a n m v
EOF
  echo -e "${NC}"
}
print_logo

# -----------------------------------------------------------------------------
# Args / config
# -----------------------------------------------------------------------------
INSTALL_ROOT="${INSTALL_ROOT:-$PWD}"
PYTHON="${PYTHON:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--install-dir DIR] [--python /path/to/python]
  -d, --install-dir   Target directory (default: current directory)
      --python        Explicit Python interpreter to use (>= 3.11)
Environment overrides:
  INSTALL_ROOT=/path  PYTHON=/path/to/python  scripts/install.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--install-dir) [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; } INSTALL_ROOT="$2"; shift 2;;
    --python)         [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; } PYTHON="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

# -----------------------------------------------------------------------------
# Resolve script dir (handles symlinks)
# -----------------------------------------------------------------------------
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

echo "📂 Install root: ${INSTALL_ROOT}"
echo "📜 Script dir  : ${SCRIPT_DIR}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
is_wsl() {
  (grep -qi microsoft /proc/version 2>/dev/null) || \
  (grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null)
}

resolve_python_path() {
  # 1) Respect explicit override
  if [[ -n "${PYTHON:-}" ]] && command -v "$PYTHON" >/dev/null 2>&1; then
    if "$PYTHON" - <<'PY' >/dev/null 2>&1; then
import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,11) else 1)
PY
      command -v "$PYTHON"; return 0
    fi
  fi
  # 2) Common names
  for cmd in python3.11 python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" - <<'PY' >/dev/null 2>&1; then
import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,11) else 1)
PY
        command -v "$cmd"; return 0
      fi
    fi
  done
  # 3) Windows launcher "py -3.11"
  if command -v py >/dev/null 2>&1 && py -3.11 -c "import sys" >/dev/null 2>&1; then
    py -3.11 -c "import sys; print(sys.executable)"; return 0
  fi
  return 1
}

to_win_path() {
  # Convert /c/.. to C:\.. when calling PowerShell
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

# -----------------------------------------------------------------------------
# Windows-specific: run PowerShell installer and set .python_cmd
# -----------------------------------------------------------------------------
install_python_windows() {
  echo "🪟 Detected Windows"

  # Find PowerShell
  local PS
  if command -v pwsh >/dev/null 2>&1; then
    PS="pwsh"
  elif command -v powershell.exe >/dev/null 2>&1; then
    PS="powershell.exe"
  elif command -v powershell >/dev/null 2>&1; then
    PS="powershell"
  else
    echo "❌ PowerShell not found. Install PowerShell 7+ from https://aka.ms/powershell" >&2
    exit 1
  fi
  echo "→ Using PowerShell: $PS"

  local ps_path="${SCRIPT_DIR}/windows/install_python_win.ps1"
  if [[ ! -f "$ps_path" ]]; then
    echo "❌ Missing $ps_path" >&2
    exit 1
  fi

  # Convert path for PowerShell on Windows
  local ps_win
  ps_win="$(to_win_path "$ps_path")"

  # Run installer
  "$PS" -NoProfile -ExecutionPolicy Bypass -File "$ps_win"

  # Resolve an actual command we can use later
  local CMD=""
  if command -v py >/dev/null 2>&1 && py -3.11 -c "import sys" >/dev/null 2>&1; then
    CMD="py -3.11"
  elif command -v python >/dev/null 2>&1 && python - <<'PY' >/dev/null 2>&1; then
import sys; raise SystemExit(0 if sys.version_info[:2]==(3,11) else 1)
PY
    CMD="python"
  fi

  if [[ -z "$CMD" ]]; then
    echo "❌ Python 3.11 not found after installation." >&2
    exit 1
  fi

  # Persist for the Makefile
  echo "$CMD" > "${INSTALL_ROOT}/.python_cmd"
  export PYTHON="$CMD"
  echo "✅ Resolved Python command: $CMD ($($CMD -V))"
}

# -----------------------------------------------------------------------------
# Try pre-existing Python (nice-to-have)
# -----------------------------------------------------------------------------
if PY_RESOLVED="$(resolve_python_path 2>/dev/null)"; then
  PYTHON="$PY_RESOLVED"
  export PYTHON
  echo "🐍 Using Python: ${PYTHON} ($("${PYTHON}" -c 'import sys; print(".".join(map(str,sys.version_info[:3])))'))"
else
  echo "ℹ️ Python ≥ 3.11 not currently available on PATH; proceeding with platform installer."
fi

# -----------------------------------------------------------------------------
# OS detection and dispatch (Python ONLY)
# -----------------------------------------------------------------------------
OS_TYPE="$(uname -s)"
case "${OS_TYPE}" in
  Linux*)
    if is_wsl; then echo "🖥 Detected Linux (WSL)"; else echo "🖥 Detected Linux"; fi
    if grep -qi '^ID=ubuntu' /etc/os-release; then
      echo "✔ Ubuntu identified"
      bash "${SCRIPT_DIR}/ubuntu/install_python311.sh" "${INSTALL_ROOT}"
    else
      echo "❌ Unsupported Linux distro (expected Ubuntu)." >&2
      exit 1
    fi
    ;;
  Darwin*)
    echo "🍎 Detected macOS"
    bash "${SCRIPT_DIR}/mac/install_python311.sh" "${INSTALL_ROOT}"
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    install_python_windows
    ;;
  *)
    echo "❓ Unknown OS: ${OS_TYPE}" >&2
    exit 1
    ;;
esac

# Re-resolve and persist command for the Makefile
if PY_RESOLVED="$(resolve_python_path 2>/dev/null)"; then
  PYTHON="$PY_RESOLVED"
  export PYTHON
  # For Makefile compatibility
  if [[ ! -f "${INSTALL_ROOT}/.python_cmd" ]]; then
    # If we got an absolute path, prefer a simple command form for Windows
    if command -v py >/dev/null 2>&1 && py -3.11 -c "import sys" >/dev/null 2>&1; then
      echo "py -3.11" > "${INSTALL_ROOT}/.python_cmd"
    else
      echo "$PYTHON" > "${INSTALL_ROOT}/.python_cmd"
    fi
  fi
  echo "🐍 Final Python: ${PYTHON} ($("${PYTHON}" -V))"
  echo "📝 Wrote interpreter command to ${INSTALL_ROOT}/.python_cmd"
else
  echo "❌ Could not resolve Python ≥ 3.11 after installation." >&2
  exit 1
fi

echo "✅ All done!"

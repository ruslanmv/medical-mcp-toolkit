#!/usr/bin/env bash
set -euo pipefail

if command -v uv >/dev/null 2>&1; then
  echo "[install_uv] uv already installed: $(uv --version)"
  exit 0
fi

echo "[install_uv] Installing uv (Astral) for current user..."
# Official one-liner installer from Astral
curl -LsSf https://astral.sh/uv/install.sh | sh

# Common install locations
CANDIDATES=("$HOME/.local/bin" "$HOME/.cargo/bin")
FOUND=0
for d in "${CANDIDATES[@]}"; do
  if [ -x "$d/uv" ]; then
    FOUND=1
    if ! grep -q "$d" <<<"$PATH"; then
      echo "[install_uv] Adding $d to PATH in shell profiles (~/.bashrc and ~/.zshrc)"
      echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc" || true
      echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$HOME/.zshrc" || true
    fi
    break
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "[install_uv] uv binary not found in common locations."
  echo "Please ensure the installer added uv to your PATH."
fi

echo "[install_uv] Done. Open a new shell or run:"
echo '  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"'

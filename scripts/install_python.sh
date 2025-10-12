#!/usr/bin/env bash
set -euo pipefail

echo "[install_python] Detecting OS..."
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Cannot detect OS. Aborting."
  exit 1
fi

if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
  echo "This installer targets Ubuntu. Detected ID='${ID:-unknown}'."
  echo "Please install Python 3.11 manually for your platform."
  exit 1
fi

echo "[install_python] Installing Python 3.11..."
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl ca-certificates

# Add deadsnakes PPA for Python 3.11 on older Ubuntus
if ! apt-cache policy | grep -q deadsnakes; then
  sudo add-apt-repository -y ppa:deadsnakes/ppa
fi

sudo apt-get update -y
sudo apt-get install -y python3.11 python3.11-venv python3.11-distutils

# Ensure pip for 3.11
if ! command -v python3.11 >/dev/null 2>&1; then
  echo "python3.11 not found after install. Aborting."
  exit 1
fi

if ! python3.11 -m pip -V >/dev/null 2>&1; then
  echo "[install_python] Installing pip for Python 3.11..."
  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
  python3.11 /tmp/get-pip.py
  rm -f /tmp/get-pip.py
fi

echo "[install_python] Completed. Version:"
python3.11 -V
python3.11 -m pip -V

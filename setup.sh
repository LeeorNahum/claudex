#!/bin/sh
set -eu
cd "$(dirname "$0")"

OS=$(uname -s)
case "$OS" in
  Darwin) PLATFORM=darwin ;;
  Linux) PLATFORM=linux ;;
  *)
    printf '%s\n' "claudex setup: unsupported OS: $OS (this repo supports Windows via the .cmd files, and macOS/Linux via these .sh files)" >&2
    exit 1
    ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) RELEASE_ARCH=amd64 ;;
  arm64|aarch64) RELEASE_ARCH=aarch64 ;;
  *)
    printf '%s\n' "claudex setup: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

if [ -x cli-proxy-api ]; then
  echo "cli-proxy-api already present, skipping download."
else
  echo "Downloading CLIProxyAPI..."
  TAG=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
  if [ -z "$TAG" ]; then
    echo "Could not determine the latest CLIProxyAPI release tag. Aborting." >&2
    exit 1
  fi
  echo "Latest release: $TAG"
  VERSION=$(printf '%s' "$TAG" | sed 's/^v//')
  ASSET="CLIProxyAPI_${VERSION}_${PLATFORM}_${RELEASE_ARCH}.tar.gz"
  curl -fsSL -o cliproxy.tar.gz "https://github.com/router-for-me/CLIProxyAPI/releases/download/${TAG}/${ASSET}"
  tar -xzf cliproxy.tar.gz cli-proxy-api
  rm -f cliproxy.tar.gz
  chmod +x cli-proxy-api
  if [ ! -x cli-proxy-api ]; then
    echo "Extraction failed: cli-proxy-api was not produced." >&2
    exit 1
  fi
fi

if [ ! -f claudex-token.txt ]; then
  echo "Generating a local proxy token..."
  openssl rand -hex 32 > claudex-token.txt
fi
TOKEN=$(cat claudex-token.txt)

if [ ! -f config.yaml ]; then
  echo "Writing config.yaml..."
  cat > config.yaml <<EOF
host: "127.0.0.1"
port: 8317
auth-dir: "auth"
api-keys:
  - "$TOKEN"
debug: false
EOF
fi

cat <<'EOF'

Setup files are ready. Two things left, both one-time:
  1. ./cli-proxy-api -codex-login   (opens a browser, authenticate with your ChatGPT/Codex account)
  2. Then just run ./claudex.sh whenever you want Claude Code routed through GPT-5.6 Sol.

Never run -claude-login. It routes your real Claude subscription through a third-party
tool, which violates Anthropic's Consumer Terms and has led to real account suspensions.

Config, the local proxy token, and the OAuth credential are all under this folder
and are gitignored. Do not commit them.
EOF

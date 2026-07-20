#!/bin/sh
set -eu
cd "$(dirname "$0")"

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claudex"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

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

if [ -x "$INSTALL_DIR/cli-proxy-api" ]; then
  echo "cli-proxy-api already installed, skipping download."
else
  echo "Downloading CLIProxyAPI..."
  TAG=$(curl -fsSL https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
  if [ -z "$TAG" ]; then
    echo "Could not determine the latest CLIProxyAPI release tag. Aborting." >&2
    exit 1
  fi
  echo "Latest release: $TAG"
  CLIPROXY_VERSION=$(printf '%s' "$TAG" | sed 's/^v//')
  ASSET="CLIProxyAPI_${CLIPROXY_VERSION}_${PLATFORM}_${RELEASE_ARCH}.tar.gz"
  TMP_TAR=$(mktemp -t claudex-cliproxy.XXXXXX)
  curl -fsSL -o "$TMP_TAR" "https://github.com/router-for-me/CLIProxyAPI/releases/download/${TAG}/${ASSET}"
  tar -xzf "$TMP_TAR" -C "$INSTALL_DIR" cli-proxy-api
  rm -f "$TMP_TAR"
  chmod +x "$INSTALL_DIR/cli-proxy-api"
  if [ ! -x "$INSTALL_DIR/cli-proxy-api" ]; then
    echo "Extraction failed: cli-proxy-api was not produced." >&2
    exit 1
  fi
fi

if [ ! -f "$INSTALL_DIR/claudex-token.txt" ]; then
  echo "Generating a local proxy token..."
  openssl rand -hex 32 > "$INSTALL_DIR/claudex-token.txt"
fi
TOKEN=$(cat "$INSTALL_DIR/claudex-token.txt")

if [ ! -f "$INSTALL_DIR/config.yaml" ]; then
  echo "Writing config.yaml..."
  cat > "$INSTALL_DIR/config.yaml" <<EOF
host: "127.0.0.1"
port: 8317
auth-dir: "auth"
api-keys:
  - "$TOKEN"
debug: false
request-retry: 3
EOF
elif ! grep -q '^request-retry:' "$INSTALL_DIR/config.yaml"; then
  # One additive migration for older installs (pre-2.x): proxy-side retry
  # smooths transient upstream errors (403/408/5xx) without touching anything
  # else in the user's existing config.
  echo "Adding request-retry to your existing config.yaml..."
  printf 'request-retry: 3\n' >> "$INSTALL_DIR/config.yaml"
fi

# Keep the proxy catalog pruned to the supported roster. The /model picker
# in claudex sessions lists whatever the proxy serves, so retired
# generations and non-chat models are excluded here. When a generation is
# retired, add its ids to this list the same way.
if ! grep -q '^oauth-excluded-models:' "$INSTALL_DIR/config.yaml"; then
  echo "Pruning retired models from the proxy catalog in config.yaml..."
  cat >> "$INSTALL_DIR/config.yaml" <<EOF
oauth-excluded-models:
  codex:
    - "gpt-5.3*"
    - "gpt-5.4*"
    - "gpt-5.5*"
    - "gpt-image*"
    - "codex-auto-review"
EOF
fi

# The launcher script is plain code, not user state: always refresh it so
# re-running setup after a git pull picks up fixes without touching the
# token, config, or OAuth credential already sitting in INSTALL_DIR.
cp claudex.sh "$INSTALL_DIR/claudex.sh"
chmod +x "$INSTALL_DIR/claudex.sh"

# The repo checkout is only needed to run this script. Once installed,
# claudex runs entirely from INSTALL_DIR, and the PATH shim is the only thing
# a user's shell ever needs to find.
cat > "$BIN_DIR/claudex" <<EOF
#!/bin/sh
exec "$INSTALL_DIR/claudex.sh" "\$@"
EOF
chmod +x "$BIN_DIR/claudex"

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "$BIN_DIR is already on your PATH." ;;
  *)
    echo "$BIN_DIR is not on your PATH yet. Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

cat <<EOF

claudex installed to $INSTALL_DIR
Two things left, both one-time:
  1. cd "$INSTALL_DIR" && ./cli-proxy-api -codex-login   (opens a browser, authenticate with your ChatGPT/Codex account)
  2. Open a new shell (or source your profile), then run claudex.

How to use it:
  claudex                 Claude Code on GPT-5.6 Sol, full model catalog in /model
  claudex gpt-5.6-terra   start on Terra instead (also gpt-5.6-luna)
  claudex k3              start on Kimi K3, after a one-time ./cli-proxy-api -kimi-login
  claude                  plain vanilla Claude Code stays untouched

Never run -claude-login. It routes your real Claude subscription through a third-party
tool, which violates Anthropic's Consumer Terms and has led to real account suspensions.

Config, the local proxy token, and the OAuth credential all live in $INSTALL_DIR,
not in this source checkout, and are not tracked by git. This folder you're running
setup from is no longer needed once setup finishes.
EOF

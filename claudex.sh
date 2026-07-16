#!/bin/sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for f in cli-proxy-api config.yaml claudex-token.txt; do
  if [ ! -e "$SCRIPT_DIR/$f" ]; then
    echo "claudex: not set up yet. Run setup.sh first." >&2
    exit 1
  fi
done
TOKEN=$(cat "$SCRIPT_DIR/claudex-token.txt")

# Curl config file keeps the bearer token out of the process command line
# (ps shows argv to any local user, not config-file contents).
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$SCRIPT_DIR/curl-auth.cfg"
chmod 600 "$SCRIPT_DIR/curl-auth.cfg"

is_ready() {
  curl -fsS -K "$SCRIPT_DIR/curl-auth.cfg" http://127.0.0.1:8317/v1/models >/dev/null 2>&1
}

if ! is_ready; then
  echo "claudex: starting the local proxy..."
  # Run in a subshell so only the background process's cwd becomes
  # SCRIPT_DIR (needed for its relative auth-dir in config.yaml), without
  # changing this script's own cwd, which must stay wherever the caller is.
  ( cd "$SCRIPT_DIR" && nohup ./cli-proxy-api -config config.yaml >proxy.log 2>&1 & disown 2>/dev/null || true )
  ready=0
  i=0
  while [ "$i" -lt 30 ]; do
    if is_ready; then
      ready=1
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ "$ready" -eq 0 ]; then
    echo "claudex: proxy did not become ready in time. Check $SCRIPT_DIR/proxy.log for errors," >&2
    echo "or run '$SCRIPT_DIR/cli-proxy-api -codex-login' again if the OAuth credential expired." >&2
    exit 1
  fi
fi

# Clear any stray real credentials first so nothing outranks the proxy override.
unset ANTHROPIC_API_KEY OPENAI_API_KEY CLAUDE_CODE_OAUTH_TOKEN

export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
export ANTHROPIC_AUTH_TOKEN="$TOKEN"
# Force subagents onto gpt-5.6-sol too. Without this, a subagent that
# defaults to a real Anthropic model (e.g. claude-opus-4-8) gets a 502
# from the proxy, since it only ever authenticates Codex/OpenAI models.
export CLAUDE_CODE_SUBAGENT_MODEL="gpt-5.6-sol"
export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3
# Claude Code's own context/compaction defaults are tuned for Anthropic's
# real models, not an arbitrary swapped-in one, so it can compact at the
# wrong point without this. 372000 matches gpt-5.6-sol's real context
# window; re-check this if the model changes.
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=372000
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=372000
export ENABLE_TOOL_SEARCH=false
# Deliberately no cd here: claude must launch from the caller's actual
# working directory, not from SCRIPT_DIR. That was the bug.
exec claude --model gpt-5.6-sol "$@"

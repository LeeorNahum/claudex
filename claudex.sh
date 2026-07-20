#!/bin/sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# claudex is Claude Code wired to the extra models and providers: every
# session runs through the local CLIProxyAPI, with the full proxy catalog in
# the /model picker. Plain vanilla Claude Code is what `claude` itself is
# for. claudex never opens it.
MODEL="gpt-5.6-sol"
case "${1:-}" in
  "" | -*)
    # No model named: default model, args forwarded untouched.
    ;;
  sonnet | opus | haiku | fable | default | opusplan | claude-*)
    echo "claudex: '$1' is a native Claude model, and claudex only serves the extra providers." >&2
    echo "claudex: for Claude itself run: claude --model $1" >&2
    exit 1
    ;;
  gpt-* | k3 | "k3[1m]" | kimi-*)
    MODEL="$1"
    shift
    ;;
  *)
    # Not a model id: treat it as a prompt/argument for Claude Code as-is.
    ;;
esac

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

# Preflight: only launch against a model the proxy actually has credentials
# for. This turns the proxy's opaque "502 unknown provider" into a clear,
# actionable error before any session starts.
CATALOG=$(curl -fsS -K "$SCRIPT_DIR/curl-auth.cfg" http://127.0.0.1:8317/v1/models 2>/dev/null || true)
# The [1m] long-context suffix is Claude Code notation. The catalog lists the base id.
CATALOG_ID=${MODEL%"[1m]"}
if ! printf '%s' "$CATALOG" | grep -q "\"id\":\"$CATALOG_ID\""; then
  echo "claudex: the local proxy has no credentials for model '$MODEL'." >&2
  case "$MODEL" in
    k3 | "k3[1m]" | kimi-*)
      echo "claudex: Kimi needs a one-time login: cd \"$SCRIPT_DIR\" && ./cli-proxy-api -kimi-login" >&2
      ;;
    *)
      echo "claudex: if the Codex OAuth credential expired, re-run: cd \"$SCRIPT_DIR\" && ./cli-proxy-api -codex-login" >&2
      ;;
  esac
  echo "claudex: models the proxy currently serves:" >&2
  printf '%s\n' "$CATALOG" | tr ',' '\n' | sed -n 's/.*"id":"\([^"]*\)".*/  \1/p' >&2
  exit 1
fi

# Keep Kimi visible even before its login: Claude Code allows one custom
# /model picker entry, so when the catalog lacks k3, pin it there as a
# signpost. Selecting it errors visibly in-chat, which tells the human (or
# the agent driving the session) exactly what to do, instead of Kimi being
# silently absent. Once -kimi-login has run, the catalog serves k3 and the
# real entry appears via gateway discovery instead.
if ! printf '%s' "$CATALOG" | grep -q '"id":"k3"'; then
  export ANTHROPIC_CUSTOM_MODEL_OPTION="k3"
  export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="Kimi K3 (not signed in)"
  export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="Enable with: cli-proxy-api -kimi-login in $SCRIPT_DIR"
fi

# Clear any stray real credentials first so nothing outranks the proxy override.
unset ANTHROPIC_API_KEY OPENAI_API_KEY CLAUDE_CODE_OAUTH_TOKEN

export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
export ANTHROPIC_AUTH_TOKEN="$TOKEN"
# Pin every internal model tier to the selected model. Without these, Claude
# Code's subagents and background calls default to real Anthropic ids
# (e.g. claude-opus-4-8, claude-haiku-4-5) and get a 502 from the proxy,
# since it only holds Codex/Kimi credentials, never Anthropic ones.
export CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_FABLE_MODEL="$MODEL"
# Let /model list the proxy's real catalog, so switching between proxy-served
# models mid-session works and unregistered models never appear as real entries.
export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3
export ENABLE_TOOL_SEARCH=false
# Gentle rate-limit smoothing: upstream limits are account-level and shared
# by every claudex terminal, so parallel sessions can trip burst throttling.
# Retry with exponential backoff until the throttle clears, instead of
# erroring out the whole thread.
export CLAUDE_CODE_MAX_RETRIES=15
export CLAUDE_CODE_RETRY_WATCHDOG=1
# Claude Code's own context/compaction defaults are tuned for Anthropic's
# real models, not an arbitrary swapped-in one, so it can compact at the
# wrong point without this. Values track each supported model's real window,
# and unknown ids keep Claude Code's defaults.
case "$MODEL" in
  gpt-5.6-*) CONTEXT_TOKENS=372000 ;;
  "k3[1m]") CONTEXT_TOKENS=1048576 ;;
  k3 | kimi-*) CONTEXT_TOKENS=262144 ;;
  *) CONTEXT_TOKENS="" ;;
esac
if [ -n "$CONTEXT_TOKENS" ]; then
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$CONTEXT_TOKENS"
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW="$CONTEXT_TOKENS"
fi
# Deliberately no cd here: claude must launch from the caller's actual
# working directory, not from SCRIPT_DIR. That was the bug.
exec claude --model "$MODEL" "$@"

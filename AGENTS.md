# claudex

Claude Code, wired to the models Anthropic doesn't serve. Every claudex session runs through the vendored local proxy (CLIProxyAPI) with the full proxy catalog in the `/model` picker. Bare `claudex` starts on `gpt-5.6-sol`, and `claudex <canonical-model-id>` starts on another proxy model. Plain vanilla Claude Code is what `claude` itself is for. claudex never opens it, and redirects native Claude model requests to `claude`. See README.md for what it does and how to set it up.

## Standing rules

- Never use em dashes in new text (see `no-em-dashes` skill).
- Never add a `-claude-login` step or any code path that registers a real Claude/Anthropic OAuth credential with the vendored proxy. That routes a real Claude subscription through a third-party tool, which violates Anthropic's Consumer Terms and has led to real account suspensions. If a subagent 502s on a real Anthropic model, the fix is `CLAUDE_CODE_SUBAGENT_MODEL`, never adding more credentials.
- Everything this repo generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credential) is gitignored. Never commit any of it.
- Keep this repo small and self-contained. No framework, no installer wizard, no dependency beyond what the launcher genuinely needs.
- Run `skill-sync` before every commit (see that skill).
- Use `release-versioning` when bumping `VERSION`, tagging, or preparing a GitHub release (see that skill). The source checkout and the installed, running copy are deliberately separate: `setup.cmd`/`setup.sh` install into a stable per-user directory and put a PATH shim there, never assuming the repo folder stays around.

## Model support contract

This section is the maintenance contract for how models and providers are represented and how new ones get added. Follow it exactly. It exists so future additions (a new GPT generation, a new provider's subscription) land cleanly without redesign.

### Canonical ids only

claudex never invents model names. A model is always referred to by the exact id its provider exposes and the proxy catalog serves (`gpt-5.6-sol`, never `sol` or another nickname). Nicknames are banned because providers reuse them across generations, and because the launcher argument, Claude Code's `/model` picker entry, and the proxy's `/v1/models` catalog must all be the same string. The one sanctioned notation exception is Claude Code's `[1m]` long-context suffix (`k3[1m]`), which the launcher strips before checking the catalog.

The live catalog is the source of truth for what exists: `curl -H "Authorization: Bearer $(cat claudex-token.txt)" http://127.0.0.1:8317/v1/models` from the install directory. The launcher preflights every proxy-mode launch against it, so unregistered models produce a clear error (with the right login command) instead of a mid-session 502.

### Current roster

The roster lives in one place: the README's model table (model id, required login, context window). Keep context windows in docs human readable. The exact token values exist only in the context-window case blocks in `claudex.cmd`/`claudex.sh`, which are the source of truth for what gets wired into the env vars. Do not copy raw token counts into prose or tables.

Older ids the proxy also serves (gpt-5.5 and earlier) deliberately pass through undocumented. The README table tracks only the latest generation per provider. Thinking level for GPT models is Claude Code's effort control (`CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1`, already set), not model-name suffixes.

A model whose provider isn't signed in yet should still be discoverable: Claude Code allows exactly one custom `/model` picker entry (`ANTHROPIC_CUSTOM_MODEL_OPTION`), and claudex uses that single slot as a "not signed in" signpost for the highest-value missing model (currently `k3` when the catalog lacks it). Selecting the signpost errors visibly in-chat, which is the intended UX: the human or driving agent reads the error and runs the login. If the roster grows more than one perpetually-missing provider, revisit this, since there is only one slot.

### Adding a new model

1. Confirm the canonical id in the live proxy catalog (or the provider's docs if the proxy needs an update first: `setup` downloads the latest CLIProxyAPI release whenever the binary is missing, so updating the proxy means deleting the old binary from the install directory and re-running setup).
2. Add its context-window entry to BOTH `claudex.cmd` and `claudex.sh`. The two launchers are one program in two dialects and are always edited together, feature-identical.
3. If the id doesn't match an existing proxy-mode pattern (`gpt-*`, `k3`, `k3[1m]`, `kimi-*`), add its pattern to the first-argument detection in both launchers.
4. Update the README model table and the setup completion messages.
5. Bump `VERSION` (minor) via the `release-versioning` skill.

### Adding a new provider

1. Prefer a CLIProxyAPI login flow when one exists (as with Kimi's `-kimi-login`), checking its README/releases first. Only consider direct `ANTHROPIC_BASE_URL` endpoints or API-key config if the proxy has no support, and keep the single-proxy architecture unless it genuinely cannot work.
2. Add the provider's id pattern to proxy-mode detection in both launchers, plus a provider-specific login hint in the preflight error message.
3. Document the one-time login command in the README and setup completion messages.
4. Never `-claude-login`, under any framing. Anthropic models are native mode only.

### Backend boundary

One Claude Code session speaks to exactly one backend (`ANTHROPIC_BASE_URL` is session-wide), and a claudex session's backend is always the proxy. Native Claude models therefore cannot appear in a claudex session. `claude` itself is the vanilla Anthropic side, and claudex redirects native model requests there. Do not try to blend backends inside a session: that road leads to registering Anthropic credentials with the proxy, which is banned above.

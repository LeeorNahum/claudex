# claudex

Claude Code, wired to the models Anthropic doesn't serve. Every claudex session runs through the vendored local proxy (CLIProxyAPI) with the proxy's catalog in the `/model` picker. Bare `claudex` starts on the default model hardcoded in the launchers, and `claudex <canonical-model-id>` starts on another proxy model. Plain vanilla Claude Code is what `claude` itself is for. claudex never opens it, and redirects native Claude model requests to `claude`. See README.md for what it does and how to set it up.

## Standing rules

- Never use em dashes in new text (see `no-em-dashes` skill).
- Never add a `-claude-login` step or any code path that registers a real Claude/Anthropic OAuth credential with the vendored proxy. That routes a real Claude subscription through a third-party tool, which violates Anthropic's Consumer Terms and has led to real account suspensions. If a subagent 502s on a real Anthropic model, the fix is `CLAUDE_CODE_SUBAGENT_MODEL`, never adding more credentials.
- Everything this repo generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credential) is gitignored. Never commit any of it.
- Keep this repo small and self-contained. No framework, no installer wizard, no dependency beyond what the launcher genuinely needs.
- Run `skill-sync` before every commit (see that skill).
- Use `release-versioning` when tagging or preparing a GitHub release (see that skill). The git tag owns the release version, which is stamped into the Windows executable at build time and reflected in the release and README badge. The source checkout and installed copy are separate: setup installs into a stable per-user directory and never assumes the checkout stays around.

## Model preference

Prefer the newest, most capable flagship GPT model supported by the provider and live proxy. Prioritize capability over speed or cost. Verify the canonical id and context window against official provider documentation, then verify the route with a real request before changing the default. Do not infer capability from alphabetical sorting, silently fall back to a smaller model, or override an explicit user model selection. GPT-6 Astra (`gpt-6-astra`) is the current default.

## Windows launcher and checks

- `claudex.cs` is the native Windows launcher, compiled with the C# compiler included in Windows .NET Framework. `claudex.cmd` is only a compatibility entry point. Preserve the raw argument tail, except for consuming the documented positional model argument. Pass the inherited cwd directly to native `claude.exe`.
- `build.ps1 -Version MAJOR.MINOR.PATCH` builds into ignored `dist/`. With no argument it reads the latest Git tag. Source archives need the explicit release version. `setup.cmd -Version MAJOR.MINOR.PATCH` delegates to `setup.ps1`, installs the native launcher, and registers user App Paths. `-UpdateProxy` downloads and verifies the latest proxy before replacing this installation's process/binary, retaining a backup.
- Run `python tests/windows.py` with port 8317 free for the deterministic mock catalog. After setup and proxy startup, run `python tests/windows.py --installed --unc \\server\share\directory` to check the live catalog and installed claudex/claudexyolo chain. Tests require Python 3 and an installed agent-yolo executable. `python tests/test_posix.py` checks shell argument/model parity using Git Bash on Windows or sh on Unix. Build treats C# warnings as errors.
- Keep provider tokens, config, and OAuth state out of test output. Use probe CLIs to inspect argv/cwd and only allowlisted environment fields. A real, short model request must also pass before publication.

## Model support contract

This section is the maintenance contract for how models and providers are represented and how new ones get added. Follow it exactly. It exists so future additions (a new GPT generation, a new provider's subscription) land cleanly without redesign.

### Canonical ids only

claudex never invents model names. A model is always referred to by the exact id its provider exposes and the proxy catalog serves (`gpt-5.6-sol`, never `sol` or another nickname). Nicknames are banned because providers reuse them across generations, and because the launcher argument, Claude Code's `/model` picker entry, and the proxy's `/v1/models` catalog must all be the same string. The one sanctioned notation exception is Claude Code's `[1m]` long-context suffix (`k3[1m]`), which the launcher strips before checking the catalog. The one sanctioned invented id is the `background-summaries` proxy alias (defined in the setup config template, mapped to the family's lightest tier, since it fills the haiku role): internal plumbing for Claude Code's haiku-tier background calls, never typed by users, named so its unavoidable `/model` picker row explains itself.

The live catalog is the source of truth for what exists: `curl -H "Authorization: Bearer $(cat claudex-token.txt)" http://127.0.0.1:8317/v1/models` from the install directory. The launcher preflights every proxy-mode launch against it, so unregistered models produce a clear error (with the right login command) instead of a mid-session 502.

### Current roster

The roster lives in one place: the README's model table (model id, required login, context window). Keep context windows in docs human readable. The exact token values live in `claudex.cs`/`claudex.sh`, which own the environment settings. Do not copy raw token counts into prose or tables.

The proxy catalog is pruned to the supported roster: retired generations and non-chat models are excluded through the `oauth-excluded-models` block that setup writes into `config.yaml`, so they never appear in the `/model` picker. The README table tracks the latest flagship and supported alternatives that remain available for explicit selection. Thinking level for GPT models is Claude Code's effort control (`CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1`, already set), not model-name suffixes.

A model whose provider isn't signed in yet should still be discoverable: Claude Code allows exactly one custom `/model` picker entry (`ANTHROPIC_CUSTOM_MODEL_OPTION`), and claudex uses that single slot as a "not signed in" signpost for the highest-value missing model (the launchers hardcode which one). Selecting the signpost errors visibly in-chat, which is the intended UX: the human or driving agent reads the error and runs the login. If the roster grows more than one perpetually-missing provider, revisit this, since there is only one slot.

### Adding a new model

1. Confirm the canonical id in the live proxy catalog and official provider docs. Use `setup.cmd -UpdateProxy` on Windows when the proxy needs an update.
2. Add its context-window entry to BOTH `claudex.cs` and `claudex.sh`. Keep Windows and POSIX model selection and environment settings consistent.
3. If the id doesn't match an existing proxy-mode pattern in the launchers' first-argument detection, add its pattern in both.
4. Update the README (model table and any other model mentions) and the setup completion messages. If the new model becomes the flagship, also change the bare-launch default in both launchers.
5. When the new model retires an old generation, add the retired ids to the `oauth-excluded-models` patterns in BOTH setup scripts (a config.yaml change needs a proxy restart to take effect).
6. Cut a minor release via the `release-versioning` skill.

### Adding a new provider

1. Prefer a CLIProxyAPI login flow when one exists (as with Kimi's `-kimi-login`), checking its README/releases first. Only consider direct `ANTHROPIC_BASE_URL` endpoints or API-key config if the proxy has no support, and keep the single-proxy architecture unless it genuinely cannot work.
2. Add the provider's id pattern to proxy-mode detection in both launchers, plus a provider-specific login hint in the preflight error message.
3. Document the one-time login command in the README and setup completion messages.
4. Never `-claude-login`, under any framing. Anthropic models belong to plain `claude` only.

### Backend boundary

One Claude Code session speaks to exactly one backend (`ANTHROPIC_BASE_URL` is session-wide), and a claudex session's backend is always the proxy. Native Claude models therefore cannot appear in a claudex session. `claude` itself is the vanilla Anthropic side, and claudex redirects native model requests there. Do not try to blend backends inside a session: that road leads to registering Anthropic credentials with the proxy, which is banned above.

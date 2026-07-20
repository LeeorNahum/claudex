# claudex

[![GitHub Release](https://img.shields.io/github/v/release/LeeorNahum/claudex?sort=semver)](https://github.com/LeeorNahum/claudex/releases/latest)

Claude Code, wired to the models Anthropic doesn't serve. `claudex` opens Claude Code with every extra model you have access to (GPT-5.6 Sol, Terra, Luna, and Kimi K3) in its `/model` picker, running through a local proxy. Plain `claude` stays your vanilla Anthropic Claude Code. claudex is the everything-else side. Windows uses the `.cmd` files, macOS/Linux use the `.sh` files.

<img width="1896" height="936" alt="Claudex Demo" src="https://github.com/user-attachments/assets/b3f6d088-e5e2-4e68-b3f3-112b07815b66" />

## Why this exists

Theo Browne, the developer behind t3.gg, made a claim that got real attention: OpenAI's newest model performs meaningfully better inside Anthropic's Claude Code than inside OpenAI's own CLI, Codex. The reason is not mysterious: Codex has a documented bug (its MultiAgent V2 mode defaults `hide_spawn_agent_metadata` to `true`, removing the very fields needed to route subagents to cheaper models), so every subagent silently inherits the full, expensive parent configuration. Theo reported cutting his own token spend by 4 to 5x after working around it. Claude Code's harness does not have this problem.

He explained the why in real detail and never actually walked through the setup on screen. This is the tested, cross-platform, from-scratch implementation of the trick, grown into one command that fronts every model you have access to.

## How it works

Claude Code's CLI only speaks Anthropic's own request format, so serving it other providers' models needs a local proxy translating that format. This repo vendors [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (MIT) for exactly that: every claudex session points Claude Code at `http://127.0.0.1:8317` with a local-only token instead of Anthropic's servers.

One session speaks to exactly one backend, and a claudex session's backend is always the proxy. The `/model` picker lists the proxy's live catalog (claudex enables gateway model discovery, and setup prunes the catalog to the supported roster), so switching between GPT and Kimi models mid-session just works. Kimi stays visible in the picker even before you've signed in, as a "Kimi K3 (not signed in)" entry. Picking it errors in-chat with the exact login command. Native Claude models can't ride through the proxy (that would require registering Claude credentials with a third-party tool, which violates Anthropic's terms), so for Claude itself you run plain `claude`, and claudex will tell you exactly that if you ask it for one.

## Usage

```text
claudex                     Claude Code on GPT-5.6 Sol, proxy catalog in /model
claudex gpt-5.6-terra       start on GPT-5.6 Terra instead (fast research tier)
claudex gpt-5.6-luna        start on GPT-5.6 Luna
claudex k3                  start on Kimi K3 (needs a Kimi for Coding subscription)
claudex "k3[1m]"            Kimi K3 on the 1M-context tier
claudex gpt-5.6-terra -p "one-shot prompt"    remaining args pass through to claude
claudex sonnet              redirects you to plain claude (claudex never opens vanilla)
```

Model names are always the provider's canonical id, exactly as Claude Code's `/model` picker and the proxy's catalog spell them. No nicknames: providers reuse names like "sol" across generations, so the id you type is the id that runs.

| Model id | Needs | Context window |
| --- | --- | --- |
| `gpt-5.6-sol` | one-time `-codex-login` (ChatGPT account) | 372k |
| `gpt-5.6-terra` | same login | 372k |
| `gpt-5.6-luna` | same login | 372k |
| `k3` | one-time `-kimi-login` (Kimi for Coding subscription) | 256k |
| `k3[1m]` | same login, 1M-tier subscription | 1M |

Asking for a model the proxy has no credentials for fails fast with the exact login command to fix it, before any session starts. That error is plain text in the terminal, so both you and any agent driving claudex can read it and act. The same goes for picking the not-signed-in Kimi entry mid-session: the error lands in the chat where either of you can see it.

## Setup

Get the source, either a `git clone` or a download of the [latest release](https://github.com/LeeorNahum/claudex/releases/latest), then run setup from inside it.

One-time setup (Windows):

```text
setup.cmd
```

One-time setup (macOS/Linux):

```text
./setup.sh
```

`setup` installs claudex into a stable per-user directory (`~/.local/share/claudex`, or `%USERPROFILE%\.local\share\claudex` on Windows), separate from wherever you got the source, and puts a `claudex` command on your PATH. It downloads the real CLIProxyAPI release for your OS/arch, generates a local-only auth token, and writes a `config.yaml` (bound to `127.0.0.1`, never exposed to the network), all inside that directory. Re-running setup later (say, after a `git pull`) refreshes the launcher script and applies any announced config migrations, without touching your token or login.

Setup prints the remaining one-time steps: running `cli-proxy-api -codex-login` from the install directory (a browser OAuth login to your ChatGPT/Codex account) enables the GPT models, and optionally `cli-proxy-api -kimi-login` (device-flow login to a Kimi for Coding subscription) enables `k3`. After that, and after opening a new terminal so the PATH change takes effect, `claudex` works from anywhere. It starts the proxy if it isn't already running and health-checks it before use.

Once setup finishes, the folder you got the source into is no longer needed. claudex runs entirely from the install directory.

## Set up with an AI coding agent

Paste this into Claude Code, Codex, or any coding agent:

> Set up claudex from https://github.com/LeeorNahum/claudex for me. Read its README.md first, then get it installed and put `claudex` on my PATH. Stop and tell me exactly when to run the one-time login step myself, since that's an interactive browser login you can't do on my behalf. Verify it actually works, then summarize what you did.

## Rate limits and stalls

Every claudex terminal shares the same provider account, and the provider's limits are account-level, in two flavors: burst throttling (fire enough parallel requests in the same moment and the account gets 429s for a few seconds, then recovers) and the rolling 5-hour plus weekly usage windows. Parallel terminals trip the burst throttle far more often than they exhaust the window. Either way, they do not each get their own allowance, and no proxy setting changes that.

So when parallel sessions get throttled, claudex chooses to wait instead of die: sessions set Claude Code to keep retrying rate-limited requests with exponential backoff until the throttle clears. A session that looks stalled mid-turn is usually doing exactly that, and will resume on its own. The proxy's own log (`proxy.log` in the install directory) shows the 429s if you want to confirm. The proxy also quietly retries transient upstream errors (`request-retry` in `config.yaml`) so brief blips never surface at all.

## Real gotchas found running this

Claude Code will show a startup warning in claudex sessions that claude.ai connectors are disabled because an auth override is set. That's expected: it's confirming the proxy override is active, not an error, and signing in does not (and cannot) route Claude models into the session.

The `/model` picker also shows one "Custom Haiku model" row mirroring the session's model. That is not an extra model: it's the override that keeps Claude Code's internal background calls on the proxy model instead of letting them request an Anthropic id and fail.

**Never run `cli-proxy-api -claude-login`.** It's tempting if something requests a real Anthropic model and gets a `502 unknown provider` from the proxy, since that command looks like the obvious fix. It is not: it routes your real Claude subscription's OAuth token through a third-party tool, which violates Anthropic's Consumer Terms. Anthropic has been enforcing this without warning since early 2026, with real accounts suspended within minutes. claudex pins subagents and internal background calls to the session's own model specifically so nothing ever asks the proxy for an Anthropic model. Native Claude models are what plain `claude` is for.

Claude Code's own context and compaction defaults are tuned for its native Anthropic models, so claudex sessions also set `CLAUDE_CODE_MAX_CONTEXT_TOKENS`/`CLAUDE_CODE_AUTO_COMPACT_WINDOW` to the selected model's real window, plus a few other settings found necessary in practice (effort control, tool-use concurrency, disabling deferred tool search). Model ids claudex doesn't know keep Claude Code's defaults.

The vendored CLIProxyAPI release also bundles its own `README.md`/`README_CN.md`/`config.example.yaml`. `setup.cmd` extracts the release into a throwaway folder and only copies out the binary, specifically so it can never silently overwrite this repo's own files.

Everything claudex generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credentials) is gitignored. Never commit any of it.

## Yolo mode

If you also want approval prompts skipped, see [agent-yolo](https://github.com/LeeorNahum/agent-yolo), a separate repo, which includes a `claudexyolo` launcher that assumes `claudex` is already set up and on your PATH.

# claudex

[![GitHub Release](https://img.shields.io/github/v/release/LeeorNahum/claudex?sort=semver)](https://github.com/LeeorNahum/claudex/releases/latest)

Claude Code, plus compatibility for other models and providers. `claudex` is normal Claude Code with your own Claude login, untouched. `claudex <model-id>` runs that session on a non-Anthropic model (GPT-5.6 Sol, Terra, Luna, or Kimi K3) through a local proxy instead. Windows uses the `.cmd` files, macOS/Linux use the `.sh` files.

<img width="1896" height="936" alt="Claudex Demo" src="https://github.com/user-attachments/assets/b3f6d088-e5e2-4e68-b3f3-112b07815b66" />

## Why this exists

Theo Browne, the developer behind t3.gg, made a claim that got real attention: OpenAI's newest model performs meaningfully better inside Anthropic's Claude Code than inside OpenAI's own CLI, Codex. The reason is not mysterious: Codex has a documented bug (its MultiAgent V2 mode defaults `hide_spawn_agent_metadata` to `true`, removing the very fields needed to route subagents to cheaper models), so every subagent silently inherits the full, expensive parent configuration. Theo reported cutting his own token spend by 4 to 5x after working around it. Claude Code's harness does not have this problem.

He explained the why in real detail and never actually walked through the setup on screen. This is the tested, cross-platform, from-scratch implementation of the trick, grown into one command that fronts every model you have access to.

## How it works

Claude Code's CLI only speaks Anthropic's own request format, so serving it other providers' models needs a local proxy translating that format. This repo vendors [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (MIT) for exactly that: `claudex <model-id>` points Claude Code at `http://127.0.0.1:8317` with a local-only token instead of Anthropic's servers, for that one session. Bare `claudex` never touches the proxy at all.

One session speaks to exactly one backend. Switching between proxy models mid-session works through the normal `/model` picker (claudex enables gateway model discovery, so the picker lists exactly what the proxy actually has credentials for). Switching between a proxy model and a native Claude model means opening a new terminal with the other invocation, which fits the one-terminal-per-agent workflow this exists for.

## Usage

```text
claudex                     normal Claude Code, your Claude login, untouched
claudex sonnet              same, with a model picked (any native alias or claude-* id)
claudex gpt-5.6-sol         this session runs GPT-5.6 Sol via your ChatGPT/Codex login
claudex gpt-5.6-terra       GPT-5.6 Terra (fast research tier)
claudex gpt-5.6-luna        GPT-5.6 Luna
claudex k3                  Kimi K3 via a Kimi for Coding subscription
claudex "k3[1m]"            Kimi K3 on the 1M-context tier
claudex gpt-5.6-terra -p "one-shot prompt"    remaining args pass through to claude
```

Model names are always the provider's canonical id, exactly as Claude Code's `/model` picker and the proxy's catalog spell them. No nicknames: providers reuse names like "sol" across generations, so the id you type is the id that runs.

| Model id | Needs | Context window |
| --- | --- | --- |
| `gpt-5.6-sol` | one-time `-codex-login` (ChatGPT account) | 372k |
| `gpt-5.6-terra` | same login | 372k |
| `gpt-5.6-luna` | same login | 372k |
| `k3` | one-time `-kimi-login` (Kimi for Coding subscription) | 256k |
| `k3[1m]` | same login, 1M-tier subscription | 1M |

Asking for a model the proxy has no credentials for fails fast with the exact login command to fix it, before any session starts. That error is plain text in the terminal, so both you and any agent driving claudex can read it and act.

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

`setup` installs claudex into a stable per-user directory (`~/.local/share/claudex`, or `%USERPROFILE%\.local\share\claudex` on Windows), separate from wherever you got the source, and puts a `claudex` command on your PATH. It downloads the real CLIProxyAPI release for your OS/arch, generates a local-only auth token, and writes a `config.yaml` (bound to `127.0.0.1`, never exposed to the network), all inside that directory. Re-running setup later (say, after a `git pull`) refreshes the launcher script without touching your existing token, config, or login.

Setup prints the remaining one-time steps: running `cli-proxy-api -codex-login` from the install directory (a browser OAuth login to your ChatGPT/Codex account) enables the GPT models, and optionally `cli-proxy-api -kimi-login` (device-flow login to a Kimi for Coding subscription) enables `k3`. After that, and after opening a new terminal so the PATH change takes effect, `claudex` works from anywhere. Proxy-model sessions start the proxy if it isn't already running and health-check it before use.

Once setup finishes, the folder you got the source into is no longer needed; claudex runs entirely from the install directory.

## Set up with an AI coding agent

Paste this into Claude Code, Codex, or any coding agent:

> Set up claudex from https://github.com/LeeorNahum/claudex for me. Read its README.md first, then get it installed and put `claudex` on my PATH. Stop and tell me exactly when to run the one-time login step myself, since that's an interactive browser login you can't do on my behalf. Verify it actually works, then summarize what you did.

## Rate limits and stalls

Every proxy-model terminal shares the same provider account, and the provider's limits are account-level: OpenAI's Codex quota is a rolling 5-hour window plus a weekly cap shared across everything that logs in as you. Eight parallel claudex terminals burn that one pool eight times faster; they do not each get their own allowance, and no proxy setting changes that.

So when parallel sessions hit the limit, claudex chooses to wait instead of die: proxy-model sessions set Claude Code to keep retrying rate-limited requests with exponential backoff until the quota window frees up. A session that looks stalled mid-turn is usually doing exactly that, and will resume on its own. The proxy's own log (`proxy.log` in the install directory) shows the 429s if you want to confirm. The proxy also quietly retries transient upstream errors (`request-retry` in `config.yaml`) so brief blips never surface at all.

## Real gotchas found running this

Claude Code will show a startup warning in proxy-model sessions that claude.ai connectors are disabled because an auth override is set. That's expected: it's confirming the proxy override is active, not an error.

**Never run `cli-proxy-api -claude-login`.** It's tempting if something requests a real Anthropic model and gets a `502 unknown provider` from the proxy, since that command looks like the obvious fix. It is not: it routes your real Claude subscription's OAuth token through a third-party tool, which violates Anthropic's Consumer Terms. Anthropic has been enforcing this without warning since early 2026, with real accounts suspended within minutes. claudex pins the subagent and every internal model tier to the session's own model specifically so nothing ever asks the proxy for an Anthropic model; native Claude models are what bare `claudex` is for.

Claude Code's own context and compaction defaults are tuned for its native Anthropic models, so proxy-model sessions also set `CLAUDE_CODE_MAX_CONTEXT_TOKENS`/`CLAUDE_CODE_AUTO_COMPACT_WINDOW` to the selected model's real window, plus a few other settings found necessary in practice (effort control, tool-use concurrency, disabling deferred tool search). Model ids claudex doesn't know keep Claude Code's defaults.

The vendored CLIProxyAPI release also bundles its own `README.md`/`README_CN.md`/`config.example.yaml`. `setup.cmd` extracts the release into a throwaway folder and only copies out the binary, specifically so it can never silently overwrite this repo's own files.

Everything claudex generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credentials) is gitignored. Never commit any of it.

## Yolo mode

If you also want approval prompts skipped, see [agent-yolo](https://github.com/LeeorNahum/agent-yolo), a separate repo, which includes a `claudexyolo` launcher that assumes `claudex` is already set up and on your PATH.

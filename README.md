# claudex

[![GitHub Release](https://img.shields.io/github/v/release/LeeorNahum/claudex?sort=semver)](https://github.com/LeeorNahum/claudex/releases/latest)

Run Claude Code's actual interface against GPT-5.6 Sol (OpenAI's model) instead of Anthropic's models. Windows uses the `.cmd` files, macOS/Linux use the `.sh` files.

## Why this exists

Theo Browne, the developer behind t3.gg, made a claim that got real attention: OpenAI's newest model performs meaningfully better inside Anthropic's Claude Code than inside OpenAI's own CLI, Codex. The reason is not mysterious: Codex has a documented bug (its MultiAgent V2 mode defaults `hide_spawn_agent_metadata` to `true`, removing the very fields needed to route subagents to cheaper models), so every subagent silently inherits the full, expensive parent configuration. Theo reported cutting his own token spend by 4 to 5x after working around it. Claude Code's harness does not have this problem.

He explained the why in real detail and never actually walked through the setup on screen. This is the tested, cross-platform, from-scratch implementation of the trick.

## How it works

Claude Code's CLI only speaks Anthropic's own request format, so making it use GPT-5.6 Sol needs a local proxy translating that format to Codex's. This repo vendors [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (MIT) for exactly that: point Claude Code at `http://127.0.0.1:8317` with a local-only token instead of Anthropic's servers.

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

Setup prints the one remaining one-time step: running `cli-proxy-api -codex-login` from the install directory, which opens a browser for a one-time OAuth login to your ChatGPT/Codex account. Credentials land in `auth/` inside the install directory. After that, and after opening a new terminal so the PATH change takes effect, run `claudex` from anywhere whenever you want Claude Code routed through GPT-5.6 Sol. It starts the proxy if it isn't already running, health-checks it before use, and launches `claude --model gpt-5.6-sol`.

Once setup finishes, the folder you got the source into is no longer needed; claudex runs entirely from the install directory.

## Set up with an AI coding agent

Paste this into Claude Code, Codex, or any coding agent:

> Set up claudex from https://github.com/LeeorNahum/claudex for me. Read its README.md first, then get it installed and put `claudex` on my PATH. Stop and tell me exactly when to run the one-time login step myself, since that's an interactive browser login you can't do on my behalf. Verify it actually works, then summarize what you did.

## Real gotchas found running this

Claude Code will show a startup warning that claude.ai connectors are disabled because an auth override is set. That's expected: it's confirming the proxy override is active, not an error.

**Never run `cli-proxy-api -claude-login`.** It's tempting if a subagent defaults to a real Anthropic model (like `claude-opus-4-8`) and gets a `502 unknown provider` from the proxy, since that command looks like the obvious fix. It is not: it routes your real Claude subscription's OAuth token through a third-party tool, which violates Anthropic's Consumer Terms. Anthropic has been enforcing this without warning since early 2026, with real accounts suspended within minutes. `claudex.cmd`/`claudex.sh` already set `CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.6-sol` specifically so subagents never hit this in the first place; if you still see it, something cleared that env var, not a reason to add Claude OAuth to the proxy.

Claude Code's own context and compaction defaults are tuned for its native Anthropic models, not an arbitrary swapped-in one, so `claudex` also sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS`/`CLAUDE_CODE_AUTO_COMPACT_WINDOW` to match GPT-5.6 Sol's real window, plus a few other settings the original claudex design found necessary (effort control, tool-use concurrency, disabling deferred tool search). Re-check these if the model changes.

The vendored CLIProxyAPI release also bundles its own `README.md`/`README_CN.md`/`config.example.yaml`. `setup.cmd` extracts the release into a throwaway folder and only copies out the binary, specifically so it can never silently overwrite this repo's own files.

Everything claudex generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credential) is gitignored. Never commit any of it.

## Yolo mode

If you also want approval prompts skipped, see [agent-yolo](https://github.com/LeeorNahum/agent-yolo), a separate repo, which includes a `claudexyolo` launcher that assumes `claudex` is already set up and on your PATH.

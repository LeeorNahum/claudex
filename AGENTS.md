# claudex

Runs Claude Code's interface against GPT-5.6 Sol instead of Anthropic's models. See README.md for what it does and how to set it up.

## Standing rules

- Never use em dashes in new text (see `no-em-dashes` skill).
- Never add a `-claude-login` step or any code path that registers a real Claude/Anthropic OAuth credential with the vendored proxy. That routes a real Claude subscription through a third-party tool, which violates Anthropic's Consumer Terms and has led to real account suspensions. If a subagent 502s on a real Anthropic model, the fix is `CLAUDE_CODE_SUBAGENT_MODEL`, never adding more credentials.
- Everything this repo generates locally (the downloaded binary, `config.yaml`, the token, the OAuth credential) is gitignored. Never commit any of it.
- Keep this repo small and self-contained. No framework, no installer wizard, no dependency beyond what the launcher genuinely needs.
- Run `skill-sync` before every commit (see that skill).
- Use `release-versioning` when bumping `VERSION`, tagging, or preparing a GitHub release (see that skill). The source checkout and the installed, running copy are deliberately separate: `setup.cmd`/`setup.sh` install into a stable per-user directory and put a PATH shim there, never assuming the repo folder stays around.

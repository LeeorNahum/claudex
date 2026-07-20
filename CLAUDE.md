<!-- BEGIN claude-code-compat (generated, do not edit) -->

@AGENTS.md

# Nested AGENTS.md

Before you create, edit, or run files in a directory, read that directory's `AGENTS.md` first when one exists. Only the root `AGENTS.md` is imported above; nested `AGENTS.md` files hold local rules for their own subtree and are not auto-loaded. The closest `AGENTS.md` at or above a file governs work on that file, so check for one whenever you enter a new part of the tree (a package, an app, or a skill directory).

# Agent Skills Index

These project skills are not Claude Code slash-command skills. When a listed skill is relevant, read its `SKILL.md` path directly instead of trying a Skill tool or slash command.

Each description is the trigger. Respect it, and when it matches the task, read the skill's `SKILL.md` plus any relevant references, assets, scripts, or nearby root files the skill points to.

## [anti-backrooms](.agents/skills/anti-backrooms/SKILL.md)

> Review and improve visual, spatial, textual, and user-facing artifacts for coherent-but-wrong failures that violate human normalcy, including nonsensical wording, unsupported claims, wrong scale, impossible adjacency, unreadable hierarchy, duplicated patterns, meta leakage, and broken viewer flow. Always use this skill when creating or critiquing UI, decks, diagrams, docs, PDFs, signage, booths, copy, or other artifacts where local plausibility can hide global incoherence.

## [claude-code-compat](.agents/skills/claude-code-compat/SKILL.md)

> Keep Claude Code in sync with cross-tool Agent Skills and AGENTS.md by regenerating a managed block in CLAUDE.md. Run it whenever anything under .agents changes, such as a skill being added, removed, renamed, or having its name or description edited, and whenever a repository has an AGENTS.md or .agents/skills but no up-to-date CLAUDE.md, because Claude Code natively reads only CLAUDE.md and .claude/skills. It lists each skill's name, path, and description so Claude can read matching skills directly.

## [no-em-dashes](.agents/skills/no-em-dashes/SKILL.md)

> Use whenever this skill is visible or available to the agent. Always prevent em dashes (U+2014) in all agent-generated replies, text, edits, docs, comments, commit messages, and tool output. Also use when the user mentions em dashes, asks for AI-like punctuation cleanup, or explicitly asks to remove em dashes from named files, folders, or repos. Full-repo retroactive cleanup only on explicit user request for that scope.

## [release-versioning](.agents/skills/release-versioning/SKILL.md)

> Manage versioned releases and release artifacts across software, apps, firmware, skills, packages, and downloadable builds. Use when bumping semver, preparing GitHub releases, syncing README badges/version mentions, publishing binaries or archives, attaching release assets, updating package/app metadata, or making sure version constants and docs agree before a release.

## [skill-sync](.agents/skills/skill-sync/SKILL.md)

> Sync and update all installed skill submodules to their latest remote commits. Use this skill before every Git commit, or whenever the user asks to update, sync, refresh, or pull installed skills, or when a skill is installed.

## [subagent-spawn-book](.agents/skills/subagent-spawn-book/SKILL.md)

> Subagent Spawn Book (SSB) is used before creating any subagent, whether the user asks for one, the agent decides to delegate, or a plan includes delegation or fan-out. Select a default model when none is named, name the session, then read the selected model's spawn reference.

<!-- END claude-code-compat -->

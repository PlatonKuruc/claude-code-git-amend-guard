# Git amend guard for Claude Code

Stops Claude Code from rewriting git history blind: amend, force-push, rebase or reset --hard on a commit it never looked at.

This is **1 of the 16 hooks** in the full [Wizalnut Quality Gates pack for Claude Code](https://wizalnut.com/en/packs) (16 hooks, 6 skills, a canary test for every hook). Free, MIT.

## The problem

Field incident: an agent ran `git commit --amend` to improve its own commit message 50 minutes later. Meanwhile three other sessions had committed to the same branch, so HEAD was someone else's fix. The amend replaced that commit's message, and it was pushed.

## What it does

A PreToolUse hook blocks blind history rewrites: `git commit --amend`, force-push (`--force`, `-f`, `--force-with-lease`), `git rebase` and `git reset --hard`. The block shows what HEAD is right now (hash, author, age, subject), so the agent can check that the commit it rewrites is its own. Not a ban on rewriting history, a ban on rewriting it without looking. Bypass after checking `git log -1`: `AMEND_HEAD_OK` in the command.

Files: `pretooluse_git_amend_blind_guard.sh`. Deterministic, no model in the loop.

## Install as a Claude Code plugin

```bash
claude plugin marketplace add PlatonKuruc/claude-code-git-amend-guard
claude plugin install claude-code-git-amend-guard@claude-code-git-amend-guard
```

Start a new session afterwards. `claude plugin uninstall claude-code-git-amend-guard@claude-code-git-amend-guard` removes it. Your `settings.json` is not touched.

Requirements: Claude Code 2.x, bash (macOS 3.2 is fine), python3, jq, git.

## Test it

```bash
QG_HOOKS_DIR="$PWD/hooks" bash hooks/tests/run_tests.sh
```

## Switch it off

`touch ~/.claude/hooks/GIT_AMEND_BLIND_GUARD_OFF`, or `claude plugin disable claude-code-git-amend-guard@claude-code-git-amend-guard`.

## More gates

[claude-code-done-gate](https://github.com/PlatonKuruc/claude-code-done-gate) · [claude-code-git-discard-guard](https://github.com/PlatonKuruc/claude-code-git-discard-guard) · [claude-code-secret-print-guard](https://github.com/PlatonKuruc/claude-code-secret-print-guard) · [all three in one](https://github.com/PlatonKuruc/wizalnut-quality-gates). Full pack: [https://wizalnut.com/en/packs](https://wizalnut.com/en/packs).

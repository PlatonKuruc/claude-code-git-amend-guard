#!/usr/bin/env bash
# Canary test for pretooluse_git_amend_blind_guard.sh
#   QG_HOOKS_DIR=/path/to/hooks bash test_pretooluse_git_amend_blind_guard.sh
# Builds a throwaway git repo in mktemp. Exit 2 = block, 0 = allow.
# Block cases that run in the repo must also print the live HEAD subject.
set -uo pipefail
HOOKS_DIR="${QG_HOOKS_DIR:-$HOME/.claude/hooks}"
HOOK="$HOOKS_DIR/pretooluse_git_amend_blind_guard.sh"
[ -f "$HOOK" ] || { echo "❌ hook not found: $HOOK"; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/qg_git_amend.XXXXXX"); trap 'rm -rf "$T"' EXIT
OK=0; BAD=0

R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email canary@example.invalid
git -C "$R" config user.name canary
echo base > "$R/a.txt"; git -C "$R" add -A
git -C "$R" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm "someone-elses-fix-canary"
SUBJECT="someone-elses-fix-canary"
FAKE_HOME="$T/home"; mkdir -p "$FAKE_HOME/.claude/hooks"; touch "$FAKE_HOME/.claude/hooks/GIT_AMEND_BLIND_GUARD_OFF"

payload() { # payload <tool_name> <command> <cwd>
  python3 -c 'import json, sys
print(json.dumps({"session_id": "gate-canary", "hook_event_name": "PreToolUse", "cwd": sys.argv[3],
                  "tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "$1" "$2" "$3"
}

t() { # t <description> <expected_exit> <tool_name> <command> [cwd] [home] [stderr must contain]
  local rc good=1
  payload "$3" "$4" "${5:-$R}" > "$T/payload.json"
  HOME="${6:-$HOME}" bash "$HOOK" < "$T/payload.json" > /dev/null 2> "$T/stderr"; rc=$?
  [ "$rc" -eq "$2" ] || good=0
  if [ -n "${7:-}" ] && ! grep -qF -- "$7" "$T/stderr"; then good=0; fi
  if [ "$good" = 1 ]; then echo "  ✅ $1"; OK=$((OK+1))
  else echo "  ❌ $1 - expected $2${7:+ + '$7' in stderr}, got $rc"; head -5 "$T/stderr" | sed 's/^/       /'; BAD=$((BAD+1)); fi
}

echo "TESTS - pretooluse_git_amend_blind_guard.sh"
t "amend -> BLOCK and shows live HEAD"            2 Bash 'git commit --amend -m "better message"' "$R" "" "$SUBJECT"
t "amend with AMEND_HEAD_OK -> allow"             0 Bash 'git commit --amend -m "better message"  # AMEND_HEAD_OK'
t "cd <repo> && amend --no-edit -> BLOCK + HEAD"  2 Bash "cd $R && git commit --amend --no-edit" "$T" "" "$SUBJECT"
t "git -C <repo> commit --amend -> BLOCK + HEAD"  2 Bash "git -C $R commit --amend --no-edit" "$T" "" "$SUBJECT"
t "push --force -> BLOCK"                         2 Bash 'git push --force origin main'
t "push -f -> BLOCK"                              2 Bash 'git push -f origin main'
t "push --force-with-lease -> BLOCK"              2 Bash 'git push --force-with-lease origin main'
t "rebase -i -> BLOCK"                            2 Bash 'git rebase -i HEAD~3'
t "reset --hard -> BLOCK"                         2 Bash 'git reset --hard HEAD~2'
t "plain commit -> allow"                         0 Bash 'git commit -m "normal work"'
t "plain push -> allow"                           0 Bash 'git push origin main'
t "soft reset -> allow"                           0 Bash 'git reset HEAD~1'
t "mention in echo -> allow"                      0 Bash 'echo "careful with git commit --amend"'
t "grep through docs -> allow"                    0 Bash 'grep -rn "git push --force" ./docs'
t "single-quoted commit message -> allow"         0 Bash "git commit -m 'never use --amend on shared branches'"
t "heredoc body -> allow"                         0 Bash "python3 - <<'EOF'
print('git rebase -i HEAD~3')
EOF"
t "comment only -> allow"                         0 Bash 'ls -la   # later: git push --force'
t "kill switch GIT_AMEND_BLIND_GUARD_OFF -> allow" 0 Bash 'git commit --amend --no-edit' "$R" "$FAKE_HOME"
t "other tool (Write) -> allow"                   0 Write 'git commit --amend --no-edit'
t "unrelated command -> allow"                    0 Bash 'ls -la'

echo "──────────────"; echo "  passed: $OK · failed: $BAD"; [ "$BAD" -eq 0 ]

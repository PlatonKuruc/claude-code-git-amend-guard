#!/usr/bin/env bash
# ============================================================================
# pretooluse_git_amend_blind_guard.sh  ·  PreToolUse (matcher: Bash)
# ============================================================================
# WHAT:    Blocks history rewrites done blind: `git commit --amend`, force-push
#          (--force, -f, --force-with-lease), `git rebase` and `git reset --hard`.
#          The block message shows what HEAD is RIGHT NOW (hash, author, age,
#          subject), so the agent can check that the commit it rewrites is its own.
#          Not a ban on rewriting history - a ban on rewriting it without looking.
#          Read-only mentions (echo/grep/cat ..., comments, single-quoted text,
#          heredoc bodies) pass. Requires: bash, python3, git.
#
# WHY:     Field incident (09/2026): an agent's commit landed at 17:52. At 18:42
#          it ran `git commit --amend` to give that commit a better message. In
#          between, three other sessions had committed to the same branch, so
#          HEAD was someone else's fix. The amend replaced that commit's message
#          with an unrelated text, and it was pushed. The code survived; the
#          explanation of someone else's work was lost.
#
# BYPASS:  AMEND_HEAD_OK anywhere in the command - only after you checked
#          `git log -1` and HEAD really is yours.
#
# DISABLE: touch $HOME/.claude/hooks/GIT_AMEND_BLIND_GUARD_OFF
#
# TEST:    tests/test_pretooluse_git_amend_blind_guard.sh
# ============================================================================
set -uo pipefail

# Read stdin BEFORE the kill switch: exiting without reading would hand the
# writer on the other end of the pipe a SIGPIPE (exit 141 instead of 0).
INPUT=$(cat)

[ -f "$HOME/.claude/hooks/GIT_AMEND_BLIND_GUARD_OFF" ] && exit 0

python3 - "$INPUT" <<'PY'
import json, os, re, subprocess, sys


def operative(s):
    """Only the part of a Bash command that actually runs as git: heredoc bodies,
    the content of single-quoted strings and comments are removed."""
    out, lines, i = [], s.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        m = re.search(r"(?<!<)<<(?!<)-?\s*['\"]?([A-Za-z_][A-Za-z_0-9]*)['\"]?", line)
        if m:
            tag = m.group(1)
            out.append(line[:m.start()])
            i += 1
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1
            continue
        out.append(line)
        i += 1
    s = "\n".join(out)
    s = re.sub(r"'[^']*'", "''", s)              # single-quoted text is data, not a command
    s = re.sub(r"(^|\s)#[^\n]*", " ", s)         # comments
    return s


try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)

raw = (d.get("tool_input") or {}).get("command") or ""
if not raw.strip():
    sys.exit(0)
if "AMEND_HEAD_OK" in raw:                       # the marker is looked up in the RAW text
    sys.exit(0)

cmd = operative(raw)

# a read-only mention (echo/grep/cat/man ...) is not a history rewrite
if re.match(r"^\s*(echo|printf|grep|rg|cat|sed\s+-n|less|man|head|tail|awk)\b", cmd):
    sys.exit(0)

CASES = [
    (r"\bgit\s+(?:-C\s+\S+\s+)?commit\b[^\n;&|]*--amend", "git commit --amend",
     "it rewrites the LAST commit - and that one is not necessarily yours"),
    (r"\bgit\s+(?:-C\s+\S+\s+)?push\b[^\n;&|]*(?:--force\b|--force-with-lease\b|\s-f\b)", "force-push",
     "it pushes a rewritten history onto everyone else"),
    (r"\bgit\s+(?:-C\s+\S+\s+)?rebase\b", "git rebase",
     "it rewrites several commits at once"),
    (r"\bgit\s+(?:-C\s+\S+\s+)?reset\b[^\n;&|]*--hard", "git reset --hard",
     "it throws away commits and work in progress"),
]
hit = next(((n, w) for rx, n, w in CASES if re.search(rx, cmd)), None)
if not hit:
    sys.exit(0)
name, why = hit

# live HEAD - exactly what the agent should have looked at itself
repo = None
m = re.search(r"git\s+-C\s+(\S+)", cmd)
if m:
    repo = m.group(1)
else:
    m = re.search(r"(?:^|[;&|]\s*)cd\s+(\S+)", cmd)
    if m:
        repo = m.group(1)
base = d.get("cwd") if os.path.isdir(d.get("cwd") or "") else os.getcwd()
if repo:
    repo = os.path.expanduser(repo.strip("'\""))
    if not os.path.isabs(repo):
        repo = os.path.join(base, repo)
else:
    repo = base
head = ""
try:
    head = subprocess.run(
        ["git", "-C", repo, "log", "-1", "--format=%h · %an · %ar%n     %s"],
        capture_output=True, text=True, timeout=8).stdout.strip()
except Exception:
    head = ""

sys.stderr.write(f"""BLOCKED - {name} without looking at WHAT you are rewriting

Why it matters: {why}.

HEAD right now:
     {head or '(unknown - check it yourself: git log -1)'}

WHY THIS GATE EXISTS (field incident, 09/2026):
  An agent's commit landed; 50 minutes later it ran `--amend` to fix the message.
  In between, three other sessions had committed to the same branch, so HEAD was
  someone else's fix. The amend overwrote that commit's message and it was pushed.
  The code survived; the explanation of the other person's work did not.

WHAT TO DO:
  1. Check that HEAD really is yours:   git log -1 --format='%h %an %ar %s'
  2. If YES -> repeat the command with the marker:   ...   # AMEND_HEAD_OK
  3. If NO  -> do NOT rewrite. Make a new commit instead, or ask the user.
     Nobody else's history gets rewritten on an agent's own initiative.

Disable: touch $HOME/.claude/hooks/GIT_AMEND_BLIND_GUARD_OFF
Gate: Wizalnut Quality Gates · pretooluse_git_amend_blind_guard.sh
""")
sys.exit(2)
PY

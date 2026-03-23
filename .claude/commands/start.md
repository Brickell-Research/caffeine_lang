---
description: Load Caffeine project context for a new session — replaces "kick off agents to understand the repo"
---

You are starting a new session on the Caffeine compiler project. Use the dynamic context below plus the project memory already loaded (CLAUDE.md + MEMORY.md) to orient yourself, then provide a brief session briefing.

## Recent Git Activity
!`git log --oneline -20`

## Current Working State
!`git status --short`

## Recently Touched Files (last 7 days)
!`git log --since="7 days ago" --name-only --pretty=format: | sort -u | head -30`

---

After reviewing the above, provide a **session briefing** with:
1. **Current state**: version, recent commits, any uncommitted changes
2. **Recent focus**: what areas have been worked on (infer from file names + commit messages)
3. **Watch-outs**: anything notable (e.g., staged-but-uncommitted changes, in-progress work)
4. **Ask**: what should we work on today?

Keep it concise. You already have full project knowledge from CLAUDE.md and MEMORY.md — don't re-explain the whole architecture, just the current snapshot.

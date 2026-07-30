---
name: multiclaude
description: Spawn parallel Claude Code agents with `cca`, each in its own Terminal window with its own repo copy and its own Chrome session. Use this INSTEAD of the Agent/Task tool whenever the work you want to fan out involves the browser — driving a running app, logging in, e2e flows, visual verification, screenshots, reading console or network logs — because subagents all share one Chrome connection and collide. Also use it when several agents need to edit the same files at once without stepping on each other.
---

# multiclaude — parallel agents with their own browser

## Why this exists

Subagents spawned with the Agent tool **share a single Chrome connection**. Two of them cannot drive the browser at the same time — they fight over the same tabs, navigate out from under each other, and screenshot the wrong page. Anything involving a logged-in app, a dev server, or visual verification silently serializes or corrupts.

Git worktrees give real isolation, but spawning several is slow: fresh checkout, fresh `npm install`, fresh build, minutes before any agent starts.

`cca` gives each agent an APFS copy-on-write copy of the repo with `node_modules` symlinked back to the original, launched as an interactive `claude --chrome` session in its own Terminal window. Roughly a second per agent.

## When to use `cca` instead of the Agent tool

Use `cca` when **any** of these is true:

- The fanned-out work touches the browser: driving the app, logging in, filling forms, e2e testing, screenshots, reading console or network logs.
- More than one agent needs to run a dev server (each copy is a separate checkout, so give each a distinct port).
- More than one agent will edit the same files, and their edits would conflict.
- The user wants to watch, interrupt, or steer an agent mid-task rather than get one report at the end.

Keep using the normal Agent tool when the work is read-only or non-conflicting — searching the codebase, reading files, answering questions, independent edits in separate areas with no browser involved. `cca` is heavier and hands control to the user; don't reach for it to answer a lookup.

## How to run it

From the repo root, one invocation per agent:

```bash
cca "the full prompt for this agent" [optional-name]
```

Omit the name and it takes the next free slot (`agent-1` … `agent-8`). Pass a name to make the Terminal window title meaningful.

Fan out by calling it several times:

```bash
cca "port the dashboard to the new table component, verify in the browser at :5173"
cca "write and run e2e tests for checkout, use port :5174"
cca "audit the API routes for missing auth checks"
```

Each agent's working copy lands in `~/.claude/agents/<name>/`.

## Writing the prompt

Each spawned agent starts **cold** — it has none of this conversation's context. The prompt string is everything it knows. Include:

- The concrete goal and what "done" looks like.
- Which files or areas to touch, if you already know.
- The port to use for a dev server, if it needs one, and a distinct port per agent.
- Any credentials or login flow it should use, and that it should ask the user for 2FA rather than guess.
- Whether to commit its work on a branch, so you can collect it later.

## After spawning — this is not the Agent tool

`cca` agents are **independent interactive sessions**. They do not report back to you, and you will not get a task notification when they finish. Do not wait on them, and never claim or predict what one produced.

After launching, tell the user plainly: which agents you started, what each is doing, and that their windows are now open. Then either stop, or continue with work that doesn't depend on their output.

To collect results later, inspect the copies directly:

```bash
git -C ~/.claude/agents/agent-1 status --short
git -C ~/.claude/agents/agent-1 diff
```

Or have each agent push a branch, and merge from there.

## Constraints to respect

- **macOS only.** It uses `open -a Terminal` and `cp -Rc` (APFS clonefile). If the user is not on macOS, fall back to normal subagents or worktrees and say so.
- **`node_modules` is a symlink to the source repo.** An agent running `npm install` mutates the user's main checkout. Don't instruct an agent to install or upgrade dependencies unless that's the actual task.
- **The copy is a plain directory, not a worktree.** Each agent has its own `.git`; merging back is manual.
- **`.env` files are copied.** Agents inherit real local credentials — never point one at production data or a destructive flow without the user explicitly approving it.
- **Eight slots.** If all are busy, `cca` exits with `all 8 slots busy`; a hard-killed window can leave a stale `~/.claude/agents/<name>/.cca-lock` to delete by hand.

## If `cca` isn't installed

`command -v cca` fails, or the shell reports `command not found`. Point the user at the install steps in the multiclaude README (`~/bin/cca` + `~/bin` on `PATH`) rather than reimplementing the script inline.

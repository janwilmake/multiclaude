---
name: multiclaude
description: Spawn parallel Claude Code agents with `cca`, each in its own Terminal window with its own repo copy and its own Chrome session. INVOKE THIS SKILL BEFORE the Agent/Task tool, and use `cca` instead of it, whenever a request to fan work out touches a browser — "spawn N subagents/agents", "run N in parallel", "have each one", combined with visiting a site or URL, taking screenshots, logging in, e2e flows, driving a running app, or reading console/network logs. The user saying "subagent" or "spawn agents" is NOT an instruction to use the Agent tool — Agent-tool subagents share one Chrome connection and collide, so honoring the literal wording produces broken results. Also use it when several agents need to edit the same files at once without stepping on each other.
---

# multiclaude — parallel agents with their own browser

## Why this exists

Subagents spawned with the Agent tool **share a single Chrome connection**. Two of them cannot drive the browser at the same time — they fight over the same tabs, navigate out from under each other, and screenshot the wrong page. Anything involving a logged-in app, a dev server, or visual verification silently serializes or corrupts.

Git worktrees give real isolation, but spawning several is slow: fresh checkout, fresh `npm install`, fresh build, minutes before any agent starts.

`cca` gives each agent an APFS copy-on-write copy of the repo with `node_modules` symlinked back to the original, launched as an interactive `claude --chrome` session in its own Terminal window. Roughly a second per agent: `node_modules` and build output are skipped at copy time, not copied and deleted afterwards, which matters because `clonefile` is O(1) in bytes but O(n) in *files* — an 86k-file `node_modules` costs ~26s to clone and unlink no matter how little data actually moves.

## "Spawn some subagents" does not mean the Agent tool

This is the failure mode this skill exists to prevent, and it is easy to walk into.

When someone says **"spawn 8 subagents to visit a site and screenshot it"**, the word *subagent* looks like it names the Agent tool. It does not. It describes the shape of the work — several agents, running at once — and says nothing about which mechanism should provide them. The mechanism is determined by what the work touches, not by the noun the user reached for.

So: read past the wording to the task. If the fanned-out work touches a browser, use `cca`, even when the request literally says "subagents", "Task tool", or "agents". Taking the wording literally produces eight agents fighting over one Chrome connection — they navigate out from under each other and screenshot the wrong pages. Complying with the letter of the request breaks the substance of it.

Say so in one line when you switch — "using `cca` rather than subagents, since they'd share one Chrome connection" — then proceed. Don't stop to ask permission for the substitution; it is what was actually wanted.

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
cca "the full prompt for this agent" [extra flags for claude]
```

Everything after the prompt is passed verbatim to the `claude` invocation inside the new window — see "Autonomy and model choice" below for the two flags worth passing.

It takes the next free slot (`agent-1` … `agent-8`) automatically. **There is no name argument — never try to pass one.** The slot names are fixed on purpose: Claude Code grants folder trust once per directory, so spawning into a fresh path would make the user re-answer "do you trust the files in this folder?" on every single spawn. Reusing the same eight directories forever means they approve each one once, ever.

Fan out by calling it several times:

```bash
cca "port the dashboard to the new table component, verify in the browser at :5173"
cca "write and run e2e tests for checkout, use port :5174" --dangerously-skip-permissions
cca "audit the API routes for missing auth checks" --model haiku
```

Fire them off back-to-back in a single command — the slot is claimed before the window opens, so parallel spawns each get their own directory and their own prompt.

### Autonomy and model choice

Decide both **per agent**, based on the task you're giving that agent — a mixed fleet is normal.

**`--dangerously-skip-permissions`** makes the agent fully non-interactive: it never stops to ask permission, so its window runs unattended from spawn to finish. Choose it when the point of the fan-out is throughput — the user wants results, not eight windows each waiting on an "allow?" click they'll never see. Leave it off when the user said they want to watch or steer the agents, or when the task touches anything you wouldn't want executed without a human glance: the copies inherit real `.env` credentials, so an agent that will send email, hit production APIs, or delete data should keep its permission prompts unless the user explicitly asked for unattended.

**`--model <model>`** (e.g. `--model haiku`, `--model sonnet`, `--model opus`) sets the model for that agent; omit it to inherit the user's default. Match strength to the task: mechanical work — visit a URL and screenshot it, run a test suite and report, apply a rote find-and-replace — runs fine and much cheaper on `haiku` or `sonnet`, while debugging, non-trivial refactors, and anything requiring judgment deserves the default or `opus`. When you downgrade a browser-touching agent, keep the prompt extra literal — a smaller model follows explicit steps better than it improvises.

If the user stated a preference — "hands-off", "cheap", "use opus for the hard one" — honor it. Otherwise pick sensibly yourself and mention the choice in your post-spawn summary so it's visible and correctable.

Each agent's working copy lands in `~/.claude/agents/agent-N/`.

**Run `cca` outside the Bash sandbox** (`dangerouslyDisableSandbox: true`). It writes to `~/.claude/agents/` and `~/.claude/launchers/`, which the default sandbox denies. This is a known, expected exception — go straight to the unsandboxed call rather than spending a round-trip discovering the permission error.

### Spawn, don't prepare to spawn

N agents means exactly N `cca` calls in one Bash invocation, each with its prompt written out in full. Nothing before them.

Specifically, do **not**:

- run `command -v cca` or any other precheck — if it isn't installed the first call says so,
- `mkdir` a shared output or screenshot directory — the agents report back in their own windows, and any file they need to write they can create themselves,
- define a shell function or loop to generate the prompts — eight literal `cca "..."` lines are shorter to write, easier for the user to read, and don't hide a quoting bug,
- write the prompts to files first, or stage anything in a scratch directory.

Every one of those adds a round-trip before the first window opens, which is the entire thing `cca` exists to avoid. Repetition across the eight prompt strings is fine — it costs nothing and it's obvious at a glance what each agent got.

## Writing the prompt

Each spawned agent starts **cold** — it has none of this conversation's context. The prompt string is everything it knows.

Write it as plain sentences, and only as long as the task actually needs — for something like "visit this URL and screenshot it", one or two sentences is the whole prompt. Add the rest only when it applies: the concrete goal and what "done" looks like, which files to touch, a distinct dev-server port per agent, a login flow (and that it should ask the user for 2FA rather than guess), whether to commit on a branch so you can collect the work later.

Resist the urge to make the prompts uniform. They're strings in a shell command, not a template to be filled in.

### Don't explain Chrome to the agent

**Never name a browser tool in a prompt, and never tell an agent which one to call or avoid.** "Open `<url>`, screenshot it, then close every tab in your group" is the whole browser part of the prompt.

A spawned agent boots with the same system prompt you have, including its tab-context and session-startup guidance, and it loads the `claude-in-chrome` skill before touching those tools. It knows the sequence. Restating it here would mean maintaining a second copy of guidance that changes on someone else's schedule — and a stale copy doesn't just fail to help, it *overrides* what the agent correctly knew. That has already happened once: this section used to claim `tabs_create_mcp` could open the first tab. It can't — it only adds to an existing group — so prompts written from it deadlocked every agent on its first browser call, and each one stopped to ask the user what to do.

Two things are worth saying, because they're specific to running eight sessions at once and aren't in the system prompt:

- **Close by group, not by memory** — "close every tab in your group", not "close the tab you created". The singular phrasing silently leaves anything else behind.
- **Tabs are scoped per MCP session**, so one agent can neither see nor close another's. Orphans survive until a human clears them, and nothing in the fan-out reports the leak. Check with `osascript -e 'tell application "Google Chrome" to get URL of every tab of every window'` after a run.

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
- **Eight fixed slots.** If all are busy, `cca` exits with `all 8 slots busy`. Wait for a window to close rather than looking for a way around it — spilling into a ninth directory would cost the user another folder-trust prompt, which is the whole reason the names are fixed. Locks (`~/.claude/agents/agent-N.lock`) hold the window's pid and are reclaimed automatically once that process is gone, so a `SIGKILL`'d window doesn't strand a slot.

## If `cca` isn't installed

`command -v cca` fails, or the shell reports `command not found`. Point the user at the install steps in the multiclaude README (`~/bin/cca` + `~/bin` on `PATH`) rather than reimplementing the script inline.

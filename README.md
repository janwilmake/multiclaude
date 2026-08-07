# multiclaude

`cca` — spawn parallel Claude Code agents, each in its own Terminal window, each with its own Chrome session, in about a second.

## The problem

Running several Claude Code agents on one repo at the same time is awkward:

- **Subagents can't have their own Chrome session.** Everything spawned inside a single Claude Code session shares one browser connection, so two subagents can't drive the browser independently — they fight over the same tabs. Anything involving a logged-in app, a dev server, or visual verification serializes.
- **Git worktrees solve isolation, but spawning several is slow.** A fresh worktree means a fresh checkout, a fresh `npm install`, a fresh build. Doing that four or five times to fan out costs minutes before any agent starts working.
- **Subagents aren't interactive.** They report back at the end. You can't watch one, interrupt it, or steer it mid-task.

## What `cca` does

One command per agent. Each agent gets:

- **Its own full copy of the repo**, made with APFS copy-on-write (`cp -Rc`). Near-instant and near-zero disk, because unchanged files share blocks with the original.
- **`node_modules` symlinked back to the original repo**, so there's no reinstall — the single most expensive part of a worktree. It's skipped during the copy rather than copied and deleted afterwards: `clonefile` is O(1) in bytes but O(n) in *files*, so cloning an 86k-file `node_modules` and unlinking it again burns ~26s per agent even though almost no data moves.
- **Its own Terminal window running interactive `claude --chrome`**, so it gets its own browser session and you can watch, interrupt, and steer it like a normal Claude Code session.
- **A fixed slot name** (`agent-1` … `agent-8`), set as the window title so you can tell the windows apart, with a lock file so a new `cca` invocation never lands on a slot that's already busy. The slot is claimed before the window opens, so you can fire all eight spawns at once and each still gets its own directory.

Slot names are **not** configurable, and that's deliberate. Claude Code asks "do you trust the files in this folder?" once per directory and remembers the answer. Spawning into a fresh path would mean answering that prompt again on every single spawn. Reusing the same eight directories forever means you approve each one once, ever — so `cca` takes a prompt, optional flags for `claude`, and no name.

When Claude exits, the window drops into your shell inside the agent's copy — so you can inspect the diff, run tests, or commit from there.

## Usage

```bash
cd ~/code/my-repo

cca "fix the failing auth tests"
```

It takes the next free slot automatically. There is no name argument.

Run it several times to fan out:

```bash
cca "port the dashboard to the new table component"
cca "write e2e tests for checkout"
cca "audit the API routes for missing auth checks"
```

Three Terminal windows, three isolated copies, three independent Chrome sessions.

Anything after the prompt is passed straight to `claude`, so you can tune autonomy and model per agent:

```bash
cca "run the e2e suite and fix what breaks" --dangerously-skip-permissions
cca "screenshot every page in the nav" --model haiku
```

`--dangerously-skip-permissions` makes that agent fully non-interactive — no permission prompts, so the window runs unattended (remember the copy inherits your real `.env`). `--model` picks a cheaper or stronger model for that agent; omit it to use your default.

Fire them back-to-back or in parallel (`cca "..." &`) — claiming a slot takes a millisecond and happens before the window opens, so spawns never collide.

Copies live in `~/.claude/agents/agent-N/`. The generated launcher scripts live in `~/.claude/launchers/`, and each slot's lock is `~/.claude/agents/agent-N.lock`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/janwilmake/multiclaude/main/install.sh | sh
```

That drops `cca` on your `PATH` and installs the bundled Claude Code skill. Restart Claude Code afterwards so the skill is picked up, then check it's there:

```bash
cca
# usage: cca "prompt" [claude flags...]
```

Re-run the same line any time to update. It prints exactly what it wrote, and warns if the install directory isn't on your `PATH` or if `claude` isn't installed yet.

`cca` goes in `~/.local/bin` or `~/bin` — whichever is already on your `PATH`, defaulting to `~/.local/bin`. The skill goes in `~/.claude/skills/multiclaude/`. Override with environment variables:

```bash
# install somewhere specific, from a branch, without the skill
curl -fsSL https://raw.githubusercontent.com/janwilmake/multiclaude/main/install.sh \
  | CCA_BIN_DIR=/usr/local/bin CCA_REF=some-branch CCA_SKILL=0 sh
```

(The variables go on `sh`, not on `curl` — a `VAR=x curl ... | sh` would set them for the download instead of the installer.)

### Or clone and symlink

If you'd rather track the repo — edits to your clone take effect immediately, and `install.sh` won't overwrite a symlinked skill:

```bash
git clone https://github.com/janwilmake/multiclaude.git
ln -s "$PWD/multiclaude/cca" ~/bin/cca
ln -s "$PWD/multiclaude/.claude/skills/multiclaude" ~/.claude/skills/multiclaude
```

### What the skill does

[`.claude/skills/multiclaude/SKILL.md`](.claude/skills/multiclaude/SKILL.md) tells Claude Code to reach for `cca` instead of its own subagents whenever the fanned-out work involves the browser. The installer puts it in `~/.claude/skills/` so it applies everywhere; drop a copy in a single project's `.claude/skills/` instead to scope it there.

## Requirements

- **macOS.** It uses `open -a Terminal` to spawn windows, and `cp -Rc` (APFS clonefile) for the fast copy. On a non-APFS volume the script falls back to a plain `cp -R`, which works but is slow.
- **Claude Code** on your `PATH`, with the `--chrome` flag available (Claude in Chrome extension set up).

## Caveats

- The copy is a **plain directory copy, not a git worktree**. Each agent has the full `.git` from the moment of the copy, so committing and branching work fine — but the agents don't share a git dir, and you have to merge the work back yourself (`git -C ~/.claude/agents/agent-1 diff`, or push a branch from inside the copy).
- `node_modules` is a **symlink to the original repo**. Agents share dependencies, so an agent running `npm install` mutates your main checkout's `node_modules`. That's the trade-off that makes spawning fast.
- The script skips build output when copying (`build/`, `.react-router/`, `coverage/`) — edit that `case` line for your project's artifacts.
- `.env` files are copied along with everything else, since it's a raw directory copy. Agents get your local credentials; keep that in mind before pointing one at production.
- **Claude Code's Bash sandbox denies writes under `~/.claude/`**, so a sandboxed `cca` call can't claim a slot. Run it with the sandbox disabled (the bundled skill tells Claude to do this). `cca` fails immediately with the underlying error rather than retrying, so it's obvious when this is what happened.
- Slots cap at 8. When all eight are busy `cca` exits with `all 8 slots busy` rather than spilling into a ninth directory — a new path would cost another folder-trust prompt, so waiting is the intended behaviour. Close a window to free its slot.
- The lock is released when the agent's Terminal window closes (normal exit or `SIGHUP`). A `SIGKILL`'d window leaves `~/.claude/agents/agent-N.lock` behind, but it holds the window's pid, so the next `cca` sees the process is gone and reclaims the slot — no manual cleanup.

## License

MIT

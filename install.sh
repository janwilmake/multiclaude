#!/bin/sh
# multiclaude installer.
#
#   curl -fsSL https://raw.githubusercontent.com/janwilmake/multiclaude/main/install.sh | sh
#
# Installs the `cca` script onto your PATH and the Claude Code skill into
# ~/.claude/skills/. Re-run it any time to update; it overwrites both.
#
# Environment overrides:
#   CCA_BIN_DIR    where to put `cca` (default: first of ~/.local/bin, ~/bin
#                  already on PATH, else ~/.local/bin)
#   CCA_REF        git ref to install from (default: main)
#   CCA_SKILL=0    skip installing the Claude Code skill
#   CCA_SKILL_DIR  where to put the skill (default: ~/.claude/skills/multiclaude)

set -eu

RAW="https://raw.githubusercontent.com/janwilmake/multiclaude"
REF="${CCA_REF:-main}"
SKILL_DIR="${CCA_SKILL_DIR:-$HOME/.claude/skills/multiclaude}"

say() { printf '%s\n' "$*"; }
warn() { printf '\n! %s\n' "$*" >&2; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

on_path() {
  case ":${PATH:-}:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# cca spawns Terminal windows with `open -a Terminal` and clones the repo with
# `cp -Rc` (APFS clonefile). Neither exists off macOS, so installing elsewhere
# would only produce a script that fails on first use.
[ "$(uname -s)" = "Darwin" ] || die "multiclaude is macOS-only (needs APFS clonefile and Terminal.app)"
command -v curl >/dev/null 2>&1 || die "curl not found"

if [ -n "${CCA_BIN_DIR:-}" ]; then
  BIN="$CCA_BIN_DIR"
elif on_path "$HOME/.local/bin"; then
  BIN="$HOME/.local/bin"
elif on_path "$HOME/bin"; then
  BIN="$HOME/bin"
else
  BIN="$HOME/.local/bin"
fi
mkdir -p "$BIN" || die "cannot create $BIN"

TMP="$(mktemp -d)" || die "cannot create a temp dir"
trap 'rm -rf "$TMP"' EXIT INT TERM

fetch() {
  curl -fsSL "$1" -o "$2" || die "download failed: $1"
}

# Download to a temp file and move into place, so an interrupted or 404'd
# fetch can never leave a half-written `cca` on your PATH. GitHub serves a
# 404 page with a 404 status, which curl -f turns into a non-zero exit, but
# check the shebang too in case CCA_REF points somewhere unexpected.
fetch "$RAW/$REF/cca" "$TMP/cca"
head -n 1 "$TMP/cca" | grep -q '^#!' || die "downloaded cca is not a script — is CCA_REF='$REF' a real ref?"
chmod +x "$TMP/cca"
mv "$TMP/cca" "$BIN/cca"
say "installed $BIN/cca"

skill_installed=0
if [ "${CCA_SKILL:-1}" = "0" ]; then
  say "skipped the Claude Code skill (CCA_SKILL=0)"
elif [ -L "$SKILL_DIR" ]; then
  # A symlinked skill dir means it's served out of a git clone. Overwriting it
  # would write through the link into that clone's working tree.
  say "skipped the skill: $SKILL_DIR is a symlink into a clone — update it there"
else
  mkdir -p "$SKILL_DIR" || die "cannot create $SKILL_DIR"
  fetch "$RAW/$REF/.claude/skills/multiclaude/SKILL.md" "$TMP/SKILL.md"
  head -n 1 "$TMP/SKILL.md" | grep -q '^---' || die "downloaded SKILL.md is missing its frontmatter"
  mv "$TMP/SKILL.md" "$SKILL_DIR/SKILL.md"
  say "installed $SKILL_DIR/SKILL.md"
  skill_installed=1
fi

out="$("$BIN/cca" 2>&1 || true)"
case "$out" in
  *"usage: cca"*) ;;
  *) die "installed, but $BIN/cca did not run: $out" ;;
esac

if ! on_path "$BIN"; then
  case "${SHELL:-}" in
    */zsh) rc="~/.zshrc" ;;
    */bash) rc="~/.bash_profile" ;;
    *) rc="your shell's startup file" ;;
  esac
  warn "$BIN is not on your PATH. Add this to $rc and restart your shell:

    export PATH=\"$BIN:\$PATH\""
fi

command -v claude >/dev/null 2>&1 || warn "\`claude\` is not on your PATH. cca launches \`claude --chrome\`, so install Claude Code before using it."

say ""
if [ "$skill_installed" = "1" ]; then
  say "Done. Restart Claude Code to pick up the skill, then from any repo:"
else
  say "Done. From any repo:"
fi
say ""
say "    cca \"fix the failing auth tests\""

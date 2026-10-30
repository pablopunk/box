#!/bin/sh
# box installer. The only instruction needed:
#   curl -fsSL https://raw.githubusercontent.com/pablopunk/box/main/install.sh | sh
#
# Clones this repo to ~/.local/share/box, links `box` into ~/.local/bin,
# installs the skill into ~/.agents/skills and ~/.claude/skills (symlink-aware:
# dirs resolving to the same place get one install, never two),
# then runs the guided `box init` TUI.
set -eu

BOX_REPO="${BOX_REPO:-pablopunk/box}"
BOX_REF="${BOX_REF:-main}"
BOX_URL="${BOX_URL:-https://github.com/${BOX_REPO}.git}"
SHARE="${BOX_HOME:-$HOME/.local/share/box}"
BIN_DIR="$HOME/.local/bin"

log() { printf 'box installer: %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { log "need '$1' — please install it first"; exit 1; }; }
need git
need ssh

# --- 1. repo (the repo root IS the skill: SKILL.md lives here) ---
if [ -d "$SHARE/.git" ]; then
  log "updating $SHARE"
  git -C "$SHARE" pull --ff-only >&2 || log "pull failed; continuing with local copy"
else
  log "cloning $BOX_URL ($BOX_REF) into $SHARE"
  mkdir -p "$(dirname "$SHARE")"
  git clone --depth 1 --branch "$BOX_REF" "$BOX_URL" "$SHARE" >&2
fi
[ -f "$SHARE/box" ] && [ -f "$SHARE/SKILL.md" ] || { log "broken checkout: $SHARE has no box/SKILL.md"; exit 1; }
chmod +x "$SHARE/box"

# --- 2. binary ---
mkdir -p "$BIN_DIR"
ln -sfn "$SHARE/box" "$BIN_DIR/box"
log "linked $BIN_DIR/box"

# --- 3. skills (once per real location; never double-install symlinked dirs) ---
canon() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$1" 2>/dev/null || realpath "$1" 2>/dev/null || printf '%s\n' "$1"
  elif [ -e "$1" ] || [ -L "$1" ]; then
    ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}
HANDLED=""
install_skill() {
  dir=$1
  mkdir -p "$dir"
  c=$(canon "$dir")
  case " $HANDLED " in
    *" $c "*) log "skipping $dir (same place as an already-installed skills dir)"; return 0;;
  esac
  HANDLED="$HANDLED $c"
  dest="$dir/box"
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -e "$dest" ] && [ ! -f "$dest/.box-installed" ]; then
    bak="$dest.bak-$(date +%s)"
    mv "$dest" "$bak"
    log "backed up existing $dest to $bak"
  fi
  mkdir -p "$dest"
  cp "$SHARE/SKILL.md" "$dest/SKILL.md"
  : > "$dest/.box-installed"
  log "installed skill: $dest"
}
install_skill "$HOME/.agents/skills"
install_skill "$HOME/.claude/skills"

# --- 4. PATH hint ---
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) log "add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- 5. guided setup (needs a real terminal; stdin is the curl pipe) ---
# Probe by actually opening /dev/tty: test -r succeeds without a controlling
# terminal but the open fails, so only the open is a reliable check.
if ( : </dev/tty ) 2>/dev/null && ( : >/dev/tty ) 2>/dev/null; then
  log "starting guided setup..."
  "$BIN_DIR/box" init </dev/tty >/dev/tty 2>&1 || log "setup did not finish; run 'box init' to retry"
else
  log "no terminal for guided setup; run: box init"
fi
log "done."

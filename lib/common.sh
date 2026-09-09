#!/usr/bin/env bash
# Paths, logging, and the small selection files. Sourced by omarchy-hf-agent; do not run.
#
# Everything the plugin persists lives in $STATE, and there is no ledger: nothing runs in the
# background, every verb finishes before it returns, so the snapshot is the whole state.
#   token          the one secret; it lives in this file only, never in the snapshot, the log, or argv
#   auth           "Authorization: Bearer <token>", the header file curl reads with -H @auth
#   models.json    the model ids the router listed last time `models` ran
#   model, harness, agent-dir   one line each: what was picked
#   snapshot.json  the read model the panel watches (rewritten, never edited); carries the last error
#   log            every verb and every refusal, for "refusal out loud" beyond the one-line error
#   agents/        per-agent launch config generated at launch time (no secret inside)

HOME_DIR="${OMARCHY_HF_USER_HOME:-$HOME}"
STATE="${OMARCHY_HF_STATE:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/omarchy/hf-agent}"
ROUTER="${OMARCHY_HF_ROUTER:-https://router.huggingface.co}"
TIMEOUT="${OMARCHY_HF_TIMEOUT:-20}"
TOKEN_FILE="$STATE/token"
AUTH_FILE="$STATE/auth"
MODELS_FILE="$STATE/models.json"
SNAPSHOT="$STATE/snapshot.json"
LOGFILE="$STATE/log"

# Everything under $STATE is private to this user: the directory is 0700 and every file the plugin
# writes there is 0600, because one of them is the token.
umask 077
state_dir() { mkdir -p "$STATE" && chmod 700 "$STATE"; }

fail() { printf 'hf-agent: %s\n' "$*" >&2; return 1; }
# refuse is fail for verbs the panel invokes: the message must also land in the snapshot, because
# the panel never sees the process's stderr.
refuse() { printf 'hf-agent: %s\n' "$*" >&2; log "error: $*"; snapshot_write "$*"; return 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { state_dir; printf '%s %s\n' "$(now)" "$*" >>"$LOGFILE"; }
bin_of() { [[ -x $HOME_DIR/.local/bin/$1 ]] && printf '%s\n' "$HOME_DIR/.local/bin/$1" || command -v "$1"; }

# the picks are one-line files; reading an absent one is the empty pick
pick_read() { cat "$STATE/$1" 2>/dev/null || true; }
pick_write() { state_dir; if [[ -n $2 ]]; then printf '%s' "$2" >"$STATE/$1"; else rm -f "$STATE/$1"; fi; }
token_set_p() { [[ -s $TOKEN_FILE ]]; }

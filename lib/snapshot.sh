#!/usr/bin/env bash
# The read model. Sourced; do not run.
#
# snapshot_write [error] derives everything from the files in $STATE plus which harnesses are
# installed, and rewrites $SNAPSHOT. The token is reported as set or not and by its file's path,
# never by value. The error is the one thing that persists only here: a verb passes its refusal
# in, a verb that worked passes "" to retire it, and a plain `snapshot` keeps what was there.

snapshot_write() {
  state_dir
  local err models
  if (($#)); then err=$1; else err=$(jq -r '.error // ""' "$SNAPSHOT" 2>/dev/null || true); fi
  models=$(cat "$MODELS_FILE" 2>/dev/null || true); [[ -n $models ]] || models='[]'
  jq -nc --arg t "$(now)" --argjson set "$(token_set_p && echo true || echo false)" --arg tf "$TOKEN_FILE" \
    --argjson models "$models" --arg model "$(pick_read model)" --argjson h "$(harnesses_json)" --arg harness "$(pick_read harness)" \
    --arg router "$ROUTER" --arg err "$err" '
    {schemaVersion:"omarchy-hf-agent/snapshot/1", updatedAt:$t, router:$router,
     token:{set:$set, file:$tf}, models:$models, model:$model, harnesses:$h, harness:$harness, error:$err}' \
    >"$SNAPSHOT.tmp.$$" && mv "$SNAPSHOT.tmp.$$" "$SNAPSHOT"
}

#!/usr/bin/env bash
# The Hugging Face Inference Providers router. Sourced; do not run.
#
# The router at https://router.huggingface.co/v1 is OpenAI-compatible: GET /v1/models lists what
# the providers serve, POST /v1/chat/completions answers. That is the whole surface this plugin
# assumes (see README). The token reaches curl as a header file (-H @auth), never as an argument,
# so /proc/<pid>/cmdline shows a path.

auth_file() { # auth_file <token-file>: (re)write the header file from a token file
  state_dir; printf 'Authorization: Bearer %s\n' "$(cat "$1")" >"$AUTH_FILE"
}
router_get() { # router_get <path> <body-file> -> prints the HTTP status; 000 when curl could not connect
  curl -sS -m "$TIMEOUT" -o "$2" -w '%{http_code}' -H @"$AUTH_FILE" "$ROUTER$1" 2>>"$LOGFILE" || printf 000
}
models_cache() { # models_cache <body-file>: keep the ids the router listed, alphabetical, no duplicates
  jq -c '[.data[]?.id // empty] | unique' "$1" >"$MODELS_FILE.tmp.$$" 2>/dev/null && mv "$MODELS_FILE.tmp.$$" "$MODELS_FILE"
}

# token_set <value>: the token is proven against the router before it is kept. A 401 is the one
# answer that means "wrong token"; anything else is the network or the router, said as such, and
# nothing is written, so a typo never replaces a working token.
token_set() {
  local body="$STATE/models.body.$$" code
  state_dir; printf '%s' "$1" >"$TOKEN_FILE.new"
  auth_file "$TOKEN_FILE.new"
  code=$(router_get /v1/models "$body")
  case $code in
    200) mv "$TOKEN_FILE.new" "$TOKEN_FILE"; models_cache "$body"; rm -f "$body"; log "token set and accepted by the router" ;;
    401|403) rm -f "$TOKEN_FILE.new" "$body"; token_set_p && auth_file "$TOKEN_FILE" || rm -f "$AUTH_FILE"
         fail "Hugging Face rejected that token ($code): make a token with inference permission at https://huggingface.co/settings/tokens and try again" ;;
    000) rm -f "$TOKEN_FILE.new" "$body"; token_set_p && auth_file "$TOKEN_FILE" || rm -f "$AUTH_FILE"
         fail "could not reach $ROUTER (see $LOGFILE)" ;;
    *) rm -f "$TOKEN_FILE.new" "$body"; token_set_p && auth_file "$TOKEN_FILE" || rm -f "$AUTH_FILE"
       fail "the router answered $code instead of listing models; the token was not kept" ;;
  esac
}
token_clear() { rm -f "$TOKEN_FILE" "$TOKEN_FILE.new" "$AUTH_FILE"; log "token cleared"; }

models_fetch() { # models_fetch: refresh the cached list; refuses out loud without a token or without the network
  local body="$STATE/models.body.$$" code
  token_set_p || { fail "no token: run omarchy-hf-agent token <hf_...>"; return; }
  auth_file "$TOKEN_FILE"
  code=$(router_get /v1/models "$body")
  case $code in
    200) models_cache "$body" || { rm -f "$body"; fail "the router's model list was not the expected shape"; return; }; rm -f "$body"; log "models: $(jq length "$MODELS_FILE") listed" ;;
    401|403) rm -f "$body"; fail "Hugging Face rejected the stored token ($code): set a new one with omarchy-hf-agent token <hf_...>" ;;
    000) rm -f "$body"; fail "could not reach $ROUTER (see $LOGFILE)" ;;
    *) rm -f "$body"; fail "the router answered $code instead of listing models" ;;
  esac
}

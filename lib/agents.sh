#!/usr/bin/env bash
# Harnesses: launch-only. Sourced; do not run.
#
# The router reaches an agent only when the agent is launched from the panel: the endpoint, token,
# and model travel in the launch command's environment and flags. Nothing on disk that the user
# owns is edited. The router serves OpenAI chat completions in full. Its /v1/messages and
# /v1/responses answer simple requests but not what the agents actually send (checked live on
# 2026-09-09: Claude Code's Messages request comes back as a short non-Message body, and the
# Responses schema rejects Codex's tool definitions; Codex 0.147 dropped wire_api=chat, so it has
# no path left), so claude and codex are not offered. Re-check both when the router changes.

HARNESSES=(pi omp opencode ori grok agy hermes copilot crush)
ENDPOINT="$ROUTER/v1"

harnesses_json() { # -> {"installed":["pi",...],"default":"pi"}; the default is Omarchy's, when it is one of ours
  local a def="" installed='[]'
  for a in "${HARNESSES[@]}"; do
    bin_of "$a" >/dev/null 2>&1 || continue
    installed=$(jq -c --arg a "$a" '.+[$a]' <<<"$installed")
  done
  command -v omarchy-default-agent >/dev/null 2>&1 && def=$(omarchy-default-agent 2>/dev/null || true)
  jq -e --arg d "$def" 'index($d)!=null' <<<"$installed" >/dev/null 2>&1 || def=""
  jq -nc --arg d "$def" --argjson i "$installed" '{installed:$i,default:$d}'
}

# agent_command <name> <model> -> prints the argv (NUL-separated) to run in a terminal.
# Each agent gets its own spelling of "use this endpoint". The token never enters argv: with_key
# prefixes a tiny bash stage that reads the token file into the named variables and execs the
# agent, so /proc/<pid>/cmdline shows the file's path and the variable names, nothing more. Agents
# that take the key from a config file get the variable's name there, which they resolve themselves.
with_key() { # with_key <VAR>... : the stage, then the caller appends the agent's own argv
  printf '%s\0' bash -c 'k=$(cat "$1") || exit 1; shift; while [[ $1 != -- ]]; do export "$1=$k"; shift; done; shift; exec "$@"' omarchy-hf-agent-launch "$TOKEN_FILE" "$@" --
}
agent_command() {
  local name=$1 model=$2 bin cfg
  bin=$(bin_of "$name") || { fail "$name is not installed"; return; }
  case $name in
    opencode)
      # opencode resolves {env:NAME} inside its config, so the token stays out of the config text too
      cfg=$(jq -nc --arg u "$ENDPOINT" --arg m "$model" \
        '{"$schema":"https://opencode.ai/config.json",provider:{"hf":{npm:"@ai-sdk/openai-compatible",name:"Hugging Face",options:{baseURL:$u,apiKey:"{env:HF_TOKEN}"},models:{($m):{name:$m}}}}}')
      with_key HF_TOKEN
      printf '%s\0' env "OPENCODE_CONFIG_CONTENT=$cfg" "$bin" --model "hf/$model" ;;
    pi|omp)
      # pi reads providers from its agent dir; a plugin-owned dir keeps the user's own untouched. pi
      # takes apiKey as the value (a variable name is sent as-is: 401, checked live), so the token
      # goes into that 0600 file. omp also wants a config.yml there, or it opens its first-run wizard.
      local dir="$STATE/agents/$name"; mkdir -p "$dir"
      jq -nc --arg u "$ENDPOINT" --arg m "$model" --arg k "$(cat "$TOKEN_FILE")" \
        '{providers:{"hf":{baseUrl:$u,apiKey:$k,api:"openai-completions",models:[{id:$m,name:$m,input:["text"]}]}}}' \
        >"$dir/models.json"
      [[ $name == omp ]] && printf 'modelRoles:\n  default: hf/%s\nsetupVersion: 2\n' "$model" >"$dir/config.yml"
      with_key HF_TOKEN
      printf '%s\0' env "PI_CODING_AGENT_DIR=$dir" "OMP_CODING_AGENT_DIR=$dir" "$bin" --provider hf --model "$model" ;;
    crush)
      # crush takes providers from XDG config only, and its XDG data file pins the last chosen model
      # over the config: give it a plugin-owned config and data home; the token goes into that 0600 file
      local dir="$STATE/agents/crush/crush"; mkdir -p "$dir"
      # a mise shim would reinstall crush under the new data home: launch the real binary instead
      [[ $bin == */mise/shims/* ]] && command -v mise >/dev/null 2>&1 && bin=$(mise which crush 2>/dev/null || printf '%s' "$bin")
      jq -nc --arg u "$ENDPOINT" --arg m "$model" --arg k "$(cat "$TOKEN_FILE")" \
        '{providers:{"hf":{type:"openai",name:"Hugging Face",base_url:$u,api_key:$k,models:[{id:$m,name:$m,context_window:131072,default_max_tokens:8192}]}},models:{large:{provider:"hf",model:$m},small:{provider:"hf",model:$m}}}' \
        >"$dir/crush.json"
      with_key HF_TOKEN
      printf '%s\0' env "XDG_CONFIG_HOME=$STATE/agents/crush" "XDG_DATA_HOME=$STATE/agents/crush" "$bin" ;;
    copilot)
      with_key COPILOT_PROVIDER_API_KEY
      printf '%s\0' env "COPILOT_PROVIDER_BASE_URL=$ENDPOINT" "$bin" --model "$model" ;;
    grok)
      with_key XAI_API_KEY
      printf '%s\0' env "GROK_CLI_CHAT_PROXY_BASE_URL=$ENDPOINT" "$bin" ;;
    *) # OpenAI-compatible by convention: hermes, ori, agy read the standard variables
      with_key OPENAI_API_KEY
      printf '%s\0' env "OPENAI_BASE_URL=$ENDPOINT" "OPENAI_API_BASE=$ENDPOINT" "OPENAI_MODEL=$model" "$bin" ;;
  esac
}

launch() { # launch [name]: the picked harness when omitted; refuses out loud when anything is missing
  local name=${1:-} model
  token_set_p || { fail "no token: run omarchy-hf-agent token <hf_...>"; return; }
  model=$(pick_read model); [[ -n $model ]] || { fail "no model: pick one on the card or run omarchy-hf-agent model <id>"; return; }
  [[ -n $name ]] || name=$(pick_read harness)
  [[ -n $name ]] || name=$(harnesses_json | jq -r '.default // ""')
  [[ -n $name ]] || { fail "no harness: pick one on the card or run omarchy-hf-agent harness <name>"; return; }
  harnesses_json | jq -e --arg a "$name" '.installed|index($a)!=null' >/dev/null \
    || { fail "$name is not an installed harness this plugin can launch"; return; }
  local -a argv=(); while IFS= read -r -d '' v; do argv+=("$v"); done < <(agent_command "$name" "$model") || return 1
  log "launch $name on $model"
  if [[ ${OMARCHY_HF_FOREGROUND:-0} == 1 ]]; then printf '%q ' "${argv[@]}"; echo; return 0; fi
  # the agent works where the person works: OMARCHY_HF_AGENT_DIR, else the directory recorded by
  # `omarchy-hf-agent agent-dir <path>`, else wherever the shell was started (usually home)
  local dir=${OMARCHY_HF_AGENT_DIR:-$(pick_read agent-dir)}
  [[ -n $dir && -d $dir ]] && cd "$dir"
  # omarchy-launch-tui blocks for the terminal's whole life, so it is detached and its exit is not
  # the launch result. It goes through uwsm's fast app daemon, which can wedge ("Timed out waiting
  # for pipes", ten seconds per call): a two-second ping decides, and a wedged daemon gets the same
  # terminal command through the plain uwsm client instead.
  if ! command -v uwsm-app >/dev/null 2>&1 || timeout 2 uwsm-app ping >/dev/null 2>&1; then
    setsid omarchy-launch-tui --app-id=org.omarchy.agent "${argv[@]}" >/dev/null 2>>"$LOGFILE" </dev/null & disown
  elif command -v uwsm >/dev/null 2>&1 && command -v xdg-terminal-exec >/dev/null 2>&1; then
    log "uwsm app daemon is not answering; opening $name through uwsm app"
    setsid uwsm app -- xdg-terminal-exec --app-id=org.omarchy.agent -e "${argv[@]}" >/dev/null 2>>"$LOGFILE" </dev/null & disown
  else fail "could not open a terminal for $name: the uwsm app daemon is not answering"; return 1; fi
}

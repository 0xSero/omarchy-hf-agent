<h1 align="center">HF Agent for Omarchy</h1>

<p align="center">
  A Hugging Face Inference Providers model and a coding agent, one button on the bar.<br>
  Give it your token once, pick a model, pick a harness, Launch.
</p>

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-hf-agent.git --enable
```

Then, once, in a terminal:

```bash
omarchy-hf-agent token hf_...
```

The token is checked against the router before it is kept; a wrong one is
refused in a sentence. Click the new bar icon: **Model** lists what the
router serves, **Harness** lists the coding agents installed on this machine,
**Launch** opens the harness on the model in a terminal. A right-click on
the icon launches without opening the card.

### Requirements

- A Hugging Face token with the *inference* permission
  (<https://huggingface.co/settings/tokens>)
- At least one coding agent Omarchy can launch: pi, omp, opencode, ori,
  codex, grok, agy, hermes, copilot, or crush
- `jq`, `curl`

No Docker, no GPU, no model on disk, nothing to configure.

## What you get

- **The router's own model list.** `Model` shows the first twelve ids from
  `GET /v1/models`; any other id the router accepts, including a
  `:provider` suffix, goes in with `omarchy-hf-agent model <id>`.
- **Any coding agent, one click.** The agent opens with the router's
  endpoint, the model, and the token in its own environment. No config
  file of yours is read or written.
- **Refusals out loud.** No token, a rejected token, no model, a harness
  that is not installed, a router that does not answer: each is a sentence
  on the card, never a dead button.

## Commands

The card is the whole interface; the same verbs exist on the command line.

```
omarchy-hf-agent snapshot                refresh and print the state the card renders
omarchy-hf-agent token <value>|--clear   store the token (checked against the router), or forget it
omarchy-hf-agent models                  refresh the list of models the router serves
omarchy-hf-agent model <id>|--clear      pick a model by id, listed or not
omarchy-hf-agent harness <name>|--clear  pick the coding agent to launch
omarchy-hf-agent launch [name]           open the picked harness (or <name>) on the picked model
omarchy-hf-agent agent-dir <path>        the directory agents open in
```

State lives in `~/.local/state/omarchy/hf-agent/` (0700): the token, the
cached model list, the picks, the snapshot the card renders, and a log of
every verb.

## Remove

```bash
omarchy-hf-agent token --clear
omarchy plugin remove sero.hf-agent
rm -rf ~/.local/state/omarchy/hf-agent
```

## How it works

**The router.** Everything goes to `https://router.huggingface.co/v1`, the
OpenAI-compatible front of Hugging Face Inference Providers. The plugin
assumes exactly two endpoints: `GET /v1/models` to list and to prove the
token, and `POST /v1/chat/completions`, which the agents call. It does not
assume an Anthropic Messages endpoint, so **claude is not offered**; codex
is launched with `wire_api=chat`, since Responses is not assumed either.
Every other agent Omarchy knows speaks chat completions.

**The token** lives in one file, `~/.local/state/omarchy/hf-agent/token`
(0600), and nowhere else: not in the snapshot the card reads (it carries
the file's path), not in the log, not in any process argument. The plugin's
own requests hand curl a header file (`-H @auth`). An agent launch is a
two-word bash stage that reads the token file into the named variables and
execs the agent, so `/proc/<pid>/cmdline` shows a path and variable names.
Agents that want a config file (pi, omp, crush, opencode) get one in a
plugin-owned directory that names the variable, not the token.

**Nothing of yours is touched.** The plugin never reads or writes
`~/.claude.json`, `~/.codex`, `~/.config/opencode`, or any other user
config; a harness typed in a terminal keeps its own provider.

## Development

```bash
bash test/all   # isolated state, shimmed curl and agents; no network, no real agent
```

42 tests cover the token (set, refused, offline, replaced, cleared), the
model list and its cache, the picks, the launch argv of every agent family
with the token absent from argv and present in the launched environment,
and every refusal. They pass on macOS bash 3.2 and Linux.

## License

MIT.

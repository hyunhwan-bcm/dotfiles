#!/bin/sh

set -eu

pi_agent_dir=${PI_CODING_AGENT_DIR:-"$HOME/.pi/agent"}
settings_file="$pi_agent_dir/settings.json"
settings_backup="$settings_file.before-opencode-routing"
plan_package='npm:@narumitw/pi-plan-mode@0.24.0'
script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
model_router_source="$script_dir/pi/plan-build-model-router.ts"
model_router_file="$pi_agent_dir/extensions/plan-build-model-router.ts"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v pi >/dev/null 2>&1 || fail "pi is required"

mkdir -p "$pi_agent_dir"

if [ -f "$settings_file" ] && [ ! -f "$settings_backup" ]; then
  cp "$settings_file" "$settings_backup"
fi

plan_install_dir="$pi_agent_dir/npm/node_modules/@narumitw/pi-plan-mode"
if ! jq -e --arg plan_package "$plan_package" '
  [.packages[] | if type == "string" then . else .source end]
  | index($plan_package) != null
' "$settings_file" >/dev/null 2>&1 || [ ! -d "$plan_install_dir" ]; then
  pi install "$plan_package"
fi

settings_tmp=$(mktemp "$pi_agent_dir/settings.json.tmp.XXXXXX")

cleanup() {
  rm -f "$settings_tmp"
}
trap cleanup EXIT HUP INT TERM

jq --arg plan_package "$plan_package" '
  .defaultProvider = "opencode-go"
  | .defaultModel = "deepseek-v4-flash"
  | .enabledModels = [
      "opencode-go/kimi-k3",
      "opencode-go/deepseek-v4-flash"
    ]
  | .packages = (
      (.packages // [])
      | map(
          select(
            (
              (if type == "string" then . else .source end)
              | (
                  startswith("npm:pi-tiered-router")
                  or startswith("npm:@narumitw/pi-plan-mode")
                )
            )
            | not
          )
        )
      + [$plan_package]
    )
' "$settings_file" >"$settings_tmp"

jq -e . "$settings_tmp" >/dev/null

mv "$settings_tmp" "$settings_file"
mkdir -p "$pi_agent_dir/extensions"
cp "$model_router_source" "$model_router_file"
chmod 600 "$settings_file"
chmod 644 "$model_router_file"
trap - EXIT HUP INT TERM

printf 'Configured Pi: Kimi K3 plans, approval gate, DeepSeek V4 Flash implements.\n'
printf 'Provider scope: OpenCode Go only. Extra validator/parser/subagent calls: not used.\n'

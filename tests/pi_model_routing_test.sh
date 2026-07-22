#!/bin/sh

set -eu

pi_agent_dir=${PI_CODING_AGENT_DIR:-"$HOME/.pi/agent"}
settings_file="$pi_agent_dir/settings.json"
auth_file="$pi_agent_dir/auth.json"
model_router_file="$pi_agent_dir/extensions/plan-build-model-router.ts"
repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
model_router_source="$repo_root/scripts/pi/plan-build-model-router.ts"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_jq() {
  file=$1
  expression=$2
  message=$3

  jq -e "$expression" "$file" >/dev/null || fail "$message"
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v pi >/dev/null 2>&1 || fail "pi is required"

[ -f "$settings_file" ] || fail "missing $settings_file"
[ -f "$auth_file" ] || fail "missing $auth_file"
[ -f "$model_router_file" ] || fail "missing $model_router_file"

jq -e . "$settings_file" >/dev/null || fail "settings.json is invalid JSON"
jq -e . "$auth_file" >/dev/null || fail "auth.json is invalid JSON"

assert_jq "$settings_file" '.defaultProvider == "opencode-go"' \
  "Pi default provider must be opencode-go"
assert_jq "$settings_file" '.defaultModel == "deepseek-v4-flash"' \
  "Pi default model must be deepseek-v4-flash"
assert_jq "$settings_file" \
  '.enabledModels == ["opencode-go/kimi-k3", "opencode-go/deepseek-v4-flash"]' \
  "Pi model cycling must contain only Kimi K3 and DeepSeek V4 Flash from OpenCode Go"
assert_jq "$settings_file" \
  '[.packages[] | if type == "string" then . else .source end] | index("npm:@narumitw/pi-plan-mode@0.24.0") != null' \
  "pi-plan-mode must be pinned at 0.24.0"
assert_jq "$settings_file" \
  '[.packages[] | if type == "string" then . else .source end] | map(select(startswith("npm:pi-tiered-router"))) | length == 0' \
  "incompatible pi-tiered-router package must not be enabled"

assert_jq "$auth_file" '.["opencode-go"].type == "api_key"' \
  "OpenCode Go API-key authentication is not configured"

cmp -s "$model_router_source" "$model_router_file" || \
  fail "installed plan/build model router differs from the tracked extension"
rg -q 'PLAN_MODEL = .*opencode-go.*kimi-k3' "$model_router_file" || \
  fail "Plan mode must route to opencode-go/kimi-k3"
rg -q 'BUILD_MODEL = .*opencode-go.*deepseek-v4-flash' "$model_router_file" || \
  fail "normal and build turns must route to opencode-go/deepseek-v4-flash"

model_catalog=$(pi --list-models opencode-go)
printf '%s\n' "$model_catalog" | rg -q '^opencode-go[[:space:]]+kimi-k3[[:space:]]' || \
  fail "opencode-go/kimi-k3 is missing from Pi's model catalog"
printf '%s\n' "$model_catalog" | rg -q '^opencode-go[[:space:]]+deepseek-v4-flash[[:space:]]' || \
  fail "opencode-go/deepseek-v4-flash is missing from Pi's model catalog"

pi --help | rg -q -- '--plan' || fail "pi-plan-mode did not register the --plan flag"

printf 'PASS: Pi routes Kimi K3 planning to DeepSeek V4 Flash implementation via OpenCode Go only\n'

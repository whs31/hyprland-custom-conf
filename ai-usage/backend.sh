#!/usr/bin/env bash

set -u

codexbar_bin="${CODEXBAR_BIN:-}"
if [[ -z "$codexbar_bin" ]]; then
    codexbar_bin="$(command -v codexbar 2>/dev/null || true)"
fi
if [[ -z "$codexbar_bin" && -x "$HOME/.local/lib/codexbar-cli/codexbar" ]]; then
    codexbar_bin="$HOME/.local/lib/codexbar-cli/codexbar"
fi

if [[ -z "$codexbar_bin" || ! -x "$codexbar_bin" ]]; then
    printf '%s\n' '[{"provider":"claude","error":{"message":"CodexBar CLI is not installed"}},{"provider":"codex","error":{"message":"CodexBar CLI is not installed"}}]'
    exit 0
fi

# CodexBar writes a small UserDefaults plist. Keep it in the per-login runtime
# directory so the portable Hyprland config remains the only persistent config.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr-ai-usage"
mkdir -p "$runtime_dir"

export XDG_CONFIG_HOME="$runtime_dir"
export NO_COLOR=1

timeout 50 "$codexbar_bin" usage \
    --provider both \
    --source oauth \
    --format json \
    --json-only \
    --no-color


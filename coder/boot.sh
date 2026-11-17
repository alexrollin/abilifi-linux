#!/usr/bin/env bash
# BEB-9809 boot step — runs INSIDE the sandbox via /linux/exec. The workflow prepends two lines that export
# OPENROUTER_API_KEY and PROMPT (the key comes from the vault by name and is never printed or baked).
set -uo pipefail
export HOME="${HOME:-/root}"
export PATH="$HOME/.opencode/bin:$PATH"
mkdir -p "$HOME/.config/opencode" /workspace
cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": { "openrouter": { "options": { "apiKey": "{env:OPENROUTER_API_KEY}" } } },
  "model": "openrouter/z-ai/glm-5.3"
}
JSON
cd /workspace
echo "== opencode version =="
opencode --version
echo "== coder turn (model openrouter/z-ai/glm-5.3) =="
opencode run "$PROMPT"
echo "== opencode exit code: $? =="
echo "== workspace after the turn =="
ls -la /workspace

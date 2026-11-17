#!/usr/bin/env bash
# BEB-9809 boot step — runs INSIDE the sandbox via /linux/exec. The workflow prepends exports for
# OPENROUTER_API_KEY and PROMPT (+ REPO/BASE/BRANCH/TICKET/GHTOK for a repo job). Secrets come from the vault
# by name and are never printed. A repo job clones the repo, works on a NEW branch (never the base) and pushes it.
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

WORKDIR=/workspace
GITAUTH=()
if [ -n "${REPO:-}" ]; then
  # token goes in a per-command header, never into .git/config or the remote URL
  B64="$(printf 'x-access-token:%s' "$GHTOK" | base64 -w0)"
  GITAUTH=(-c "http.extraHeader=Authorization: Basic $B64")
  echo "== clone $REPO (base $BASE) =="
  git "${GITAUTH[@]}" clone --quiet --depth 50 --branch "$BASE" "https://github.com/$REPO.git" /workspace/repo 2>&1 | sed -E 's#https://[^ ]*@#https://***@#g' || true
  [ -d /workspace/repo/.git ] || { echo "CLONE FAILED for $REPO"; exit 3; }
  cd /workspace/repo
  git checkout -q -b "$BRANCH"
  WORKDIR=/workspace/repo
fi
cd "$WORKDIR"

echo "== opencode version =="
opencode --version
echo "== coder turn (model openrouter/z-ai/glm-5.3) in $WORKDIR =="
opencode run "$PROMPT"
CODE=$?
echo "== opencode exit code: $CODE =="

if [ -n "${REPO:-}" ]; then
  echo "== git status after the turn =="
  git status --short | head -40
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git -c user.name="abilifi-coder" -c user.email="coder@abilifi.net" commit -q -m "coder${TICKET:+ $TICKET}: $(printf '%s' "$PROMPT" | head -1 | cut -c1-72)"
    echo "== pushing branch $BRANCH =="
    git "${GITAUTH[@]}" push --quiet origin "$BRANCH" 2>&1 | sed -E 's#https://[^ ]*@#https://***@#g'
    echo "PUSHED branch=$BRANCH sha=$(git rev-parse --short HEAD) files=$(git diff --name-only HEAD~1 HEAD | wc -l)"
    git diff --stat HEAD~1 HEAD | tail -8
  else
    echo "NO CHANGES made by the coder — nothing pushed"
  fi
else
  echo "== workspace after the turn =="
  ls -la /workspace
fi
exit "$CODE"

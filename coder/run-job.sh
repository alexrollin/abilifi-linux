#!/usr/bin/env bash
# Provision a sandbox and run one coder turn in it, retrying ONLY failures where nothing ran
# (provision not ready, or exec failed fast <90s with no output: the intermittent first-call 500).
# A run that got going is never retried. Prints a VERDICT line; exit 1 = red.
# env in: WORKER_URL GATE OR_KEY PROMPT JOB_REPO JOB_BASE JOB_BRANCH JOB_TICKET GHTOK (GITHUB_ENV, GITHUB_STEP_SUMMARY optional)
set -uo pipefail
AUTH=(-H "X-Linux-Gate: $GATE" -H "Authorization: Bearer bb_000coder" -H 'Content-Type: application/json')
SPEC="$(jq -c '{spec: .}' coder/provision-spec.json)"
{ printf 'export OPENROUTER_API_KEY=%q\n' "$OR_KEY"; printf 'export PROMPT=%q\n' "$PROMPT"
  printf 'export REPO=%q BASE=%q BRANCH=%q TICKET=%q\n' "${JOB_REPO:-}" "${JOB_BASE:-master}" "${JOB_BRANCH:-}" "${JOB_TICKET:-}"
  [ -z "${GHTOK:-}" ] || printf 'export GHTOK=%q\n' "$GHTOK"
  cat coder/boot.sh; } > run.sh

destroy() {
  [ -n "${1:-}" ] || return 0
  curl -sS --max-time 120 -X POST "$WORKER_URL/linux/destroy" "${AUTH[@]}" -d "{\"id\":\"$1\"}" >/dev/null || true
}

RAN=0
for attempt in 1 2 3; do
  curl -sS --max-time 900 -o prov.json -w "provision attempt $attempt http %{http_code}\n" -X POST "$WORKER_URL/linux/provision" "${AUTH[@]}" -d "$SPEC" || true
  cat prov.json; echo
  ID="$(jq -r '.id // empty' prov.json 2>/dev/null || true)"
  if [ -z "$ID" ] || [ "$(jq -r '.status' prov.json 2>/dev/null)" != "ready" ]; then
    destroy "$ID"; sleep 20; continue
  fi
  [ -z "${GITHUB_ENV:-}" ] || echo "SANDBOX_ID=$ID" >> "$GITHUB_ENV"
  BODY="$(jq -n --arg id "$ID" --rawfile code run.sh '{id:$id, code:$code, lang:"bash"}')"
  T0=$(date +%s)
  curl -sS --max-time 1200 -o exec.json -w "exec attempt $attempt http %{http_code}\n" -X POST "$WORKER_URL/linux/exec" "${AUTH[@]}" -d "$BODY" || true
  ELAPSED=$(( $(date +%s) - T0 ))
  if [ "$(head -c1 exec.json)" != "{" ]; then
    echo "---- RAW exec response (not JSON) ----"; head -c 800 exec.json; echo
    echo '{"exitCode":-1,"stdout":""}' > exec.json
  fi
  if [ "$(jq -r '.exitCode' exec.json)" = "-1" ] && [ -z "$(jq -r '.stdout // empty' exec.json)" ] && [ "$ELAPSED" -lt 90 ] && [ "$attempt" -lt 3 ]; then
    echo "exec failed fast (${ELAPSED}s, nothing ran): $(jq -c '{error,name}' exec.json) — destroying and retrying"
    destroy "$ID"; sleep 20; continue
  fi
  RAN=1; break
done

[ "$RAN" = "1" ] || { echo "VERDICT: FAILED — no sandbox ran the job after 3 attempts"; exit 1; }

echo "---- stdout ----";  jq -r '.stdout // empty' exec.json
echo "---- stderr ----";  jq -r '.stderr // empty' exec.json | tail -n 40
jq -c 'select(.error) | {error,name}' exec.json
EC="$(jq -r '.exitCode' exec.json)"
echo "---- exitCode: $EC"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### coder turn"; echo "sandbox: \`$ID\`  exit: \`$EC\`"; echo '```'; jq -r '.stdout // empty' exec.json | tail -n 40; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$EC" != "0" ]; then echo "VERDICT: FAILED — coder exited $EC (red, no false green)"; exit 1; fi
if [ -n "${JOB_REPO:-}" ] && ! jq -r '.stdout // empty' exec.json | grep -q '^PUSHED '; then
  echo "VERDICT: FAILED — repo job ended with no pushed branch"; exit 1
fi
echo "VERDICT: OK — coder exit 0${JOB_REPO:+, branch pushed: $(jq -r '.stdout // empty' exec.json | grep '^PUSHED ' | head -1)}"

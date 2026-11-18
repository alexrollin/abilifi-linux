#!/usr/bin/env bash
# Provision a sandbox, START the coder turn DETACHED inside it, then POLL for the result.
# Why detached (Fable m73590): one long exec holding a single connection open gets reset by Cloudflare
# ("curl 56 connection reset") after the job has started. Short exec calls (launch, poll, fetch) don't.
# Retries only where nothing ran: provision not ready, or the launch exec failed fast. A job that got going is never re-run.
# Prints a VERDICT line; exit 1 = red.
# env in: WORKER_URL GATE OR_KEY PROMPT JOB_REPO JOB_BASE JOB_BRANCH JOB_TICKET GHTOK (GITHUB_ENV, GITHUB_STEP_SUMMARY optional)
set -uo pipefail
AUTH=(-H "X-Linux-Gate: $GATE" -H "Authorization: Bearer bb_000coder" -H 'Content-Type: application/json')
SPEC="$(jq -c '{spec: .}' coder/provision-spec.json)"
POLL_S=15            # seconds between polls
MAX_WAIT_S=1500      # give up on the job after 25 min
MAX_POLL_ERRS=12     # consecutive failed polls before the run is called lost
{ printf 'export OPENROUTER_API_KEY=%q\n' "$OR_KEY"; printf 'export PROMPT=%q\n' "$PROMPT"
  printf 'export REPO=%q BASE=%q BRANCH=%q TICKET=%q\n' "${JOB_REPO:-}" "${JOB_BASE:-master}" "${JOB_BRANCH:-}" "${JOB_TICKET:-}"
  [ -z "${GHTOK:-}" ] || printf 'export GHTOK=%q\n' "$GHTOK"
  cat coder/boot.sh; } > run.sh
JOB_B64="$(base64 -w0 run.sh)"

destroy() {
  [ -n "${1:-}" ] || return 0
  curl -sS --max-time 120 -X POST "$WORKER_URL/linux/destroy" "${AUTH[@]}" -d "{\"id\":\"$1\"}" >/dev/null || true
}

# sx <id> <bash code> <max-seconds>: one short exec; result in exec.json; returns 0 only if exec ran (exitCode 0)
sx() {
  local body; body="$(jq -n --arg id "$1" --arg code "$2" '{id:$id, code:$code, lang:"bash"}')"
  curl -sS --max-time "$3" -o exec.json -X POST "$WORKER_URL/linux/exec" "${AUTH[@]}" -d "$body" 2>/dev/null || return 1
  [ "$(head -c1 exec.json)" = "{" ] || return 1
  [ -z "$(jq -r '.error // empty' exec.json)" ] || return 1
  [ "$(jq -r '.exitCode // -1' exec.json)" = "0" ]
}

LAUNCHED=0
for attempt in 1 2 3; do
  curl -sS --max-time 900 -o prov.json -w "provision attempt $attempt http %{http_code}\n" -X POST "$WORKER_URL/linux/provision" "${AUTH[@]}" -d "$SPEC" || true
  cat prov.json; echo
  ID="$(jq -r '.id // empty' prov.json 2>/dev/null || true)"
  if [ -z "$ID" ] || [ "$(jq -r '.status' prov.json 2>/dev/null)" != "ready" ]; then
    destroy "$ID"; sleep 20; continue
  fi
  [ -z "${GITHUB_ENV:-}" ] || echo "SANDBOX_ID=$ID" >> "$GITHUB_ENV"
  LAUNCH="echo '$JOB_B64' | base64 -d > /tmp/job.sh && setsid nohup bash -c 'bash /tmp/job.sh > /tmp/job.out 2>&1; echo \$? > /tmp/job.exit' >/dev/null 2>&1 < /dev/null & sleep 1; echo launched"
  if sx "$ID" "$LAUNCH" 120 && jq -r '.stdout // empty' exec.json | grep -q '^launched'; then
    echo "job launched detached on attempt $attempt (sandbox $ID)"; LAUNCHED=1; break
  fi
  echo "launch failed on attempt $attempt: $(head -c 300 exec.json 2>/dev/null) — destroying and retrying"
  destroy "$ID"; sleep 20
done

[ "$LAUNCHED" = "1" ] || { echo "VERDICT: FAILED — could not start the job in any sandbox after 3 attempts"; exit 1; }

START=$(date +%s); ERRS=0; EC=""
while :; do
  sleep "$POLL_S"
  if sx "$ID" 'if [ -f /tmp/job.exit ]; then echo "DONE=$(cat /tmp/job.exit)"; else echo RUNNING; fi' 60; then
    ERRS=0
    R="$(jq -r '.stdout // empty' exec.json | tail -n1)"
    case "$R" in DONE=*) EC="${R#DONE=}"; break;; esac
  else
    ERRS=$((ERRS+1)); echo "poll error $ERRS/$MAX_POLL_ERRS: $(head -c 200 exec.json 2>/dev/null)"
    [ "$ERRS" -lt "$MAX_POLL_ERRS" ] || { echo "VERDICT: FAILED — lost contact with the running job (${MAX_POLL_ERRS} polls in a row failed)"; exit 1; }
  fi
  [ $(( $(date +%s) - START )) -lt "$MAX_WAIT_S" ] || { echo "VERDICT: FAILED — job still running after ${MAX_WAIT_S}s"; exit 1; }
done

# fetch the output (retry: a reset here must not lose a finished job)
GOT=0
for i in 1 2 3 4 5; do
  if sx "$ID" 'tail -c 60000 /tmp/job.out' 120; then GOT=1; break; fi
  sleep 10
done
OUT=""; [ "$GOT" = "1" ] && OUT="$(jq -r '.stdout // empty' exec.json)"
echo "---- job output ----"; printf '%s\n' "$OUT" | tail -n 80
echo "---- exitCode: $EC"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### coder turn"; echo "sandbox: \`$ID\`  exit: \`$EC\`"; echo '```'; printf '%s\n' "$OUT" | tail -n 40; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$EC" != "0" ]; then echo "VERDICT: FAILED — coder exited $EC (red, no false green)"; exit 1; fi
if [ -n "${JOB_REPO:-}" ] && ! printf '%s\n' "$OUT" | grep -q '^PUSHED '; then
  echo "VERDICT: FAILED — repo job ended with no pushed branch"; exit 1
fi
echo "VERDICT: OK — coder exit 0${JOB_REPO:+, branch pushed: $(printf '%s\n' "$OUT" | grep '^PUSHED ' | head -1)}"

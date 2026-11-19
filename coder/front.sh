#!/usr/bin/env bash
# front(ticket) — the caller passes ONE ticket in; this checks it, refuses BY NAME, or writes + pushes jobs/<id>-<n>.md
# which starts a coder run (BEB-9847 C8, BEB-9867 C1). It holds no tracker credential: the caller (CC/Fable) read the ticket.
# usage: bash coder/front.sh ticket.json     ticket.json = {id,title,status,estimate,cost_ceiling,description}
# Prints exactly one line: REFUSED: <name> — <missing piece>   or   FRONTED: <id> job=<file> commit=<sha>
set -uo pipefail
T="${1:?usage: front.sh ticket.json}"
f() { jq -r "$1 // empty" "$T"; }
ID="$(f .id)"; TITLE="$(f .title)"; STATUS="$(f .status)"; EST="$(f .estimate)"; CEIL="$(f .cost_ceiling)"; DESC="$(f .description)"
refuse() { echo "REFUSED: $1 — $2"; exit 2; }
printf '%s' "$ID" | grep -Eq '^BEB-[0-9]+$' || refuse "no-ticket-id" "id must look like BEB-1234"
[ "$STATUS" = "todo" ] || refuse "not-todo" "$ID status is '$STATUS', only todo goes out"
[ -n "$EST" ] && [ -n "$CEIL" ] || refuse "no-budget" "$ID has no estimate/cost_ceiling columns set"
CLASS="$(printf '%s\n' "$DESC" | sed -n 's/^Class:[[:space:]]*\([A-Za-z]*\).*/\1/p' | head -1)"
[ "$CLASS" = "CODE" ] || refuse "not-code" "$ID Class is '${CLASS:-missing}', coder takes CODE only"
REPO="$(printf '%s\n' "$DESC" | sed -n 's/^Repo:[[:space:]]*\([A-Za-z0-9_.-]*\/[A-Za-z0-9_.-]*\).*/\1/p' | head -1)"
[ -n "$REPO" ] || refuse "no-repo" "$ID has no 'Repo: owner/name' line — the coder must know which repo to branch"
N=$(( $(ls jobs 2>/dev/null | grep -c "^$ID-") + 1 ))
FILE="jobs/$ID-$N.md"
{
  echo "repo: $REPO"; echo "base: master"; echo "branch: coder/$ID-$N"; echo "ticket: $ID"; echo
  echo "Ticket $ID — $TITLE"; echo
  echo "Do exactly what the ticket description asks, on a new branch, and push it. Acceptance items are runnable checks; run them and report each PASS/FAIL. If a clause is unclear, say which and stop — do not invent."; echo
  echo "---- ticket description ----"; printf '%s\n' "$DESC"
} > "$FILE"
git add "$FILE" && git commit -q -m "job: $ID run $N fronted (BEB-9847 C8)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_011JWGTpGbSSoThCLb84g7hf" && git push -q origin master || refuse "push-failed" "could not push $FILE"
echo "FRONTED: $ID job=$FILE commit=$(git rev-parse --short HEAD)"

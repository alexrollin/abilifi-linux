repo: alexrollin/abilifi-linux
base: master
branch: coder/beb-9847-de7d37ab
ticket: BEB-9847

Work on this ticket in the repo, commit and stop (the branch is pushed for you).

Ticket BEB-9847 — FRONT: CF opencode coder takes the right tickets in goal order, and CC can interrupt it at any time

Repo: alexrollin/abilifi-linux (runner) + tracker
Class: CODE
Lane: part
Budget: estimate 80 / ceiling 160
Related: BEB-9809 (CF coder, live 11-17), BEB-9824 (goal_plan), BEB-9828 (breaker)

Alex 2026-11-17: Coolify handover will take an unknown number of days, so opencode on CF is the coder meanwhile. It must work the right tickets, and CC must be able to interrupt it to get work done.

1. Ticket choice: the coder takes the next ready ticket by goal weight, then priority, then age. It only takes tickets that are todo, budgeted, and have no unmet dependency. It uses goal_plan once BEB-9824 is live, and the same order from the tracker before that. — Q: n/a
2. FRONT: a ticket marked FRONT (label or comment) jumps the queue and is taken next. — Q: n/a
3. Interrupt: CC (or Fable) can stop the coder's current job through one tracker call, with no shell. The job stops within 60 s, its work so far is saved as a branch, and the ticket gets a dated INTERRUPTED line saying who stopped it. — Q: n/a
4. Pause/resume: one switch (a settings row) pauses all coder runs and another resumes them; a paused coder takes nothing new. This ties into the breaker, BEB-9828. — Q: n/a
5. Each run writes one line on its ticket: started, finished or failed, with the cost. Nothing goes on the bridge. — Q: n/a

Acceptance: with 3 ready tickets of different goal weights, the coder takes the highest first; a FRONT ticket overtakes it; an interrupt call stops a running job inside 60 s and saves its branch; pause stops new claims; every action is visible as a line on its ticket.

# abilifi-linux — Agent Linux Desktop (one-click)

WordPress-on-SQLite dev environment, preinstalled. Deploys to **your own account** — remote build, **no local Docker needed**.

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/alexrollin/abilifi-linux)

Click → authorize → Cloudflare builds the container remotely (php 8.1 + sqlite + wp-cli + WordPress 7.0) + provisions D1 + deploys. Endpoints: `/linux/provision`, `/linux/exec`, `/linux/status`. Org-scoped, self-init schema. Every step proven live before dockerizing (see PROOF in the source repo).

## Coder runs

`.github/workflows/coder-run.yml` runs opencode headlessly inside the abilifi-linux sandbox — no laptop, no person.
A fresh random gate is opened for the run and rotated away afterwards, so the route stays closed to the world.
The coder clones the target repo, works on a new branch (never the base) and pushes that branch when done.

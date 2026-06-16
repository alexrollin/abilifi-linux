# abilifi-linux — Agent Linux Desktop (one-click)

WordPress-on-SQLite dev environment, preinstalled. Deploys to **your own account** — remote build, **no local Docker needed**.

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/alexrollin/abilifi-linux)

Click → authorize → Cloudflare builds the container remotely (php 8.1 + sqlite + wp-cli + WordPress 7.0) + provisions D1 + deploys. Endpoints: `/linux/provision`, `/linux/exec`, `/linux/status`. Org-scoped, self-init schema. Every step proven live before dockerizing (see PROOF in the source repo).

# CISO Assistant on the Pi (Coolify)

This fork (`coden00bj/ciso-assistant`) is intuitem's
[CISO Assistant Community](https://github.com/intuitem/ciso-assistant-community)
at a release tag, plus this `deploy/pi/` directory, which is the only part
we write ourselves. Keeping upstream files untouched means merging a new
release is conflict-free.

**Live:** https://ciso.coffeeandnoobcode.com (public; Cloudflare tunnel `sainsburys-pi`)

## How it runs

```
Cloudflare (TLS) ─tunnel─▶ Coolify Traefik :80 ─▶ caddy :80 ─┬─ /api/* ─▶ backend :8000 (Django/gunicorn)
                                                             └─ /*     ─▶ frontend :3000 (SvelteKit)
                                                  huey (task queue) ── shares the backend image + volume
```

- **Images are upstream's prebuilt multi-arch images** (`ghcr.io/intuitem/ciso-assistant-community/*`),
  pinned in `docker-compose.yml`. Nothing is built on the Pi. The frontend build
  allows a 10 GB Node heap and the backend bundles PyTorch, so building on the Pi
  is a bad idea.
- **Data:** SQLite at `/code/db/ciso-assistant.sqlite3` plus `/code/db/attachments/`,
  all on the compose named volume `ciso-db` (Docker volume `<app-uuid>_ciso-db`,
  stored under `/mnt/ssd/docker/volumes/`).
- **Dropped from upstream:** qdrant (only used by the AI chat, `ENABLE_CHAT` is off)
  and the MCP server (opt-in upstream; add it later if wanted).
- Upstream's hardening is kept: read-only rootfs, `cap_drop: ALL`,
  no-new-privileges, uid 1001.

## Coolify app

| Setting | Value |
|---|---|
| Build pack | Docker Compose |
| Repo / branch | `coden00bj/ciso-assistant` / `main` (GitHub App, auto-deploy) |
| Compose file | `/deploy/pi/docker-compose.yml` |
| Watch paths | `deploy/pi/**`: upstream merges don't redeploy |
| Domain | `caddy` service → `http://ciso.coffeeandnoobcode.com:80` (http like every tunnel app; TLS ends at Cloudflare) |
| Env | `DJANGO_SECRET_KEY` (copy at `~/coolify-migration/ciso-credentials.txt`) |

## Gotchas (each one breaks login if wrong)

- **Caddy must trust the upstream `X-Forwarded-Proto`** (`trusted_proxies static private_ranges`).
  Otherwise it rewrites the header to `http`, Django's `SECURE_PROXY_SSL_HEADER`
  treats the request as insecure, and CSRF fails. Traefik needs the equivalent
  patch, which is already in place on this Pi.
- **`ORIGIN` (frontend) and `CISO_ASSISTANT_URL` (backend) must both be exactly
  `https://ciso.coffeeandnoobcode.com`.** Django's `CSRF_TRUSTED_ORIGINS` is only
  that one URL, so a second hostname (e.g. a LAN address) will not work alongside it.
- **`DJANGO_SECRET_KEY` must be set in the environment.** huey overrides the
  entrypoint and skips `startup.sh`, which is the only place a key file gets
  persisted.
- **`db-init`** chowns the volume to 1001. A fresh named volume is root-owned
  because `/code/db` is excluded from the image.
- **`${VAR:?msg}` is unsafe in Coolify.** Its compose parser can store the message
  as the variable's default value. Use plain `${VAR}`.

## First admin

There is no mailer, so create the superuser once by hand and keep the password in
`~/coolify-migration/ciso-credentials.txt`:

```bash
B=$(docker ps --format '{{.Names}}' | grep '^backend-')
docker exec -e DJANGO_SUPERUSER_EMAIL=you@example.com -e DJANGO_SUPERUSER_PASSWORD='…' \
  "$B" python manage.py createsuperuser --noinput
docker exec -it "$B" python manage.py changepassword you@example.com   # recovery
```

Then turn on MFA for that account in the UI (Profile → MFA). The site is public.

## Backups

`deploy/pi/backup.sh` streams a `.tar.gz` (an online sqlite backup + attachments)
out of the running backend into `/mnt/ssd/backups/ciso-assistant/`, keeping 14
days. Cron (wern) runs it at 03:30 nightly.

Restore: stop the app in Coolify, then extract the archive into the volume and fix
ownership:

```bash
V=/mnt/ssd/docker/volumes/<app-uuid>_ciso-db/_data
sudo tar -xzf ciso-assistant-YYYYmmdd-HHMMSS.tar.gz -C "$V" && sudo chown -R 1001:1001 "$V"
```

## Upgrading

1. Run `./backup.sh`.
2. Run `git fetch upstream --tags && git merge vX.Y.Z` from the repo root.
3. Bump the three image tags in `deploy/pi/docker-compose.yml` to `vX.Y.Z`.
4. Push to `main`. Coolify redeploys, and `startup.sh` runs migrations plus `storelibraries`.

Check upstream's compose diff (`git diff vOLD vX.Y.Z -- docker-compose.yml config/templates/`)
for new env vars or services.

## Changing the code later

Once there's something to change, build our own arm64 images on GitHub Actions
(free arm64 runners for public repos) to `ghcr.io/coden00bj/ciso-assistant/*`, and
point this compose file at them. Upstream's `.github/workflows/docker-build-and-push.yml`
shows how. The fork's Actions are currently **disabled**, because the ~25 upstream
workflows are noise for us.

## Licence

AGPL-3.0, except `enterprise/`, which is under intuitem's commercial licence and
unused here. This fork is public, which satisfies AGPL source availability for the
public deployment.

# ciso-assistant (fork) — Claude context

This is a public fork (`coden00bj/ciso-assistant`) of intuitem's
[CISO Assistant Community](https://github.com/intuitem/ciso-assistant-community),
a GRC platform licensed under AGPL-3.0 (except `enterprise/`). It runs on the Pi at
**https://ciso.coffeeandnoobcode.com**. This file is ours, not upstream's.

- **`main` = upstream release tag (currently `v4.1.2`) + our files only:** this
  `CLAUDE.md` and `deploy/pi/`. Don't edit upstream files unless we deliberately
  start carrying patches, because that makes every upstream merge harder.
- **We run upstream's prebuilt arm64 images. Nothing is built on the Pi.** The
  frontend build allows a 10 GB Node heap and the backend bundles PyTorch.
  `deploy/pi/README.md` has the full deploy, upgrade, backup and gotcha notes.
  Read it before changing anything under `deploy/pi/`.
- **Coolify app:** `cax4cwbctsgvtr04enantkqk` (Docker Compose build pack, watch
  paths `deploy/pi/**`). Pushing to `main` redeploys only when `deploy/pi/` changes.
- **Remotes:** `origin` = the fork, `upstream` = intuitem. The fork's GitHub
  Actions are disabled.

## TODO (later)

- **MCP connector for Claude.** Upstream ships an MCP server: image
  `ghcr.io/intuitem/ciso-assistant-community/mcp`, source in `cli/ca_mcp/`, setup
  in `cli/MCP_SETUP_GUIDE.md`. Its HTTP mode authenticates **each request with a
  CISO Assistant PAT header** (`Authorization: Token <PAT>` or `X-CISO-Token`)
  and has **no OAuth**.
  - **Claude Code / Desktop (easy):** add an `mcp` service to
    `deploy/pi/docker-compose.yml`, copied from upstream's `docker-compose.yml`.
    Set `CA_MCP_TRANSPORT=streamable-http`, `CA_MCP_READ_ONLY=true`,
    `CA_MCP_ALLOWED_HOSTS=ciso.coffeeandnoobcode.com`, `CA_MCP_ALLOW_ENV_TOKEN=false`.
    Route `/mcp*` to `mcp:8001` in the caddy block. Create a **dedicated
    read-only user** and give it its own PAT, rather than using an admin PAT.
    Then run `claude mcp add --transport http --header "Authorization: Token …" ciso https://ciso.coffeeandnoobcode.com/mcp`.
  - **Claude.ai web/mobile (bigger):** custom connectors need OAuth 2.1 + PKCE,
    so put a small OAuth front in front of the MCP server that maps a login to a
    PAT. The pattern is in `recipe-planner/` and its Claude.ai popup-OAuth
    gotchas are in workspace memory.

## Deliberately not done

- **Off-Pi backup copy:** declined for now (2026-10-17). Nightly backups exist only
  on the Pi's SSD (`/mnt/ssd/backups/ciso-assistant/`, 14 days). If wanted later,
  rclone crypt to Google Drive or R2 was the shortlist.
- Cloudflare Access in front of the site: declined. The app's own login + MFA is the gate.

# romm-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/romm-v510-or-rom-manager-no-stranger-can?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [RomM template](https://railway.com/deploy/romm-v510-or-rom-manager-no-stranger-can?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway-tuned wrapper image for [RomM](https://github.com/rommapp/romm), the
self-hosted ROM manager and player. Published as
`ghcr.io/bon5co/romm-railway`.

What the wrapper adds on top of `rommapp/romm:5.1.0`:

- **Seeds the admin account before the public port ever listens.** A stock RomM
  instance with no admin users is claimable by any anonymous caller:
  `POST /api/users` is registered with an empty scope list and its 403 is gated
  on `admins_exist`, so the first stranger to reach the URL can create a
  super-admin. `DISABLE_SETUP_WIZARD` does not close it — that flag is read only
  by the heartbeat endpoint. RomM ships no admin-seeding environment variable,
  so the entrypoint runs the migrations and inserts the account itself, in a
  process that must exit before `/init` starts nginx.
- **Refuses to boot on an empty `ROMM_ADMIN_PASSWORD`**, rather than serving a
  claimable instance.
- **Brute-force protection on `/api/login`, `/api/token` and
  `/api/forgot-password`** (10 r/m, burst 5). RomM has no login throttle at all
  and the stock nginx config ships no `limit_req`. The key is the first address
  of `X-Forwarded-For`: on Railway `$remote_addr` is always the edge and the
  edge hop in `X-Forwarded-For` rotates between requests.
- **Relocates the internal valkey data dir onto the single Railway volume.** The
  upstream image declares two volumes (`/romm` and `/redis-data`); Railway
  mounts one per service.
- **Pins the release tag.** `/init` runs `alembic upgrade head` unconditionally
  on every start and downgrades are never run, so `latest` makes each redeploy a
  one-way upgrade of the deployer's database.

Deployed by the Railway template published from
[bon5co/railwaytemplate2](https://github.com/bon5co/railwaytemplate2) (`romm/`).

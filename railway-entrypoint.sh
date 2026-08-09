#!/usr/bin/env bash
# Railway wrapper entrypoint for RomM.
#
# Three jobs, all of which must happen before the stock entrypoint hands over to
# `/init` (which starts nginx and therefore the public listener):
#
#   1. Move the internal valkey's data directory onto the one Railway volume.
#      The image declares TWO volumes (`/romm` and `/redis-data`) and Railway
#      mounts exactly one per service, so the job queue and cached metadata that
#      the internal valkey snapshots would otherwise sit on the container layer.
#   2. Wait for the database, run the migrations, and seed the admin account.
#      `/init` runs `alembic upgrade head` itself, but it does so after starting
#      valkey and immediately before starting gunicorn/nginx — too late to seed
#      into a schema that does not exist yet. Running it here first is
#      idempotent; the second run is a no-op.
#   3. Refuse to boot at all when no admin password was supplied, rather than
#      serve a claimable instance (see railway-seed.py).
set -euo pipefail

BASE_PATH="${ROMM_BASE_PATH:-/romm}"

# --- 1. valkey data onto the volume -----------------------------------------
if [[ -z ${REDIS_HOST:-} ]]; then
	mkdir -p "${BASE_PATH}/redis-data"
	if [[ -L /redis-data ]]; then
		echo "[railway] internal valkey data dir -> $(readlink /redis-data)"
	elif rm -rf /redis-data 2>/dev/null && ln -s "${BASE_PATH}/redis-data" /redis-data; then
		echo "[railway] internal valkey data dir -> ${BASE_PATH}/redis-data"
	else
		# Happens under a plain `docker run`, which honours the image's
		# `VOLUME /redis-data` and makes it a live mountpoint. Railway mounts
		# one volume per service and never mounts this path, so there it is a
		# plain directory and the relocation succeeds.
		echo "[railway] /redis-data is a live mountpoint, leaving it alone" >&2
	fi
fi

# --- 2. database ------------------------------------------------------------
cd /backend

echo "[railway] waiting for the database"
for _ in $(seq 1 60); do
	if python3 -c "
import sys
sys.path.insert(0, '/backend')
from sqlalchemy import text
from handler.database.base_handler import sync_engine
with sync_engine.connect() as c:
    c.execute(text('SELECT 1'))
" >/dev/null 2>&1; then
		break
	fi
	sleep 2
done

echo "[railway] running database migrations before seeding"
alembic upgrade head

# --- 3. admin account, before anything listens ------------------------------
python3 /usr/local/bin/railway-seed.py

exec /docker-entrypoint.sh "$@"

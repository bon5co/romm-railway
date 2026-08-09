"""Create RomM's first admin account before the HTTP listener exists.

A stock RomM instance with zero admin users is claimable by anyone who can
reach it. `POST /api/users` is registered with an empty scope list
(`backend/endpoints/user.py`, `@protected_route(router.post, "", [])`), and the
403 inside the handler is gated on `admins_exist`, so while the users table
holds no admin any anonymous caller can create one with `role: "admin"`.
`GET /api/heartbeat` publishes `SHOW_SETUP_WIZARD`, i.e. advertises the window.
`DISABLE_SETUP_WIZARD` does not close it — that flag is only read by the
heartbeat endpoint and the frontend, never by `add_user`.

RomM ships no environment variable that seeds an account (there is no
ADMIN_USERNAME/ADMIN_PASSWORD anywhere in the source), so the template has to
do it itself, and it has to finish before nginx binds the public port.

Idempotent: if any admin already exists this exits without touching the
database, so a redeploy never resets the deployer's password.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, "/backend")

from handler.auth import auth_handler  # noqa: E402
from handler.database import db_user_handler  # noqa: E402
from models.user import Role, User  # noqa: E402


def main() -> int:
    username = os.environ.get("ROMM_ADMIN_USERNAME", "admin").strip()
    password = os.environ.get("ROMM_ADMIN_PASSWORD", "")

    if not password:
        print(
            "[railway] ROMM_ADMIN_PASSWORD is empty. Refusing to boot: an "
            "instance with no admin can be claimed by any anonymous caller.",
            file=sys.stderr,
        )
        return 1

    if db_user_handler.get_admin_users():
        print("[railway] admin account already exists, leaving it alone")
        return 0

    db_user_handler.add_user(
        User(
            username=username,
            hashed_password=auth_handler.get_password_hash(password),
            email=os.environ.get("ROMM_ADMIN_EMAIL") or None,
            role=Role.ADMIN,
            enabled=True,
        )
    )

    if not db_user_handler.get_admin_users():
        print("[railway] admin seed did not persist", file=sys.stderr)
        return 1

    print(f"[railway] seeded admin '{username}' before first listen")
    return 0


if __name__ == "__main__":
    sys.exit(main())

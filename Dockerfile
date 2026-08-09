# Railway-tuned RomM.
#
# Pinned to a release tag rather than `latest`: `/init` runs
# `alembic upgrade head` unconditionally on every container start and alembic
# downgrades are never run, so an unpinned redeploy is a one-way, unrequested
# upgrade of the deployer's database.
FROM rommapp/romm:5.1.0

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY railway-seed.py /usr/local/bin/railway-seed.py
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Brute-force protection on the auth routes. RomM has none: backend/endpoints/
# auth.py has no limiter, no attempt counter and no lockout, and the image's
# nginx config ships no limit_req. The key is the FIRST address of
# X-Forwarded-For, never the whole header and never $remote_addr: on Railway
# $remote_addr is always the edge, and XFF is "<client>, <edge>" with the edge
# hop rotating between requests, so a key built from the whole header changes
# every few requests and the limiter never fires.
#
# Patched at build time, not at boot, so a template that no longer matches
# upstream's nginx template fails the image build instead of quietly shipping
# without the limiter.
RUN set -eux; \
    tpl=/etc/nginx/templates/default.conf.template; \
    grep -q '^server {' "$tpl"; \
    grep -q '# Backend api calls' "$tpl"; \
    printf '%s\n' \
      'map $http_x_forwarded_for $romm_client_ip {' \
      '    default $remote_addr;' \
      '    "~^([^,[:space:]]+)" $1;' \
      '}' \
      'limit_req_zone $romm_client_ip zone=romm_auth:10m rate=10r/m;' \
      '' > /tmp/limit.conf; \
    sed -i "1r /tmp/limit.conf" "$tpl"; \
    printf '%s\n' \
      '    location = /api/login {' \
      '        limit_req zone=romm_auth burst=5 nodelay;' \
      '        limit_req_status 429;' \
      '        proxy_pass http://wsgi_server;' \
      '    }' \
      '    location = /api/token {' \
      '        limit_req zone=romm_auth burst=5 nodelay;' \
      '        limit_req_status 429;' \
      '        proxy_pass http://wsgi_server;' \
      '    }' \
      '    location = /api/forgot-password {' \
      '        limit_req zone=romm_auth burst=5 nodelay;' \
      '        limit_req_status 429;' \
      '        proxy_pass http://wsgi_server;' \
      '    }' \
      '' > /tmp/authloc.conf; \
    sed -i "/# Backend api calls/r /tmp/authloc.conf" "$tpl"; \
    rm -f /tmp/limit.conf /tmp/authloc.conf; \
    grep -q 'romm_auth' "$tpl"

# Baked, NOT published as template variables: templateGenerate drops a variable
# whose default is a literal and republishes it as a blank REQUIRED field on the
# deploy form. Only values that genuinely belong to the deployer stay variables,
# and those are Railway expressions (${{secret(n)}}, ${{RAILWAY_PUBLIC_DOMAIN}}).
#
# ROMM_PORT is left at the image default of 8080, which is also the port Railway
# injects; the app does not read $PORT, and Railway's HTTP healthcheck dials the
# injected port rather than the domain's target port, so 8080 is the only value
# that keeps both the edge and the healthcheck pointed at nginx.
ENV ROMM_ADMIN_USERNAME=admin \
    DB_USER=romm \
    DB_NAME=romm \
    ROMM_BASE_PATH=/romm \
    ROMM_SESSION_SECURE_COOKIE=true \
    DISABLE_SETUP_WIZARD=true \
    HASHEOUS_API_ENABLED=true

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/init"]

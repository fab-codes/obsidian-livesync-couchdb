#!/bin/bash
# Wrapper around the official CouchDB entrypoint. It does one thing: CouchDB
# reads its port from an .ini file, while PaaS providers (Railway, Render,
# Fly, ...) announce it through $PORT. We bridge the two, then hand over to
# /docker-entrypoint.sh, which does the rest (chown of the volume, admin
# creation, dropping privileges).
set -euo pipefail

HTTP_PORT="${PORT:-5984}"

if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || [ "$HTTP_PORT" -lt 1 ] || [ "$HTTP_PORT" -gt 65535 ]; then
    echo "[entrypoint] invalid PORT: '$HTTP_PORT'" >&2
    exit 1
fi

cat > /opt/couchdb/etc/local.d/20-port.ini <<INI
; Rewritten by entrypoint.sh on every container boot. Do not edit by hand.
[chttpd]
port = ${HTTP_PORT}
INI
chmod 0644 /opt/couchdb/etc/local.d/20-port.ini

echo "[entrypoint] CouchDB listening on 0.0.0.0:${HTTP_PORT}"

if [ -n "${NODENAME:-}" ]; then
    echo "[entrypoint] WARNING: NODENAME is set ('${NODENAME}')." >&2
    echo "[entrypoint] The node name is written inside the database shard" >&2
    echo "[entrypoint] maps: changing it after the first boot makes the data" >&2
    echo "[entrypoint] unreachable. See the README." >&2
fi

if [ -z "${COUCHDB_SECRET:-}" ]; then
    echo "[entrypoint] Note: COUCHDB_SECRET is not set. CouchDB will generate" >&2
    echo "[entrypoint] a random one on every deploy, so existing session" >&2
    echo "[entrypoint] cookies stop working. Harmless with Basic auth." >&2
fi

exec /docker-entrypoint.sh "$@"

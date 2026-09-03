# syntax=docker/dockerfile:1

# CouchDB for Obsidian Self-hosted LiveSync.
#
# Pinned by digest: a tag can be re-published with different contents, a digest
# cannot. To move to a newer version, change the tag AND the digest together
# (README, "Updating the image"). Dependabot does both in the same pull
# request: see .github/dependabot.yml.
FROM couchdb:3.5.2.1@sha256:9ea24cbd76522fe845d1c32c7fd1dcfc8a3ba73dcc4817d62f8a7f7f1dfaffe3

# An inherited label cannot be removed, only replaced: without this override
# the image stays attributed to the CouchDB developers.
LABEL org.opencontainers.image.title="obsidian-livesync-couchdb" \
      org.opencontainers.image.description="Apache CouchDB preconfigured for Obsidian Self-hosted LiveSync" \
      org.opencontainers.image.authors="Fabrizio Greco (@fab-codes)" \
      org.opencontainers.image.vendor="Fabrizio Greco" \
      org.opencontainers.image.url="https://github.com/fab-codes/obsidian-livesync-couchdb" \
      org.opencontainers.image.source="https://github.com/fab-codes/obsidian-livesync-couchdb" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="docker.io/library/couchdb:3.5.2.1" \
      maintainer="Fabrizio Greco (@fab-codes)"

# CORS, mandatory auth, size limits. In local.d/ so it overrides default.ini.
# The mode is set here rather than by a later RUN chmod, so it does not depend
# on how the host stored the file (Windows carries no usable executable bit).
COPY --chmod=0644 couchdb/10-livesync.ini /opt/couchdb/etc/local.d/10-livesync.ini

# Injects $PORT before handing over to the official entrypoint, which chowns
# the volume and drops from root to the couchdb user (uid 5984).
COPY --chmod=0755 entrypoint.sh /usr/local/bin/livesync-entrypoint.sh

# Documentation only, and only for the default: the real port comes from $PORT
# at runtime. The base image also exposes 4369 and 9100 (Erlang), which cannot
# be un-exposed; they stay unused because the node runs without Erlang
# distribution.
EXPOSE 5984

# Same probe the platforms use: /_up is the one endpoint reachable without
# credentials. curl ships with the base image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
    CMD curl -fsS "http://127.0.0.1:${PORT:-5984}/_up" || exit 1

# tini is already in the base image and is what the official entrypoint uses.
ENTRYPOINT ["tini", "--", "/usr/local/bin/livesync-entrypoint.sh"]
CMD ["/opt/couchdb/bin/couchdb"]

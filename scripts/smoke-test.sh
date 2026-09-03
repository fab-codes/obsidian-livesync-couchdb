#!/usr/bin/env bash
# Checks that a CouchDB instance is correctly configured for LiveSync. It
# writes nothing: read-only requests only.
#
#   ./scripts/smoke-test.sh https://your-service.up.railway.app user password
#
# Set MAX_TIME to raise the per-request deadline (default 15s) if the service
# is cold and takes a while to wake up.
set -uo pipefail

HOST="${1:?usage: $0 <url> <user> <password>}"
USER="${2:?usage: $0 <url> <user> <password>}"
PASS="${3:?usage: $0 <url> <user> <password>}"
HOST="${HOST%/}"

# Every request carries a deadline, so an unreachable host fails instead of
# hanging. The two limits differ on purpose: a host that is up but slow gets
# the full MAX_TIME, while one that is simply not there is given up on after
# 5s rather than making every check below wait out the whole deadline.
CURL=(curl -sS --connect-timeout 5 --max-time "${MAX_TIME:-15}")

fail=0

# Colours only when stdout is a terminal: in a file or a CI log they are noise.
if [ -t 1 ]; then
    green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
else
    green=''; red=''; reset=''
fi
ok()   { printf '  %sOK%s   %s\n' "$green" "$reset" "$1"; }
bad()  { printf '  %sKO%s   %s\n' "$red" "$reset" "$1"; fail=1; }

# Reads one value from the running configuration. Admin-only endpoint, and it
# reports what CouchDB actually loaded rather than what the .ini says.
config_get() {
    "${CURL[@]}" -u "$USER:$PASS" "$HOST/_node/_local/_config/$1/$2" 2>/dev/null \
        | tr -d '"\n'
}

# Prints the status code. The body comes first and is dropped with tail rather
# than by pointing curl at /dev/null: under Git Bash that intermittently fails
# with "client returned ERROR on write".
http_code() {
    "${CURL[@]}" "$@" -w '\n%{http_code}' | tail -1
}

echo "Checking $HOST"

# 1. The server answers and the healthcheck is public.
if [ "$(http_code "$HOST/_up")" = "200" ]; then
    ok "/_up reachable without credentials (healthcheck)"
else
    bad "/_up does not return 200 - the platform will mark the deploy as down"
fi

# 2. No anonymous access to the root.
if [ "$(http_code "$HOST/")" = "401" ]; then
    ok "anonymous access blocked (require_valid_user is on)"
else
    bad "the root answers without credentials - require_valid_user is NOT on"
fi

# 3. The credentials work.
if "${CURL[@]}" -f -u "$USER:$PASS" "$HOST/" >/dev/null 2>&1; then
    ok "credentials accepted"
else
    bad "credentials rejected"
fi

# 4. The system databases exist (single_node did its job).
for db in _users _replicator; do
    if "${CURL[@]}" -f -u "$USER:$PASS" "$HOST/$db" >/dev/null 2>&1; then
        ok "system database $db present"
    else
        bad "system database $db missing - single_node did not initialise"
    fi
done

# 5. CORS. Obsidian talks from a different origin on every platform, and all
#    three need credentials too: without Access-Control-Allow-Credentials the
#    browser drops the auth header and LiveSync cannot log in.
for origin in "app://obsidian.md" "capacitor://localhost" "http://localhost"; do
    headers=$("${CURL[@]}" -X OPTIONS "$HOST/" \
            -H "Origin: $origin" \
            -H "Access-Control-Request-Method: GET" \
            -D - 2>/dev/null | tr -d '\r')
    allowed=$(printf '%s\n' "$headers" | grep -i '^access-control-allow-origin:' || true)
    creds=$(printf '%s\n' "$headers" | grep -i '^access-control-allow-credentials:' || true)
    # Matched with bash globs, not grep: the origin comes back verbatim, and
    # the GNU grep 3.0 in Git Bash aborts when -i and -F are combined.
    if [[ "$allowed" != *"$origin"* ]]; then
        bad "CORS: $origin not allowed (got: ${allowed:-nothing})"
    elif [[ "$creds" != *[Tt]rue* ]]; then
        bad "CORS: $origin allowed, but not with credentials (got: ${creds:-nothing})"
    else
        ok "CORS: $origin"
    fi
done

# 6. Node name: it must stay stable across deploys.
node=$("${CURL[@]}" -u "$USER:$PASS" "$HOST/_membership" 2>/dev/null \
        | grep -o '"[a-zA-Z0-9_.-]*@[a-zA-Z0-9_.-]*"' | head -1 | tr -d '"')
if [ -n "$node" ]; then
    ok "node: $node   (must stay identical on every deploy)"
else
    bad "could not read /_membership"
fi

# 7. Size limits. Too low a value does not show up as an error here: it shows
#    up much later, as the first sync of a large vault failing.
check_limit() {   # section  key  expected-minimum
    local value
    value=$(config_get "$1" "$2")
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        bad "$2: could not read it from the running config"
    elif [ "$value" -lt "$3" ]; then
        bad "$2 = $value, below the $3 this image configures"
    else
        ok "$2 = $value"
    fi
}
check_limit couchdb max_document_size     50000000
check_limit chttpd  max_http_request_size 4294967296

# 8. Version, for the record.
version=$("${CURL[@]}" -u "$USER:$PASS" "$HOST/" 2>/dev/null \
        | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
if [ -n "$version" ]; then
    ok "CouchDB version: $version"
else
    bad "could not read the CouchDB version from /"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "All good."
else
    echo "Some checks failed, see above."
fi
exit "$fail"

#!/usr/bin/env bash
# Start authentik, apply the terraform config, and connect the LDAP outpost.
# Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

UO_TFVARS=stacks/uo/env.tfvars

for f in .env env.tfvars; do
    if [ ! -f "$f" ]; then
        echo "Missing $f. Copy $f.example and fill it in (see README)." >&2
        exit 1
    fi
done

# Same port compose uses: the environment wins, then .env, then the default
PORT=${COMPOSE_PORT_HTTP:-$(sed -n 's/^COMPOSE_PORT_HTTP=//p' .env | tr -d "\"'")}
PORT=${PORT:-9000}

# wait_for <description> <timeout seconds> <command...>
wait_for() {
    local desc=$1 timeout=$2
    shift 2
    local deadline=$((SECONDS + timeout))
    printf 'Waiting for %s...' "$desc"
    until "$@" > /dev/null 2>&1; do
        if ((SECONDS >= deadline)); then
            echo " timed out after ${timeout}s." >&2
            exit 1
        fi
        printf '.'
        sleep 2
    done
    echo " ready."
}

# Run Python in the authentik shell and print the last line of output
ak_shell() {
    docker compose exec -T server ak shell -c "$1" 2> /dev/null | tail -1
}

is_token() {
    [[ $1 =~ ^[A-Za-z0-9]{20,}$ ]]
}

authentik_ready() {
    curl -sf "http://localhost:${PORT}/-/health/ready/"
}

# Create or retrieve a non-expiring API token for akadmin. The health endpoint
# passes before migrations finish, so this retries until the ORM is usable.
fetch_api_token() {
    TOKEN=$(ak_shell "
from authentik.core.models import Token, User
user = User.objects.get(username='akadmin')
token, _ = Token.objects.get_or_create(
    identifier='terraform',
    defaults={'user': user, 'intent': 'api', 'expiring': False}
)
print(token.key)
")
    is_token "$TOKEN"
}

# The bootstrap worker creates the default flows and stages terraform looks up
default_stages_ready() {
    curl -sf -H "Authorization: Bearer ${TOKEN}" \
        "http://localhost:${PORT}/api/v3/stages/all/?name=default-source-enrollment-login" |
        python3 -c "import json,sys; exit(0 if json.load(sys.stdin)['pagination']['count'] > 0 else 1)"
}

# set_tfvar <file> <key> <value>: replace the key's line, or append one
set_tfvar() {
    if grep -q "^$2[[:space:]]*=" "$1"; then
        sed -i.bak "s|^$2[[:space:]]*=.*|$2 = \"$3\"|" "$1" && rm "$1.bak"
    else
        echo "$2 = \"$3\"" >> "$1"
    fi
}

echo "Starting authentik..."
docker compose up -d postgresql server worker

wait_for "authentik" 300 authentik_ready
wait_for "API token" 180 fetch_api_token

[ -f "$UO_TFVARS" ] || cp stacks/uo/env.tfvars.example "$UO_TFVARS"
# The uo stack talks to the same server with the same token
SERVER=$(sed -n 's/^server *= *"\(.*\)".*/\1/p' env.tfvars)
set_tfvar env.tfvars token "$TOKEN"
set_tfvar "$UO_TFVARS" token "$TOKEN"
set_tfvar "$UO_TFVARS" server "$SERVER"
echo "Terraform token written to env.tfvars and $UO_TFVARS."

wait_for "default stages" 180 default_stages_ready

echo "Running terraform..."
terraform init -input=false
terraform apply -var-file=env.tfvars -auto-approve

echo "Getting LDAP outpost token..."
LDAP_TOKEN=$(ak_shell "
from authentik.outposts.models import Outpost
print(Outpost.objects.get(name='ldap').token.key)
") || true
if ! is_token "$LDAP_TOKEN"; then
    echo "Could not read the LDAP outpost token." >&2
    exit 1
fi
(umask 077 && echo "AUTHENTIK_TOKEN=${LDAP_TOKEN}" > ldap.env)
echo "LDAP outpost token written to ldap.env."

echo "Starting LDAP outpost..."
docker compose up -d ldap

echo "Setup complete."

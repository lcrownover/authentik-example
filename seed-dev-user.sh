#!/usr/bin/env bash
# Create a dev user with an SSH key and add it to authentik Admins.
# The key pair is generated into .dev-ssh/ on first run and is for local testing only.
set -euo pipefail
cd "$(dirname "$0")"

DEV_USER=${DEV_USER:-devuser}
DEV_PASSWORD=${DEV_PASSWORD:-devpassword}
KEY=.dev-ssh/id_ed25519
DOMAIN=$(sed -n 's/^domain *= *"\(.*\)".*/\1/p' env.tfvars 2> /dev/null)
DOMAIN=${DOMAIN:-example.org}

if [ ! -f "$KEY" ]; then
    mkdir -p .dev-ssh
    ssh-keygen -q -t ed25519 -N "" -C "${DEV_USER}@authentik-dev" -f "$KEY"
    echo "Generated SSH key pair at $KEY."
fi

echo "Seeding dev user ${DEV_USER}..."
docker compose exec -T \
    -e DEV_USER="$DEV_USER" \
    -e DEV_PASSWORD="$DEV_PASSWORD" \
    -e DEV_EMAIL="${DEV_USER}@${DOMAIN}" \
    -e DEV_PATH="${DOMAIN}/external" \
    -e DEV_SSH_KEY="$(cat "$KEY.pub")" \
    server ak shell -c "
import os
from authentik.core.models import User, Group

env = os.environ
user, created = User.objects.get_or_create(
    username=env['DEV_USER'],
    defaults={
        'name': 'Dev User',
        'email': env['DEV_EMAIL'],
        'is_active': True,
        'path': env['DEV_PATH'],
        'attributes': {'sshPublicKey': env['DEV_SSH_KEY']},
    },
)

if created:
    user.set_password(env['DEV_PASSWORD'])
    user.save()
    print('User created.')
else:
    print('User already exists, skipping.')

Group.objects.get(name='authentik Admins').users.add(user)
print('Added to authentik Admins.')
" 2> /dev/null | grep -E '^(User|Added)'
echo "Done. Sign in as ${DEV_USER} / ${DEV_PASSWORD}. The SSH private key is ${KEY}."

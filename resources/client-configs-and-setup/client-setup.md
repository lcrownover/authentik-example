# SSSD + LDAP login on Debian

Configure a Debian VM to authenticate SSH logins against an LDAP server
(tested against Authentik's LDAP outpost), with SSH public keys pulled
from the `sshPublicKey` LDAP attribute.

## What you'll end up with

- Users defined in LDAP can `ssh` into the Debian box using the SSH
  public key stored in LDAP (password logins are disabled in sshd below).
- Only members of `uo.pirg.*` groups are allowed to log in.
- Home directories are created automatically on first login.
- No per-user configuration on the Debian box — add a user in LDAP and
  they can log in immediately.

Throughout this guide, replace:

- `YOUR_LDAP_SERVER` with the host running the LDAP outpost (port 389).
- `YOUR_BIND_PASSWORD` with `bind_account_password` from `env.tfvars`.
- `dc=example,dc=org` with the base DN for your `domain` (`example.org` becomes `dc=example,dc=org`).

## Prerequisites

- A Debian box (tested on Debian 12) with root access.
- An LDAP server reachable from the Debian box.
- A bind/service account in LDAP that can search the user tree.
- LDAP users with at minimum: `cn` (username), `uidNumber`, `gidNumber`,
  `homeDirectory`, and optionally `sshPublicKey`.

Verify the bind account works before starting:

```bash
ldapsearch -x -H ldap://YOUR_LDAP_SERVER \
  -D "cn=ldapservice,ou=users,dc=example,dc=org" \
  -w 'YOUR_BIND_PASSWORD' \
  -b "dc=example,dc=org" \
  "(objectClass=user)" dn cn uidNumber
```

If that returns your users, you're ready.

## Install packages

```bash
sudo apt update
sudo apt install -y \
    sudo \
    sssd sssd-ldap sssd-tools \
    libnss-sss libpam-sss \
    ldap-utils openssh-server
```

## Configure SSSD

Create `/etc/sssd/sssd.conf` (must be mode `0600`, owned by root):

```ini
[sssd]
services = nss, pam, ssh
domains = LDAP

[domain/LDAP]
id_provider = ldap
# access_provider => see /etc/sssd/conf.d/50-pirg-access.conf
sudo_provider = none
ldap_id_mapping = false
ldap_uri = ldap://YOUR_LDAP_SERVER
ldap_schema = rfc2307bis
ldap_search_base = dc=example,dc=org
ldap_default_bind_dn = cn=ldapservice,ou=users,dc=example,dc=org
ldap_default_authtok_type = password
ldap_default_authtok = YOUR_BIND_PASSWORD

# SSH Key from ldap
ldap_user_ssh_public_key = sshPublicKey
ldap_user_extra_attrs = sshPublicKey

# Authentik-specific: username lives in cn, not uid
ldap_user_object_class = user
ldap_user_name = cn
ldap_group_object_class = group
ldap_group_name = cn
ldap_user_uuid = entryUUID
ldap_group_uuid = entryUUID

# POSIX attributes Authentik does provide
ldap_user_uid_number = uidNumber
ldap_user_gid_number = gidNumber
ldap_user_home_directory = homeDirectory

# Authentik doesn't ship loginShell, so force one
default_shell = /bin/bash
fallback_homedir = /home/%u

ldap_id_use_start_tls = false
```

Lock down permissions (SSSD refuses to start otherwise):

```bash
sudo chown root:root /etc/sssd/sssd.conf
sudo chmod 600 /etc/sssd/sssd.conf
```

Create the script that limits logins to PIRG members, at
`/usr/local/sbin/refresh-pirg-access`:

```bash
#!/bin/bash
# Allow logins only for members of uo.pirg.* groups in LDAP.
set -euo pipefail

CONF=/etc/sssd/conf.d/50-pirg-access.conf

groups=$(ldapsearch -LLL -x -H ldap://YOUR_LDAP_SERVER \
  -D "cn=ldapservice,ou=users,dc=example,dc=org" -w 'YOUR_BIND_PASSWORD' \
  -b "ou=groups,dc=example,dc=org" "(cn=uo.pirg.*)" cn \
  | awk '/^cn:/ {print $2}' | paste -sd, -)

# SSSD's simple provider allows EVERYONE when the allow list is empty, so never
# write an empty list (e.g. when LDAP is unreachable).
if [ -z "$groups" ]; then
  echo "refresh-pirg-access: no uo.pirg.* groups found, leaving $CONF unchanged" >&2
  exit 1
fi

tmp=$(mktemp)
cat > "$tmp" <<EOF
[domain/LDAP]
access_provider = simple
simple_allow_groups = ${groups}
EOF

# Only restart sssd when the group list actually changed
if ! cmp -s "$tmp" "$CONF"; then
  install -m 600 "$tmp" "$CONF"
  sss_cache -E
  systemctl restart sssd
fi
rm -f "$tmp"
```

Make it executable, run it once, and schedule it:

```bash
sudo chmod 700 /usr/local/sbin/refresh-pirg-access
sudo /usr/local/sbin/refresh-pirg-access
echo '*/5 * * * * root /usr/local/sbin/refresh-pirg-access' | sudo tee /etc/cron.d/refresh-pirg-access
```

New PIRG groups created by the uo stack are picked up within five minutes,
or immediately if you run the script by hand.

### What the Authentik block is doing

Authentik's LDAP outpost stores usernames in `cn` (not `uid`) and uses
`user`/`group` object classes (not `posixAccount`/`posixGroup`). The
`ldap_user_*` and `ldap_group_*` overrides tell SSSD how to map those
to standard POSIX fields. If you're pointing SSSD at vanilla OpenLDAP
or 389 Directory Server, delete that block.

### A note on TLS

The config above disables TLS for simplicity. For anything beyond a
trusted internal network, replace the `ldap_id_use_start_tls = false` line with:

```ini
ldap_id_use_start_tls = true
ldap_tls_reqcert = demand
ldap_tls_cacert = /etc/ssl/certs/your-ca.pem
```

## Enable home directory creation

```bash
sudo pam-auth-update --enable mkhomedir
```

This adds `pam_mkhomedir` to the PAM stack so first-time logins get a
home directory created from `/etc/skel`.

## Configure sshd

Edit `/etc/ssh/sshd_config` and set:

```
AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
AuthorizedKeysCommandUser nobody
UsePAM yes
PasswordAuthentication no
```

Make sure you have a way back into root such as setting an SSH key for root, or ensuring
that you have a user with an SSH key that can su to root!

`sss_ssh_authorizedkeys` is the helper sshd calls to fetch keys from
SSSD for the user logging in.

## Start everything

```bash
sudo systemctl stop sssd
sudo sss_cache -E
sudo systemctl enable --now sssd
sudo systemctl restart ssh
```

Clearing the cache is important — SSSD caches aggressively, so config
changes don't always take effect without it.

## Verify

```bash
# Does NSS see the user?
getent passwd alice

# Does SSSD resolve group membership?
id alice

# Does SSSD return the user's SSH key?
sss_ssh_authorizedkeys alice

# Log in
ssh alice@your-debian-box
```

## Troubleshooting

**`getent passwd alice` returns nothing.** Either the search base is
wrong, or the schema overrides don't match your LDAP. Run an
`ldapsearch` with the same bind DN SSSD uses and confirm the user
appears with the attributes you expect.

**SSSD won't start.** Check `journalctl -u sssd -f`. The most common
cause is wrong permissions on `/etc/sssd/sssd.conf` — must be `600`
and owned by root.

**TLS errors in the journal.** Lookups need `ldap_id_use_start_tls = false`
(as above) or a proper CA cert. If you enable password logins without TLS,
SSSD also requires `ldap_auth_disable_tls_never_use_in_production = true`.

**`sss_ssh_authorizedkeys alice` returns nothing.** Confirm the
attribute is actually populated and readable by the bind account:

```bash
ldapsearch -x -H ldap://YOUR_LDAP -D "BIND_DN" -w 'PW' \
  -b "SEARCH_BASE" "(cn=alice)" sshPublicKey
```

If it's empty, the issue is on the LDAP side. If it's populated but
SSSD doesn't return it, double-check `ldap_user_ssh_public_key` and
`ldap_user_extra_attrs` are in the config and you cleared the cache.

**Login fails with `Permission denied`.** Check `/var/log/auth.log`.
Usually either PAM doesn't have `pam_sss` enabled (re-run
`sudo pam-auth-update`) or your LDAP server's access policy rejects
the user.

## Useful commands

```bash
# Tail SSSD logs
sudo journalctl -u sssd -f

# Wipe cache and restart (after any config change)
sudo systemctl stop sssd && sudo rm -f /var/lib/sss/db/* /var/lib/sss/mc/* && sudo systemctl start sssd

# Test an LDAP bind manually
ldapwhoami -x -H ldap://YOUR_LDAP -D "BIND_DN" -w 'PW'
```

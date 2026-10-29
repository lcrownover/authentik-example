# authentik-example

An example identity system for research computing, built on [Authentik](https://goauthentik.io) and managed with Terraform. It runs locally with Docker Compose and provides:

- **InCommon sign-in** through an Entra ID OAuth source. These users are active immediately.
- **Direct sign-up** with a password and SSH key. These accounts are created inactive, and admins are emailed to approve them.
- **An LDAP outpost** that Linux hosts bind to through SSSD, so users can SSH in with the key stored in Authentik.
- **Per-institution stacks** (`stacks/uo`) that manage groups and their members in code.

> [!WARNING]
> This is a development setup. LDAP runs without TLS, the defaults are throwaway values, and the worker has access to the Docker socket. Don't expose it to untrusted networks as-is.

## Layout

| Path | What it is |
| --- | --- |
| `compose.yml` | Postgres, Authentik server and worker, and the LDAP outpost |
| `*.tf` | The environment: flows, stages, policies, branding and LDAP. One file per flow. |
| `stacks/uo/` | An example groups stack, a separate Terraform root with its own state |
| `run.sh` | Brings everything up and wires the tokens together (`make run`) |
| `seed-dev-user.sh` | Creates a dev user with a generated SSH key (`make seed`) |
| `blueprints/custom/` | Blueprints Authentik applies on startup |
| `custom-templates/` | Email templates |
| `resources/client-configs-and-setup/` | [Configuring a Debian host to log in through LDAP](resources/client-configs-and-setup/client-setup.md) |
| `DEMO.md` | Script for an end-to-end demo |

## Setup

Requires Docker with Compose v2.24 or newer, Terraform 1.9 or newer, `curl`, `python3` and `ssh-keygen`.

### 1. Configure

```bash
cp .env.example .env
cp env.tfvars.example env.tfvars
```

In **`.env`**:

| Setting | |
| --- | --- |
| `PG_PASS`, `AUTHENTIK_SECRET_KEY` | **Required.** Generate each with `openssl rand -base64 36 \| tr -d '\n'`. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | The `akadmin` password, applied when the database is first created. |
| `AUTHENTIK_EMAIL__*` | Your SMTP server. Without one, everything works except the approval emails. |
| `COMPOSE_PORT_*` | Optional, if the default ports (9000, 9443, 389, 636) are taken. |

In **`env.tfvars`**:

| Setting | |
| --- | --- |
| `bind_account_password` | **Required.** Password for the `ldapservice` account that LDAP clients bind with. |
| `domain` | Brand domain. Also sets the LDAP base DN: `example.org` becomes `dc=example,dc=org`. |
| `oidc_*` | Entra ID app details for InCommon sign-in (see below). Leave them blank to skip it. |
| `server` | The Authentik URL. Change the port here if you changed `COMPOSE_PORT_HTTP`. |
| `token` | Leave blank. `make run` fills it in. |

### 2. Run

```bash
make run
```

This is safe to re-run. It:

1. Starts Postgres, the server and the worker, and waits for Authentik to be healthy.
2. Creates (or reuses) a non-expiring `akadmin` API token and writes it to `env.tfvars`. It also writes the token and server URL to `stacks/uo/env.tfvars`, creating that file if needed.
3. Runs `terraform apply` for the environment.
4. Writes the LDAP outpost's token to `ldap.env` and starts the LDAP container.

Then sign in at <http://localhost:9000> as **`akadmin`** with your bootstrap password.

### 3. Optional: seed a dev user

```bash
make seed
```

Creates `devuser` (password `devpassword`) in `authentik Admins`. The first run also generates an SSH key pair for it in `.dev-ssh/`, which is gitignored. Set `DEV_USER` or `DEV_PASSWORD` to override the defaults.

### 4. Deploy the groups stack

```bash
make uo
```

Groups and their members are defined in `stacks/uo/groups.tf`. Members are matched by username. A username that doesn't exist yet is skipped, so re-run `make uo` after the user signs up. The example groups include `devuser`, so after `make seed` you can see membership show up in LDAP right away.

To add another institution, copy `stacks/uo` and give it its own groups.

### 5. Optional: InCommon sign-in through Entra ID

1. In the Entra admin center, go to **App registrations → New registration**.
2. Add a **Web** redirect URI. Use the `oidc_callback_uri` that `make run` prints, which by default is `http://localhost:9000/source/oauth/callback/incommon/`.
3. Under **Certificates & secrets**, create a client secret and copy its **Value**.
4. Put the tenant ID, the application (client) ID and the secret into `env.tfvars`, then run `make run` again.

## Connecting a Linux host

The LDAP outpost listens on port 389. [The client setup guide](resources/client-configs-and-setup/client-setup.md) configures a Debian host so that:

- users log in with the SSH key stored in Authentik;
- only members of `uo.pirg.*` groups are allowed in.

To check the outpost from your machine:

```bash
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=ldapservice,ou=users,dc=example,dc=org" -w 'YOUR_BIND_PASSWORD' \
  -b "dc=example,dc=org" "(objectClass=user)" cn sshPublicKey
```

## Make targets

```
make run        Start authentik and apply terraform (safe to re-run)
make seed       Create the devuser dev user (with an SSH key) in authentik Admins
make stop       Stop containers, keeping data
make plan       Show pending changes to the environment
make terraform  Apply the environment config only
make uo         Apply the uo stack (groups and members)
make clean      Delete containers, the database and all terraform state
```

## Resetting

```bash
make clean && make run
```

`make clean` deletes the database volume, both Terraform states and `ldap.env`. Every API token dies with the database. `make run` issues new ones and writes them everywhere they're needed, so `make seed` and `make uo` work right after.

## Troubleshooting

**Sign-in says the password is invalid.** Check the username first. The login form asks for a password even when the username doesn't exist, so a typo shows up as a bad password.

**`terraform apply` fails with "already exists" errors.** Terraform state was lost, but the objects are still in the database. The fix is `make clean && make run`. If the database has data you need, back it up first:

```bash
docker compose exec -T postgresql pg_dumpall -U authentik > backup.sql
```

**The LDAP outpost won't connect, or clients can't bind.** Run `docker compose logs ldap`. Re-running `make run` refreshes the outpost token in `ldap.env`.

**No approval emails arrive.** Check the `AUTHENTIK_EMAIL__*` settings, then `docker compose logs worker`. To send a test message: `docker compose exec worker ak test_email you@example.org`.

# Demo

An end-to-end walkthrough: a user signs in through InCommon, registers an SSH key, is added to a group in code, and can then SSH into a Linux host that knows nothing about them in advance.

You'll need:

- This environment set up per the [README](README.md), including the Entra ID app.
- A Debian host configured with the [client setup guide](resources/client-configs-and-setup/client-setup.md), shown below as `client.example.org`.
- A local account with sudo on that host, for watching from the inside.
- An InCommon account to sign in with. Below, its Authentik username is `jdoe`.

## Script

1. Log in to the client host with your local account and become root.

   ```bash
   ssh localadmin@client.example.org
   sudo -i
   ```

1. Show that `jdoe` doesn't exist on the host and can't log in.

   ```bash
   id jdoe
   ssh jdoe@client.example.org
   ```

1. Start the environment.

   ```bash
   make run
   ```

1. Open <http://localhost:9000> and sign in as `akadmin` with the bootstrap password. Show **Directory → Users** and **Groups**.

1. In a private window, choose the InCommon sign-in button. When the enrollment flow asks for an SSH key, show that an invalid key is rejected, then paste the user's real public key.

1. Show the self-service settings, such as changing the SSH key.

1. Talk through the access model. New users could get sandbox access through a default group. To join a specific research group (PIRG), they ask their support team, who add them in code.

1. Show `stacks/uo/groups.tf` and add `jdoe` to a group:

   ```hcl
   "uo.pirg.test" = { members = ["jdoe"] }
   ```

1. Deploy the uo stack, then show the group and its member in the admin portal.

   ```bash
   make uo
   ```

1. Back in the root session on the client host, refresh the PIRG access list and show that the user now resolves.

   ```bash
   refresh-pirg-access
   id jdoe
   ```

1. SSH in as the user with their key.

   ```bash
   ssh jdoe@client.example.org
   ```

1. Show their group memberships, and that admins get sudo if the host grants it to `uo.admins`.

   ```bash
   id
   sudo -l
   ```

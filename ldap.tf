# LDAP outpost, provider and the service account clients bind with.

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

# LDAP bind account
resource "authentik_user" "ldapservice" {
  type     = "service_account"
  name     = "LDAP Service Account"
  username = "ldapservice"
  password = var.bind_account_password
}

resource "authentik_rbac_role" "ldap_search" {
  name = "LDAP search"
}


# The provider can't grant the search_full_directory permission, so do it in the shell.
resource "terraform_data" "ldap_search_permission" {
  triggers_replace = {
    role_id = authentik_rbac_role.ldap_search.id
    user_id = authentik_user.ldapservice.id
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      docker compose exec -T server ak shell -c "
from authentik.core.models import User
from authentik.rbac.models import Role
from django.contrib.auth.models import Permission
role = Role.objects.get(name='LDAP search')
perm = Permission.objects.get(codename='search_full_directory')
user = User.objects.get(username='ldapservice')
_, created = role.rolemodelpermission_set.get_or_create(permission=perm, content_type=perm.content_type)
print('Permission assigned.' if created else 'Permission already existed.')
role.users.add(user)
print('User assigned to role.')
"
    EOT
  }

  depends_on = [authentik_rbac_role.ldap_search]
}

resource "authentik_outpost" "ldap" {
  name = "ldap"
  type = "ldap"
  protocol_providers = [
    authentik_provider_ldap.ldap.id
  ]
}
resource "authentik_provider_ldap" "ldap" {
  name             = "ldap"
  base_dn          = local.ldap_base_dn
  bind_flow        = authentik_flow.authentication.uuid
  unbind_flow      = data.authentik_flow.default_invalidation_flow.id
  bind_mode        = "direct"
  search_mode      = "direct"
  mfa_support      = false
  uid_start_number = 10000
  gid_start_number = 60000
}

resource "authentik_application" "statewide" {
  name              = "statewide"
  slug              = "statewide"
  protocol_provider = authentik_provider_ldap.ldap.id
}

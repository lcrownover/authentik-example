terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
    }
  }
}

data "authentik_users" "all" {}

locals {
  member_pks = toset([
    for u in data.authentik_users.all.users : u.pk
    if contains(var.members, u.username)
  ])
}

resource "authentik_group" "this" {
  name  = var.name
  users = local.member_pks
}

# Group name => usernames. Usernames that don't exist yet are skipped,
# so re-run `make uo` after new users sign up.
locals {
  groups = {
    "uo.admins"    = { members = ["devuser"] }
    "uo.pirg.test" = { members = ["devuser"] }
  }
}

module "groups" {
  source   = "./modules/uo_pirg"
  for_each = local.groups
  name     = each.key
  members  = each.value.members
}

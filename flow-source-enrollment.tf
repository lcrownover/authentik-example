# Enrollment for users arriving from InCommon (Entra ID) via the OAuth source.

# OIDC Auth Source. Only created once the Entra ID app details are set in env.tfvars.
resource "authentik_source_oauth" "oidc" {
  count = local.oidc_enabled ? 1 : 0

  name                = "InCommon Federated Identity"
  slug                = "incommon"
  authentication_flow = authentik_flow.authentication.uuid
  enrollment_flow     = authentik_flow.source_enrollment.uuid

  promoted            = true
  provider_type       = "openidconnect"
  access_token_url    = "https://login.microsoftonline.com/${var.oidc_tenant_id}/oauth2/v2.0/token"
  authorization_url   = "https://login.microsoftonline.com/${var.oidc_tenant_id}/oauth2/v2.0/authorize"
  oidc_jwks_url       = "https://login.microsoftonline.com/${var.oidc_tenant_id}/discovery/v2.0/keys"
  profile_url         = "https://graph.microsoft.com/oidc/userinfo"
  oidc_well_known_url = "https://login.microsoftonline.com/${var.oidc_tenant_id}/v2.0/.well-known/openid-configuration"
  user_path_template  = "${var.domain}/incommon"
  consumer_key        = var.oidc_client_id
  consumer_secret     = var.oidc_client_secret
}

# Configure the enrollment flow -- Run when a new user is created (either by OIDC or SignUp)
resource "authentik_flow" "source_enrollment" {
  name           = "Create the account"
  title          = "Welcome to Oregon Statewide Research Computing!"
  slug           = "custom-source-enrollment"
  designation    = "enrollment"
  authentication = "require_unauthenticated"
}

# Checks if they came from external IDP
resource "authentik_policy_expression" "if_sso" {
  name       = "custom-source-enrollment-if-sso"
  expression = <<-EOT
# This policy ensures that this flow can only be used when the user
# is in a SSO Flow (meaning they come from an external IdP)
return ak_is_sso_flow
  EOT
}

# resource "authentik_policy_binding" "if_sso" {
#   target  = authentik_flow.source_enrollment.uuid
#   policy  = authentik_policy_expression.if_sso.id
#   order   = 10
#   enabled = true
#   timeout = 30
# }

# Enrollment flow -- Stage 1
resource "authentik_stage_prompt" "custom_source_enrollment" {
  name = "custom-source-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.name.id,
    authentik_stage_prompt_field.username.id,
  ]
}
resource "authentik_flow_stage_binding" "default_source_enrollment_prompt" {
  target = authentik_flow.source_enrollment.uuid
  stage  = authentik_stage_prompt.custom_source_enrollment.id
  order  = 0
}
resource "authentik_policy_binding" "if_username" {
  target  = authentik_flow_stage_binding.default_source_enrollment_prompt.id
  policy  = authentik_policy_expression.if_username.id
  order   = 10
  enabled = true
  timeout = 30
}

# Checks if IDP gave a username (oauth success)
resource "authentik_policy_expression" "if_username" {
  name       = "custom-source-enrollment-if-username"
  expression = <<-EOT
# Check if we've not been given a username by the external IdP
# and trigger the enrollment flow
return 'username' not in context.get('prompt_data', {})
  EOT
}

# Enrollment flow -- Stage 2
resource "authentik_flow_stage_binding" "enrollment_ssh_key_prompt" {
  target = authentik_flow.source_enrollment.uuid
  stage  = authentik_stage_prompt.ssh_public_key.id
  order  = 10
}

# SSH key prompt (used in SSO enrollment flow)
resource "authentik_stage_prompt" "ssh_public_key" {
  name = "custom-enrollment-ssh-key-prompt"
  fields = [
    authentik_stage_prompt_field.ssh_public_key.id,
  ]
  validation_policies = [
    authentik_policy_expression.valid_ssh_key.id,
  ]
}

# Enrollment flow -- Stage 3
resource "authentik_flow_stage_binding" "default_source_enrollment_write" {
  target = authentik_flow.source_enrollment.uuid
  stage  = authentik_stage_user_write.enrollment_write.id
  order  = 20
}

# Enrollment Write (SSO users — active immediately, already university-authenticated)
resource "authentik_stage_user_write" "enrollment_write" {
  name                     = "custom-source-enrollment-write"
  create_users_as_inactive = false
  user_type                = "internal"
  user_creation_mode       = "always_create"
  user_path_template       = "${var.domain}/incommon"
}

# Enrollment flow -- Stage 4
data "authentik_stage" "default_source_enrollment_login" {
  name = "default-source-enrollment-login"
}
resource "authentik_flow_stage_binding" "default_source_enrollment_login" {
  target = authentik_flow.source_enrollment.uuid
  stage  = data.authentik_stage.default_source_enrollment_login.id
  order  = 30
}

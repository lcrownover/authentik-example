# Login flow: identification -> password -> MFA -> login.
# Also used as the LDAP bind flow.

resource "authentik_flow" "authentication" {
  name        = "Entrypoint for application access"
  title       = "Welcome!"
  slug        = "custom-authentication-flow"
  designation = "authentication"
}

# Primary identification stage for initial app access
resource "authentik_stage_identification" "custom_authentication_identification" {
  name                      = "custom-authentication-identification"
  user_fields               = ["username"]
  enable_remember_me        = true
  case_insensitive_matching = true
  sources                   = authentik_source_oauth.oidc[*].uuid
  enrollment_flow           = authentik_flow.direct_enrollment.uuid
}

# Authentication flow -- Stage 1
resource "authentik_flow_stage_binding" "custom_authentication_identification" {
  target = authentik_flow.authentication.uuid
  stage  = authentik_stage_identification.custom_authentication_identification.id
  order  = 10
}

# Authentication flow -- Stage 2
resource "authentik_flow_stage_binding" "default_authentication_password" {
  target = authentik_flow.authentication.uuid
  stage  = data.authentik_stage.default_authentication_password.id
  order  = 20
}
resource "authentik_policy_binding" "password_stage_gate" {
  target  = authentik_flow_stage_binding.default_authentication_password.id
  policy  = authentik_policy_expression.password_stage.id
  order   = 10
  enabled = true
  timeout = 30
}

data "authentik_stage" "default_authentication_password" {
  name = "default-authentication-password"
}

# Authentication flow -- Stage 3
data "authentik_stage" "default_authentication_mfa_validation" {
  name = "default-authentication-mfa-validation"
}
resource "authentik_flow_stage_binding" "default_authentication_mfa_validation" {
  target = authentik_flow.authentication.uuid
  stage  = data.authentik_stage.default_authentication_mfa_validation.id
  order  = 30
}
resource "authentik_policy_binding" "mfa_stage_gate" {
  target  = authentik_flow_stage_binding.default_authentication_mfa_validation.id
  policy  = authentik_policy_expression.mfa_stage.id
  order   = 10
  enabled = true
  timeout = 30
}

# Authentication flow -- Stage 4
data "authentik_stage" "default_authentication_login" {
  name = "default-authentication-login"
}
resource "authentik_flow_stage_binding" "default_authentication_login" {
  target = authentik_flow.authentication.uuid
  stage  = data.authentik_stage.default_authentication_login.id
  order  = 40
}

# Password Policy Expression (no data source, so redefine here)
resource "authentik_policy_expression" "password_stage" {
  name       = "custom-authentication-flow-password-stage"
  expression = <<-EOT
flow_plan = request.context.get("flow_plan")
if not flow_plan:
    return True
# If the user does not have a backend attached to it, they haven't
# been authenticated yet and we need the password stage
return not hasattr(flow_plan.context.get("pending_user"), "backend")
  EOT
}

# MFA Policy Expression (no data source, so redefine here)
resource "authentik_policy_expression" "mfa_stage" {
  name       = "custom-authentication-flow-authenticator-validate-stage"
  expression = <<-EOT
flow_plan = request.context.get("flow_plan")
if not flow_plan:
    return True
# if the authentication method is webauthn (passwordless), then we skip the authenticator
# validation stage by returning false (true will execute the stage)
return not (flow_plan.context.get("auth_method") == "auth_webauthn_pwl")
  EOT
}

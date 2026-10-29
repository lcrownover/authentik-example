# Flow users run to edit their own name, username and SSH key.

# Flow used when user modifies their account
resource "authentik_flow" "user_settings" {
  name        = "User settings"
  title       = "Update your info"
  slug        = "custom-user-settings-flow"
  designation = "stage_configuration"
}

# User settings
resource "authentik_stage_prompt" "user_settings" {
  name = "custom-user-settings"
  fields = [
    authentik_stage_prompt_field.name.id,
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.ssh_public_key.id,
  ]
  validation_policies = [
    authentik_policy_expression.user_settings_authorization.id,
    authentik_policy_expression.valid_ssh_key.id,
  ]
}

# User Settings Authorization Policy Expression (no data source, so redefine here)
resource "authentik_policy_expression" "user_settings_authorization" {
  name       = "custom-user-settings-authorization"
  expression = <<-EOT
from authentik.core.models import (
    USER_ATTRIBUTE_CHANGE_NAME,
    USER_ATTRIBUTE_CHANGE_USERNAME
)
prompt_data = request.context.get("prompt_data")

if not request.user.group_attributes(request.http_request).get(
    USER_ATTRIBUTE_CHANGE_NAME, request.http_request.tenant.default_user_change_name
):
    if prompt_data.get("name") != request.user.name:
        ak_message("Not allowed to change name.")
        return False

if not request.user.group_attributes(request.http_request).get(
    USER_ATTRIBUTE_CHANGE_USERNAME, request.http_request.tenant.default_user_change_username
):
    if prompt_data.get("username") != request.user.username:
        ak_message("Not allowed to change username.")
        return False

return True
  EOT
}

# User settings flow -- Stage 1
resource "authentik_flow_stage_binding" "custom_user_settings" {
  target = authentik_flow.user_settings.uuid
  stage  = authentik_stage_prompt.user_settings.id
  order  = 10
}

# User Writing
resource "authentik_stage_user_write" "user_write" {
  name      = "custom-user-settings-write"
  user_type = "internal"
}

# User settings flow -- Stage 2
resource "authentik_flow_stage_binding" "custom_user_settings_write" {
  target = authentik_flow.user_settings.uuid
  stage  = authentik_stage_user_write.user_write.id
  order  = 20
}

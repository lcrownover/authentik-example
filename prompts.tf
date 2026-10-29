# Prompt fields and validation shared by the enrollment and user settings flows.

# Name and username
resource "authentik_stage_prompt_field" "name" {
  name                     = "custom-user-settings-field-name"
  field_key                = "name"
  label                    = "Name"
  type                     = "text"
  required                 = true
  placeholder              = "Name"
  order                    = 10
  initial_value            = <<-EOT
try:
    return user.name
except:
    return ''
  EOT
  initial_value_expression = true
}
resource "authentik_stage_prompt_field" "username" {
  name                     = "custom-user-settings-field-username"
  field_key                = "username"
  label                    = "Username"
  type                     = "username"
  required                 = true
  placeholder              = "Username"
  order                    = 20
  initial_value            = <<-EOT
try:
    return user.username
except:
    return ''
  EOT
  initial_value_expression = true
}

# SSH Public Key prompt field
resource "authentik_stage_prompt_field" "ssh_public_key" {
  name                     = "custom-enrollment-ssh-key-prompt-field"
  field_key                = "attributes.sshPublicKey"
  label                    = "SSH Public Key"
  type                     = "text_area"
  required                 = true
  order                    = 50
  placeholder              = "ssh-ed25519 AAAA... user@host"
  sub_text                 = "What's this? [Link here]"
  initial_value            = <<-EOT
try:
    return user.attributes.get("sshPublicKey", "")
except:
    return ""
  EOT
  initial_value_expression = true
}

# Validates that the submitted value is a parseable SSH public key
resource "authentik_policy_expression" "valid_ssh_key" {
  name       = "custom-enrollment-valid-ssh-key"
  expression = <<-EOT
from cryptography.hazmat.primitives.serialization import load_ssh_public_key

prompt_data = request.context.get("prompt_data", {})

# field_key "attributes.sshPublicKey" may be stored flat or nested depending on context
key_str = (
    prompt_data.get("attributes.sshPublicKey") or
    prompt_data.get("attributes", {}).get("sshPublicKey", "")
)
key_str = str(key_str).strip() if key_str else ""

if not key_str:
    ak_message("SSH public key is required.")
    return False

try:
    load_ssh_public_key(key_str.encode())
    return True
except Exception:
    ak_message("Please provide a valid SSH public key. What's that? [Link]")
    return False
  EOT
}

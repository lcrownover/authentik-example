# Self-service sign-up with a password. Accounts are created inactive and admins are emailed.

# Direct sign-up flow -- name, username, password, ssh key, then login
resource "authentik_flow" "direct_enrollment" {
  name           = "Direct enrollment"
  title          = "Create your account"
  slug           = "custom-direct-enrollment"
  designation    = "enrollment"
  authentication = "require_unauthenticated"
}

# Password fields (used in direct enrollment flow)
resource "authentik_stage_prompt_field" "password" {
  name      = "custom-enrollment-password-field"
  field_key = "password"
  label     = "Password"
  type      = "password"
  required  = true
  order     = 30
}
resource "authentik_stage_prompt_field" "password_repeat" {
  name      = "custom-enrollment-password-repeat-field"
  field_key = "password_repeat"
  label     = "Confirm Password"
  type      = "password"
  required  = true
  order     = 40
}

# Direct enrollment prompt (name, username, password, ssh key)
resource "authentik_stage_prompt" "direct_enrollment" {
  name = "custom-direct-enrollment-prompt"
  fields = [
    authentik_stage_prompt_field.name.id,
    authentik_stage_prompt_field.username.id,
    authentik_stage_prompt_field.password.id,
    authentik_stage_prompt_field.password_repeat.id,
    authentik_stage_prompt_field.ssh_public_key.id,
  ]
  validation_policies = [
    authentik_policy_expression.valid_ssh_key.id,
  ]
}

# Direct enrollment -- Stage 1: collect name, username, password, ssh key
resource "authentik_flow_stage_binding" "direct_enrollment_prompt" {
  target = authentik_flow.direct_enrollment.uuid
  stage  = authentik_stage_prompt.direct_enrollment.id
  order  = 10
}

# Direct Enrollment Write (password signups — inactive until admin approves)
resource "authentik_stage_user_write" "direct_enrollment_write" {
  name                     = "custom-direct-enrollment-write"
  create_users_as_inactive = true
  user_type                = "internal"
  user_creation_mode       = "always_create"
  user_path_template       = "${var.domain}/external"
}

# Direct enrollment -- Stage 2: write user (password is picked up from prompt_data)
resource "authentik_flow_stage_binding" "direct_enrollment_write" {
  target = authentik_flow.direct_enrollment.uuid
  stage  = authentik_stage_user_write.direct_enrollment_write.id
  order  = 20
}

# Direct enrollment -- Stage 3: pending approval message
resource "authentik_stage_prompt_field" "enrollment_pending" {
  name                     = "custom-direct-enrollment-pending-field"
  field_key                = "pending"
  label                    = "Status"
  type                     = "static"
  required                 = false
  order                    = 0
  initial_value            = "Your account has been submitted for review. You will receive an email once it has been approved."
  initial_value_expression = false
}
resource "authentik_stage_prompt" "enrollment_pending" {
  name   = "custom-direct-enrollment-pending"
  fields = [authentik_stage_prompt_field.enrollment_pending.id]
}
resource "authentik_flow_stage_binding" "direct_enrollment_pending" {
  target               = authentik_flow.direct_enrollment.uuid
  stage                = authentik_stage_prompt.enrollment_pending.id
  order                = 30
  evaluate_on_plan     = false
  re_evaluate_policies = true
}

# Send admin notification email directly after user is written
resource "authentik_policy_expression" "fire_pending_notification" {
  name       = "custom-direct-enrollment-fire-notification"
  expression = <<-EOT
from authentik.core.models import Group
from authentik.stages.email.utils import TemplateEmailMessage
from authentik.stages.email.tasks import send_mail

flow_plan = request.context.get("flow_plan")
if not flow_plan:
    return True

user = flow_plan.context.get("pending_user")
if not user:
    return True

admin_url = request.http_request.build_absolute_uri(
    f"/if/admin/#/identity/users/{user.pk}"
)

try:
    admin_group = Group.objects.get(name="authentik Admins")
    recipients = [
        (u.name, u.email)
        for u in admin_group.users.filter(is_active=True).exclude(email="")
    ]
except Exception as e:
    ak_logger.error(f"fire_pending_notification: error getting recipients: {e}")
    recipients = []

template_context = {
    "key_value": {
        "event_user_username": user.username,
        "event_user_email": user.email,
    },
    "body": f"{user.name} ({user.username}) has registered and requires activation.",
    "title": "New User Pending Activation",
    "link": {
        "target": admin_url,
        "label": "View User",
    },
}

for recipient_name, recipient_email in recipients:
    try:
        mail = TemplateEmailMessage(
            subject="Action Required: New User Pending Activation",
            to=[(recipient_name, recipient_email)],
            language="",
            template_name="email/new-user-pending.html",
            template_context=template_context,
        )
        send_mail.send_with_options(args=(mail.__dict__,))
    except Exception as e:
        ak_logger.error(f"fire_pending_notification: failed to queue email to {recipient_email}: {e}")

return True
  EOT
}
resource "authentik_policy_binding" "direct_enrollment_fire_notification" {
  target  = authentik_flow_stage_binding.direct_enrollment_pending.id
  policy  = authentik_policy_expression.fire_pending_notification.id
  order   = 0
  enabled = true
  timeout = 30
}

resource "authentik_system_settings" "settings" {
  default_token_duration = "hours=24"
}
resource "authentik_brand" "statewide" {
  domain              = var.domain
  default             = true
  branding_title      = "Statewide"
  flow_authentication = authentik_flow.authentication.uuid
  flow_user_settings  = authentik_flow.user_settings.uuid
  branding_favicon    = "/static/dist/assets/icons/icon.png"
  branding_logo       = "/static/dist/assets/icons/icon_left_brand.svg"

}

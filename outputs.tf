# Register this as the redirect URI on the Entra ID app
output "oidc_callback_uri" {
  value = "${trimsuffix(var.server, "/")}/source/oauth/callback/incommon/"
}

variable "server" {
  type        = string
  description = "Authentik base URL, e.g. http://localhost:9000"
}

variable "token" {
  type        = string
  sensitive   = true
  description = "Authentik API token. run.sh writes this automatically."
}

variable "domain" {
  type        = string
  default     = "example.org"
  description = "Brand domain. Also sets the LDAP base DN and user paths."
}

variable "oidc_tenant_id" {
  type        = string
  description = "Entra ID tenant for the InCommon OAuth source."
}

variable "oidc_client_id" {
  type = string
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "bind_account_password" {
  type        = string
  sensitive   = true
  description = "Password for the ldapservice account that LDAP clients bind with."

  validation {
    condition     = length(var.bind_account_password) >= 8
    error_message = "Set bind_account_password in env.tfvars (at least 8 characters)."
  }
}

locals {
  oidc_enabled = var.oidc_tenant_id != "" && var.oidc_client_id != "" && var.oidc_client_secret != ""
  ldap_base_dn = join(",", formatlist("dc=%s", split(".", var.domain)))
}

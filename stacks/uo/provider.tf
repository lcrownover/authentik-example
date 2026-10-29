terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.2.0"
    }
  }
}

provider "authentik" {
  url   = var.server
  token = var.token
}

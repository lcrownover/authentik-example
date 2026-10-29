variable "name" {
  type        = string
  description = "Group name in Authentik"
}

variable "members" {
  type        = list(string)
  default     = []
  description = "Usernames of members. Unrecognized usernames are silently ignored."
}

variable "boundary_url" {
  type        = string
  description = "The URL of the Boundary controller"
}

variable "admin_username" {
  type        = string
  description = "The admin username for Boundary"
  default     = "admin"
}

variable "admin_password" {
  type        = string
  description = "The admin password for Boundary"
  sensitive   = true
}

variable "org_name" {
  type        = string
  description = "The name of the Boundary Organization"
  default     = "Comet IT"
}

variable "project_name" {
  type        = string
  description = "The name of the Boundary Project"
  default     = "Comet Core"
}

variable "ldap_config" {
  type = object({
    url           = string
    user_dn       = string
    user_attr     = string
    group_dn      = string
    group_attr    = string
    bind_dn       = string
    bind_password = string
    state         = optional(string, "active-public")
  })
  description = "Optional LDAP configuration for the auth method"
  default     = null
}

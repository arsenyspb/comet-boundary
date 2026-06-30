output "auth_method_id" {
  description = "The ID of the auth method to use in Comet"
  value       = var.ldap_config != null ? boundary_auth_method_ldap.ldap[0].id : "ampw_12345" # fallback to placeholder if no ldap
}

output "target_ids" {
  description = "List of provisioned target IDs"
  value       = [for t in boundary_target.tcp : t.id]
}

output "org_id" {
  description = "The ID of the organization"
  value       = boundary_scope.org.id
}

output "project_id" {
  description = "The ID of the project"
  value       = boundary_scope.project.id
}

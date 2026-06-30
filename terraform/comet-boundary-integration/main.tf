data "boundary_scope" "global" {
  name     = "global"
  scope_id = "global"
}

resource "boundary_scope" "org" {
  name                     = var.org_name
  description              = "Organization for Comet"
  scope_id                 = data.boundary_scope.global.id
  auto_create_admin_role   = true
  auto_create_default_role = true
}

resource "boundary_scope" "project" {
  name                   = var.project_name
  description            = "Project for Comet Core"
  scope_id               = boundary_scope.org.id
  auto_create_admin_role = true
}

resource "boundary_auth_method_ldap" "ldap" {
  count         = var.ldap_config != null ? 1 : 0
  name          = "ldap_auth"
  description   = "LDAP Auth Method for Comet"
  scope_id      = boundary_scope.org.id
  urls          = [var.ldap_config.url]
  user_dn       = var.ldap_config.user_dn
  user_attr     = var.ldap_config.user_attr
  group_dn      = var.ldap_config.group_dn
  group_attr    = var.ldap_config.group_attr
  bind_dn       = var.ldap_config.bind_dn
  bind_password = var.ldap_config.bind_password
  state         = var.ldap_config.state
}

resource "boundary_managed_group_ldap" "team_a" {
  count          = var.ldap_config != null ? 1 : 0
  name           = "team_a"
  auth_method_id = boundary_auth_method_ldap.ldap[0].id
  group_names    = ["team-a"]
}

resource "boundary_host_catalog_static" "static" {
  name        = "comet_static_catalog"
  description = "Static Host Catalog"
  scope_id    = boundary_scope.project.id
}

resource "boundary_host_static" "host1" {
  name            = "ssh-target-1"
  description     = "SSH Target 1"
  host_catalog_id = boundary_host_catalog_static.static.id
  address         = "ssh-target-1"
}

resource "boundary_host_set_static" "set" {
  name            = "comet_host_set"
  host_catalog_id = boundary_host_catalog_static.static.id
  host_ids        = [boundary_host_static.host1.id]
}

resource "boundary_credential_store_static" "static_creds" {
  name        = "comet_static_creds"
  description = "Static Credentials for Comet"
  scope_id    = boundary_scope.project.id
}

resource "boundary_credential_username_password" "ssh_cred" {
  name                = "ssh_user_password"
  description         = "Brokered credential for SSH"
  credential_store_id = boundary_credential_store_static.static_creds.id
  username            = "boundary-user"
  password            = "password"
}

resource "boundary_target" "tcp" {
  count                          = 1
  name                           = "comet_ssh_target"
  description                    = "TCP target for SSH"
  type                           = "tcp"
  default_port                   = 2222
  scope_id                       = boundary_scope.project.id
  host_source_ids                = [boundary_host_set_static.set.id]
  brokered_credential_source_ids = [boundary_credential_username_password.ssh_cred.id]
}

resource "boundary_role" "team_a_role" {
  count         = var.ldap_config != null ? 1 : 0
  name          = "team_a_access"
  scope_id      = boundary_scope.project.id
  grant_strings = ["ids=${boundary_target.tcp[0].id};actions=read,authorize-session"]
  principal_ids = [boundary_managed_group_ldap.team_a[0].id]
}

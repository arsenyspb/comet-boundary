# Comet Boundary Terraform Module

This Terraform module is designed to bootstrap HashiCorp Boundary resources for Comet integration.

## Usage

```hcl
module "comet_boundary" {
  source = "./terraform/comet-boundary-integration"

  boundary_url   = "http://localhost:9200"
  admin_username = "admin"
  admin_password = "password"
  
  ldap_config = {
    url           = "ldap://localhost:389"
    user_dn       = "ou=users,dc=comet,dc=example"
    user_attr     = "uid"
    group_dn      = "ou=groups,dc=comet,dc=example"
    group_attr    = "cn"
    bind_dn       = "cn=admin,dc=comet,dc=example"
    bind_password = "admin"
  }
}
```

## Deployment Flow
```text
Terraform Module ──(outputs)──> Helm Chart values.yaml ──(deploys)──> Comet Container
     │ configures                                                          │
     v                                                                     v
Boundary Cluster (existing) <──────(boundary connect subprocess)───── Comet Container
     │
     v
SSH Targets (existing)
```

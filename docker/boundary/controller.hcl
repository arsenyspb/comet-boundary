disable_mlock = true

telemetry {
  prometheus_retention_time = "24h"
  disable_hostname          = true
}

events {
  audit_enabled       = true
  sysevents_enabled   = true
  observations_enable = true

  sink "stderr" {
    name        = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format      = "cloudevents-json"
    audit_config {
      audit_filter_overrides {
        sensitive = ""
      }
    }
  }
}


controller {
  name        = "comet-controller"
  description = "Controller for Comet Boundary prototype"

  database {
    url = "postgresql://postgres:postgres@postgres:5432/boundary?sslmode=disable"
  }

  public_cluster_addr = "controller:9201"
}

listener "tcp" {
  address     = "0.0.0.0:9200"
  purpose     = "api"
  tls_disable = true
}

listener "tcp" {
  address     = "0.0.0.0:9201"
  purpose     = "cluster"
  tls_disable = true
}

kms "aead" {
  purpose   = "root"
  aead_type = "aes-gcm"
  key       = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=" # 32 bytes base64
  key_id    = "global_root"
}

kms "aead" {
  purpose   = "worker-auth"
  aead_type = "aes-gcm"
  key       = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI="
  key_id    = "global_worker-auth"
}

kms "aead" {
  purpose   = "recovery"
  aead_type = "aes-gcm"
  key       = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI="
  key_id    = "global_recovery"
}

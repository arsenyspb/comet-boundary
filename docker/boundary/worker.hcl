disable_mlock = true

worker {
  name              = "comet-worker"
  description       = "Worker for Comet Boundary prototype"
  initial_upstreams = ["controller:9201"]
  public_addr       = "worker:9202"
}

listener "tcp" {
  address     = "0.0.0.0:9202"
  purpose     = "proxy"
  tls_disable = true
}

kms "aead" {
  purpose   = "worker-auth"
  aead_type = "aes-gcm"
  key       = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI="
  key_id    = "global_worker-auth"
}

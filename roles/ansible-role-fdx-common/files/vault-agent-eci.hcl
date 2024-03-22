vault {
  address = "https://vault-prod-centralus-core.chrazure.cloud"
  ca_cert = "/etc/pki/ca-trust/source/anchors/chr-ca.pem"
}
auto_auth {
  method "azure" {
    config {
      role = "eci"
      resource = "http://vault-aks-sp"
    }
  }
  sink "file" {
    config = {
      path = "/etc/vault/vault-token"
    }
  }
}

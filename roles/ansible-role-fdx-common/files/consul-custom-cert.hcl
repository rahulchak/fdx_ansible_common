# This denotes the start of the configuration section for Consul. All values
# contained in this section pertain to Consul.
consul {
  # This block specifies the basic authentication information to pass with the
  # request. For more information on authentication, please see the Consul
  # documentation.
  auth {
    enabled  = false
    username = "test"
    password = "test"
  }

  # This is the address of the Consul agent. By default, this is
  # 127.0.0.1:8500, which is the default bind and port for a local Consul
  # agent. It is not recommended that you communicate directly with a Consul
  # server, and instead communicate with the local Consul agent. There are many
  # reasons for this, most importantly the Consul agent is able to multiplex
  # connections to the Consul server and reduce the number of open HTTP
  # connections. Additionally, it provides a "well-known" IP address for which
  # clients can connect.
  address = "127.0.0.1:8500"

  # This is the ACL token to use when connecting to Consul. If you did not
  # enable ACLs on your Consul cluster, you do not need to set this option.
  #
  # This option is also available via the environment variable CONSUL_TOKEN.
  token = "abcd1234"

  # This controls the retry behavior when an error is returned from Consul.
  # Consul Template is highly fault tolerant, meaning it does not exit in the
  # face of failure. Instead, it uses exponential back-off and retry functions
  # to wait for the cluster to become available, as is customary in distributed
  # systems.
  retry {
    # This enabled retries. Retries are enabled by default, so this is
    # redundant.
    enabled = true

    # This specifies the number of attempts to make before giving up. Each
    # attempt adds the exponential backoff sleep time. Setting this to
    # zero will implement an unlimited number of retries.
    attempts = 12

    # This is the base amount of time to sleep between retry attempts. Each
    # retry sleeps for an exponent of 2 longer than this base. For 5 retries,
    # the sleep times would be: 250ms, 500ms, 1s, 2s, then 4s.
    backoff = "250ms"

    # This is the maximum amount of time to sleep between retry attempts.
    # When max_backoff is set to zero, there is no upper limit to the
    # exponential sleep between retry attempts.
    # If max_backoff is set to 10s and backoff is set to 1s, sleep times
    # would be: 1s, 2s, 4s, 8s, 10s, 10s, ...
    max_backoff = "1m"
  }

  # This block configures the SSL options for connecting to the Consul server.
  ssl {
    # This enables SSL. Specifying any option for SSL will also enable it.
    enabled = false

    # This enables SSL peer verification. The default value is "true", which
    # will check the global CA chain to make sure the given certificates are
    # valid. If you are using a self-signed certificate that you have not added
    # to the CA chain, you may want to disable SSL verification. However, please
    # understand this is a potential security vulnerability.
    verify = false

    # This is the path to the certificate to use to authenticate. If just a
    # certificate is provided, it is assumed to contain both the certificate and
    # the key to convert to an X509 certificate. If both the certificate and
    # key are specified, Consul Template will automatically combine them into an
    # X509 certificate for you.
    cert = "/path/to/client/cert"
    key  = "/path/to/client/key"

    # This is the path to the certificate authority to use as a CA. This is
    # useful for self-signed certificates or for organizations using their own
    # internal certificate authority.
    ca_cert = "/path/to/ca"

    # This is the path to a directory of PEM-encoded CA cert files. If both
    # `ca_cert` and `ca_path` is specified, `ca_cert` is preferred.
    ca_path = "path/to/certs/"

    # This sets the SNI server name to use for validation.
    server_name = "my-server.com"
  }
}

# This is the signal to listen for to trigger a reload event. The default
# value is shown below. Setting this value to the empty string will cause CT
# to not listen for any reload signals.
reload_signal = "SIGHUP"

# This is the signal to listen for to trigger a graceful stop. The default
# value is shown below. Setting this value to the empty string will cause CT
# to not listen for any graceful stop signals.
kill_signal = "SIGINT"

# This is the maximum interval to allow "stale" data. By default, only the
# Consul leader will respond to queries; any requests to a follower will
# forward to the leader. In large clusters with many requests, this is not as
# scalable, so this option allows any follower to respond to a query, so long
# as the last-replicated data is within these bounds. Higher values result in
# less cluster load, but are more likely to have outdated data.
max_stale = "10m"

# This is the log level. If you find a bug in Consul Template, please enable
# debug logs so we can help identify the issue. This is also available as a
# command line flag.
log_level = "warn"

# This is the path to store a PID file which will contain the process ID of the
# Consul Template process. This is useful if you plan to send custom signals
# to the process.
pid_file = "/etc/consul/consul-custom-cert.pid"

# This is the quiescence timers; it defines the minimum and maximum amount of
# time to wait for the cluster to reach a consistent state before rendering a
# template. This is useful to enable in systems that have a lot of flapping,
# because it will reduce the the number of times a template is rendered.
wait {
  min = "5s"
  max = "10s"
}

# This denotes the start of the configuration section for Vault. All values
# contained in this section pertain to Vault.
vault {
  # This is the address of the Vault leader. The protocol (http(s)) portion
  # of the address is required.
  address = "https://vault-prod-centralus-core.chrazure.cloud"

  # This is a Vault Enterprise namespace to use for reading/writing secrets.
  #
  # This value can also be specified via the environment variable VAULT_NAMESPACE.
  #  namespace = "foo"

  # This is the token to use when communicating with the Vault server.
  # Like other tools that integrate with Vault, Consul Template makes the
  # assumption that you provide it with a Vault token; it does not have the
  # incorporated logic to generate tokens via Vault's auth methods.
  #
  # This value can also be specified via the environment variable VAULT_TOKEN.
  # When using a token from Vault Agent, the vault_agent_token_file setting
  # should be used instead, as that will take precedence over this field.
  #  token = "abcd1234"

  # This tells Consul Template to load the Vault token from the contents of a file.
  # If this field is specified:
  # - by default Consul Template will not try to renew the Vault token, if you want it
  # to renew you will nee dto specify renew_token = true as below.
  # - Consul Template will periodically stat the file and update the token if it has
  # changed.
  vault_agent_token_file = "/etc/vault/vault-token"

  # This tells Consul Template that the provided token is actually a wrapped
  # token that should be unwrapped using Vault's cubbyhole response wrapping
  # before being used. Please see Vault's cubbyhole response wrapping
  # documentation for more information.
  unwrap_token = false

  # This option tells Consul Template to automatically renew the Vault token
  # given. If you are unfamiliar with Vault's architecture, Vault requires
  # tokens be renewed at some regular interval or they will be revoked. Consul
  # Template will automatically renew the token at half the lease duration of
  # the token. The default value is true, but this option can be disabled if
  # you want to renew the Vault token using an out-of-band process.
  #
  # Note that secrets specified in a template (using {{secret}} for example)
  # are always renewed, even if this option is set to false. This option only
  # applies to the top-level Vault token itself.
  renew_token = true

  # This section details the retry options for connecting to Vault. Please see
  # the retry options in the Consul section for more information (they are the
  # same).
  retry {
    # ...
  }

  # This section details the SSL options for connecting to the Vault server.
  # Please see the SSL options in the Consul section for more information (they
  # are the same).
  ssl {
    ca_cert = "/etc/pki/ca-trust/source/anchors/chr-ca.pem"
  }
}

# This block defines the configuration for connecting to a syslog server for
# logging.
syslog {
  # This enables syslog logging. Specifying any other option also enables
  # syslog logging.
  enabled = true

  # This is the name of the syslog facility to log to.
  facility = "LOCAL5"
}

# This block defines the configuration for de-duplication mode. Please see the
# de-duplication mode documentation later in the README for more information
# on how de-duplication mode operates.
deduplicate {
  # This enables de-duplication mode. Specifying any other options also enables
  # de-duplication mode.
  enabled = false

  # This is the prefix to the path in Consul's KV store where de-duplication
  # templates will be pre-rendered and stored.
  prefix = "consul-template/dedup/"
}

# This block defines the configuration for exec mode. Please see the exec mode
# documentation at the bottom of this README for more information on how exec
# mode operates and the caveats of this mode.

# This block defines the configuration for a template. Unlike other blocks,
# this block may be specified multiple times to configure multiple templates.
# It is also possible to configure templates via the CLI directly.
template {
  source           = "/etc/consul/templates/custom-cert.tpl"
  destination      = "/etc/consul/pki/custom-cert.crt"
  create_dest_dirs = true
  #  command = "restart service foo"
  #  command_timeout = "60s"
  error_on_missing_key = true
  perms                = 0644
  backup               = false
  wait {
    min = "2s"
    max = "10s"
  }
}
template {
  source           = "/etc/consul/templates/custom-cert-key.tpl"
  destination      = "/etc/consul/pki/custom-cert.key"
  create_dest_dirs = true
  #  command = "restart service foo"
  #  command_timeout = "60s"
  error_on_missing_key = true
  perms                = 0644
  backup               = false
  wait {
    min = "2s"
    max = "10s"
  }
}


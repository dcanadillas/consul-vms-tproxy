#!/bin/bash

# This script is for use from an image that has already Consul binary installed and CA certificates created. Also the encryption key should
# be placed in /etc/consul.d/keygen.out. In that case we are assuring that the same is used in all agents

CONSUL_DIR="/etc/consul.d"

NODE_HOSTNAME=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/hostname)
PUBLIC_IP=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
PRIVATE_IP=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
DC="${dc_name}"
CONSUL_LICENSE="${consul_license}"


sudo apt update
sudo apt install -y jq

# ---- Check directories ----
if [ -d "$CONSUL_DIR" ];then
    echo "Consul configurations will be created in $CONSUL_DIR" >> /tmp/consul-log.out
else
    echo "Consul configurations directoy does not exist. Exiting..." >> /tmp/consul-log.out
    exit 1
fi

if [ -d "/opt/consul" ]; then
    echo "Consul data directory will be created at existing /opt/consul" >> /tmp/consul-log.out
else
    echo "/opt/consul does not exist. Check that VM image is the right one. Creating directory anyway..."
    sudo mkdir -p /opt/consul
    sudo chown -R consul:consul /opt/consul
fi

# Creating a directory for audit
sudo mkdir -p /tmp/consul/audit


# ---- Enterprise Licenses ----
echo $CONSUL_LICENSE | sudo tee $CONSUL_DIR/license.hclic > /dev/null

# ---- Preparing certificates ----
echo "==> Adding server certificates to /etc/consul.d"
consul tls cert create -server -dc $DC \
    -ca "$CONSUL_DIR"/tls/consul-agent-ca.pem \
    -key  "$CONSUL_DIR"/tls/consul-agent-ca-key.pem
sudo mv "$DC"-server-consul-*.pem "$CONSUL_DIR"/tls/

# ----------------------------------
echo "==> Generating Consul configs"

sudo tee $CONSUL_DIR/consul.hcl > /dev/null <<EOF
datacenter = "$DC"
data_dir = "/opt/consul"
node_name = "${node_name}"
node_meta = {
  hostname = "$(hostname)"
  gcp_instance = "$(curl "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")"
  gcp_zone = "$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/zone" | awk -F / '{print $NF}')"
}
encrypt = "$(cat $CONSUL_DIR/keygen.out)"
tls = {
  defaults = {
    ca_file = "$CONSUL_DIR/tls/consul-agent-ca.pem"
    cert_file = "$CONSUL_DIR/tls/$DC-server-consul-0.pem"
    key_file = "/etc/consul.d/tls/$DC-server-consul-0-key.pem"
    verify_incoming = false
    verify_outgoing = false
    # verify_server_hostname = false
  }
}

recursors = ["8.8.8.8", "8.8.4.4"]

retry_join = ["provider=gce project_name=${gcp_project} tag_value=${tag} zone_pattern=${region}-.*"]
license_path = "$CONSUL_DIR/license.hclic"

auto_encrypt {
  allow_tls = true
}

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens = {
    initial_management = "${bootstrap_token}"
    agent = "${bootstrap_token}"
  }
}

performance {
  raft_multiplier = 1
}

audit {
  enabled = true
  sink "${dc_name}_sink" {
    type   = "file"
    format = "json"
    path   = "/opt/consul/audit/audit.json"
    delivery_guarantee = "best-effort"
    rotate_duration = "24h"
    rotate_max_files = 15
    rotate_bytes = 25165824
    mode = "644"
  }
}


EOF

sudo tee $CONSUL_DIR/server.hcl > /dev/null <<EOF
server = true
bootstrap_expect = ${nodes}

ui_config = {
  enabled = true
}
client_addr = "0.0.0.0"
advertise_addr = "$PRIVATE_IP"

connect {
  enabled = true
}

ports {
  https = 8501
  grpc = 8502
  grpc_tls = 8503
}

node_meta {
  zone = "${zone}"
}
EOF

echo "==> Creating the Consul service"
sudo tee /usr/lib/systemd/system/consul.service > /dev/null <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONSUL_DIR/consul.hcl

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir="$CONSUL_DIR"/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Let's set some permissions to read certificates from Consul
echo "==> Changing permissions"
sudo chown -R consul:consul "$CONSUL_DIR"/tls
sudo chown -R consul:consul /tmp/consul/audit

# ---------------




# INIT SERVICES

echo "==> Starting Consul..."
sudo systemctl start consul

sleep 10


echo "==> Adding the default token..."
# We create a policy that works for DNS
consul acl policy create -partition "default" -namespace "default" -name "dns-access" -description "DNS Policy" -token ${bootstrap_token} -rules - <<EOF
partition "default" {
    namespace "default" {
        query_prefix "" {
            policy = "read"
        }
    }
}
partition_prefix "" {
  namespace_prefix "" {
    node_prefix "" {
      policy = "read"
    }
    service_prefix "" {
      policy = "read"
    }
  }
}
EOF

# DEFAULT_TOKEN=$(consul acl token create -secret ${default_token} -token ${bootstrap_token} -format json | jq .SecretID)

# We create the token from the uuid generated in Terraform
consul acl token create -partition "default" -namespace "default" -description "Default token for DNS" -policy-name "dns-access" -secret ${default_token} -token ${bootstrap_token}

cat $CONSUL_DIR/consul.hcl | sed -e "/agent =/s/.*/&\n    default = \"${default_token}\"/" | sudo tee $CONSUL_DIR/consul.hcl

# And we restart Consul
sudo systemctl restart consul
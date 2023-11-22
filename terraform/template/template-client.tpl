#!/bin/bash

# This script is for use from an image that has already Consul binary installed and CA certificates created. Also the encryption key should
# be placed in /etc/consul.d/keygen.out. In that case we are assuring that the same is used in all agents

CONSUL_DIR="/etc/consul.d"

NODE_HOSTNAME=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/hostname)
PUBLIC_IP=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
PRIVATE_IP=$(curl -H 'Metadata-Flavor:Google' http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
DC="${dc_name}"
CONSUL_LICENSE="${consul_license}"
# ENVOY_VERSION="1.26.6"


# ---- Adding some extra packages for CTS ----
curl --fail --silent --show-error --location https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo dd of=/usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
 sudo tee -a /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update

sudo apt-get install -y consul-terraform-sync-enterprise docker-compose jq


# Installing Envoy
curl -sL https://releases.hashicorp.com/envoy/${envoy_version}/envoy_${envoy_version}_linux_amd64.zip -o envoy.zip
unzip envoy.zip
chmod 755 envoy
sudo mv envoy /usr/local/bin

sudo useradd envoy


# Download Fake Service demoapp in case we want
curl -L https://github.com/nicholasjackson/fake-service/releases/download/v0.26.0/fake_service_linux_amd64.zip -o fake-service.zip
unzip fake-service.zip
chmod 755 fake-service
sudo mv fake-service /usr/local/bin


# ---- Check directories ----
# Because we are using an expected image we need to check that required folders are already existing
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
sudo mkdir -p /opt/consul/audit


# ---- Enterprise Licenses ----
echo $CONSUL_LICENSE | sudo tee $CONSUL_DIR/license.hclic > /dev/null

# ---- Preparing certificates ----
# This is not needed anyway because we are using `auto_encrypt` method
echo "==> Creating client certificates to /etc/consul.d"
consul tls cert create -client -dc $DC \
    -ca "$CONSUL_DIR"/tls/consul-agent-ca.pem \
    -key  "$CONSUL_DIR"/tls/consul-agent-ca-key.pem
sudo mv "$DC"-client-consul-*.pem "$CONSUL_DIR"/tls/

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
    # cert_file = "$CONSUL_DIR/tls/$DC-client-consul-0.pem"
    # key_file = "/etc/consul.d/tls/$DC-client-consul-0-key.pem"
    verify_incoming = false
    verify_outgoing = true
    # verify_server_hostname = true
  }
}

retry_join = ["provider=gce project_name=${gcp_project} tag_value=${tag} zone_pattern=${region}-.*"]
license_path = "$CONSUL_DIR/license.hclic"

auto_encrypt {
  tls = true
}

acl = {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens = {
    initial_management = "${bootstrap_token}"
    agent = "${bootstrap_token}"
    default = "${default_token}"
  }
}

recursors = ["8.8.8.8", "8.8.4.4"]

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

client_addr = "0.0.0.0"
advertise_addr = "$PRIVATE_IP"

connect {
  enabled = true
}

ports {
 grpc = 8502
 # grpc_tls = 8503
}

disable_remote_exec = false

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
echo "==> Changing permissions for Consul"
sudo chown -R consul:consul "$CONSUL_DIR"/tls
sudo chown -R consul:consul /tmp/consul/audit


# ---------------



# ----- CTS CONFIG --------

# CTS NIA config
sudo useradd --system --home /etc/consul-nia.d --shell /bin/false consul-nia
sudo mkdir -p /opt/consul-nia && sudo mkdir -p /etc/consul-nia.d

echo "==> Changing permissions for Consul Terraform Sync"
sudo chown --recursive consul-nia:consul-nia /opt/consul-nia && \
  sudo chmod -R 0750 /opt/consul-nia && \
  sudo chown --recursive consul-nia:consul-nia /etc/consul-nia.d && \
  sudo chmod -R 0750 /etc/consul-nia.d

echo "==> Creating the CTS service"
sudo tee /usr/lib/systemd/system/consul-terraform-sync.service > /dev/null <<EOF
[Unit]
Description="HashiCorp Consul-Terraform-Sync - A Network Infrastructure Automation solution"
Documentation=https://www.consul.io/docs/nia
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul-nia.d/config.hcl

[Service]
EnvironmentFile=/etc/consul-nia.d/consul-nia.env
User=consul-nia
Group=consul-nia
ExecStart=/usr/bin/consul-terraform-sync start -config-dir=/etc/consul-nia.d/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

EOF

# ---------------

# INIT SERVICES

echo "==> Starting Consul..."
sudo systemctl start consul

sleep 10


# echo "==> Adding the default token..."
# # Let's create a node identity token in Consul and modify the config to make DNS work for every node
# DEFAULT_TOKEN=$(consul acl token create -node-identity ${node_name}:$DC -token ${bootstrap_token} -format json | jq .SecretID)
# cat $CONSUL_DIR/consul.hcl | sed -e "/agent =/s/.*/&\n    default = $DEFAULT_TOKEN/" | sudo tee $CONSUL_DIR/consul.hcl

# # And we restart Consul
# sudo systemctl restart consul

#Configuring DNS resolution for Consul
sudo mkdir -p /etc/systemd/resolved.conf.d

sudo tee /etc/systemd/resolved.conf.d/consul.conf <<EOF
[Resolve]
DNS=127.0.0.1
DNSSEC=false
Domains=~consul
EOF

sudo iptables --table nat --append OUTPUT --destination localhost --protocol udp --match udp --dport 53 --jump REDIRECT --to-ports 8600
sudo iptables --table nat --append OUTPUT --destination localhost --protocol tcp --match tcp --dport 53 --jump REDIRECT --to-ports 8600

sudo systemctl restart systemd-resolved

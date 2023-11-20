# Consul in GCP with Transparent Proxy

## Requirements
* A MacOS or Linux terminal
* Packer CLI
* Terraform CLI
* Owner of a GCP project
* `jq` command installed in your terminal (it is )
* gcloud CLI

## Configure your GCP environment
Configure your GCP creds:
```
gcloud auth login
```

```
gcloud config set project <gcp_project_id>
```

## Create your image with Packer
Get into the Packer directory
```
cd packer
```

Create your variables file 
```
tee consul_gcp.auto.pkrvars.hcl <<EOF
consul_version = "1.16.3+ent"
image = "consul-ent"
image_family = "custom-consul"
sshuser = "packer"
gcp_project = "<your_gcp_project_id>"
EOF
```

Build the image that will be used later for Terraform:
```
packer build . 
```

Get out of the Packer directory
```
cd ..
```

## Deploy Consul

Get into the Terraform directory:
```
cd terraform
```

Create the variable values file (replace your values):
```
tee terraform.auto.tfvars <<EOF
gcp_region = "europe-southwest1"
gcp_zone = "europe-southwest1-c"
gcp_project = "<gcp_project_id>"
gcp_instance = "n2-standard-2"
numnodes = 3
numclients = 2
# One of the names that you should see from "gcloud iam service-accounts list --format="table(NAME)""
gcp_sa = "<service_account_name>"
cluster_name = "consul-gcp-demo"
owner = "<owner_nickname>"
image_family = "custom-consul"
consul_license = "<your_Consul_Ent_license_string>"
consul_bootstrap_token = "Consul43v3r"
EOF
```


## Transparent proxy use case
We will deploy two applications (one per client node) to demonstrate how transparent proxy works to isolate the traffic between the applications authorized by Consul intentions.

Let's deploy and configure first an API demo application in the first client node

### Client Node 1

Connect to the first client node:
```
eval $(terraform output -json gcp_clients | jq -r .[0])
```

We create a `docker-compose` file to deploy the application in a docker container:

```
tee docker-compose.yaml <<EOF
version: "3.7"
services:

  api:
    image: nicholasjackson/fake-service:v0.7.8
    environment:
      LISTEN_ADDR: 0.0.0.0:9094
      MESSAGE: "API response"
      NAME: "api"
      SERVER_TYPE: "http"
      HTTP_CLIENT_APPEND_REQUEST: "true"
    ports:
    - "9094:9094"
EOF
```

And we run the application:
```
docker-compose up -d
```

> NOTE: If you want to run Docker commands without root privileges using your user 

Check the application is running:
```
curl localhost:9094
```

Let's create a service to be registered in Consul:
```
tee fake-api.hcl <<EOF
service {
  name = "fake-api"
  id = "fake-api"
  tags = ["backend", "api"]
  port = 9094


  check {
    id =  "check-fake-api",
    name = "api status check",
    service_id = "fake-api",
    tcp  = "localhost:9094",
    interval = "5s",
    timeout = "5s"
  }

  connect {
    sidecar_service {
      proxy {
        mode = "transparent"
      }
    }
  }
}
EOF
```

And register the service:
```
consul services register fake-api.hcl -token Consul43v3r
```

Now we will use the [`redirect-traffic` command](https://developer.hashicorp.com/consul/commands/connect/redirect-traffic) in Consul to automatically apply the `iptable` rules to enable the Transparent Proxy
 
```
 sudo consul connect redirect-traffic -proxy-uid 1234 \
 -proxy-id fake-api-sidecar-proxy \
 -exclude-uid $(id --user consul) \
 -exclude-uid 0 \
 -exclude-uid $(id --user _apt) \
 -exclude-inbound-port 22 \
 -token Consul43v3r
```

In this case we are forcing all the fraffic to go through Envoy, except those executed by `root` or `_apt` users. We do this for demo purposes to not block the node to access internet for some provileged workloads (being able to update with `apt update`, for example). Also, we are excluding the 22 port to be able to access the node through ssh.

You can check that the traffic is filtered now by trying to access to an URL without and with root privileges:
```
curl -L hashicorp.com
sudo curl -L hashicorp.com
```

Let's run the envoy to force all the traffic go through it:
```
sudo nohup consul connect envoy -sidecar-for fake-api -token Consul43v3r &
```

### Client Node 2
Connect to the second client node:
```
eval $(terraform output -json gcp_clients | jq -r .[1])
```

We will do the same thing in the second client node, but for a demo app called `web`.

```
tee docker-compose.yaml <<EOF
version: "3.7"
services:
  web:
    image: nicholasjackson/fake-service:v0.7.8
    environment:
      LISTEN_ADDR: 0.0.0.0:9094
      MESSAGE: "Web response"
      NAME: "web"
      SERVER_TYPE: "http"
      HTTP_CLIENT_APPEND_REQUEST: "true"
    ports:
    - "9094:9094"
EOF
```

```
docker-compose up -d
```

Let's create a service to be registered in Consul:
```
tee fake-web.hcl <<EOF
service {
  name = "fake-web"
  id = "fake-web"
  tags = ["frontend", "web"]
  port = 9094


  check {
    id =  "check-fake-web",
    name = "web status check",
    service_id = "fake-web",
    tcp  = "localhost:9094",
    interval = "5s",
    timeout = "5s"
  }

  connect {
    sidecar_service {
      proxy {
        mode = "transparent"
      }
    }
  }
}
EOF
```

And register the service:
```
consul services register -token Consul43v3r fake-web.hcl 
```


```
 sudo consul connect redirect-traffic -proxy-uid 1234 \
 -proxy-id fake-web-sidecar-proxy \
 -exclude-uid $(id --user consul) \
 -exclude-uid 0 \
 -exclude-uid $(id --user _apt) \
 -exclude-inbound-port 22 \
 -token Consul43v3r
```

```
sudo nohup consul connect envoy -sidecar-for fake-web -token Consul43v3r &
```

## Applying Consul intentions to check traffic

We remain on the client node where the web application is running.

Using Consul DNS, the `fake-api` service is discoverable:
```
host fake-api.service.consul

host fake-api.virtual.consul
```

We can check that API service is not accessible:
```
curl fake-api.virtual.consul
```

That is because Consul has a `deny all` policy by default, so services cannot be reachable (because all traffic is going through the Envoy proxy)

Let's then create the authorization `fake-web --> fake-api` by creating the corresponding Consul intention:
```
consul config write -token Consul43v3r - <<EOF
Kind = "service-intentions"
Name = "fake-api"
Sources = [

  {
    Name   = "fake-web"
    Action = "allow"
  }
]
EOF
```
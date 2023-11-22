Kind = "tcp-route"
Name = "tcp-route"

// Rules define how requests will be routed
Services = [
  {
    Name = "fake-web"
  }
]
Parents = [
  {
    Kind = "api-gateway"
    Name = "api-gateway"
    SectionName = "gw-tcp-listener"
  }
]
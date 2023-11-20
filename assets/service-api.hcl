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
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
Kind = "api-gateway"
Name = "api-gateway"

// Each listener configures a port which can be used to access the Consul cluster
Listeners = [
    {
        Port = 9090
        Name = "gw-tcp-listener"
        Protocol = "tcp"
        # TLS = {
        #     Certificates = [
        #         {
        #             Kind = "inline-certificate"
        #             Name = "my-certificate"
        #         }
        #     ]
        # }
    }
]
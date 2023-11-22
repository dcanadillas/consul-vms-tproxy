Kind = "api-gateway"
Name = "api-gateway"

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
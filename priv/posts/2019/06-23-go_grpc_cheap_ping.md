%{
  title: "Go gRPC Cheap ping",
  author: "Gabriel Garrido",
  description: "In this article we will explore gRPC with a cheap ping application, basically we will do a ping and measure the time it takes for the message to go to the server and back before...",
  tags: ~w(golang grpc),
  published: true,
}
---

![golang](/images/golang-grpc.png){:class="mx-auto"}

##### **Introduction**
In this article we will explore gRPC with a cheap ping application, basically we will do a ping and measure the time it takes for the message to go to the server and back before reporting it to the terminal. You can find the source code [here](https://github.com/kainlite/grpc-ping).

##### **Protobuf**
As you might already know gRPC serializes data using [protocol buffers](https://developers.google.com/protocol-buffers/), We are just going to create a [Unary RPC](https://grpc.io/docs/guides/concepts/) as follows.
```elixir
syntax = "proto3";

service PingService {
  rpc Ping (PingRequest) returns (PingResponse);
}

message PingRequest {
  string data = 1;
}

message PingResponse {
  string data = 1;
}

```
With this file in place we are defining a service that will be able to send a single `PingRequest` and get a single `PingResponse`, we have a `Data` field that goes back and forth in order to send some bytes over the wire (even that we don't really care about that, it could be important or crucial in a performance test).

##### **Generating the code**
In order to be able to use protobuf we need to generate the code for the app that we're writing in this case for golang the command would be this one:
```elixir
 protoc -I ping/ ping/ping.proto --go_out=plugins=grpc:ping

```
This will give us a definition of the service and the required structs to carry the data that we have defined as messages.

##### **Client**
The client does most of the work here, as you can see you can supply 2 arguments one to point to another host:port and the second to send a string of your liking, then it measures the time it takes to send and receive the message back and prints it to the screen with a similar line to what the actual `ping` command looks in linux.
```elixir
package main

import (
    "context"
    "log"
    "os"
    "time"

    pb "github.com/kainlite/grpc-ping/ping"
    "google.golang.org/grpc"
)

const (
    defaultAddress = "localhost:50000"
    defaultData    = "00"
)

func main() {
    data := defaultData
    address := defaultAddress
    if len(os.Args) > 2 {
        address = os.Args[1]
        data = os.Args[2]
    }

    conn, err := grpc.Dial(address, grpc.WithInsecure())
    if err != nil {
        log.Fatalf("did not connect: %v", err)
    }
    defer conn.Close()
    c := pb.NewPingServiceClient(conn)

    index := 0
    for {
        trip_time := time.Now()
        ctx, cancel := context.WithTimeout(context.Background(), time.Second)
        defer cancel()
        r, err := c.Ping(ctx, &pb.PingRequest{Data: data})
        if err != nil {
            log.Fatalf("could not connect to: %v", err)
        }

        log.Printf("%d characters roundtrip to (%s): seq=%d time=%s", len(r.Data), address, index, time.Since(trip_time))
        time.Sleep(1 * time.Second)
        index++
    }
}

```

##### **Server**
The server is a merely echo server since it will send back whatever you send to it and log it to the console, by default it will listen in port `50000`.
```elixir
package main

import (
    "context"
    "log"
    "net"

    pb "github.com/kainlite/grpc-ping/ping"
    "google.golang.org/grpc"
)

const (
    port = ":50000"
)

// server is used to implement ping.PingServer.
type server struct{}

// Ping implements ping.PingServer
func (s *server) Ping(ctx context.Context, in *pb.PingRequest) (*pb.PingResponse, error) {
    log.Printf("Received: %v", in.Data)
    return &pb.PingResponse{Data: "Data: " + in.Data}, nil
}

func main() {
    lis, err := net.Listen("tcp", port)
    if err != nil {
        log.Fatalf("failed to listen: %v", err)
    }
    s := grpc.NewServer()
    pb.RegisterPingServiceServer(s, &server{})
    if err := s.Serve(lis); err != nil {
        log.Fatalf("failed to serve: %v", err)
    }
}

```

##### **Testing it**
###### **Regular ping**
```elixir
$ ping localhost -c 4
PING localhost(localhost (::1)) 56 data bytes
64 bytes from localhost (::1): icmp_seq=1 ttl=64 time=0.145 ms
64 bytes from localhost (::1): icmp_seq=2 ttl=64 time=0.152 ms
64 bytes from localhost (::1): icmp_seq=3 ttl=64 time=0.154 ms
64 bytes from localhost (::1): icmp_seq=4 ttl=64 time=0.141 ms

--- localhost ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3144ms
rtt min/avg/max/mdev = 0.141/0.148/0.154/0.005 ms

```

###### **Client**
This is what we would see in the terminal while testing it.
```elixir
$ go run ping_client/main.go                
2019/06/23 18:01:02 8 characters roundtrip to (localhost:50000): seq=0 time=1.941841ms
2019/06/23 18:01:03 8 characters roundtrip to (localhost:50000): seq=1 time=420.992µs
2019/06/23 18:01:04 8 characters roundtrip to (localhost:50000): seq=2 time=401.115µs
2019/06/23 18:01:05 8 characters roundtrip to (localhost:50000): seq=3 time=428.467µs
2019/06/23 18:01:06 8 characters roundtrip to (localhost:50000): seq=4 time=374.057µs

```
As you can see the initial connection takes a bit more time but after that the roundtrip time is very consistent (of course our cheap ping doesn't cover errors, packet loss, etc).

###### **Server**
The server just echoes back and logs what received over the wire.
```elixir
$ go run ping_server/main.go                       
2019/06/23 18:01:02 Received: 00
2019/06/23 18:01:03 Received: 00
2019/06/23 18:01:04 Received: 00
2019/06/23 18:01:05 Received: 00
2019/06/23 18:01:06 Received: 00

```

##### **Closing notes**
As you can see gRPC is pretty fast and simplifies a lot everything that you need to do in order to have a highly efficient message system or communication between microservices for example, it's also easy to generate the boilerplate for whatever language you prefer and have a common interface that everyone has to agree on.

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

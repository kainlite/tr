%{
  title: "SSH Local Port Forward",
  author: "Gabriel Garrido",
  description: "SSH is a great tool not only to connect and interact with remote servers, in this article we will
  explore SSH Local port forward and what it means, we also will explore SSH Remote port...",
  tags: ~w(openssh linux networking),
  published: true,
  image: "openssh.png"
}
---

![openssh](/images/openssh.png){:class="mx-auto"}

##### **Introduction**
SSH is a great tool not only to connect and interact with remote servers, in this article we will explore SSH Local port forward and what it means, we also will explore [SSH Remote Port Forward](/blog/ssh_remote_port_forward) and [SSH Socks Proxy](/blog/ssh_socks_proxy) and how to use that functionality.
<br />

##### **Explanation**
Local port forward basically let's you forward one port from a remote machine to your local machine, for example you want to connect to a remote service from machine but just temporarily or there is a firewall that won't let you do it, let's say you want to connect to a mysql instance on the default port (3306).
<br />

##### **The command**
```elixir
ssh -Nn -L 3306:localhost:3306 user@example.com
```
<br />

Here we are forwarding localhost:3306 in the remote machine to localhost:3306, but you can specify another address in the network for example 172.16.16.200 and the command would look like this:

```elixir
ssh -Nn -L 3306:172.16.16.200:3306 user@example.com
```
This will give you access to the ip 172.16.16.200 and port 3306 in the remote network.
<br />

##### **The parameters and their meaning**
I extracted a portion of the meaning of parameter from the man page, but in a nutshell it means local port forward without a shell.
```elixir
-N Do not execute a remote command. This is useful for just forwarding ports.
-n Redirects stdin from /dev/null (actually, prevents reading from stdin). This must be used when ssh is run in the background.
-L Specifies that connections to the given TCP port or Unix socket on the local (client) host are to be forwarded to the given host and port, or Unix socket, on the remote side.
<br />
```

##### **Server configuration**
There is a configuration parameter that can change the behaviour of remote and local forwarded ports, that parameter is `AllowTcpForwarding`.
<br />

##### **AllowTcpForwarding**
By default this option is set to `yes`, you can restrict remote and local port forwarding by setting it to `no` or allow only local by setting it to `local`.
<br />

##### **Closing notes**
As you can see this option can be really handy to bypass firewalls for example or have a temporary port forward, also if you want to make this automatic and not so temporary you can check autossh. You can use nc (netcat) if you don't want to install anything to test the connections and the tunnels (nc -l -p PORT) in the server side and (nc HOST PORT) in the client.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />

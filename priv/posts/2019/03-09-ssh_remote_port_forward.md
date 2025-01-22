%{
  title: "SSH Remote Port Forward",
  author: "Gabriel Garrido",
  description: "SSH is a great tool not only to connect and interact with remote servers, in this article we will explore SSH Remote port forward and what it means, we also will explore ...",
  tags: ~w(linux openssh networking),
  published: true,
  image: "openssh.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
SSH is a great tool not only to connect and interact with remote servers, in this article we will explore SSH Remote port forward and what it means, we also will explore [SSH Local Port Forward](/blog/ssh_local_port_forward) and [SSH Socks Proxy](/blog/ssh_socks_proxy) and how to use that functionality.
<br />

##### **Explanation**
Remote port forward basically let's you forward one port from your machine to a remote machine, for example you want to connect to a local service from a remote server but just temporarily, let's say you want to connect to a mysql instance on the default port (3306).
<br />

**The command**
```elixir
ssh -Nn -R 3306:localhost:3306 user@example.com
```
<br />

**The parameters and their meaning**
I extracted a portion of the meaning of parameter from the man page, but in a nutshell it means remote port forward without a shell.
```elixir
-N Do not execute a remote command. This is useful for just forwarding ports.
-n Redirects stdin from /dev/null (actually, prevents reading from stdin). This must be used when ssh is run in the background.
-R Specifies that connections to the given TCP port or Unix socket on the remote (server) host are to be forwarded to the local side.
```
<br />

##### **Server configuration**
There are two configuration parameters that can change the behaviour of remote and local forwarded ports, those parameters are `GatewayPorts` and `AllowTcpForwarding`.
<br />

##### **GatewayPorts**
By default this option is `no` which means that only the remote computer will be able to connect to the forwarded port, you can set it to `yes` or `clientspecified` to allow other machines use that remote port-forward (handy and dangerous).
<br />

##### **AllowTcpForwarding**
By default this option is set to `yes`, you can restrict remote and local port forwarding by setting it to `no` or allow only local by setting it to `local`.
<br />

### **Closing notes**
As you can see this option can be really handy to bypass firewalls for example or have a temporary port forward, also if you want to make this automatic and not so temporary you can check autossh. You can use nc (netcat) if you don't want to install anything to test the connections and the tunnels (nc -l -p PORT) in the server side and (nc HOST PORT) in the client.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "SSH redireccion de puerto remoto",
  author: "Gabriel Garrido",
  description: "SSH no es solo sirve para conectarse a servidores u otras maquinas, tambien se puede usar para redirigir puertos...",
  tags: ~w(linux openssh networking),
  published: true,
  image: "openssh.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
SSH es una excelente herramienta no solo para conectarte e interactuar con servidores remotos. En este artículo vamos a explorar el reenvío de puertos remotos con SSH y qué significa. También exploraremos el [Reenvío de puertos locales con SSH](/blog/ssh_local_port_forward) y el [Proxy Socks con SSH](/blog/ssh_socks_proxy) y cómo usar esas funcionalidades.
<br />

##### **Explicación**
El reenvío de puertos remotos te permite redirigir un puerto desde tu máquina local hacia una máquina remota. Por ejemplo, si querés conectarte a un servicio local desde un servidor remoto pero solo temporalmente. Supongamos que querés conectarte a una instancia de MySQL en el puerto por defecto (3306).
<br />

**El comando**
```elixir
ssh -Nn -R 3306:localhost:3306 user@example.com
```
<br />

**Los parámetros y su significado**
Saqué una porción del significado de los parámetros de la página del manual, pero en resumen significa reenvío de puerto remoto sin ejecutar un shell.
```elixir
-N No ejecuta un comando remoto. Esto es útil solo para redirigir puertos.
-n Redirige stdin desde /dev/null (evita leer desde stdin). Esto debe usarse cuando SSH se ejecuta en segundo plano.
-R Especifica que las conexiones al puerto TCP o socket Unix en el host remoto (servidor) deben redirigirse hacia el lado local.
```
<br />

##### **Configuración del servidor**
Hay dos parámetros de configuración que pueden cambiar el comportamiento del reenvío de puertos locales y remotos. Estos parámetros son `GatewayPorts` y `AllowTcpForwarding`.
<br />

##### **GatewayPorts**
Por defecto, esta opción está configurada en `no`, lo que significa que solo la computadora remota podrá conectarse al puerto redirigido. Podés configurarlo en `yes` o `clientspecified` para permitir que otras máquinas usen ese puerto remoto redirigido (es útil, pero también puede ser peligroso).
<br />

##### **AllowTcpForwarding**
Por defecto, esta opción está configurada en `yes`. Podés restringir el reenvío de puertos locales y remotos configurándola en `no`, o permitir solo el reenvío local configurándola en `local`.
<br />

### **Notas finales**
Como podés ver, esta opción es muy útil para saltarse firewalls o crear un reenvío de puertos temporal. Si querés hacerlo automático y no tan temporal, podés revisar **autossh**. Para probar las conexiones y los túneles sin instalar nada adicional, podés usar **nc** (netcat): en el servidor ejecutás `nc -l -p PUERTO`, y en el cliente, `nc HOST PUERTO`.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />

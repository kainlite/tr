%{
  title: "SSH Local Port Forward",
  author: "Gabriel Garrido",
  description: "SSH is a great tool not only to connect and interact with remote servers, in this article we will
  explore SSH Local port forward and what it means, we also will explore SSH Remote port...",
  tags: ~w(openssh linux networking),
  published: true,
  image: "openssh.png",
  sponsored: false,
  video: "",
  lang: "en"
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
---lang---
%{
  title: "SSH redirigir puerto local",
  author: "Gabriel Garrido",
  description: "SSH no es solo sirve para conectarse a servidores u otras maquinas, tambien se puede usar para redirigir
  puertos entre otras cosas...",
  tags: ~w(openssh linux networking),
  published: true,
  image: "openssh.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![openssh](/images/openssh.png){:class="mx-auto"}

### **Introducción**
SSH es una excelente herramienta no solo para conectarte e interactuar con servidores remotos. En este artículo vamos a explorar el reenvío de puertos locales con SSH y qué significa. También exploraremos el [Reenvío de puertos remotos con SSH](/blog/ssh_remote_port_forward) y el [Proxy Socks con SSH](/blog/ssh_socks_proxy) y cómo usar estas funcionalidades.
<br />

### **Explicación**
El reenvío de puertos locales básicamente te permite redirigir un puerto de una máquina remota hacia tu máquina local. Por ejemplo, si querés conectarte a un servicio remoto desde tu máquina pero solo temporalmente o si hay un firewall que no te deja hacerlo. Supongamos que querés conectarte a una instancia de MySQL en el puerto por defecto (3306).
<br />

### **El comando**
```elixir
ssh -Nn -L 3306:localhost:3306 user@example.com
```
<br />

En este caso, estamos redirigiendo `localhost:3306` de la máquina remota a `localhost:3306` de tu máquina local, pero también podés especificar otra dirección de la red, por ejemplo 172.16.16.200, y el comando se vería así:

```elixir
ssh -Nn -L 3306:172.16.16.200:3306 user@example.com
```
Esto te dará acceso a la IP 172.16.16.200 y al puerto 3306 en la red remota.
<br />

### **Los parámetros y su significado**
Saqué una porción del significado de los parámetros de la página del manual, pero en resumen significa un reenvío de puerto local sin ejecutar un shell.
```elixir
-N No ejecuta un comando remoto. Esto es útil solo para redirigir puertos.
-n Redirige stdin desde /dev/null (en realidad, evita la lectura desde stdin). Debe usarse cuando SSH se ejecuta en segundo plano.
-L Especifica que las conexiones al puerto TCP o socket Unix en el host local (cliente) deben ser redirigidas al host y puerto dados, o socket Unix, en el lado remoto.
```
<br />

### **Configuración del servidor**
Hay un parámetro de configuración que puede cambiar el comportamiento del reenvío de puertos locales y remotos. Ese parámetro es `AllowTcpForwarding`.
<br />

### **AllowTcpForwarding**
Por defecto, esta opción está configurada en `yes`. Podés restringir el reenvío de puertos remotos y locales configurándola en `no`, o permitir solo el reenvío local configurándola en `local`.
<br />

### **Notas finales**
Como podés ver, esta opción puede ser muy útil para saltarse firewalls o tener un reenvío de puertos temporal. Si querés hacerlo automático y no tan temporal, podés revisar **autossh**. Para probar las conexiones y los túneles sin instalar nada adicional, podés usar **nc** (netcat): en el servidor ejecutás `nc -l -p PUERTO`, y en el cliente, `nc HOST PUERTO`.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

Además, podés revisar el código fuente y los cambios en el [código generado](https://github.com/kainlite/kainlite.github.io) y las [fuentes aquí](https://github.com/kainlite/blog)

<br />

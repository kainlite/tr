%{
  title: "SSH Socks Proxy",
  author: "Gabriel Garrido",
  description: "SSH is a great tool not only to connect and interact with remote servers, in this article we will
  explore SSH Socks proxy and what it means, we also will explore SSH remote proxy...",
  tags: ~w(linux openssh networking),
  published: true,
  image: "openssh.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
SSH is a great tool not only to connect and interact with remote servers, in this article we will explore SSH Socks proxy and what it means, we also will explore [SSH Remote Port Forward](/blog/ssh_remote_port_forward) and [SSH Local Port Forward](/blog/ssh_local_port_forward) and how to use that functionality.
<br />

##### **Explanation**
SOCKS is an Internet protocol that exchanges network packets between a client and server through a proxy server (Extracted from Wikipedia). So basically it allows our remote server to become a VPNey likey thingy using SSH, so let's see the different options of how and when to use it. But we will need to tell the application to use that SOCKS proxy, for example our browser or curl.
<br />

**The command**
```elixir
ssh -D 9999 -Nn ec2-user@54.210.37.203
```
<br />

For example I started a EC2 instance for this example and this is the output from curl:
```elixir
$ curl --socks4 localhost:9999 icanhazip.com
# OUTPUT:
# 54.210.37.203
```
<br />

##### **The parameters and their meaning**
I extracted a portion of the meaning of parameter from the man page, but in a nutshell it means dynamic port forward without a shell.
```elixir
-N Do not execute a remote command. This is useful for just forwarding ports.
-n Redirects stdin from /dev/null (actually, prevents reading from stdin). This must be used when ssh is run in the background.
-D Specifies a local “dynamic” application-level port forwarding.  This works by allocating a socket to listen to port on the local side, optionally bound to the specified bind_address.
```
<br />

##### **Closing notes**
As you can see this option can be really handy to have a temporary VPN or proxy, also if you want to make this automatic and not so temporary you can check autossh or any real VPN solution like OpenVPN. You can use this kind of proxy in any App that supports SOCKS, most browsers do for example.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "SSH como proxy Socks",
  author: "Gabriel Garrido",
  description: "En este articulo exploraremos como usar SSH como proxy Socks...",
  tags: ~w(linux openssh networking),
  published: true,
  image: "openssh.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
SSH es una excelente herramienta no solo para conectarte e interactuar con servidores remotos. En este artículo vamos a explorar el proxy SOCKS de SSH y qué significa. También veremos el [Reenvío de puertos remotos con SSH](/blog/ssh_remote_port_forward) y el [Reenvío de puertos locales con SSH](/blog/ssh_local_port_forward) y cómo usar esas funcionalidades.
<br />

##### **Explicación**
SOCKS es un protocolo de Internet que intercambia paquetes de red entre un cliente y un servidor a través de un servidor proxy (extraído de Wikipedia). Básicamente, permite que nuestro servidor remoto se convierta en algo similar a una VPN usando SSH. Veamos las distintas opciones de cómo y cuándo usarlo. Pero es importante mencionar que tendremos que configurar la aplicación para que use ese proxy SOCKS, por ejemplo, nuestro navegador o curl.
<br />

**El comando**
```elixir
ssh -D 9999 -Nn ec2-user@54.210.37.203
```
<br />

Por ejemplo, inicié una instancia EC2 para este ejemplo y este es el resultado de curl:
```elixir
$ curl --socks4 localhost:9999 icanhazip.com
# OUTPUT:
# 54.210.37.203
```
<br />

##### **Los parámetros y su significado**
Saqué una porción del significado de los parámetros de la página del manual, pero en resumen significa reenvío dinámico de puerto sin ejecutar un shell.
```elixir
-N No ejecuta un comando remoto. Esto es útil solo para redirigir puertos.
-n Redirige stdin desde /dev/null (evita leer desde stdin). Esto debe usarse cuando SSH se ejecuta en segundo plano.
-D Especifica un reenvío de puerto “dinámico” a nivel de aplicación. Funciona asignando un socket para escuchar en un puerto del lado local, opcionalmente enlazado a la dirección especificada (bind_address).
```
<br />

##### **Notas finales**
Como podés ver, esta opción es muy útil para crear una VPN o proxy temporal. Si querés hacerlo automático y no tan temporal, podés revisar **autossh** o una solución VPN más completa como **OpenVPN**. Podés usar este tipo de proxy en cualquier aplicación que soporte SOCKS; la mayoría de los navegadores, por ejemplo, lo soportan.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

Además, podés revisar el código fuente y los cambios en el [código generado](https://github.com/kainlite/kainlite.github.io) y las [fuentes aquí](https://github.com/kainlite/blog)

<br />

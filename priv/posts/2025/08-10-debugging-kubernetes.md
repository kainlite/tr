%{
  title: "Debugging Distroless Containers: When Your Container Has No Shell",
  author: "Gabriel Garrido",
  description: "We will see how to debug distroless containers in Kubernetes using kubectl debug and manual user creation...",
  tags: ~w(kubernetes debugging containers distroless),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will explore how to debug distroless containers in Kubernetes when your application container has no shell, no package manager, and basically no debugging tools whatsoever. If you've ever tried to `kubectl exec` into a distroless container only to be greeted with "executable file not found in $PATH: /bin/sh", you know the pain.

<br />

Distroless containers are amazing for security and size - they contain only your application and its runtime dependencies, nothing else. No shell, no package managers, no debugging tools. They're perfect for production... until something goes wrong and you need to poke around inside.

<br />

But fear not! Kubernetes has a solution: ephemeral containers via `kubectl debug`. We'll not only see how to use this feature, but also how to manually set up a user environment and access the main container's filesystem through the `/proc/1/root` trick.

<br />

##### **What are Distroless Containers?**
Before we dive into debugging, let's quickly understand what we're dealing with. Distroless containers, popularized by Google, contain only:

> * Your application binary
> * Runtime dependencies (libraries, certificates, timezone data)
> * A minimal user setup (usually just root or a dedicated user)

<br />

What they DON'T contain:
> * Package managers (apt, yum, apk)
> * Shells (bash, sh, zsh)
> * Debugging tools (ps, netstat, curl, wget)
> * Text editors (vi, nano)
> * Pretty much anything that makes debugging easy

<br />

This is fantastic for security (smaller attack surface) and performance (smaller images), but terrible when you need to debug a running container.

<br />

##### **The Problem**
Let's say you have a Go application running in a distroless container and it's behaving strangely. Your natural instinct is:

```elixir
kubectl exec -it my-pod -- /bin/sh
```

But you're greeted with:
```elixir
OCI runtime exec failed: exec failed: unable to start container process: 
exec: "/bin/sh": executable file not found in $PATH: unknown
```

<br />

Even trying different shells won't help:
```elixir
kubectl exec -it my-pod -- bash
kubectl exec -it my-pod -- /bin/bash
# Same error, different shell
```

<br />

So what now? This is where `kubectl debug` comes to the rescue.

<br />

##### **Enter kubectl debug**
Kubernetes 1.18+ introduced ephemeral containers, and `kubectl debug` makes them easy to use. Think of it as attaching a debugging sidecar to your running pod temporarily.

<br />

Here's the basic syntax:
```elixir
kubectl debug -it my-pod --image=ubuntu --target=my-container
```

<br />

This command:
- Creates an ephemeral container using the `ubuntu` image
- Attaches to it interactively (`-it`)
- Shares the process namespace with the target container

<br />

But there's a catch - even with this setup, you still can't directly access your application's filesystem. That's where the `/proc/1/root` magic comes in.

<br />

##### **The /proc/1/root Trick**
In Linux, `/proc/1/root` is a symbolic link to the root filesystem of process ID 1. When containers share a process namespace (which `kubectl debug` does by default), you can access the main container's filesystem through this path.

<br />

Here's the full debugging workflow:

<br />

##### **Step 1: Create the Debug Container**
```elixir
kubectl debug -it my-pod --image=ubuntu --target=my-container --share-processes
```

<br />

You'll be dropped into a shell in the Ubuntu container. The `--share-processes` flag ensures you can see all processes from both containers.

<br />

##### **Step 2: Verify Process Sharing**
```elixir
ps aux
```

You should see both your application process (PID 1) and the shell processes from the debug container. If your app is running as PID 1, you're good to go.

<br />

##### **Step 3: Access the Main Container's Filesystem**
```elixir
ls /proc/1/root/
```

This shows you the filesystem of your distroless container! You can now navigate and inspect files:

```elixir
# Check your application binary
ls -la /proc/1/root/app

# Look at configuration files
cat /proc/1/root/etc/ssl/certs/ca-certificates.crt

# Check environment variables
cat /proc/1/environ | tr '\0' '\n'

# Examine the working directory
ls -la /proc/1/root/app/
```

<br />

##### **Step 4: Creating a Proper User Environment**
Sometimes you might want to work more comfortably. Here's how to set up a proper user environment in your debug container:

```elixir
# Update package list and install useful tools
apt update && apt install -y curl wget netstat-nat procps tree

# Create a user (optional, but good practice)
useradd -m -s /bin/bash debuguser
usermod -aG sudo debuguser

# Switch to the new user
su - debuguser
```

<br />

Now you have a full debugging environment with all the tools you need, while still being able to access your distroless container's filesystem.

<br />

##### **Advanced Debugging Techniques**
Once you have access, here are some powerful debugging techniques:

<br />

**Network Debugging:**
```elixir
# Check what your app is listening on
netstat -tlnp

# Test connectivity from the debug container
curl http://localhost:8080/health

# Check DNS resolution
nslookup your-service
```

<br />

**File System Investigation:**
```elixir
# Check disk usage
du -sh /proc/1/root/*

# Find recently modified files
find /proc/1/root/ -type f -mtime -1

# Search for configuration files
find /proc/1/root/ -name "*.conf" -o -name "*.yaml" -o -name "*.json"
```

<br />

**Process Analysis:**
```elixir
# Check what files your app has open
lsof -p 1

# Monitor system calls (if strace is available)
strace -p 1 -f

# Check memory usage
cat /proc/1/status | grep -E "(VmSize|VmRSS|VmPeak)"
```

<br />

##### **Real-World Example**
Let me show you a complete example. Let's say you have a Go application in a distroless container that's failing health checks:

```elixir
# First, identify the problematic pod
kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
my-app-7d4b8c8f5-xyz42   1/1     Running   5          2h

# Create debug container
kubectl debug -it my-app-7d4b8c8f5-xyz42 --image=ubuntu --target=my-app

# Inside the debug container:
apt update && apt install -y curl procps

# Check if the app is responding
curl http://localhost:8080/health
# Connection refused - aha!

# Check what the app is actually listening on
netstat -tlnp
# Shows it's listening on 0.0.0.0:3000, not 8080

# Check the app's environment variables for clues
cat /proc/1/environ | tr '\0' '\n' | grep PORT
# PORT=3000

# Test the correct port
curl http://localhost:3000/health
# {"status": "ok"} - there's our problem!
```

The issue was a misconfigured health check endpoint - the service was configured to check port 8080, but the app was listening on 3000.

<br />

##### **When kubectl debug Isn't Available**
If you're running an older Kubernetes version (< 1.18) or your cluster doesn't support ephemeral containers, you have a few alternatives:

<br />

**Option 1: Add a debug sidecar to your pod spec**
```elixir
apiVersion: v1
kind: Pod
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    image: gcr.io/distroless/java:11
    # your app config
  - name: debug
    image: ubuntu
    command: ["/bin/sleep", "infinity"]
    stdin: true
    tty: true
```

<br />

**Option 2: Use kubectl cp to get files out**
```elixir
# Copy files from the container to investigate locally
kubectl cp my-pod:/app/config.json ./config.json
kubectl cp my-pod:/var/log/ ./logs/
```

<br />

##### **Troubleshooting Common Issues**

**Debug container can't see main container processes:**
Make sure you're using `--share-processes` or that `shareProcessNamespace: true` is set in your pod spec.

<br />

**Permission denied accessing /proc/1/root:**
This can happen if your debug container doesn't have sufficient privileges. Try:
```elixir
ls -hal /prot/1
```
To determine the UID/GID and create an user with these values to be able to read/write.

<br />

**Main container isn't PID 1:**
If your app isn't running as PID 1, find the correct process:
```elixir
ps aux | grep your-app-name
# Use the correct PID instead of 1
ls /proc/PID/root/
```

<br />

##### **Security Considerations**
While `kubectl debug` is incredibly useful, keep these security considerations in mind:

> * Debug containers can access sensitive information from the main container
> * They run with the same service account permissions
> * Logs from debug containers might contain sensitive data
> * Always clean up debug containers when done (they're ephemeral by default)

<br />

##### **Best Practices**
Here are some best practices I've learned over the years:

> * **Use minimal debug images**: Start with alpine or ubuntu, add tools as needed
> * **Document your debugging process**: Save useful commands for your team
> * **Create debugging runbooks**: Common issues and their investigation steps
> * **Use labels**: Tag your debug containers for easy identification
> * **Set resource limits**: Debug containers can consume cluster resources too

<br />

##### **Creating a Debug Container Template**
You might want to create a pre-configured debug image for your team:

```elixir
FROM ubuntu:22.04

RUN apt update && apt install -y \
    curl \
    wget \
    netcat \
    netstat-nat \
    procps \
    strace \
    tcpdump \
    tree \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Add any custom debugging tools your team needs
COPY debug-scripts/ /usr/local/bin/

CMD ["/bin/bash"]
```

<br />

Build and push this to your registry, then use it for debugging:
```elixir
kubectl debug -it my-pod --image=your-registry/debug-toolkit:latest
```

<br />

##### **Conclusion**
Debugging distroless containers doesn't have to be a nightmare. With `kubectl debug` and the `/proc/1/root` technique, you can investigate issues in even the most minimal containers. The key is understanding that you're not trying to add tools to the distroless container - you're bringing your own toolbox and accessing the container's filesystem from the outside.

<br />

This approach gives you the security benefits of distroless containers in production while maintaining the ability to debug when things go wrong. It's the best of both worlds - secure, minimal containers with full debugging capabilities when you need them.

<br />

Remember, the goal isn't to avoid issues entirely (though that would be nice), but to be able to quickly identify and resolve them when they inevitably occur. With these techniques in your toolkit, distroless containers become much less scary to debug.

<br />

Hope you found this useful and enjoyed reading it, until next time!

---lang---
%{
  title: "Debugeando Contenedores Distroless: Cuando Tu Contenedor No Tiene Shell",
  author: "Gabriel Garrido",
  description: "Vamos a ver como debugear contenedores distroless en Kubernetes usando kubectl debug y creación manual de usuarios...",
  tags: ~w(kubernetes debugging containers distroless),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a explorar cómo debugear contenedores distroless en Kubernetes cuando tu contenedor de aplicación no tiene shell, no tiene package manager, y básicamente no tiene herramientas de debugging. Si alguna vez intentaste hacer `kubectl exec` en un contenedor distroless solo para recibir "executable file not found in $PATH: /bin/sh", conocés el dolor.

<br />

Los contenedores distroless son increíbles para seguridad y tamaño - contienen solo tu aplicación y sus dependencias de runtime, nada más. Sin shell, sin package managers, sin herramientas de debugging. Son perfectos para producción... hasta que algo sale mal y necesitás curiosear adentro.

<br />

¡Pero no te preocupes! Kubernetes tiene una solución: contenedores efímeros via `kubectl debug`. No solo vamos a ver cómo usar esta característica, sino también cómo configurar manualmente un entorno de usuario y acceder al filesystem del contenedor principal a través del truco `/proc/1/root`.

<br />

##### **¿Qué son los Contenedores Distroless?**
Antes de meternos en el debugging, entendamos rápidamente con qué estamos lidiando. Los contenedores distroless, popularizados por Google, contienen solo:

> * Tu binario de aplicación
> * Dependencias de runtime (librerías, certificados, datos de zona horaria)
> * Una configuración mínima de usuario (usualmente solo root o un usuario dedicado)

<br />

Lo que NO contienen:
> * Package managers (apt, yum, apk)
> * Shells (bash, sh, zsh)
> * Herramientas de debugging (ps, netstat, curl, wget)
> * Editores de texto (vi, nano)
> * Prácticamente cualquier cosa que haga el debugging fácil

<br />

Esto es fantástico para seguridad (menor superficie de ataque) y performance (imágenes más pequeñas), pero terrible cuando necesitás debugear un contenedor corriendo.

<br />

##### **El Problema**
Digamos que tenés una aplicación Go corriendo en un contenedor distroless y se está comportando extraño. Tu instinto natural es:

```elixir
kubectl exec -it mi-pod -- /bin/sh
```

Pero te recibe con:
```elixir
OCI runtime exec failed: exec failed: unable to start container process: 
exec: "/bin/sh": executable file not found in $PATH: unknown
```

<br />

Incluso intentar diferentes shells no ayuda:
```elixir
kubectl exec -it mi-pod -- bash
kubectl exec -it mi-pod -- /bin/bash
# Mismo error, diferente shell
```

<br />

¿Y ahora qué? Acá es donde `kubectl debug` viene al rescate.

<br />

##### **Entra kubectl debug**
Kubernetes 1.18+ introdujo contenedores efímeros, y `kubectl debug` los hace fáciles de usar. Pensalo como adjuntar un sidecar de debugging a tu pod corriendo temporalmente.

<br />

Acá está la sintaxis básica:
```elixir
kubectl debug -it mi-pod --image=ubuntu --target=mi-contenedor
```

<br />

Este comando:
- Crea un contenedor efímero usando la imagen `ubuntu`
- Se adjunta a él interactivamente (`-it`)
- Comparte el namespace de procesos con el contenedor objetivo

<br />

Pero hay una trampa - incluso con esta configuración, todavía no podés acceder directamente al filesystem de tu aplicación. Ahí es donde entra la magia de `/proc/1/root`.

<br />

##### **El Truco /proc/1/root**
En Linux, `/proc/1/root` es un enlace simbólico al filesystem raíz del proceso ID 1. Cuando los contenedores comparten un namespace de procesos (que `kubectl debug` hace por defecto), podés acceder al filesystem del contenedor principal a través de esta ruta.

<br />

Acá está el flujo completo de debugging:

<br />

##### **Paso 1: Crear el Contenedor de Debug**
```elixir
kubectl debug -it mi-pod --image=ubuntu --target=mi-contenedor --share-processes
```

<br />

Vas a caer en una shell en el contenedor Ubuntu. La flag `--share-processes` asegura que puedas ver todos los procesos de ambos contenedores.

<br />

##### **Paso 2: Verificar el Compartir de Procesos**
```elixir
ps aux
```

Deberías ver tanto tu proceso de aplicación (PID 1) como los procesos de shell del contenedor de debug. Si tu app está corriendo como PID 1, estás listo.

<br />

##### **Paso 3: Acceder al Filesystem del Contenedor Principal**
```elixir
ls /proc/1/root/
```

¡Esto te muestra el filesystem de tu contenedor distroless! Ahora podés navegar e inspeccionar archivos:

```elixir
# Verificar tu binario de aplicación
ls -la /proc/1/root/app

# Mirar archivos de configuración
cat /proc/1/root/etc/ssl/certs/ca-certificates.crt

# Verificar variables de entorno
cat /proc/1/environ | tr '\0' '\n'

# Examinar el directorio de trabajo
ls -la /proc/1/root/workspace/
```

<br />

##### **Paso 4: Crear un Entorno de Usuario Apropiado**
A veces podrías querer trabajar más cómodamente. Acá está cómo configurar un entorno de usuario apropiado en tu contenedor de debug:

```elixir
# Actualizar lista de paquetes e instalar herramientas útiles
apt update && apt install -y curl wget netstat-nat procps tree

# Crear un usuario (opcional, pero buena práctica)
useradd -m -s /bin/bash debuguser
usermod -aG sudo debuguser

# Cambiar al nuevo usuario
su - debuguser
```

<br />

Ahora tenés un entorno de debugging completo con todas las herramientas que necesitás, mientras seguís pudiendo acceder al filesystem de tu contenedor distroless.

<br />

##### **Técnicas de Debugging Avanzadas**
Una vez que tenés acceso, acá hay algunas técnicas de debugging poderosas:

<br />

**Debugging de Red:**
```elixir
# Verificar en qué está escuchando tu app
netstat -tlnp

# Probar conectividad desde el contenedor de debug
curl http://localhost:8080/health

# Verificar resolución DNS
nslookup tu-servicio
```

<br />

**Investigación del Sistema de Archivos:**
```elixir
# Verificar uso de disco
du -sh /proc/1/root/*

# Encontrar archivos modificados recientemente
find /proc/1/root/ -type f -mtime -1

# Buscar archivos de configuración
find /proc/1/root/ -name "*.conf" -o -name "*.yaml" -o -name "*.json"
```

<br />

**Análisis de Procesos:**
```elixir
# Verificar qué archivos tiene abiertos tu app
lsof -p 1

# Monitorear system calls (si strace está disponible)
strace -p 1 -f

# Verificar uso de memoria
cat /proc/1/status | grep -E "(VmSize|VmRSS|VmPeak)"
```

<br />

##### **Ejemplo del Mundo Real**
Te muestro un ejemplo completo. Digamos que tenés una aplicación Go en un contenedor distroless que está fallando los health checks:

```elixir
# Primero, identificar el pod problemático
kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
mi-app-7d4b8c8f5-xyz42   1/1     Running   5          2h

# Crear contenedor de debug
kubectl debug -it mi-app-7d4b8c8f5-xyz42 --image=ubuntu --target=mi-app

# Dentro del contenedor de debug:
apt update && apt install -y curl procps

# Verificar si la app está respondiendo
curl http://localhost:8080/health
# Connection refused - ¡ajá!

# Verificar en qué está escuchando realmente la app
netstat -tlnp
# Muestra que está escuchando en 0.0.0.0:3000, no 8080

# Verificar las variables de entorno de la app para pistas
cat /proc/1/environ | tr '\0' '\n' | grep PORT
# PORT=3000

# Probar el puerto correcto
curl http://localhost:3000/health
# {"status": "ok"} - ¡ahí está nuestro problema!
```

El problema era un endpoint de health check mal configurado - el servicio estaba configurado para verificar el puerto 8080, pero la app estaba escuchando en 3000.

<br />

##### **Cuando kubectl debug No Está Disponible**
Si estás corriendo una versión anterior de Kubernetes (< 1.18) o tu cluster no soporta contenedores efímeros, tenés algunas alternativas:

<br />

**Opción 1: Agregar un sidecar de debug a tu spec de pod**
```elixir
apiVersion: v1
kind: Pod
spec:
  shareProcessNamespace: true
  containers:
  - name: app
    image: gcr.io/distroless/java:11
    # configuración de tu app
  - name: debug
    image: ubuntu
    command: ["/bin/sleep", "infinity"]
    stdin: true
    tty: true
```

<br />

**Opción 2: Usar kubectl cp para sacar archivos**
```elixir
# Copiar archivos del contenedor para investigar localmente
kubectl cp mi-pod:/app/config.json ./config.json
kubectl cp mi-pod:/var/log/ ./logs/
```

<br />

##### **Debugeando Problemas Comunes**

**El contenedor de debug no puede ver los procesos del contenedor principal:**
Asegurate de usar `--share-processes` o que `shareProcessNamespace: true` esté configurado en tu spec de pod.

<br />

**Permiso denegado accediendo /proc/1/root:**
Esto puede pasar si tu contenedor de debug no tiene privilegios suficientes. Probá:
```elixir
ls -hal /proc/1
```
Para determinar que UID/GID y luego crea un usuario con esos valores para poder leer/escribir.

<br />

**El contenedor principal no es PID 1:**
Si tu app no está corriendo como PID 1, encontrá el proceso correcto:
```elixir
ps aux | grep nombre-de-tu-app
# Usar el PID correcto en lugar de 1
ls /proc/PID/root/
```

<br />

##### **Consideraciones de Seguridad**
Mientras que `kubectl debug` es increíblemente útil, mantené estas consideraciones de seguridad en mente:

> * Los contenedores de debug pueden acceder información sensible del contenedor principal
> * Corren con los mismos permisos de service account
> * Los logs de contenedores de debug podrían contener datos sensibles
> * Siempre limpiá los contenedores de debug cuando termines (son efímeros por defecto)

<br />

##### **Mejores Prácticas**
Acá hay algunas mejores prácticas que aprendí a lo largo de los años:

> * **Usar imágenes de debug mínimas**: Empezar con alpine o ubuntu, agregar herramientas según necesites
> * **Documentar tu proceso de debugging**: Guardar comandos útiles para tu equipo
> * **Crear runbooks de debugging**: Problemas comunes y sus pasos de investigación
> * **Usar labels**: Etiquetar tus contenedores de debug para fácil identificación
> * **Configurar límites de recursos**: Los contenedores de debug también pueden consumir recursos del cluster

<br />

##### **Crear un Template de Contenedor de Debug**
Podrías querer crear una imagen de debug preconfigurada para tu equipo:

```elixir
FROM ubuntu:22.04

RUN apt update && apt install -y \
    curl \
    wget \
    netcat \
    netstat-nat \
    procps \
    strace \
    tcpdump \
    tree \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Agregar cualquier herramienta de debugging personalizada que tu equipo necesite
COPY debug-scripts/ /usr/local/bin/

CMD ["/bin/bash"]
```

<br />

Construir y pushear esto a tu registry, después usarlo para debugging:
```elixir
kubectl debug -it mi-pod --image=tu-registry/debug-toolkit:latest
```

<br />

##### **Conclusión**
Debugear contenedores distroless no tiene que ser una pesadilla. Con `kubectl debug` y la técnica `/proc/1/root`, podés investigar problemas en incluso los contenedores más mínimos. La clave es entender que no estás tratando de agregar herramientas al contenedor distroless - estás trayendo tu propia caja de herramientas y accediendo al filesystem del contenedor desde afuera.

<br />

Este enfoque te da los beneficios de seguridad de los contenedores distroless en producción mientras mantenés la habilidad de debugear cuando las cosas salen mal. Es lo mejor de ambos mundos - contenedores seguros y mínimos con capacidades completas de debugging cuando las necesitás.

<br />

Recordá, el objetivo no es evitar problemas completamente (aunque sería lindo), sino poder identificar y resolverlos rápidamente cuando inevitablemente ocurren. Con estas técnicas en tu toolkit, los contenedores distroless se vuelven mucho menos aterradores de debugear.

<br />

¡Espero que te haya sido útil y hayas disfrutado leyéndolo, hasta la próxima!


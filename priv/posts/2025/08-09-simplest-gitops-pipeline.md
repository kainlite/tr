%{
  title: "The Simplest GitOps Implementation That Actually Works",
  author: "Gabriel Garrido",
  description: "Let's build the most minimal GitOps setup that you can actually use in production...",
  tags: ~w(gitops cicd github-actions kubernetes),
  published: true,
  image: "gitops.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will strip GitOps down to its bare essentials and build the simplest implementation that actually works. No fancy operators, minimal tooling - just Git, GitHub Actions, and a sprinkle of automation magic.

<br />

After exploring different GitOps approaches in my [previous article](/blog/lets-talk-gitops), I realized that sometimes we overthink things. Sometimes, all you need is a simple, reliable pipeline that gets the job done. Let's build exactly that, using a real example from my [tools repository](https://github.com/kainlite/tools).

<br />

The goal here is simple:

> * **One repository** for your application code
> * **One repository** for your Kubernetes manifests  
> * **One workflow** that connects them together
> * **Zero additional infrastructure** beyond what you already have

<br />

Just pure, simple GitOps that you can understand, debug, and maintain without a PhD in cloud-native technologies.

<br />

#### **What we're building**
We're going to implement a push-based GitOps workflow that:
1. Builds and tests your Go application
2. Creates a container image with proper versioning
3. Pushes it to GitHub Container Registry (free with GitHub!)
4. Updates your Kubernetes manifests automatically
5. Adds security scanning because, well, we're not cowboys

<br />

The entire setup requires just two repositories and one GitHub Actions workflow:
- **Application repository**: [github.com/kainlite/tools](https://github.com/kainlite/tools) - where your Go code lives
- **Manifests repository**: [github.com/kainlite/tools-manifests](https://github.com/kainlite/tools-manifests) - where your Kubernetes manifests live

<br />

For the deployment part, I'm using ArgoCD to watch the manifests repository and sync changes to the cluster, but you could just as easily apply the manifests manually or use a simple CronJob. The beauty is in the simplicity of the pipeline itself.

<br />

##### **The Application Repository**
First, let's talk about the application repository. This is where your code lives, and where developers spend most of their time. The only GitOps-specific thing here is the CI/CD workflow.

<br />

Here's what happens when you push code:

```elixir
name: CI/CD Pipeline

on:
  push:
    branches: [ master ]
    tags: [ 'v*' ]
```

<br />

Simple trigger - push to master or create a tag, and the magic begins. No webhooks to configure, no external services to integrate. GitHub handles everything.

<br />

##### **Step 1: Testing (Because We're Professionals)**
```elixir
test:
  runs-on: ubuntu-latest
  steps:
  - uses: actions/checkout@v4
  
  - name: Set up Go
    uses: actions/setup-go@v4
    with:
      go-version: '1.24'
  
  - name: Run tests
    run: go test -v ./...
  
  - name: Run golangci-lint
    uses: golangci/golangci-lint-action@v8
    with:
      version: latest
```

<br />

Nothing fancy here. Check out the code, set up Go, run the tests, and lint the code. If tests fail or the linter complains, nothing else happens. This is your first quality gate, and it's non-negotiable.

<br />

##### **Step 2: Build and Push the Container**
Here's where things get interesting. We're using GitHub Container Registry (ghcr.io) because it's free, integrated, and just works:

```elixir
build-and-push:
  needs: test
  runs-on: ubuntu-latest
  
  permissions:
    contents: read
    packages: write

  steps:
  - name: Log in to Container Registry
    uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}
```

<br />

Notice something beautiful here? We're using `GITHUB_TOKEN` for the registry, no need to create and manage registry credentials. GitHub provides this token automatically with just the right permissions. One less secret to rotate, one less thing to worry about.

<br />

The image tagging strategy is where the magic happens:

```elixir
- name: Extract metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    tags: |
      type=sha,prefix=,suffix=,format=short
      type=ref,event=branch
      type=raw,value=latest,enable={{is_default_branch}}
```

<br />

We tag images with the commit SHA. Why? Because SHAs are immutable, unique, and tell you exactly what code is running in production. No more "latest" nightmares, no more version conflicts.

<br />

##### **Step 3: Security Scanning**
Before we deploy anything, let's make sure we're not shipping known vulnerabilities:

```elixir
security-scan:
  needs: build-and-push
  runs-on: ubuntu-latest
  
  steps:
  - name: Run Trivy vulnerability scanner
    uses: aquasecurity/trivy-action@master
    with:
      image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
      format: 'sarif'
      output: 'trivy-results.sarif'
```

<br />

Trivy scans our image for known vulnerabilities and reports them directly to GitHub's Security tab. If critical vulnerabilities are found, you'll know immediately. No external dashboards, no additional logins - everything stays in GitHub.

<br />

##### **Step 4: The GitOps Magic - Updating Manifests**
This is where GitOps actually happens. After our image is built and scanned, we update the manifest repository:

```elixir
update-manifests:
  needs: [build-and-push, security-scan]
  runs-on: ubuntu-latest
  
  steps:
  - name: Checkout manifest repository
    uses: actions/checkout@v4
    with:
      repository: kainlite/tools-manifests
      token: ${{ secrets.MANIFEST_REPO_TOKEN }}
      path: manifests

  - name: Update deployment image
    working-directory: manifests
    run: |
      yq eval '.spec.template.spec.containers[0].image = "ghcr.io/kainlite/tools:${{ github.sha }}"' \
        -i 02-deployment.yaml
      
  - name: Commit and push changes
    working-directory: manifests
    run: |
      git config --local user.email "action@github.com"
      git config --local user.name "GitHub Action"
      
      git add 02-deployment.yaml
      git commit -m "Update image to sha-${{ github.sha }} from ${{ github.repository }}"
      git push
```

<br />

This is beautiful in its simplicity. We check out the manifest repo, update the image tag using `yq`, commit the change, and push. That's it. Your manifests now reflect the exact version that was just built. Note that I'm using Kustomize in my setup, but the principle remains the same - update the image reference, commit, push.

<br />

##### **The Manifest Repository**
The manifest repository is even simpler. It contains your Kubernetes YAML files and... that's it. No scripts, no pipelines, just declarative configuration:

```elixir
# 02-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tools
  namespace: tools
spec:
  template:
    spec:
      containers:
      - name: tools
        image: ghcr.io/kainlite/tools:968faeda187b88f51dd07635301839cee38754f3
        # This SHA gets updated automatically by CI
        imagePullPolicy: Always
        ports:
        - containerPort: 3000
```

<br />

If you're using ArgoCD like I am, you'd also have an Application spec:

```elixir
# 01-appspec.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tools
  namespace: tools
spec:
  source:
    repoURL: https://github.com/kainlite/tools-manifests
    targetRevision: master
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: tools
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

<br />

Every change to this repository is tracked in Git. You can see who deployed what, when, and why. Need to rollback? Just revert the commit. Need to see what's running in production? Look at the main branch. The SHA in the image tag tells you exactly which commit is deployed.

<br />

##### **Setting It Up**
Ready to implement this? Here's your checklist:

<br />

**1. Create a Personal Access Token**
```elixir
# Go to GitHub Settings > Developer settings > Personal access tokens
# Create a token with 'repo' scope for the manifest repository
# Save it as MANIFEST_REPO_TOKEN in your app repo's secrets
```

<br />

**2. Create Your Manifest Repository**
```elixir
mkdir k8s-manifests
cd k8s-manifests
git init

# Add your Kubernetes YAML files
cp /path/to/your/*.yaml .

git add .
git commit -m "Initial manifests"
git push
```

<br />

**3. Add the Workflow**
Copy the workflow to `.github/workflows/ci.yaml` in your application repository. Update the repository names and you're done.

<br />

**4. Deploy to Your Cluster**
Now, you have a few options:

**Option A: Using ArgoCD (what I use)**
If you have ArgoCD installed, just apply the Application spec and it will handle everything:
```elixir
kubectl apply -f https://raw.githubusercontent.com/kainlite/tools-manifests/main/01-appspec.yaml
```

ArgoCD will then watch the repository and automatically sync changes. Done.

<br />

**Option B: Manual sync (simplest)**
```elixir
kubectl apply -f https://raw.githubusercontent.com/kainlite/tools-manifests/main/02-deployment.yaml
```

<br />

**Option C: Automated sync without ArgoCD**
Set up a simple CronJob in your cluster that pulls and applies changes:
```elixir
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitops-sync
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              kubectl apply -f https://raw.githubusercontent.com/kainlite/tools-manifests/main/
```

<br />

That's it. Every 5 minutes, your cluster checks for changes and applies them. No operators needed if you don't want them.

<br />

##### **Why This Works**
This approach might seem too simple, but that's exactly why it works:

> * **No learning curve**: If you know Git and basic CI/CD, you're ready
> * **Debuggable**: When something breaks, you can see exactly where and why
> * **Portable**: Works with any Kubernetes cluster, anywhere
> * **Auditable**: Every change is in Git with full history
> * **Free**: Uses only GitHub's free tier features
> * **Secure**: Minimal attack surface, standard GitHub security

<br />

##### **When to Use This**
This setup is perfect for:
- Small to medium teams getting started with GitOps
- Projects where simplicity trumps features  
- Teams that want to understand their entire pipeline
- Situations where you can't install additional tools in the cluster

<br />

It's probably not ideal if you need:
- Multi-cluster deployments
- Complex rollout strategies (canary, blue-green)
- Automatic rollback on metrics
- Multi-tenancy with strict RBAC

<br />

But you know what? You can always add those features later. Start simple, understand the basics, then add complexity only when you actually need it.

<br />

##### **Common Pitfalls and Solutions**

**Image not updating?**
Check that your image pull policy isn't set to `IfNotPresent` with a tag that doesn't change. Using SHAs solves this automatically.

<br />

**Manifest repo token expired?**
Use GitHub's fine-grained personal access tokens with longer expiration dates, or better yet, use a GitHub App for production.

<br />

**Need to rollback quickly?**
```elixir
git revert HEAD
git push
# Wait for sync, or manually apply
```

<br />

##### **Conclusion**
GitOps doesn't have to be complicated. This simple setup gives you 90% of the benefits with 10% of the complexity. You get version control, automated deployments, security scanning, and full auditability with just one GitHub Actions workflow.

<br />

Start here, get comfortable with the concepts, and then explore more advanced tools like ArgoCD or Flux when you actually need their features. Remember, the best GitOps implementation is the one your team can understand and maintain.

<br />

Sometimes, the simplest solution is the best solution. And in this case, simple doesn't mean amateur - it means focused, maintainable, and production-ready.

<br />

Hope you found this useful and enjoyed reading it, until next time!

---lang---
%{
  title: "La Implementación de GitOps Más Simple Que Realmente Funciona",
  author: "Gabriel Garrido",
  description: "Construyamos la configuración de GitOps más mínima que puedas usar en producción...",
  tags: ~w(gitops cicd github-actions kubernetes),
  published: true,
  image: "gitops.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a reducir GitOps a sus elementos esenciales y construir la implementación más simple que realmente funciona. Sin operadores sofisticados, sin herramientas complejas - solo Git, GitHub Actions y un poco de magia de automatización.

<br />

Después de explorar diferentes enfoques de GitOps en mi [artículo anterior](/blog/lets-talk-gitops), me di cuenta de que a veces pensamos demasiado las cosas. A veces, todo lo que necesitás es un pipeline simple y confiable que haga el trabajo. Construyamos exactamente eso.

<br />

El objetivo acá es simple:

> * **Un repositorio** para tu código de aplicación
> * **Un repositorio** para tus manifiestos de Kubernetes
> * **Un workflow** que los conecte
> * **Cero infraestructura adicional** más allá de lo que ya tenés

<br />

Solo GitOps puro y simple que podés entender, depurar y mantener sin un doctorado en tecnologías cloud-native.

<br />

#### **Lo que vamos a construir**
Vamos a implementar un flujo de trabajo GitOps basado en push que:
1. Construye y prueba tu aplicación
2. Crea una imagen de contenedor con versionado apropiado
3. La pushea a GitHub Container Registry (¡gratis con GitHub!)
4. Actualiza tus manifiestos de Kubernetes automáticamente
5. Agrega escaneo de seguridad porque, bueno, no somos cowboys

<br />

Toda la configuración requiere solo dos repositorios y un workflow de GitHub Actions. Eso es todo. Sin servicios adicionales, sin facturas mensuales, sin configuraciones complejas.

<br />

##### **El Repositorio de la Aplicación**
Primero, hablemos del repositorio de la aplicación. Acá es donde vive tu código, y donde los desarrolladores pasan la mayor parte del tiempo. Lo único específico de GitOps acá es el workflow de CI/CD.

<br />

Esto es lo que pasa cuando pusheás código:

```elixir
name: CI/CD Pipeline

on:
  push:
    branches: [ master ]
    tags: [ 'v*' ]
```

<br />

Disparador simple - push a master o creá un tag, y la magia comienza. Sin webhooks para configurar, sin servicios externos para integrar. GitHub maneja todo.

<br />

##### **Paso 1: Testing (Porque Somos Profesionales)**
```elixir
test:
  runs-on: ubuntu-latest
  steps:
  - uses: actions/checkout@v4
  
  - name: Set up Go
    uses: actions/setup-go@v4
    with:
      go-version: '1.24'
  
  - name: Run tests
    run: go test -v ./...
```

<br />

Nada sofisticado acá. Checkout del código, configurar el entorno, ejecutar las pruebas. Si las pruebas fallan, nada más sucede. Esta es tu primera puerta de calidad, y no es negociable.

<br />

##### **Paso 2: Construir y Pushear el Contenedor**
Acá es donde las cosas se ponen interesantes. Estamos usando GitHub Container Registry (ghcr.io) porque es gratis, está integrado y simplemente funciona:

```elixir
build-and-push:
  needs: test
  runs-on: ubuntu-latest
  
  permissions:
    contents: read
    packages: write

  steps:
  - name: Log in to Container Registry
    uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}
```

<br />

Estamos usando `GITHUB_TOKEN` para el registry de github, no necesitás crear y gestionar credenciales del registro. GitHub proporciona este token automáticamente con los permisos justos. Un secreto menos para rotar, una cosa menos de qué preocuparse.

<br />

La estrategia de etiquetado de imágenes es donde ocurre la magia:

```elixir
- name: Extract metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    tags: |
      type=sha,prefix=,suffix=,format=short
      type=ref,event=branch
      type=raw,value=latest,enable={{is_default_branch}}
```

<br />

Etiquetamos las imágenes con el SHA del commit. ¿Por qué? Porque los SHAs son inmutables, únicos y te dicen exactamente qué código está corriendo en producción. No más pesadillas con "latest", no más conflictos de versiones.

<br />

##### **Paso 3: Escaneo de Seguridad**
Antes de desplegar cualquier cosa, asegurémonos de que no estamos enviando vulnerabilidades:

```elixir
security-scan:
  needs: build-and-push
  runs-on: ubuntu-latest
  
  steps:
  - name: Run Trivy vulnerability scanner
    uses: aquasecurity/trivy-action@master
    with:
      image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
      format: 'sarif'
      output: 'trivy-results.sarif'
```

<br />

Trivy escanea nuestra imagen en busca de vulnerabilidades conocidas y las reporta directamente a la pestaña de Seguridad de GitHub. Si se encuentran vulnerabilidades críticas, lo sabrás inmediatamente. Sin dashboards externos, sin logins adicionales - todo permanece en GitHub.

<br />

##### **Paso 4: La Magia de GitOps - Actualizando Manifiestos**
Acá es donde GitOps realmente sucede. Después de que nuestra imagen está construida y escaneada, actualizamos el repositorio de manifiestos:

```elixir
update-manifests:
  needs: [build-and-push, security-scan]
  runs-on: ubuntu-latest
  
  steps:
  - name: Checkout manifest repository
    uses: actions/checkout@v4
    with:
      repository: tu-org/tus-manifiestos
      token: ${{ secrets.MANIFEST_REPO_TOKEN }}
      path: manifests

  - name: Update deployment image
    working-directory: manifests
    run: |
      yq eval '.spec.template.spec.containers[0].image = "ghcr.io/${{ github.repository }}:${{ github.sha }}"' \
        -i deployment.yaml
      
  - name: Commit and push changes
    working-directory: manifests
    run: |
      git config --local user.email "action@github.com"
      git config --local user.name "GitHub Action"
      
      git add deployment.yaml
      git commit -m "Update image to ${{ github.sha }}"
      git push
```

<br />

Esto es hermoso en su simplicidad. Hacemos checkout del repo de manifiestos, actualizamos el tag de la imagen usando `yq`, commiteamos el cambio y pusheamos. Eso es todo. Tus manifiestos ahora reflejan la versión exacta que se acaba de construir.

<br />

##### **El Repositorio de Manifiestos**
El repositorio de manifiestos es aún más simple. Contiene tus archivos YAML de Kubernetes y... eso es todo. Sin scripts, sin pipelines, solo configuración declarativa:

```elixir
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: ghcr.io/tu-org/tu-app:abc123f
        # Este SHA se actualiza automáticamente por CI
```

<br />

Cada cambio en este repositorio está rastreado en Git. Podés ver quién desplegó qué, cuándo y por qué. ¿Necesitás hacer rollback? Solo revertí el commit. ¿Necesitás ver qué está corriendo en producción? Mirá la rama principal.

<br />

##### **Configurándolo**
¿Listo para implementar esto? Acá está tu checklist:

<br />

**1. Crear un Token de Acceso Personal**
```elixir
# Andá a GitHub Settings > Developer settings > Personal access tokens
# Creá un token con scope 'repo' para el repositorio de manifiestos
# Guardalo como MANIFEST_REPO_TOKEN en los secrets del repo de tu app
```

<br />

**2. Crear Tu Repositorio de Manifiestos**
```elixir
mkdir k8s-manifests
cd k8s-manifests
git init

# Agregá tus archivos YAML de Kubernetes
cp /ruta/a/tus/*.yaml .

git add .
git commit -m "Manifiestos iniciales"
git push
```

<br />

**3. Agregar el Workflow**
Copiá el workflow a `.github/workflows/ci.yaml` en tu repositorio de aplicación. Actualizá los nombres de los repositorios y listo.

<br />

**4. Desplegar en Tu Cluster**
Ahora, tenés dos opciones:

**Opción A: Sincronización manual (más simple)**
```elixir
kubectl apply -f https://raw.githubusercontent.com/tu-org/tus-manifiestos/main/deployment.yaml
```

<br />

**Opción B: Sincronización automatizada**
Configurá un CronJob simple en tu cluster que hace pull y aplica los cambios:
```elixir
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitops-sync
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              kubectl apply -f https://raw.githubusercontent.com/tu-org/tus-manifiestos/main/
```

<br />

Eso es todo. Cada 5 minutos, tu cluster verifica cambios y los aplica. Sin operadores, sin controladores, solo un simple cron job.

<br />

##### **Por Qué Esto Funciona**
Este enfoque puede parecer demasiado simple, pero es exactamente por eso que funciona:

> * **Sin curva de aprendizaje**: Si conocés Git y CI/CD básico, estás listo
> * **Depurable**: Cuando algo se rompe, podés ver exactamente dónde y por qué
> * **Portable**: Funciona con cualquier cluster de Kubernetes, en cualquier lugar
> * **Auditable**: Cada cambio está en Git con historial completo
> * **Gratis**: Usa solo las características gratuitas de GitHub
> * **Seguro**: Superficie de ataque mínima, seguridad estándar de GitHub

<br />

##### **Cuándo Usar Esto**
Esta configuración es perfecta para:
- Equipos pequeños a medianos comenzando con GitOps
- Proyectos donde la simplicidad supera a las características
- Equipos que quieren entender todo su pipeline
- Situaciones donde no podés instalar herramientas adicionales en el cluster

<br />

Probablemente no sea ideal si necesitás:
- Despliegues multi-cluster
- Estrategias de despliegue complejas (canary, blue-green)
- Rollback automático basado en métricas
- Multi-tenancy con RBAC estricto

<br />

¿Pero sabés qué? Siempre podés agregar esas características más tarde. Empezá simple, entendé lo básico, después agregá complejidad solo cuando realmente la necesites.

<br />

##### **Problemas Comunes y Soluciones**

**¿La imagen no se actualiza?**
Verificá que tu política de pull de imagen no esté configurada en `IfNotPresent` con un tag que no cambia. Usar SHAs resuelve esto automáticamente.

<br />

**¿Token del repo de manifiestos expirado?**
Usá tokens de acceso personal de GitHub con fechas de vencimiento más largas, o mejor aún, usá una GitHub App para producción.

<br />

**¿Necesitás hacer rollback rápidamente?**
```elixir
git revert HEAD
git push
# Esperá la sincronización, o aplicá manualmente
```

<br />

##### **Conclusión**
GitOps no tiene que ser complicado. Esta configuración simple te da el 90% de los beneficios con el 10% de la complejidad. Obtenés control de versiones, despliegues automatizados, escaneo de seguridad y auditoría completa con solo un workflow de GitHub Actions.

<br />

Empezá acá, sentite cómodo con los conceptos, y después explorá herramientas más avanzadas como ArgoCD o Flux cuando realmente necesites sus características. Recordá, la mejor implementación de GitOps es la que tu equipo puede entender y mantener.

<br />

A veces, la solución más simple es la mejor solución. Y en este caso, simple no significa amateur - significa enfocado, mantenible y listo para producción.

<br />

¡Espero que te haya sido útil y hayas disfrutado leyéndolo, hasta la próxima!

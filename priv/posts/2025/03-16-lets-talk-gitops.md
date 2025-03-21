%{
  title: "Lets talk GitOps",
  author: "Gabriel Garrido",
  description: "We will see how GitOps works and how to tackle it effectively...",
  tags: ~w(cicd gitops argocd),
  published: true,
  image: "gitops.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---


##### **Introduction**
In this article we will explore GitOps and what it means, how it is used and why it is so effective in many large
organizations.

<br />

GitOps as the name suggests is a way to manage operations. Operations is often the name given to the management of
software and infrastructure required for it to function and be delivered and deployed (SDLC). But why Git? Well, 
turns out that Git is the perfect match to track changes in code and also in infrastructure and related resources. 

<br />

Some of the benefits are:

> * **Traceability**: Every change is logged with author, timestamp and commit message
> * **Integrity**: Git's cryptographic hashing ensures the integrity of your infrastructure definitions
> * **Easier collaboration**: Pull requests, reviews, and branching strategies enable better teamwork
> * **Adaptability**: Works with different infrastructures, platforms, and tools

Among other benefits, but it doesn't come for free. It also has its challenges and things depend a lot on personal
preferences and organizational requirements. 

<br />

Let's explore what this means in practice.

<br />

#### **Mental models**
There are basically two mental models in GitOps: **push-based** and **pull-based**. You might be thinking this is simple enough, but the end
result can change substantially based on which approach you pick.

<br />

Note: imagine we have a Kubernetes cluster and some repos with GitHub Actions as CI/CD.

<br />

##### Push-based GitOps
In a push-based approach, your workflows will trigger a mechanism to update the application (environment), whether in containers 
or somewhere in a data center. Basically, after you have your artifact built (docker image, tar file, package, jar file, whatever it might be),
you need to push that change or trigger the workflow that will push that change so the newer version of the application starts to run and replaces
the old version, while this may sounds super simple there are multiple ways of achieving it, let's explore these 3
initial scenarios:

<br />

###### Push-based basic pseudo-GitOps
![Push-based GitOps](/images/push-based-basic.png){:class="mx-auto"}

A change in the repository triggers a build in CI, which is then pushed to an image registry, the next step in the
pipeline is to trigger the update for the environment.

<br />

Imagine helm is being used to deploy the application so CI would have something like: 

```elixir
helm upgrade --install my-release -n my-namespace --set='image.tag'="${{ github.sha }}" 
```

<br />

###### Push-based pseudo-GitOps
![Push-based GitOps](/images/push-based-alternative.png){:class="mx-auto"}

The next iteration is similar but the deployment gets triggered by the image being pushed to the registry.

<br />

Note: these two are pseudo GitOps because git is almost the source of truth, we are missing the manifests repository.

<br />

###### Push-based GitOps
![Push-based GitOps](/images/push-based-alternative-pro.png){:class="mx-auto"}

This is the first true GitOps approach where we have an extra repository called "app-manifests" or also known as the
environment repository, that's where the SHA of the code repository gets stored, and then a deployment pipeline gets
triggered by that change.

<br />

Simple enough, right? This works great in small environments where there are not a lot of dependencies. However, as your
application starts to grow and you have more and more services, dependencies start to form and also bring complexity
to this scenario. While it is possible to handle complex scenarios with this approach, it can get more
cumbersome over time. 
 
<br />

There is another alternative flavor for the push-based model, and that's using webhooks. Basically, what would trigger an action in
another system, for example GitHub can trigger an http request to your defined endpoint when there are changes in your
repository, then you can parse the payload and do some extra processing or trigger a remote build, and so on, either way
you are triggering another workflow or sending an http to a custom system this is still part of the push-based model.

<br />

The main benefit of this approach is the flexibility given by the code at the receiving endpoint to make all the decisions you need, 
plus the speed, in most cases webhooks are received immediately. There could be issues as well, like delays or missing 
messages which would translate to missing builds or deployments.

<br />

So now, let's explore the pull-based mechanism.

<br />

###### Pull-based GitOps
So what about pull-based GitOps? "Pull" means that there is a mechanism checking your resources externally (there could be hybrid
mechanisms using webhooks for example). Imagine that you have a process checking your repository every few minutes to
discover changes and trigger builds, deploys, etc.

<br />

###### Pull-based GitOps
![Pull-based GitOps](/images/pull-based.png){:class="mx-auto"}
In this scenario the first part is still the same, but our CI has the reponsibility of updating the manifest or
environment repository, our controller then will be watching changes in both the repository and the registry for changes
as well as the infrastructure to keep things in sync, in my opinion that puts just too many reponsibilities in the
controller, but this way you could handle many more complex scenarios straight from your preferred language.

<br />

###### Pull-based GitOps Alternative (GitOps Controller Architecture)
![Pull-based GitOps](/images/pull-based-alternative.png){:class="mx-auto"}
You might have read the last article about the subject [GitOps Operator](/blog/create-your-own-gitops-controller-with-rust), 
if not maybe it is a good time to check it out, but basically in this case the controller is in charge of monitoring git
and the image registry for changes (validate that there is a new image for a new SHA) and updating the manifests or
environment repository, then we have ArgoCD (it could be flux or whatever you prefer) watching the manifests repository
and applying changes to the environment.

<br />

##### **Building on our previous work**
In our previous article, we built a custom GitOps operator in Rust that follows the pull-based model. The operator watches Kubernetes deployments with specific annotations and automatically updates manifests in a Git repository when a new application version is detected.

<br />

This demonstrates a practical implementation of the pull-based GitOps workflow, where:
> 1. Developers push code changes to an application repository
> 2. CI builds and publishes a new container image
> 3. Our operator detects the new version and updates the manifest repository
> 4. ArgoCD deploys the updated manifests to the cluster

<br />

This workflow provides complete traceability through Git, automated deployments, and clear separation of concerns between application development and deployment.

<br />

##### **Understanding the differences**

| Feature | Push-based | Pull-based |
|---------|-----------|------------|
| **Trigger mechanism** | CI system pushes changes | Controller periodically checks for changes |
| **Permissions** | CI needs cluster access | Cluster components pull from Git |
| **Security boundary** | CI system has outbound connection to cluster | Git is the only entry point |
| **Complexity** | Simpler initial setup | Requires additional controller/operator |
| **Audit trail** | Git history + CI logs | Git history is the single source of truth |
| **Drift detection** | Requires additional tooling | Built-in (controller constantly reconciles) |

<br />

##### **Some Pull-based Tools:**
> - ArgoCD
> - Flux CD
> - Our custom [GitOps Operator](/blog/create-your-own-gitops-controller-with-rust), 
> - Many more.

<br />

##### **Getting started with GitOps**
If you're looking to implement GitOps in your organization, here are some steps to get started:

> * Choose your model: Decide whether push-based or pull-based makes more sense for your team.
  
> * **Select tools**: Based on your model, choose the appropriate tools (e.g., ArgoCD for pull-based).
  
> * **Structure your repositories**: Decide how to organize your code and manifests - single repo or separate repos.
  
> * **Start small**: Begin with a simple application and expand as you gain confidence.
  
> * **Establish best practices**: Create guidelines for commits, reviews, and approvals.

<br />

##### **Choosing the right approach**
The approach you choose depends on several factors:

> 1. **Team size and structure**
> Smaller teams might prefer push-based for simplicity, while larger organizations with 
> multiple teams benefit from the governance of pull-based.

> 2. **Security requirements**: If your security team requires strict control over what gets deployed, 
pull-based provides better isolation.

> 3. **Operational maturity**: Pull-based approaches enforce more discipline but require more initial investment.

> 4. **Deployment frequency**: High-frequency deployments might benefit from either approach, depending on your specific requirements.

<br />

##### **Conclusion**
GitOps provides a powerful paradigm for managing both applications and infrastructure. Whether you choose a push-based or pull-based approach, the core principle remains the same: Git as the single source of truth.

<br />

By adopting GitOps practices, you gain better visibility, reliability, and governance over your deployments. As you've seen in our previous article's implementation, creating custom GitOps tooling is also possible to meet specific requirements.

<br />

Remember that there's no one-size-fits-all solution. The best approach depends on your team's needs, skillset, and organizational constraints. Start small, learn from your experiences, and adapt as you go.

<br />

If you want to learn more about GitOps I encourage you to read this [page](https://www.gitops.tech/) and experiment with it yourself.

<br />

Hope you found this useful and enjoyed reading it, until next time!

---lang---
%{
  title: "Hablemos de GitOps",
  author: "Gabriel Garrido",
  description: "Vamos a ver que es y como usar GitOps efectivamente... ",
  tags: ~w(cicd gitops argocd),
  published: true,
  image: "rust.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a explorar qué es GitOps, cómo se utiliza y por qué es tan efectivo en muchas organizaciones grandes.

<br />

GitOps, como su nombre lo sugiere, es una forma de gestionar operaciones, operaciones es el nombre que se le da habitualmente a la gestión de software e infraestructura necesaria para su funcionamiento (SDLC). ¿Pero por qué Git? Bueno, resulta que Git es la herramienta perfecta para rastrear cambios en el código y también en la infraestructura y recursos relacionados.

<br />

Algunos de los beneficios son:

> * **Trazabilidad**: Cada cambio queda registrado con autor, fecha y mensaje de commit
> * **Integridad**: El hashing criptográfico de Git asegura la integridad de las definiciones de infraestructura
> * **Colaboración más sencilla**: Pull requests, revisiones y estrategias de ramificación permiten un mejor trabajo en equipo
> * **Adaptabilidad**: Funciona con diferentes infraestructuras, plataformas y herramientas

Entre otros beneficios, pero no viene gratis. También tiene sus desafíos y las cosas dependen mucho de las preferencias personales y los requisitos organizacionales.

<br />

Veamos qué significa esto en la práctica.

<br />

#### **Modelos mentales**
Básicamente hay dos modelos mentales en GitOps: **basado en push** y **basado en pull**. Quizás estés pensando que esto es bastante simple, pero el resultado final puede cambiar sustancialmente según el enfoque que elijas.

<br />

Nota: imaginemos que tenemos un cluster de Kubernetes y algunos repositorios con GitHub Actions como CI/CD.

<br />

##### GitOps basado en push
En un enfoque basado en push, tus workflows dispararán un mecanismo para actualizar la aplicación (entorno), ya sea en contenedores o en algún lugar de un centro de datos. Básicamente, después de tener tu artefacto construido (imagen de docker, archivo tar, paquete, archivo jar, lo que sea), necesitás pushear ese cambio o disparar el workflow que pusheará ese cambio para que la nueva versión de la aplicación comience a ejecutarse y reemplace la versión anterior. Si bien esto puede sonar super simple, hay múltiples formas de lograrlo, exploremos estos 3 escenarios iniciales:

<br />

###### GitOps básico basado en push (pseudo-GitOps)
![GitOps basado en push](/images/push-based-basic.png){:class="mx-auto"}

Un cambio en el repositorio dispara una construcción en CI, que luego se pushea a un registro de imágenes. El siguiente paso en el pipeline es disparar la actualización para el entorno. 

<br />

Imaginate que se está usando Helm para desplegar la aplicación, entonces CI tendría algo como:

```elixir
helm upgrade --install my-release -n my-namespace --set='image.tag'="${{ github.sha }}" 
```

<br />

###### Pseudo-GitOps basado en push
![GitOps basado en push](/images/push-based-alternative.png){:class="mx-auto"}

La siguiente iteración es similar, pero el despliegue se dispara por la imagen que se pushea al registro.

<br />

Nota: estos dos son pseudo-GitOps porque Git es casi la fuente de verdad todavia nos falta el repositorio del los manifests.

<br />

###### GitOps basado en push
![GitOps basado en push](/images/push-based-alternative-pro.png){:class="mx-auto"}

Este es el primer enfoque verdadero de GitOps donde tenemos un repositorio extra llamado "app-manifests" o también conocido como el repositorio de entorno. Ahí es donde se almacena el SHA del repositorio de código, y luego un pipeline de despliegue se dispara por ese cambio.

<br />

Bastante simple, ¿no? Esto funciona muy bien en entornos pequeños donde no hay muchas dependencias. Sin embargo, a medida que tu aplicación crece y tenés más y más servicios, las dependencias comienzan a formarse y también traen complejidad a este escenario. Si bien es posible manejar escenarios complejos con este enfoque, puede volverse más engorroso con el tiempo. 

<br />

Hay otra variante alternativa para el modelo basado en push, y es usando webhooks. Básicamente, lo que dispararía una acción en otro sistema, por ejemplo, GitHub puede disparar una solicitud http a tu endpoint definido cuando hay cambios en tu repositorio, luego podés analizar la carga útil y hacer algún procesamiento adicional o disparar una construcción remota, y así sucesivamente. De cualquier manera, estás disparando otro workflow o enviando una solicitud http a un sistema personalizado, esto sigue siendo parte del modelo basado en push.

<br />

El principal beneficio de este enfoque es la flexibilidad que da el código en el endpoint receptor para tomar todas las decisiones que necesitás, además de la velocidad. En la mayoría de los casos, los webhooks se reciben inmediatamente. También podría haber problemas, como retrasos o mensajes perdidos que se traducirían en construcciones o despliegues perdidos.

<br />

Así que ahora, exploremos el mecanismo basado en pull.

<br />

###### GitOps basado en pull
¿Y qué hay del GitOps basado en pull? "Pull" significa que hay un mecanismo que verifica tus recursos externamente (podría haber mecanismos híbridos usando webhooks, por ejemplo). Imaginate que tenés un proceso que verifica tu repositorio cada pocos minutos para descubrir cambios y disparar construcciones, despliegues, etc.

<br />

###### GitOps basado en pull
![GitOps basado en pull](/images/pull-based.png){:class="mx-auto"}
En este escenario, la primera parte sigue siendo la misma, pero nuestro CI tiene la responsabilidad de actualizar el repositorio de manifiestos o entorno. Nuestro controlador luego estará observando los cambios tanto en el repositorio como en el registro para detectar cambios, así como en la infraestructura para mantener las cosas sincronizadas. En mi opinión, esto pone demasiadas responsabilidades en el controlador, pero de esta manera podrías manejar muchos escenarios más complejos directamente desde tu lenguaje preferido.

<br />

###### GitOps basado en pull alternativo (Arquitectura del Controlador GitOps)
![GitOps basado en pull](/images/pull-based-alternative.png){:class="mx-auto"}
Es posible que hayas leído el último artículo sobre el tema [GitOps Operator](/blog/create-your-own-gitops-controller-with-rust), si no, tal vez sea un buen momento para revisarlo. Pero básicamente, en este caso, el controlador se encarga de monitorear git y el registro de imágenes para detectar cambios (validar que hay una nueva imagen para un nuevo SHA) y actualizar los manifiestos o el repositorio de entorno. Luego tenemos ArgoCD (podría ser Flux o lo que prefieras) observando el repositorio de manifiestos y aplicando cambios al entorno.

<br />

##### **Continuando con nuestro trabajo anterior**
En nuestro artículo anterior, construimos un operador GitOps personalizado en Rust que sigue el modelo basado en pull. El operador observa los despliegues de Kubernetes con anotaciones específicas y actualiza automáticamente los manifiestos en un repositorio Git cuando se detecta una nueva versión de la aplicación.

<br />

Esto demuestra una implementación práctica del flujo de trabajo GitOps basado en pull, donde:
> 1. Los desarrolladores pushean cambios de código a un repositorio de aplicación
> 2. CI construye y publica una nueva imagen de contenedor
> 3. Nuestro operador detecta la nueva versión y actualiza el repositorio de manifiestos
> 4. ArgoCD despliega los manifiestos actualizados en el cluster

Este flujo de trabajo proporciona trazabilidad completa a través de Git, despliegues automatizados y una clara separación de preocupaciones entre el desarrollo de aplicaciones y el despliegue.

<br />

##### **Entendiendo las diferencias**

| Característica | Basado en Push | Basado en Pull |
|---------|-----------|------------|
| **Mecanismo de disparo** | El sistema CI pushea cambios | El controlador verifica periódicamente los cambios |
| **Permisos** | CI necesita acceso al cluster | Los componentes del cluster hacen pull desde Git |
| **Límite de seguridad** | El sistema CI tiene conexión saliente al cluster | Git es el único punto de entrada |
| **Complejidad** | Configuración inicial más simple | Requiere controlador/operador adicional |
| **Auditoría** | Historial de Git + logs de CI | El historial de Git es la única fuente de verdad |
| **Detección de desviaciones** | Requiere herramientas adicionales | Integrado (el controlador reconcilia constantemente) |

<br />

##### **Algunas herramientas basadas en Pull:**
> - ArgoCD
> - Flux CD
> - Nuestro [GitOps Operator](/blog/create-your-own-gitops-controller-with-rust) personalizado
> - Muchas más.

<br />

##### **Comenzando con GitOps**
Si estás pensando en implementar GitOps en tu organización, acá hay algunos pasos para comenzar:

> 1. **Elegí tu modelo**: Decidí si el enfoque basado en push o pull tiene más sentido para tu equipo.

> 2. **Seleccioná herramientas**: Basado en tu modelo, elegí las herramientas apropiadas (por ejemplo, ArgoCD para el enfoque basado en pull).

> 3. **Estructurá tus repositorios**: Decidí cómo organizar tu código y manifiestos - un solo repo o repos separados.

> 4. **Empezá de a poco**: Comenzá con una aplicación simple y expandite a medida que ganás confianza.

> 5. **Establecé mejores prácticas**: Creá pautas para commits, revisiones y aprobaciones.

<br />

##### **Eligiendo el enfoque correcto**
El enfoque que elijas depende de varios factores:

> 1. **Tamaño y estructura del equipo**: Los equipos más pequeños podrían preferir el enfoque basado en push por su simplicidad, mientras que las organizaciones más grandes con múltiples equipos se benefician de la gobernanza del enfoque basado en pull.

> 2. **Requisitos de seguridad**: Si tu equipo de seguridad requiere un control estricto sobre lo que se despliega, el enfoque basado en pull proporciona mejor aislamiento.

> 3. **Madurez operativa**: Los enfoques basados en pull exigen más disciplina pero requieren una inversión inicial mayor.

> 4. **Frecuencia de despliegue**: Los despliegues de alta frecuencia podrían beneficiarse de cualquiera de los enfoques, dependiendo de tus requisitos específicos.

<br />

##### **Conclusión**
GitOps proporciona un paradigma poderoso para gestionar tanto aplicaciones como infraestructura. Ya sea que elijas un enfoque basado en push o en pull, el principio central sigue siendo el mismo: Git como la única fuente de verdad.

<br />

Al adoptar prácticas de GitOps, obtenés mejor visibilidad, confiabilidad y gobernanza sobre tus despliegues. Como viste en la implementación de nuestro artículo anterior, también es posible crear herramientas GitOps personalizadas para cumplir con requisitos específicos.

<br />

Recordá que no hay una solución única para todos. El mejor enfoque depende de las necesidades de tu equipo, habilidades y restricciones organizacionales. Comenzá de a poco, aprendé de tus experiencias y adaptate a medida que avanzás.

<br />

Si querés aprender más sobre GitOps, te recomiendo leer esta [página](https://www.gitops.tech/) y experimentar vos mismo.

<br />

¡Espero que te haya gustado y te sea útil\! ¡Hasta la próxima\!

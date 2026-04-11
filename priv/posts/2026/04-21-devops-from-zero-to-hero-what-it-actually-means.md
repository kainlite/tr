%{
  title: "DevOps from Zero to Hero: What It Actually Means and Why You Should Care",
  author: "Gabriel Garrido",
  description: "We will explore what DevOps actually means beyond the buzzword, the DORA metrics that measure it, how it relates to SRE and Platform Engineering, and what this series will cover...",
  tags: ~w(devops beginners culture),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
This is the first article in a twenty-part series called "DevOps from Zero to Hero." The goal is to take
you from knowing nothing about DevOps to being comfortable with the tools and practices that modern teams
use every day. We will use TypeScript, AWS, Kubernetes, and GitHub Actions throughout the series, building
real things along the way.

<br />

But before we touch any tools, we need to understand what DevOps actually is. This word gets thrown around
a lot. Job postings ask for "DevOps Engineers," companies buy "DevOps tools," and somehow everyone has a
different definition. In this article we are going to cut through the noise and talk about what DevOps
really means, where it came from, how to measure it, and what it is definitely not.

<br />

Let's get into it.

<br />

##### **What is DevOps?**
DevOps is not a tool. It is not a job title. It is not a team you create so developers can stop caring
about production. DevOps is a combination of cultural practices, processes, and tools that increases an
organization's ability to deliver software faster and more reliably.

<br />

The simplest way to think about it: DevOps is about removing the walls between the people who write
code and the people who run it in production.

<br />

There are three pillars to DevOps:

<br />

> * **Culture**: Teams share responsibility for the full lifecycle of their software, from writing it to running it
> * **Practices**: Continuous integration, continuous delivery, infrastructure as code, monitoring, and fast feedback loops
> * **Tools**: The automation that makes those practices possible at scale

<br />

If you only adopt the tools without changing how your teams work, you are not doing DevOps. You are just
automating the same broken process. This is a critical point that many organizations miss.

<br />

##### **A brief history: the wall of confusion**
To understand why DevOps exists, you need to know what came before it. For decades, software organizations
had two separate groups:

<br />

> * **Development (Dev)**: Writes the code, ships features, moves fast, wants to deploy often
> * **Operations (Ops)**: Runs the servers, keeps things stable, moves carefully, wants to deploy never

<br />

These two groups had completely different incentives. Dev wanted change because change meant new features.
Ops wanted stability because change meant risk. The handoff between them was called "the wall of confusion."
Dev would throw code over the wall, Ops would try to figure out how to run it, and when things broke,
everyone blamed each other.

<br />

This created a painful cycle:

<br />

> * Deployments were rare (monthly or quarterly) because they were risky and stressful
> * Each deployment was huge because all the changes piled up
> * Huge deployments meant more things could go wrong
> * When things went wrong, it took forever to figure out which change caused the problem
> * So deployments became even more rare, and the cycle continued

<br />

In 2008 and 2009, a few people started talking about breaking this cycle. Patrick Debois organized the
first "DevOpsDays" conference in Ghent, Belgium in 2009. The idea was simple: what if Dev and Ops worked
together instead of against each other? What if we deployed small changes frequently instead of big
changes rarely? What if we automated everything that could be automated?

<br />

These ideas were not entirely new. Google had been practicing something similar internally for years
(they later published it as Site Reliability Engineering). But the DevOps movement gave it a name and
made it accessible to everyone, not just companies with Google-scale resources.

<br />

##### **The DORA metrics: measuring DevOps performance**
One of the most important contributions to the DevOps movement came from the DORA (DevOps Research and
Assessment) team, led by Dr. Nicole Forsgren, Jez Humble, and Gene Kim. They spent years researching
what separates high-performing teams from low-performing ones. Their findings were published in the book
"Accelerate" and in annual State of DevOps reports.

<br />

They identified four key metrics that predict software delivery performance:

<br />

> * **Deployment Frequency**: How often your team deploys to production. Elite teams deploy on demand, multiple times per day. Low performers deploy monthly or less.
> * **Lead Time for Changes**: How long it takes from a code commit to that code running in production. Elite teams measure this in less than one hour. Low performers take between one and six months.
> * **Change Failure Rate**: What percentage of deployments cause a failure in production that requires a fix (rollback, patch, etc.). Elite teams have a rate of 0-15%. Low performers hit 46-60%.
> * **Mean Time to Recovery (MTTR)**: When something breaks in production, how long does it take to restore service? Elite teams recover in less than one hour. Low performers take between one week and one month.

<br />

Here is the key insight from their research: these four metrics are correlated. Teams that deploy more
frequently also have lower failure rates and faster recovery times. Speed and stability are not enemies.
They reinforce each other.

<br />

```plaintext
Traditional thinking:
  "If we deploy more often, more things will break"

What DORA research actually shows:
  "Teams that deploy more often break fewer things AND recover faster"

Why? Because:
  - Smaller changes are easier to understand and debug
  - Frequent deployments mean faster feedback loops
  - Fast feedback loops mean problems get caught earlier
  - Earlier problems are cheaper and simpler to fix
```

<br />

This might feel counterintuitive at first. But think about it this way: would you rather debug a
deployment that contains 3 commits or one that contains 300? The answer is obvious. Deploying
frequently forces you to keep changes small, and small changes are inherently less risky.

<br />

##### **DevOps vs SRE vs Platform Engineering**
You will hear these three terms used interchangeably, but they are distinct (and complementary) disciplines.
Understanding how they relate will save you a lot of confusion.

<br />

**DevOps** is the cultural movement. It is the philosophy that says Dev and Ops should work together, share
responsibility, and use automation to deliver software faster and more reliably. DevOps is about principles:
you own what you build, you automate everything you can, and you measure outcomes.

<br />

**Site Reliability Engineering (SRE)** is one way to implement DevOps principles. Google created it in the
early 2000s before the term "DevOps" even existed. SRE treats operations as a software engineering problem.
SRE teams write code to automate operational work, define Service Level Objectives (SLOs) to measure
reliability, and use error budgets to balance reliability with feature velocity.

<br />

Ben Treynor Sloss, the founder of Google's SRE team, described it this way:

<br />

```plaintext
"SRE is what happens when you ask a software engineer to design an operations function."
```

<br />

If DevOps is the "what" (principles and culture), SRE is one answer to the "how" (specific practices and
frameworks).

<br />

**Platform Engineering** is the newest of the three. It emerged as organizations realized that asking every
development team to fully own their infrastructure was not scaling. Platform Engineering teams build internal
developer platforms (IDPs) that abstract away infrastructure complexity. Instead of every team learning
Kubernetes, Terraform, and CI/CD pipelines from scratch, the platform team provides golden paths, templates,
and self-service tools.

<br />

Think of it this way:

<br />

```plaintext
DevOps says:     "You build it, you run it"
SRE says:        "Here are the practices and metrics to run it well"
Platform Eng:    "Here is a platform that makes running it easy"
```

<br />

These three approaches are not competing. In a mature organization, they work together. DevOps provides the
culture, SRE provides the reliability framework, and Platform Engineering provides the developer experience
layer on top.

<br />

##### **The DevOps toolchain**
While DevOps is not just about tools, the tools do matter. They are what make the practices possible at scale.
Here is the typical DevOps toolchain, organized by stage:

<br />

**Plan and track**
> * Issue trackers (GitHub Issues, Jira, Linear)
> * Project boards, documentation wikis

<br />

**Version control**
> * Git (GitHub, GitLab, Bitbucket)
> * Branching strategies, pull requests, code review

<br />

**Continuous Integration (CI)**
> * Automatically build, test, and validate every code change
> * Tools: GitHub Actions, GitLab CI, Jenkins, CircleCI

<br />

**Continuous Delivery/Deployment (CD)**
> * Automatically deploy validated changes to production
> * Tools: ArgoCD, Flux, Spinnaker, GitHub Actions

<br />

**Containers and orchestration**
> * Package applications consistently across environments
> * Tools: Docker, Kubernetes, ECS

<br />

**Infrastructure as Code (IaC)**
> * Define and manage infrastructure through code, not clicking in consoles
> * Tools: Terraform, Pulumi, AWS CDK, CloudFormation

<br />

**Monitoring and observability**
> * Know what is happening in production before your users tell you
> * Tools: Prometheus, Grafana, Datadog, OpenTelemetry

<br />

**Security**
> * Shift security left, automate scanning, manage secrets
> * Tools: Trivy, Snyk, HashiCorp Vault, GitHub security features

<br />

In this series we will focus on a specific subset of these tools: TypeScript for application code, GitHub
Actions for CI/CD, Docker for containers, Kubernetes for orchestration, and AWS for cloud infrastructure.
This stack is widely used, well documented, and gives you skills that transfer to almost any organization.

<br />

##### **What this series will cover**
Here is the roadmap for the twenty articles in this series:

<br />

> * **Article 1 (this one)**: What DevOps actually means
> * **Articles 2-3**: Version control with Git and GitHub workflows
> * **Articles 4-5**: Containers with Docker, from basics to multi-stage builds
> * **Articles 6-8**: CI/CD with GitHub Actions, from simple pipelines to advanced workflows
> * **Articles 9-11**: Cloud fundamentals with AWS (networking, compute, storage)
> * **Articles 12-14**: Kubernetes from scratch, deploying and managing real applications
> * **Articles 15-16**: Infrastructure as Code with Terraform
> * **Articles 17-18**: Monitoring, logging, and observability
> * **Article 19**: Security practices and secrets management
> * **Article 20**: Putting it all together, a complete DevOps pipeline from commit to production

<br />

Each article builds on the previous ones. By the end of the series, you will have built a complete
pipeline that takes a TypeScript application from a git commit all the way to a production Kubernetes
cluster on AWS, with automated testing, security scanning, monitoring, and alerting.

<br />

**Who is this for?**

<br />

> * Developers who want to understand what happens to their code after they push it
> * Junior engineers or students who want to learn modern DevOps practices from scratch
> * Ops people who want to adopt a more engineering-driven approach
> * Anyone who keeps hearing "DevOps" in meetings and wants to actually understand what it means

<br />

You do not need prior experience with any of the tools we will use. I will explain everything from the
ground up. Basic programming knowledge and comfort with the command line are helpful but not strictly
required.

<br />

##### **What DevOps is NOT: common anti-patterns**
Let's close with something equally important: what DevOps is not. These are real anti-patterns that
organizations fall into constantly.

<br />

**Anti-pattern 1: Renaming your Ops team to "DevOps"**

<br />

If you take your existing operations team, change their title to "DevOps Engineer," and nothing else
changes, you have not adopted DevOps. You have renamed a team. DevOps requires cultural change, not
just a title change.

<br />

**Anti-pattern 2: Buying tools and calling it DevOps**

<br />

Purchasing a CI/CD platform, a container orchestrator, and a monitoring tool does not make you a DevOps
organization. Tools without the right practices and culture are just expensive shelfware. I have seen
organizations spend millions on tooling while their teams still deploy manually every two weeks.

<br />

**Anti-pattern 3: Creating a DevOps silo**

<br />

The irony of this one is painful. DevOps was created to break down silos between Dev and Ops. Some
organizations responded by creating a third silo called "the DevOps team" that sits between Dev and
Ops. Now you have three walls of confusion instead of one.

<br />

**Anti-pattern 4: All tools, no culture**

<br />

This is worth repeating because it is the most common mistake. If your developers write code and then
throw it over the wall to someone else to deploy, you are not doing DevOps no matter what tools you use.
DevOps means shared ownership. The team that builds the software is responsible for running it.

<br />

**Anti-pattern 5: DevOps means "developers do everything"**

<br />

DevOps does not mean firing your ops team and making developers manage servers. It means that development
and operations work together, share knowledge, and both contribute to automation. Developers gain
operational awareness, and ops engineers gain development skills. The goal is collaboration, not
consolidation.

<br />

##### **Closing notes**
DevOps is, at its core, a simple idea: the people who build software and the people who run it should
work together, share responsibility, and use automation to move faster without sacrificing stability.
The DORA metrics prove that this approach works. Speed and reliability are not opposites. They go hand
in hand.

<br />

In the next article, we will start getting practical. We will set up a development environment, create
a TypeScript project, initialize a Git repository, and learn the version control fundamentals that
everything else in this series will build on.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps desde Cero: Que Significa Realmente y Por Que Deberia Importarte",
  author: "Gabriel Garrido",
  description: "Vamos a explorar que significa realmente DevOps mas alla del buzzword, las metricas DORA que lo miden, como se relaciona con SRE y Platform Engineering, y que vamos a cubrir en esta serie...",
  tags: ~w(devops beginners culture),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Este es el primer articulo de una serie de veinte partes llamada "DevOps desde Cero." El objetivo es
llevarte desde no saber nada sobre DevOps hasta sentirte comodo con las herramientas y practicas que
los equipos modernos usan todos los dias. Vamos a usar TypeScript, AWS, Kubernetes y GitHub Actions
a lo largo de la serie, construyendo cosas reales en el camino.

<br />

Pero antes de tocar cualquier herramienta, necesitamos entender que es realmente DevOps. Esta palabra
se usa mucho. Las ofertas de trabajo piden "DevOps Engineers," las empresas compran "herramientas DevOps,"
y de alguna manera todos tienen una definicion diferente. En este articulo vamos a ir al grano y hablar
de lo que DevOps realmente significa, de donde viene, como medirlo, y que definitivamente no es.

<br />

Vamos a meternos de lleno.

<br />

##### **Que es DevOps?**
DevOps no es una herramienta. No es un titulo de puesto. No es un equipo que creas para que los
desarrolladores dejen de preocuparse por produccion. DevOps es una combinacion de practicas culturales,
procesos y herramientas que aumenta la capacidad de una organizacion para entregar software mas rapido
y de forma mas confiable.

<br />

La forma mas simple de pensarlo: DevOps se trata de eliminar las paredes entre las personas que escriben
codigo y las personas que lo corren en produccion.

<br />

Hay tres pilares en DevOps:

<br />

> * **Cultura**: Los equipos comparten la responsabilidad del ciclo de vida completo de su software, desde escribirlo hasta correrlo
> * **Practicas**: Integracion continua, entrega continua, infraestructura como codigo, monitoreo y ciclos de feedback rapidos
> * **Herramientas**: La automatizacion que hace posibles esas practicas a escala

<br />

Si solo adoptas las herramientas sin cambiar como trabajan tus equipos, no estas haciendo DevOps. Solo
estas automatizando el mismo proceso roto. Este es un punto critico que muchas organizaciones no entienden.

<br />

##### **Una breve historia: el muro de confusion**
Para entender por que existe DevOps, necesitas saber que habia antes. Durante decadas, las organizaciones
de software tenian dos grupos separados:

<br />

> * **Desarrollo (Dev)**: Escribe el codigo, entrega features, se mueve rapido, quiere deployar seguido
> * **Operaciones (Ops)**: Corre los servidores, mantiene las cosas estables, se mueve con cuidado, quiere no deployar nunca

<br />

Estos dos grupos tenian incentivos completamente diferentes. Dev queria cambios porque cambios significaban
features nuevos. Ops queria estabilidad porque cambios significaban riesgo. La transferencia entre ellos
se llamaba "el muro de confusion." Dev tiraba el codigo por encima del muro, Ops intentaba averiguar como
correrlo, y cuando las cosas se rompian, todos se culpaban mutuamente.

<br />

Esto creaba un ciclo doloroso:

<br />

> * Los deploys eran raros (mensuales o trimestrales) porque eran riesgosos y estresantes
> * Cada deploy era enorme porque todos los cambios se acumulaban
> * Deploys enormes significaban mas cosas que podian salir mal
> * Cuando algo salia mal, tardaba una eternidad encontrar cual cambio causo el problema
> * Entonces los deploys se volvian aun mas raros, y el ciclo continuaba

<br />

En 2008 y 2009, algunas personas empezaron a hablar de romper este ciclo. Patrick Debois organizo la
primera conferencia "DevOpsDays" en Ghent, Belgica en 2009. La idea era simple: que pasaria si Dev y
Ops trabajaran juntos en lugar de enfrentados? Que pasaria si deployearamos cambios chicos frecuentemente
en lugar de cambios grandes raramente? Que pasaria si automatizaramos todo lo que se pudiera automatizar?

<br />

Estas ideas no eran completamente nuevas. Google venia practicando algo similar internamente durante anios
(despues lo publicaron como Site Reliability Engineering). Pero el movimiento DevOps le dio un nombre y
lo hizo accesible para todos, no solo para empresas con los recursos de Google.

<br />

##### **Las metricas DORA: midiendo el rendimiento DevOps**
Una de las contribuciones mas importantes al movimiento DevOps vino del equipo DORA (DevOps Research and
Assessment), liderado por la Dra. Nicole Forsgren, Jez Humble y Gene Kim. Pasaron anios investigando que
separa a los equipos de alto rendimiento de los de bajo rendimiento. Sus hallazgos se publicaron en el
libro "Accelerate" y en reportes anuales del State of DevOps.

<br />

Identificaron cuatro metricas clave que predicen el rendimiento en entrega de software:

<br />

> * **Frecuencia de Deploy**: Que tan seguido tu equipo deploya a produccion. Los equipos elite deployean on demand, multiples veces por dia. Los de bajo rendimiento deployean mensualmente o menos.
> * **Lead Time para Cambios**: Cuanto tiempo pasa desde un commit de codigo hasta que ese codigo esta corriendo en produccion. Los equipos elite miden esto en menos de una hora. Los de bajo rendimiento tardan entre uno y seis meses.
> * **Tasa de Fallo de Cambios**: Que porcentaje de deploys causan una falla en produccion que requiere un fix (rollback, parche, etc.). Los equipos elite tienen una tasa del 0-15%. Los de bajo rendimiento llegan al 46-60%.
> * **Tiempo Medio de Recuperacion (MTTR)**: Cuando algo se rompe en produccion, cuanto tiempo toma restaurar el servicio? Los equipos elite se recuperan en menos de una hora. Los de bajo rendimiento tardan entre una semana y un mes.

<br />

Aca esta el insight clave de su investigacion: estas cuatro metricas estan correlacionadas. Los equipos
que deployean mas frecuentemente tambien tienen tasas de fallo mas bajas y tiempos de recuperacion mas
rapidos. Velocidad y estabilidad no son enemigos. Se refuerzan mutuamente.

<br />

```plaintext
Pensamiento tradicional:
  "Si deployeamos mas seguido, mas cosas se van a romper"

Lo que la investigacion de DORA realmente muestra:
  "Los equipos que deployean mas seguido rompen menos cosas Y se recuperan mas rapido"

Por que? Porque:
  - Cambios mas chicos son mas faciles de entender y debuggear
  - Deploys frecuentes significan ciclos de feedback mas rapidos
  - Ciclos de feedback rapidos significan que los problemas se detectan antes
  - Problemas detectados antes son mas baratos y simples de arreglar
```

<br />

Esto puede parecer contraintuitivo al principio. Pero pensalo de esta manera: preferis debuggear un
deploy que contiene 3 commits o uno que contiene 300? La respuesta es obvia. Deployear frecuentemente
te fuerza a mantener los cambios chicos, y los cambios chicos son inherentemente menos riesgosos.

<br />

##### **DevOps vs SRE vs Platform Engineering**
Vas a escuchar estos tres terminos usados de forma intercambiable, pero son disciplinas distintas (y
complementarias). Entender como se relacionan te va a ahorrar mucha confusion.

<br />

**DevOps** es el movimiento cultural. Es la filosofia que dice que Dev y Ops deberian trabajar juntos,
compartir responsabilidad, y usar automatizacion para entregar software mas rapido y de forma mas
confiable. DevOps se trata de principios: sos duenio de lo que construis, automatizas todo lo que
puedas, y medis resultados.

<br />

**Site Reliability Engineering (SRE)** es una forma de implementar los principios DevOps. Google lo creo
a principios de los 2000 antes de que existiera el termino "DevOps." SRE trata las operaciones como
un problema de ingenieria de software. Los equipos SRE escriben codigo para automatizar el trabajo
operativo, definen Service Level Objectives (SLOs) para medir la confiabilidad, y usan error budgets
para balancear confiabilidad con velocidad de features.

<br />

Ben Treynor Sloss, el fundador del equipo SRE de Google, lo describio asi:

<br />

```plaintext
"SRE es lo que pasa cuando le pedis a un ingeniero de software que disenie una funcion de operaciones."
```

<br />

Si DevOps es el "que" (principios y cultura), SRE es una respuesta al "como" (practicas y frameworks
especificos).

<br />

**Platform Engineering** es el mas nuevo de los tres. Surgio cuando las organizaciones se dieron cuenta
de que pedirle a cada equipo de desarrollo que sea duenio completo de su infraestructura no escalaba.
Los equipos de Platform Engineering construyen plataformas internas para desarrolladores (IDPs) que
abstraen la complejidad de la infraestructura. En lugar de que cada equipo aprenda Kubernetes, Terraform
y pipelines de CI/CD desde cero, el equipo de plataforma provee golden paths, templates y herramientas
de autoservicio.

<br />

Pensalo asi:

<br />

```plaintext
DevOps dice:          "Lo construis, lo corres"
SRE dice:             "Aca estan las practicas y metricas para correrlo bien"
Platform Eng dice:    "Aca hay una plataforma que hace facil correrlo"
```

<br />

Estos tres enfoques no compiten entre si. En una organizacion madura, trabajan juntos. DevOps provee
la cultura, SRE provee el framework de confiabilidad, y Platform Engineering provee la capa de
experiencia de desarrollador encima de todo.

<br />

##### **El toolchain de DevOps**
Si bien DevOps no se trata solo de herramientas, las herramientas importan. Son lo que hace posibles las
practicas a escala. Aca esta el toolchain tipico de DevOps, organizado por etapa:

<br />

**Planificacion y seguimiento**
> * Issue trackers (GitHub Issues, Jira, Linear)
> * Tableros de proyecto, wikis de documentacion

<br />

**Control de versiones**
> * Git (GitHub, GitLab, Bitbucket)
> * Estrategias de branching, pull requests, code review

<br />

**Integracion Continua (CI)**
> * Compilar, testear y validar automaticamente cada cambio de codigo
> * Herramientas: GitHub Actions, GitLab CI, Jenkins, CircleCI

<br />

**Entrega/Deploy Continuo (CD)**
> * Deployear automaticamente los cambios validados a produccion
> * Herramientas: ArgoCD, Flux, Spinnaker, GitHub Actions

<br />

**Containers y orquestacion**
> * Empaquetar aplicaciones de forma consistente entre ambientes
> * Herramientas: Docker, Kubernetes, ECS

<br />

**Infraestructura como Codigo (IaC)**
> * Definir y gestionar infraestructura a traves de codigo, no clickeando en consolas
> * Herramientas: Terraform, Pulumi, AWS CDK, CloudFormation

<br />

**Monitoreo y observabilidad**
> * Saber que esta pasando en produccion antes de que tus usuarios te avisen
> * Herramientas: Prometheus, Grafana, Datadog, OpenTelemetry

<br />

**Seguridad**
> * Mover la seguridad a la izquierda, automatizar escaneos, gestionar secretos
> * Herramientas: Trivy, Snyk, HashiCorp Vault, funcionalidades de seguridad de GitHub

<br />

En esta serie nos vamos a enfocar en un subconjunto especifico de estas herramientas: TypeScript para
codigo de aplicacion, GitHub Actions para CI/CD, Docker para containers, Kubernetes para orquestacion,
y AWS para infraestructura cloud. Este stack es ampliamente usado, esta bien documentado, y te da
habilidades que se transfieren a casi cualquier organizacion.

<br />

##### **Que va a cubrir esta serie**
Aca esta el plan para los veinte articulos de esta serie:

<br />

> * **Articulo 1 (este)**: Que significa realmente DevOps
> * **Articulos 2-3**: Control de versiones con Git y workflows de GitHub
> * **Articulos 4-5**: Containers con Docker, desde lo basico hasta multi-stage builds
> * **Articulos 6-8**: CI/CD con GitHub Actions, desde pipelines simples hasta workflows avanzados
> * **Articulos 9-11**: Fundamentos de cloud con AWS (networking, compute, storage)
> * **Articulos 12-14**: Kubernetes desde cero, deployeando y gestionando aplicaciones reales
> * **Articulos 15-16**: Infraestructura como Codigo con Terraform
> * **Articulos 17-18**: Monitoreo, logging y observabilidad
> * **Articulo 19**: Practicas de seguridad y gestion de secretos
> * **Articulo 20**: Juntando todo, un pipeline DevOps completo desde commit hasta produccion

<br />

Cada articulo construye sobre los anteriores. Al final de la serie, vas a haber construido un pipeline
completo que lleva una aplicacion TypeScript desde un commit de git hasta un cluster de Kubernetes en
produccion en AWS, con testing automatizado, escaneo de seguridad, monitoreo y alertas.

<br />

**Para quien es esto?**

<br />

> * Desarrolladores que quieren entender que pasa con su codigo despues de pushearlo
> * Ingenieros juniors o estudiantes que quieren aprender practicas DevOps modernas desde cero
> * Gente de Ops que quiere adoptar un enfoque mas orientado a ingenieria
> * Cualquiera que sigue escuchando "DevOps" en reuniones y quiere realmente entender que significa

<br />

No necesitas experiencia previa con ninguna de las herramientas que vamos a usar. Voy a explicar todo
desde la base. Conocimiento basico de programacion y comodidad con la linea de comandos ayudan pero
no son estrictamente necesarios.

<br />

##### **Lo que DevOps NO es: anti-patrones comunes**
Cerremos con algo igualmente importante: lo que DevOps no es. Estos son anti-patrones reales en los
que las organizaciones caen constantemente.

<br />

**Anti-patron 1: Renombrar tu equipo de Ops a "DevOps"**

<br />

Si tomas tu equipo de operaciones existente, les cambias el titulo a "DevOps Engineer," y nada mas
cambia, no adoptaste DevOps. Renombraste un equipo. DevOps requiere cambio cultural, no solo cambio
de titulo.

<br />

**Anti-patron 2: Comprar herramientas y decir que haces DevOps**

<br />

Comprar una plataforma de CI/CD, un orquestador de containers y una herramienta de monitoreo no te
convierte en una organizacion DevOps. Herramientas sin las practicas y cultura correctas son simplemente
shelfware caro. He visto organizaciones gastar millones en herramientas mientras sus equipos siguen
deployeando manualmente cada dos semanas.

<br />

**Anti-patron 3: Crear un silo de DevOps**

<br />

La ironia de este es dolorosa. DevOps se creo para romper silos entre Dev y Ops. Algunas organizaciones
respondieron creando un tercer silo llamado "el equipo de DevOps" que se sienta entre Dev y Ops.
Ahora tenes tres muros de confusion en lugar de uno.

<br />

**Anti-patron 4: Todas las herramientas, nada de cultura**

<br />

Esto vale la pena repetirlo porque es el error mas comun. Si tus desarrolladores escriben codigo y
despues se lo tiran a alguien mas para que lo deploye, no estas haciendo DevOps sin importar que
herramientas uses. DevOps significa propiedad compartida. El equipo que construye el software es
responsable de correrlo.

<br />

**Anti-patron 5: DevOps significa "los desarrolladores hacen todo"**

<br />

DevOps no significa echar a tu equipo de ops y hacer que los desarrolladores gestionen servidores.
Significa que desarrollo y operaciones trabajan juntos, comparten conocimiento, y ambos contribuyen
a la automatizacion. Los desarrolladores ganan conciencia operativa, y los ingenieros de ops ganan
habilidades de desarrollo. El objetivo es colaboracion, no consolidacion.

<br />

##### **Notas finales**
DevOps es, en su esencia, una idea simple: las personas que construyen software y las personas que lo
corren deberian trabajar juntos, compartir responsabilidad, y usar automatizacion para moverse mas
rapido sin sacrificar estabilidad. Las metricas DORA prueban que este enfoque funciona. Velocidad y
confiabilidad no son opuestos. Van de la mano.

<br />

En el proximo articulo, vamos a empezar con lo practico. Vamos a configurar un entorno de desarrollo,
crear un proyecto TypeScript, inicializar un repositorio Git, y aprender los fundamentos de control
de versiones sobre los que todo lo demas en esta serie se va a construir.

<br />

Espero que te haya resultado util y lo hayas disfrutado! Hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, por favor mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en las [fuentes aca](https://github.com/kainlite/tr)

<br />

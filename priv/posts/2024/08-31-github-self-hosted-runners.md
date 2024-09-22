%{
  title: "Did you know that you can have up to 10000 Github self-hosted runners?",
  author: "Gabriel Garrido",
  description: "In this article we will quickly explore how easy it is to configure a new runner, to build or automate
  any task within github actions",
  tags: ~w(git github tips-and-tricks),
  published: true,
  image: "github-logo.png",
  sponsored: false,
  video: "https://youtu.be/sDjXY5RJX3c",
  lang: "en"
}
---

### **Introduction**
<br />

Did you know that you can have up to 10000 Github self-hosted runners?
Yes you read that correctly, that means you can control your costs, how you organize and manage your CI infrastructure,
by default at this time, GitHub usage limits are pretty high for self-hosted runners, you can read more [here](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#usage-limits).
<br />

This might change, so refer to their docs for an updated version but as of now:
* Job execution time - Each job in a workflow can run for up to 5 days of execution time. If a job reaches this limit, the job is terminated and fails to complete.
* Workflow run time - Each workflow run is limited to 35 days. If a workflow run reaches this limit, the workflow run is cancelled. This period includes execution duration, and time spent on waiting and approval.
* Job queue time - Each job for self-hosted runners that has been queued for at least 24 hours will be canceled. The actual time in queue can reach up to 48 hours before cancellation occurs. If a self-hosted runner does not start executing the job within this limit, the job is terminated and fails to complete.
* API requests - You can execute up to 1,000 requests to the GitHub API in an hour across all actions within a repository. If requests are exceeded, additional API calls will fail which might cause jobs to fail.
* Job matrix - A job matrix can generate a maximum of 256 jobs per workflow run. This limit applies to both GitHub-hosted and self-hosted runners.
* Workflow run queue - No more than 500 workflow runs can be queued in a 10 second interval per repository. If a workflow run reaches this limit, the workflow run is terminated and fails to complete.
* Registering self-hosted runners - You can have a maximum of 10,000 self-hosted runners in one runner group. If this limit is reached, adding a new runner will not be possible.

<br />
You can add a self-hosted runner to a repository, an organization, or an enterprise. 
<br />

### **Why do I need self-hosted runners?**

Let's say you need to build and run software on Linux ARM64, there are no GitHub-hosted runners for that Operative
system and architecture yet.
<br />

At the same time you get full control of your runner, this can be tricky in public repositories where someone could send
a Pull Requests to leak information about your infrastructure, or run some dangerous package, etc, if you are going to
be using this publicly you should spend some time hardening the setup to avoid bad actors, however there are several
alternatives that can work fine.

<br />
Some interesting terraform modules and alternatives:
* https://philips-labs.github.io/terraform-aws-github-runner
* https://github.com/cloudandthings/terraform-aws-github-runners

### **How can I get started with self-hosted runners?**

That's pretty straight-forward, if you are only going to use it from a specific repository you can add it from the
repository settings, here is an example, go to your repository, then actions, then runners, hit the green button to add
a new runner, it should look something like this 👇.

![img1](/images/github-selfhosted-1.png){:class="mx-auto"}

The next step would be to configure it in your node, this of course is not the most reliable way to configure your
runners specially when you need to consider auto-scaling or zero-scaling, or ephemeral runners, however to test things
out or get started is enough.

![img1](/images/github-selfhosted-console-1.png){:class="mx-auto"}

If everything was done correctly, then you should see your node listed in there:
![img1](/images/github-selfhosted-2.png){:class="mx-auto"}

To remove the node just execute the script again as shown in the image.
![img1](/images/github-selfhosted-3.png){:class="mx-auto"}

And that's it, remember be very security concious and heavily restrict the actions that can be performed on your
repository if it is a public repo.

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Sabias que podes tener hasta 10000 ejecutores propios en Github Actions?",
  author: "Gabriel Garrido",
  description: "La forma mas basica de configurar un agente para correr tareas desde GitHub Actions",
  tags: ~w(git github tips-and-tricks),
  published: true,
  image: "github-logo.png",
  sponsored: false,
  video: "https://youtu.be/sDjXY5RJX3c",
  lang: "es"
}
---

### **Introducción**
<br />

¿Sabías que podés tener hasta 10.000 runners auto-hospedados en Github? 
Sí, leíste bien, eso significa que podés controlar tus costos, cómo organizás y gestionás tu infraestructura de CI. 
Por defecto, en este momento, los límites de uso de GitHub son bastante altos para los runners auto-hospedados. Podés leer más [aquí](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#usage-limits).
<br />

Esto puede cambiar, así que revisá su documentación para una versión actualizada, pero por ahora los límites son:
* Tiempo de ejecución del trabajo: Cada trabajo en un workflow puede ejecutarse hasta 5 días. Si se alcanza este límite, el trabajo se cancela y falla.
* Tiempo de ejecución del workflow: Cada ejecución de un workflow está limitada a 35 días. Si se alcanza este límite, la ejecución del workflow se cancela. Este período incluye la duración de la ejecución, el tiempo de espera y la aprobación.
* Tiempo en la cola del trabajo: Cada trabajo para runners auto-hospedados que haya estado en cola por al menos 24 horas se cancelará. El tiempo en cola real puede llegar hasta 48 horas antes de que ocurra la cancelación.
* Solicitudes a la API: Podés ejecutar hasta 1.000 solicitudes a la API de GitHub en una hora en todas las acciones dentro de un repositorio. Si se exceden las solicitudes, las llamadas adicionales a la API fallarán, lo que podría causar que los trabajos fallen.
* Matriz de trabajos: Una matriz de trabajos puede generar un máximo de 256 trabajos por ejecución de workflow. Este límite se aplica tanto a los runners auto-hospedados como a los runners hospedados por GitHub.
* Cola de ejecución de workflows: No más de 500 ejecuciones de workflow pueden estar en cola en un intervalo de 10 segundos por repositorio. Si se alcanza este límite, la ejecución del workflow se termina y falla.
* Registro de runners auto-hospedados: Podés tener un máximo de 10.000 runners auto-hospedados en un grupo de runners. Si se alcanza este límite, no será posible agregar un nuevo runner.

<br />
Podés agregar un runner auto-hospedado a un repositorio, una organización o una empresa.
<br />

### **¿Por qué necesito runners auto-hospedados?**

Imaginá que necesitás construir y ejecutar software en Linux ARM64. Todavía no hay runners hospedados por GitHub para ese sistema operativo y arquitectura.
<br />

Además, obtenés control total de tu runner. Esto puede ser complicado en repositorios públicos donde alguien podría enviar un Pull Request para filtrar información sobre tu infraestructura o ejecutar un paquete peligroso, etc. Si vas a usar esto en público, deberías dedicar tiempo a endurecer la configuración para evitar malos actores. Sin embargo, hay varias alternativas que pueden funcionar bien.

<br />
Algunos módulos de terraform interesantes y alternativas:
* https://philips-labs.github.io/terraform-aws-github-runner
* https://github.com/cloudandthings/terraform-aws-github-runners

### **¿Cómo puedo comenzar con los runners auto-hospedados?**

Es bastante simple. Si solo lo vas a usar desde un repositorio específico, podés agregarlo desde la configuración del repositorio. Aquí tenés un ejemplo: andá a tu repositorio, luego a "actions", luego a "runners", y hacé clic en el botón verde para agregar un nuevo runner. Debería verse algo así 👇.

![img1](/images/github-selfhosted-1.png){:class="mx-auto"}

El siguiente paso sería configurarlo en tu nodo. Esto, por supuesto, no es la forma más confiable de configurar tus runners, especialmente cuando necesitás considerar el auto-escalado, el escalado a cero, o runners efímeros. Sin embargo, para probar o comenzar es suficiente.

![img1](/images/github-selfhosted-console-1.png){:class="mx-auto"}

Si todo se hizo correctamente, deberías ver tu nodo listado allí:
![img1](/images/github-selfhosted-2.png){:class="mx-auto"}

Para eliminar el nodo, simplemente ejecutá el script nuevamente como se muestra en la imagen.
![img1](/images/github-selfhosted-3.png){:class="mx-auto"}

Y eso es todo. Recordá ser muy consciente de la seguridad y restringir fuertemente las acciones que se pueden realizar en tu repositorio si es un repositorio público.

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

También podés revisar el código fuente y los cambios en los [sources aquí](https://github.com/kainlite/tr)

<br />

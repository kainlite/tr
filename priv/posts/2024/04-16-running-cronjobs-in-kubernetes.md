%{
  title: "Scheduled tasks in your elixir application",
  author: "Gabriel Garrido",
  description: "In this article we will see how to create and run tasks automatically with the help of kubernetes, in
  this particular scenario for the blog and also specifically for a phoenix web app, while the kubernetes part is
  general enough, there are some interesting things to learn about the elixir ecosystem as well.",
  tags: ~w(elixir kubernetes phoenix tips-and-tricks),
  published: true,
  image: "trickster-cool.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Introduction**

![trickster](/images/trickster-cool.png){:class="mx-auto" style="max-height: 450px;"}
In case you are wondering about the image, it is intended to represent the trickster, as I plan to do many posts about
tips and tricks.
<br/> 

In this article we will explore how to run scheduled tasks using the 
[CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) resource in kubernetes, you might be 
wondering when to use this instead of creating your gen_server for example and dealing with it from the application
itself, the answer is pretty simple, everytime that you need to run a repeating specific task, for example: create a
daily backup, send some daily statistics, etc, it would be still doable and completely ok to do it with elixir for
example using the [quantum-core](https://github.com/quantum-elixir/quantum-core) app (hint: a subsequent post will possibly be
about testing this approach 😉).
<br/> 

### When to use each option? key differences?

#### Home-made scheduler:
* Flexible
* Tailored to your needs
* Might require a deployment to change/update the schedule/tasks
* More load on the beam as more apps will be running

#### External scheduler (k8s cronjobs, regular vm cronjob, etc)
* Slight delay at startup (similar to cold starts, requires more preparation)
* Easier to change/update schedule without redeploying
* Logging and history are easily preserved (and configurable)
* History and job preservation are easily configurable.
* More load on the k8s API server.

#### Library or app (cron-like, for example quantum-core)
* Very similar to a regular cronjob 
* Super flexible
* Might require a deployment to change/update the schedule/tasks
* More load on the beam as more apps will be running

### Some questions
Some questions you might ask yourself before scheduling a task:
* Can it safely be run concurrently? given that for example the previous one didn't finish for example.
* How often does it need to run?
* Does it need to alter any data besides what the task is in charge of? for example setting something up beforehand
  (script)

And there could be many more questions that you can ask yourself before creating an scheduled task, but for now that
will do.
<br/> 

### **Scenarios**
We have actually two cronjobs running each at different times, but we will explore the second one only as the
configuration is very similar between the two of them, the second cronjob if you are curious is a bit more contrived and
needs some serious refactors, this one basically does sentiment analysis on the comments using ollama then it approves 
comments automatically if the sentiment is neutral or positive, the other cronjob is in charge of sending an email 
notification everyday at 00:00 server time about the new posts to the subscribers of the blog (registered accounts) if
you are curious and want to check it out.
<br/> 
Enough preamble, let's get to business, there are some interesting things in there, for example using 
`concurrencyPolicy: Forbid` we can let kubernetes know that we don't want another pod to replace it
or to run concurrenly (the other options are `Allow` and `Replace`), since we need to boot our application we need some
secrets present in order to be able to send emails and connect to the database, the rest is pretty straight forward and
not specific to this task, except the command, that's probably the most interesting bit in there, by calling the release
of the app with `eval` we can call our module in this case the function `Tr.Tracker.start`.
<br/> 
Note: by default cronjobs keep the last 3 runs for successful jobs and 1 for failed jobs, that's configurable under the 
keys: `.spec.successfulJobsHistoryLimit`, `.spec.failedJobsHistoryLimit`.
```elixir
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tr-approver
  namespace: tr
  labels:
    name: tr
spec:
  concurrencyPolicy: Forbid
  schedule: "00 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
          imagePullSecrets:
          - name: regcred
          containers:
          - name: tr
            image: kainlite/tr:master
            command:
              - /app/bin/tr
              - eval
              - Tr.Approver.start
            envFrom:
            - secretRef:
                name: tr-postgres-config
            - secretRef:
                name: tr-mailer-config
            env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: status.podIP
            securityContext:
              allowPrivilegeEscalation: false
            imagePullPolicy: Always
          restartPolicy: Never
```
<br/> 
Let's explore the code a bit, the example is great to see how to start the apps and use the beam almost in headless 
manner, almost like a lambda function if you like, as you might notice start basically ensures that our app and all
required apps are running before doing any actual job, this is required given the way the apps work in the BEAM,
basically it fetches all comments that have not been yet approved and sends it to Ollama, the model has been configured
to answer: positive, neutral or negative depending on the text provided in the comment, if it believes that the comment
is ok, then it is approved automatically without human intervention, otherwise it stays unapproved, there are several
improvements that can be done here, but for now it gets the job done.

<br/> 
[lib/tr/approver.ex](https://github.com/kainlite/tr/blob/master/lib/tr/approver.ex)
```elixir
defmodule Tr.Approver do
  @moduledoc """
  Basic task runner to approve comments if they pass sentiment analysis
  """
  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  If the llama agrees upon the sentiment then the comment can be automatically approved
  """
  def check_comment_sentiment(comment) do
    ollama_sentiment = Tr.Ollama.send(comment.body)

    ollama_sentiment
  end

  def start do
    start_app()

    comments = Tr.Post.get_unapproved_comments()

    Enum.each(comments, fn comment ->
      if check_comment_sentiment(comment) do
        Tr.Post.approve_comment(comment)
      end
    end)
  end
end
```
   
<br/> 
Curious about how to talk to Ollama from elixir? 

[lib/tr/ollama.ex](https://github.com/kainlite/tr/blob/master/lib/tr/ollama.ex)
```elixir
defmodule Tr.Ollama do
  @moduledoc """
  FROM orca-mini

  PARAMETER temperature 0.2

  MESSAGE user thank you, this was really useful for me
  MESSAGE assistant POSITIVE
  MESSAGE user you should do something else, this is really bad
  MESSAGE assistant NEGATIVE
  MESSAGE user this has nothing to do with this post
  MESSAGE assistant NEUTRAL

  SYSTEM You are a sentiment analyzer. You will receive text and output only one word, either POSITIVE or NEGATIVE or NEUTRAL, depending on the sentiment of the text
  """

  def send(message) do
    api = api()
    p = %Ollamex.PromptRequest{model: "sentiments:latest", prompt: "MESSAGE " <> message}

    case Ollamex.generate_with_timeout(p, api) do
      {:error, :timeout} -> false
      {:ok, r} -> parse(r.response)
    end
  end

  defp api do
    Ollamex.API.new(System.get_env("OLLAMA_ENDPOINT", "http://localhost:11434/api"))
  end

  defp parse(r) do
    clean = r |> String.downcase() |> String.trim()

    clean =
      cond do
        String.contains?(clean, ":") ->
          String.split(clean, ":") |> List.last() |> String.trim()

        String.contains?(clean, ".") ->
          String.split(clean, ".") |> List.first() |> String.trim()
      end

    case clean do
      "neutral" -> true
      "positive" -> true
      "negative" -> false
    end
  end
end
```
The code is very simplistic, by reading it now after some time I see many improvements and refactors that can be done,
but that's for a future episode 😆!
<br/> 
Any questions? Drop a comment 👇, you might need to wait 60 minutes for the job to run before it can be read 😄, but at
least now you know how it works!

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Tareas programadas en tu applicacion elixir o phoenix",
  author: "Gabriel Garrido",
  description: "Tareas programadas en Elixir/Erlang.",
  tags: ~w(elixir kubernetes phoenix tips-and-tricks),
  published: true,
  image: "trickster-cool.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**

![trickster](/images/trickster-cool.png){:class="mx-auto" style="max-height: 450px;"}
Por si te lo preguntás, la imagen está pensada para representar al trickster, ya que planeo hacer muchas publicaciones sobre tips y trucos.
<br/>

En este artículo exploraremos cómo ejecutar tareas programadas utilizando el recurso [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) en Kubernetes. Podrías preguntarte cuándo usar esto en lugar de crear tu propio gen_server y manejarlo desde la aplicación misma. La respuesta es bastante simple: cada vez que necesites ejecutar una tarea específica de manera repetitiva, por ejemplo: crear un respaldo diario, enviar estadísticas diarias, etc. Aún sería posible y completamente válido hacerlo con Elixir usando la app [quantum-core](https://github.com/quantum-elixir/quantum-core) (pista: posiblemente un próximo post trate sobre probar este enfoque 😉).
<br/>

### ¿Cuándo usar cada opción? Principales diferencias:

#### Programador casero:
* Flexible.
* Adaptado a tus necesidades.
* Puede requerir un deployment para cambiar/actualizar la programación o tareas.
* Más carga sobre el BEAM, ya que más apps estarán corriendo.

#### Programador externo (cronjobs en k8s, cronjob en máquinas virtuales, etc.):
* Ligeramente más lento en el arranque (similar a los "cold starts", requiere más preparación).
* Más fácil cambiar/actualizar la programación sin hacer un redeployment.
* El registro y el historial se preservan fácilmente (y son configurables).
* Historial y conservación de trabajos fácilmente configurables.
* Más carga sobre el API server de k8s.

#### Librería o app (tipo cron, como quantum-core):
* Muy similar a un cronjob regular.
* Súper flexible.
* Puede requerir un deployment para cambiar/actualizar la programación o tareas.
* Más carga sobre el BEAM, ya que más apps estarán corriendo.

### Algunas preguntas
Algunas preguntas que podrías hacerte antes de programar una tarea:
* ¿Puede ejecutarse de manera concurrente de forma segura? ¿Qué pasa si la tarea anterior no terminó, por ejemplo?
* ¿Con qué frecuencia necesita ejecutarse?
* ¿Necesita alterar algún dato fuera de la tarea en sí? Por ejemplo, preparar algo previamente (script).

Y muchas más preguntas podrían surgir antes de crear una tarea programada, pero por ahora esto debería ser suficiente.
<br/>

### **Escenarios**
Tenemos dos cronjobs ejecutándose en diferentes momentos, pero exploraremos solo el segundo, ya que la configuración es muy similar entre ambos. Este cronjob hace un análisis de sentimientos en los comentarios usando Ollama, luego aprueba automáticamente aquellos comentarios que sean neutrales o positivos. El otro cronjob envía una notificación por correo electrónico diariamente a las 00:00 (hora del servidor) sobre las nuevas publicaciones a los suscriptores del blog (cuentas registradas), por si tenías curiosidad y querés echarle un vistazo.
<br/>
Basta de preámbulos, vamos al grano. Hay cosas interesantes como el uso de `concurrencyPolicy: Forbid`, que le indica a Kubernetes que no queremos que otro pod reemplace o ejecute el cronjob de manera concurrente (las otras opciones son `Allow` y `Replace`). Como necesitamos iniciar nuestra aplicación, también necesitamos que algunos secretos estén presentes para poder enviar correos y conectarnos a la base de datos. El resto es bastante sencillo y no específico de esta tarea, excepto por el comando, que probablemente sea la parte más interesante. Al llamar a la release de la app con `eval`, podemos ejecutar nuestro módulo, en este caso, la función `Tr.Tracker.start`.
<br/>
Nota: por defecto, los cronjobs conservan las últimas 3 ejecuciones exitosas y 1 fallida, configurable bajo las claves: `.spec.successfulJobsHistoryLimit`, `.spec.failedJobsHistoryLimit`.

```elixir
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tr-approver
  namespace: tr
  labels:
    name: tr
spec:
  concurrencyPolicy: Forbid
  schedule: "00 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
          imagePullSecrets:
          - name: regcred
          containers:
          - name: tr
            image: kainlite/tr:master
            command:
              - /app/bin/tr
              - eval
              - Tr.Approver.start
            envFrom:
            - secretRef:
                name: tr-postgres-config
            - secretRef:
                name: tr-mailer-config
            env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  apiVersion: v1
                  fieldPath: status.podIP
            securityContext:
              allowPrivilegeEscalation: false
            imagePullPolicy: Always
          restartPolicy: Never
```
<br/>
Exploremos el código un poco. Este ejemplo es excelente para ver cómo iniciar las apps y usar el BEAM de manera casi "headless", casi como una función Lambda si querés. Como notarás, el `start` asegura que nuestra app y todas las aplicaciones necesarias estén corriendo antes de hacer cualquier trabajo. Esto es necesario debido a cómo funcionan las apps en el BEAM. Básicamente, busca todos los comentarios que aún no han sido aprobados y los envía a Ollama. El modelo está configurado para responder: positivo, neutral o negativo dependiendo del texto en el comentario. Si considera que el comentario es aceptable, se aprueba automáticamente sin intervención humana; de lo contrario, queda sin aprobar. Hay varias mejoras que se pueden hacer aquí, pero por ahora hace el trabajo.

<br/>
[lib/tr/approver.ex](https://github.com/kainlite/tr/blob/master/lib/tr/approver.ex)
```elixir
defmodule Tr.Approver do
  @moduledoc """
  Tarea básica para aprobar comentarios si pasan el análisis de sentimiento
  """
  @app :tr

  defp load_app do
    Application.load(@app)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  @doc """
  Si la llama está de acuerdo con el sentimiento, entonces el comentario puede ser aprobado automáticamente
  """
  def check_comment_sentiment(comment) do
    ollama_sentiment = Tr.Ollama.send(comment.body)

    ollama_sentiment
  end

  def start do
    start_app()

    comments = Tr.Post.get_unapproved_comments()

    Enum.each(comments, fn comment ->
      if check_comment_sentiment(comment) do
        Tr.Post.approve_comment(comment)
      end
    end)
  end
end
```
   
<br/>
¿Curioso sobre cómo interactuar con Ollama desde Elixir?

[lib/tr/ollama.ex](https://github.com/kainlite/tr/blob/master/lib/tr/ollama.ex)
```elixir
defmodule Tr.Ollama do
  @moduledoc """
  FROM orca-mini

  PARAMETER temperature 0.2

  SYSTEM Eres un analizador de sentimientos. Recibirás un texto y solo deberás devolver una palabra: POSITIVE, NEGATIVE o NEUTRAL, dependiendo del sentimiento del texto.
  """

  def send(message) do
    api = api()
    p = %Ollamex.PromptRequest{model: "sentiments:latest", prompt: "MESSAGE " <> message}

    case Ollamex.generate_with_timeout(p, api) do
      {:error, :timeout} -> false
      {:ok, r} -> parse(r.response)
    end
  end

  defp api do
    Ollamex.API.new(System.get_env("OLLAMA_ENDPOINT", "http://localhost:11434/api"))
  end

  defp parse(r) do
    clean = r |> String.downcase() |> String.trim()

    clean =
      cond do
        String.contains?(clean, ":") ->
          String.split(clean, ":") |> List.last() |> String.trim()

        String.contains?(clean, ".") ->
          String.split(clean, ".") |> List.first() |> String.trim()
      end

    case clean do
      "neutral" -> true
      "positive" -> true
      "negative" -> false
    end
  end
end
```
El código es muy simple. Al leerlo ahora, después de un tiempo, veo muchas mejoras y refactorizaciones que se podrían hacer, ¡pero eso será para un futuro episodio 😆!
<br/>
¿Tenés alguna pregunta? Dejá un comentario 👇, es posible que tengas que esperar 60 minutos para que la tarea se ejecute antes de que puedas leerla 😄, ¡pero al menos ahora ya sabés cómo funciona!

##### **Errata**
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para que se pueda corregir.

También podés revisar el código fuente y los cambios en los [sources aquí](https://github.com/kainlite/tr)

<br/>

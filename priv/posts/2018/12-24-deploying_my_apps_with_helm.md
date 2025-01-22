%{
  title: "Deploying my apps with Helm",
  author: "Gabriel Garrido",
  description: "How to use helm from the cli...",
  tags: ~w(kubernetes helm),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Deploying my apps with Helm**

If you are already familiar with [Helm](https://helm.sh/), and the different types of kubernetes workloads / resource types you might be wondering how to install apps directly to kubernetes, yes, you don't have to re-invent the wheel for your mysql installation, or your postgres, or nginx, jenkins, You name it. Helm solves that problem with [Charts](https://github.com/helm/charts), this list has the official charts maintained by the community, where the folder incubator may refer to charts that are still not compliant with the [technical requirements](https://github.com/helm/charts/blob/master/CONTRIBUTING.md#technical-requirements) but probably usable and the folder stable is for _graduated_ charts. This is not the only source of charts as you can imagine, You can use any source for your charts, even just the [tgz](https://docs.helm.sh/using_helm/#helm-install-installing-a-package) files, as we will see in this post.
<br />

How do I search for charts?:

```elixir
$ helm search wordpress
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
stable/wordpress        3.3.0           4.9.8           Web publishing platform for building blogs and websites.
```
<br />
Note that I'm not a fan of Wordpress or PHP itself, but it seems like the most common example everywhere. As we can see here it says stable/wordpress so we know that we're using the official repo in the folder stable, but what if we don't want that chart, but someone else provides one with more features or something that You like better. Let's use the one from [Bitnami](https://bitnami.com/stack/wordpress/helm), so if we check their page you can select different kind of deployments but for it to work we need to add another external repo:
```elixir
helm repo add bitnami https://charts.bitnami.com/bitnami
```
<br />
So if we search again we will now see two options (at the moment of this writing, the latest version is actually 5.0.2):
```elixir
$ helm search wordpress
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
bitnami/wordpress       5.0.2           5.0.2           Web publishing platform for building blogs and websites.
stable/wordpress        3.3.0           4.9.8           Web publishing platform for building blogs and websites.
```
Let's check the [documentation](https://github.com/helm/charts/tree/master/stable/wordpress) of the chart to create our `values.yaml` file, note that in this example the stable wordpress chart it's also maintained by Bitnami, so they have the same configuration :), this won't always be the case but it simplifies things for us.
<br />

Our example `values.yaml` will look like:
```elixir
wordpressBlogName: "Testing Helm Charts"
persistence:
  size: 1Gi
ingress:
  enabled: true
```
<br />
We will only change the blog name by default, the persistent volume size and also enable [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) (Our app should be available through `wordpress.local` inside the cluster), if you are using minikube be sure to enable the [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) addon.
```elixir
$ minikube addons enable ingress
ingress was successfully enabled
```
<br />

We can then install `stable/wordpress` or `bitnami/wordpress`, we will follow up with the one from Bitnami repo.
```elixir
$ helm install bitnami/wordpress \
--set image.repository=bitnami/wordpress \
--set image.tag=5.0.2 \
-f values.yaml
```
As it's a common good practice to use specific versions we will do it here, it's better to do it this way because you can easily move between known versions and also avoid unknown states, this can happen by misunderstanding what latest means, [follow the example](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).
<br />

You should see something like:
```elixir
NAME:   plucking-condor
LAST DEPLOYED: Mon Dec 24 13:06:38 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Pod(related)
NAME                                        READY  STATUS             RESTARTS  AGE
plucking-condor-wordpress-84845db8b5-hkqhc  0/1    ContainerCreating  0         0s
plucking-condor-mariadb-0                   0/1    Pending            0         0s

==> v1/Secret

NAME                       AGE
plucking-condor-mariadb    0s
plucking-condor-wordpress  0s

==> v1/ConfigMap
plucking-condor-mariadb        0s
plucking-condor-mariadb-tests  0s

==> v1/PersistentVolumeClaim
plucking-condor-wordpress  0s

==> v1/Service
plucking-condor-mariadb    0s
plucking-condor-wordpress  0s

==> v1beta1/Deployment
plucking-condor-wordpress  0s

==> v1beta1/StatefulSet
plucking-condor-mariadb  0s

==> v1beta1/Ingress
wordpress.local-plucking-condor  0s


NOTES:
1. Get the WordPress URL:

  You should be able to access your new WordPress installation through
  http://wordpress.local/admin

2. Login with the following credentials to see your blog

  echo Username: user
  echo Password: $(kubectl get secret --namespace default plucking-condor-wordpress -o jsonpath="{.data.wordpress-password}" | base64 --decode)
```
Depending on the cluster provider or installation itself, you might need to replace the `persistence.storageClass` to match what your cluster has, note that in the values file is represented like JSON with dot notation but in your `values.yaml` you need to stick to YAML format and indent `storageClass` under persistence as usual, the kubernetes API parses and uses JSON but YAML seems more human friendly.
<br />

At this point we should a working wordpress installation, also move between versions, but be aware that the application is in charge of the database schema and updating it to match what the new version needs, this can also be troublesome rolling back or when downgrading, so if you use persistent data *ALWAYS* have a working backup, because when things go south, you will want to quickly go back to a known state, also note that I said "working backup", yes, test that the backup works and that You can restore it somewhere else before doing anything destructive or that can has repercussions, this will bring you peace of mind and better ways to organize yourself while upgrading, etc.
<br />

Now let's check that all resources are indeed working and that we can use our recently installed app.
```elixir
$ kubectl get all
NAME                                             READY     STATUS        RESTARTS   AGE
pod/plucking-condor-mariadb-0                    1/1       Running       0          12m
pod/plucking-condor-wordpress-84845db8b5-hkqhc   1/1       Running       0          12m

NAME                                TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
service/kubernetes                  ClusterIP      10.96.0.1        <none>           443/TCP                      37h
service/plucking-condor-mariadb     ClusterIP      10.106.219.59    <none>           3306/TCP                     12m
service/plucking-condor-wordpress   LoadBalancer   10.100.239.163   10.100.239.163   80:31764/TCP,443:32308/TCP   12m

NAME                                        DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/plucking-condor-wordpress   1         1         1            1           12m

NAME                                                   DESIRED   CURRENT   READY     AGE
replicaset.apps/plucking-condor-wordpress-84845db8b5   1         1         1         12m

NAME                                       DESIRED   CURRENT   AGE
statefulset.apps/plucking-condor-mariadb   1         1         12m
```
You can deploy it to a custom namespace (In this case I deployed it to the default namespace), the only change for that would be to set the parameter `--namespace` in the `helm install` line.
<br />

If you use minikube then ingress will expose a nodeport that we can find using `minikube service list` then using the browser or curl to navigate our freshly installed wordpress.
```elixir
 $ minikube service list
|-------------|---------------------------|--------------------------------|
|  NAMESPACE  |           NAME            |              URL               |
|-------------|---------------------------|--------------------------------|
| default     | kubernetes                | No node port                   |
| default     | plucking-condor-mariadb   | No node port                   |
| default     | plucking-condor-wordpress | http://192.168.99.100:31764    |
|             |                           | http://192.168.99.100:32308    |
| kube-system | default-http-backend      | http://192.168.99.100:30001    |
| kube-system | kube-dns                  | No node port                   |
| kube-system | kubernetes-dashboard      | No node port                   |
| kube-system | tiller-deploy             | No node port                   |
|-------------|---------------------------|--------------------------------|
```
In the cloud or on premises this will indeed be different and you should have a publicly available installation using your own domain name (In this case http is at: http://192.168.99.100:31764 and https at: http://192.168.99.100:32308, and http://192.168.99.100:30001 is the default backend for the ingress controller), your ips can be different but the basics are the same.

Sample screenshot:

![img](/images/wordpress-example.webp){:class="mx-auto"}

### Notes
As long as we have the [persistent volume](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) our data should be preserved in this case the PV is used for tha database, but we could add another volume to preserve images, etc.

Clean everything up:
```elixir
helm del --purge plucking-condor
```


That's all I have for now, I will be adding more content next week.
<br />

### Don't Repeat Yourself
DRY is a good design goal and part of the art of a good template is knowing when to add a new template and when to update or use an existing one. While helm and go helps with that, there is no perfect tool so we will explore other options in the following posts, explore what the community provides and what seems like a suitable tool for you. Happy Helming!.
<br />

### Upcoming topics
The following posts will be about package managers, development deployment tools, etc. It's hard to put all the tools in a category, but they are trying to solve similar problems in different ways, and we will be exploring the ones that seem more promising to me, if you would like me to cover any other tool/project/whatever, just send me a message :)

* Getting started with Ksonnet and friends.
* Getting started with Skaffold.
* Getting started with Gitkube.

<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Desplegando aplicaciones con Helm",
  author: "Gabriel Garrido",
  description: "En este articulo vamos a ver como usar helm desde la terminal en mas detalle...",
  tags: ~w(kubernetes helm),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Desplegando applicaciones con Helm**

Si ya estás familiarizado con Helm y los diferentes tipos de workloads/tipos de recursos de Kubernetes, podrías preguntarte cómo instalar aplicaciones directamente en Kubernetes. Sí, no tienes que reinventar la rueda para tu instalación de MySQL, o tu Postgres, o Nginx, Jenkins, lo que sea. Helm resuelve ese problema con Charts. Esta lista contiene los charts oficiales mantenidos por la comunidad, donde la carpeta 'incubator' puede referirse a charts que aún no cumplen con los requisitos técnicos pero probablemente utilizables, y la carpeta 'stable' es para charts graduados. Como puedes imaginar, esta no es la única fuente de charts. Puedes usar cualquier fuente para tus charts, incluso los archivos tgz, como veremos en este post. <br />

¿Cómo busco charts?:
<br />

```elixir
$ helm search wordpress
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
stable/wordpress        3.3.0           4.9.8           Web publishing platform for building blogs and websites.
```
<br />
Nota que no soy fan de WordPress o PHP en sí, pero parece ser el ejemplo más común en todas partes. Como vemos aquí, dice stable/wordpress, así que sabemos que estamos usando el repositorio oficial en la carpeta 'stable'. Pero, ¿y si no queremos ese chart, sino que alguien más proporciona uno con más características o algo que te guste más? Usemos el de [Bitnami](https://bitnami.com/stack/wordpress/helm). Si revisamos su página, puedes seleccionar diferentes tipos de despliegues, pero para que funcione necesitamos añadir otro repositorio externo:
```elixir
helm repo add bitnami https://charts.bitnami.com/bitnami
```
<br />
sí que si buscamos de nuevo, ahora veremos dos opciones (en el momento de escribir esto, la versión más reciente es en realidad la 5.0.2): 
```elixir
$ helm search wordpress
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
bitnami/wordpress       5.0.2           5.0.2           Web publishing platform for building blogs and websites.
stable/wordpress        3.3.0           4.9.8           Web publishing platform for building blogs and websites.
```
Revisemos la [documentación](https://github.com/helm/charts/tree/master/stable/wordpress) del chart para crear nuestro archivo `values.yaml`. Nota que en este ejemplo el chart de WordPress estable también es mantenido por Bitnami, así que tienen la misma configuración :). Esto no siempre será el caso, pero nos simplifica las cosas.
<br />

Nuestro ejemplo de `values.yaml` se verá así:
```elixir
wordpressBlogName: "Testing Helm Charts"
persistence:
  size: 1Gi
ingress:
  enabled: true
```
<br />
Solo cambiaremos el nombre del blog por defecto, el tamaño del volumen persistente y también habilitaremos [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) (nuestra aplicación debería estar disponible a través de `wordpress.local` dentro del clúster). Si estás usando Minikube, asegúrate de habilitar el addon de [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/).
```elixir
$ minikube addons enable ingress
ingress was successfully enabled
```
<br />

Podemos entonces instalar `stable/wordpress` o `bitnami/wordpress`; continuaremos con el del repositorio de Bitnami.
```elixir
$ helm install bitnami/wordpress \
--set image.repository=bitnami/wordpress \
--set image.tag=5.0.2 \
-f values.yaml
```
Como es una buena práctica usar versiones específicas, lo haremos aquí. Es mejor hacerlo de esta manera porque puedes moverte fácilmente entre versiones conocidas y también evitar estados desconocidos; esto puede suceder al malinterpretar lo que significa 'latest'. Sigue el ejemplo.
<br />

Deberías ver algo como:
```elixir
NAME:   plucking-condor
LAST DEPLOYED: Mon Dec 24 13:06:38 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Pod(related)
NAME                                        READY  STATUS             RESTARTS  AGE
plucking-condor-wordpress-84845db8b5-hkqhc  0/1    ContainerCreating  0         0s
plucking-condor-mariadb-0                   0/1    Pending            0         0s

==> v1/Secret

NAME                       AGE
plucking-condor-mariadb    0s
plucking-condor-wordpress  0s

==> v1/ConfigMap
plucking-condor-mariadb        0s
plucking-condor-mariadb-tests  0s

==> v1/PersistentVolumeClaim
plucking-condor-wordpress  0s

==> v1/Service
plucking-condor-mariadb    0s
plucking-condor-wordpress  0s

==> v1beta1/Deployment
plucking-condor-wordpress  0s

==> v1beta1/StatefulSet
plucking-condor-mariadb  0s

==> v1beta1/Ingress
wordpress.local-plucking-condor  0s


NOTES:
1. Get the WordPress URL:

  You should be able to access your new WordPress installation through
  http://wordpress.local/admin

2. Login with the following credentials to see your blog

  echo Username: user
  echo Password: $(kubectl get secret --namespace default plucking-condor-wordpress -o jsonpath="{.data.wordpress-password}" | base64 --decode)
```
Dependiendo del proveedor del clúster o de la instalación en sí, podrías necesitar reemplazar `persistence.storageClass` para que coincida con lo que tiene tu clúster. Nota que en el archivo de valores se representa como JSON con notación de puntos, pero en tu `values.yaml` necesitas ceñirte al formato YAML e indentar storageClass bajo persistence como de costumbre. La API de Kubernetes analiza y usa JSON, pero YAML parece más amigable para los humanos.
<br />

En este punto deberíamos tener una instalación de WordPress funcionando y también movernos entre versiones. Pero ten en cuenta que la aplicación se encarga del esquema de la base de datos y de actualizarlo para que coincida con lo que necesita la nueva versión. Esto también puede ser problemático al revertir o al degradar. Así que si usas datos persistentes, SIEMPRE ten una copia de seguridad funcional, porque cuando las cosas van mal, querrás volver rápidamente a un estado conocido. También nota que dije "copia de seguridad funcional": sí, prueba que la copia de seguridad funcione y que puedas restaurarla en otro lugar antes de hacer algo destructivo o que pueda tener repercusiones. Esto te brindará tranquilidad y mejores maneras de organizarte mientras actualizas, etc.
<br />

Ahora verifiquemos que todos los recursos están realmente funcionando y que podemos usar nuestra aplicación recién instalada.
```elixir
$ kubectl get all
NAME                                             READY     STATUS        RESTARTS   AGE
pod/plucking-condor-mariadb-0                    1/1       Running       0          12m
pod/plucking-condor-wordpress-84845db8b5-hkqhc   1/1       Running       0          12m

NAME                                TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)                      AGE
service/kubernetes                  ClusterIP      10.96.0.1        <none>           443/TCP                      37h
service/plucking-condor-mariadb     ClusterIP      10.106.219.59    <none>           3306/TCP                     12m
service/plucking-condor-wordpress   LoadBalancer   10.100.239.163   10.100.239.163   80:31764/TCP,443:32308/TCP   12m

NAME                                        DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/plucking-condor-wordpress   1         1         1            1           12m

NAME                                                   DESIRED   CURRENT   READY     AGE
replicaset.apps/plucking-condor-wordpress-84845db8b5   1         1         1         12m

NAME                                       DESIRED   CURRENT   AGE
statefulset.apps/plucking-condor-mariadb   1         1         12m
```

Puedes desplegarlo en un espacio de nombres personalizado (en este caso lo desplegué en el espacio de nombres por defecto); el único cambio para eso sería establecer el parámetro --namespace en la línea de helm install. <br />

<br />

Si usas Minikube, entonces ingress expondrá un nodeport que podemos encontrar usando minikube service list y luego, usando el navegador o curl, navegar por nuestro WordPress recién instalado.
```elixir
 $ minikube service list
|-------------|---------------------------|--------------------------------|
|  NAMESPACE  |           NAME            |              URL               |
|-------------|---------------------------|--------------------------------|
| default     | kubernetes                | No node port                   |
| default     | plucking-condor-mariadb   | No node port                   |
| default     | plucking-condor-wordpress | http://192.168.99.100:31764    |
|             |                           | http://192.168.99.100:32308    |
| kube-system | default-http-backend      | http://192.168.99.100:30001    |
| kube-system | kube-dns                  | No node port                   |
| kube-system | kubernetes-dashboard      | No node port                   |
| kube-system | tiller-deploy             | No node port                   |
|-------------|---------------------------|--------------------------------|
```
En la nube o en instalaciones locales, esto será diferente y deberías tener una instalación disponible públicamente usando tu propio nombre de dominio (en este caso, HTTP está en: http://192.168.99.100:31764 y HTTPS en: http://192.168.99.100:32308, y http://192.168.99.100:30001 es el backend predeterminado para el controlador de ingress). Tus IPs pueden ser diferentes, pero los fundamentos son los mismos.

Ejemplo:

![img](/images/wordpress-example.webp){:class="mx-auto"}

### Notes
Mientras tengamos el volumen persistente, nuestros datos deberían preservarse. En este caso, el PV se usa para la base de datos, pero podríamos agregar otro volumen para preservar imágenes, etc.

Limpiando:
```elixir
helm del --purge plucking-condor
```

Eso es todo por ahora; estaré agregando más contenido la próxima semana.
<br />

### Don't Repeat Yourself
DRY es un buen objetivo de diseño y parte del arte de una buena plantilla es saber cuándo añadir una nueva plantilla y cuándo actualizar o usar una existente. Aunque Helm y Go ayudan con eso, no hay una herramienta perfecta, así que exploraremos otras opciones en los siguientes posts. Exploraremos lo que la comunidad proporciona y lo que parece una herramienta adecuada para ti. ¡Happy Helming!
<br />

### Proximos temas

* Empezando con Ksonnet y amigos.
* Empezando con Skaffold.
* Empezando con Gitkube.

<br />

### Erratas
Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />

%{
  title: "Exploring some Istio features",
  author: "Gabriel Garrido",
  description: "Continue building on Istio and understand how can be used...",
  tags: ~w(kubernetes istio),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### Introduction
This article builds up on what we did in the [last article](/blog/why_do_i_need_a_service_mesh), so refer to that one before starting this one, if you are planing to follow the documentation examples you will find many similarities since I based this article on that.
<br />

In this example I will be using [Digital Ocean](https://m.do.co/c/01d040b789de) (that's my referral link), note that I do not have any association with Digital Ocean but they give you $100 to test their products for 60 days, if you spend $25 I get another $25.
<br />

### Before starting a few concepts
* A VirtualService defines the rules that control how requests for a service are routed within an Istio service mesh.
* A DestinationRule configures the set of policies to be applied to a request after VirtualService routing has occurred.
* A ServiceEntry is commonly used to enable requests to services outside of an Istio service mesh.
* A Gateway configures a load balancer for HTTP/TCP traffic, most commonly operating at the edge of the mesh to enable ingress traffic for an application.
These basic concepts will help you understand the manifest that we are going to see.
<br />

### Let's get started
We already have the bookinfo project deployed and using all three versions of the service (ratings) but we will need to make some changes to test route based on user identity, you can check the configuration with:
```elixir
$ kubectl get destinationrules -o yaml
apiVersion: v1
items:
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"details","namespace":"default"},"spec":{"host":"details","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"}]}}
    creationTimestamp: 2019-01-11T00:58:54Z
    generation: 1
    name: details
    namespace: default
    resourceVersion: "921688"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/details
    uid: 11490656-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: details
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"productpage","namespace":"default"},"spec":{"host":"productpage","subsets":[{"labels":{"version":"v1"},"name":"v1"}]}}
    creationTimestamp: 2019-01-11T00:58:53Z
    generation: 1
    name: productpage
    namespace: default
    resourceVersion: "921684"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/productpage
    uid: 10a42a24-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: productpage
    subsets:
    - labels:
        version: v1
      name: v1
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"ratings","namespace":"default"},"spec":{"host":"ratings","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"},{"labels":{"version":"v2-mysql"},"name":"v2-mysql"},{"labels":{"version":"v2-mysql-vm"},"name":"v2-mysql-vm"}]}}
    creationTimestamp: 2019-01-11T00:58:54Z
    generation: 1
    name: ratings
    namespace: default
    resourceVersion: "921686"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/ratings
    uid: 111299e1-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: ratings
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
    - labels:
        version: v2-mysql
      name: v2-mysql
    - labels:
        version: v2-mysql-vm
      name: v2-mysql-vm
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"reviews","namespace":"default"},"spec":{"host":"reviews","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"},{"labels":{"version":"v3"},"name":"v3"}]}}
    creationTimestamp: 2019-01-11T00:58:53Z
    generation: 1
    name: reviews
    namespace: default
    resourceVersion: "921685"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/reviews
    uid: 10db9ee2-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: reviews
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
    - labels:
        version: v3
      name: v3
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""
```
There we have all the destination rules, and now we need to apply the new manifest that will send everything to the version 1 and the user _jason_ to the version 2 of the reviews microservice.
<br />

```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/virtual-service-reviews-test-v2.yaml
virtualservice.networking.istio.io "reviews" created

$ kubectl get virtualservice reviews -o yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"reviews","namespace":"default"},"spec":{"hosts":["reviews"],"http":[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"reviews","subset":"v2"}}]},{"route":[{"destination":{"host":"reviews","subset":"v1"}}]}]}}
  creationTimestamp: 2019-01-11T02:30:35Z
  generation: 1
  name: reviews
  namespace: default
  resourceVersion: "930577"
  selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/virtualservices/reviews
  uid: e0701f0d-1548-11e9-9eda-6a85233ec1d5
spec:
  hosts:
  - reviews
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: reviews
        subset: v2
  - route:
    - destination:
        host: reviews
        subset: v1
```
What's going on here, how Istio knows what user is logged in?, well, the app adds a header called end-user and value _jason_ then the route will be used, it's a nifty trick.
<br />

Not jason:
![img](/images/istio-servicev1.webp){:class="mx-auto"}
<br />

jason:
![img](/images/istio-servicev2.webp){:class="mx-auto"}
As you can see the difference in the v1 and v2 of the app are the stars below the reviews, but that is more than enough to indicate that it works, this is really nice for beta testers you don't need or have to complicate your code but just add a header.
<br />

### Injecting an HTTP abort fault:
This time we will inject a failure for our friend _jason_:
```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/virtual-service-ratings-test-abort.yaml
virtualservice.networking.istio.io "ratings" created

$ kubectl get virtualservice ratings -o yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"ratings","namespace":"default"},"spec":{"hosts":["ratings"],"http":[{"fault":{"abort":{"httpStatus":500,"percent":100}},"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"ratings","subset":"v1"}}]},{"route":[{"destination":{"host":"ratings","subset":"v1"}}]}]}}
  creationTimestamp: 2019-01-11T02:50:59Z
  generation: 1
  name: ratings
  namespace: default
  resourceVersion: "932552"
  selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/virtualservices/ratings
  uid: b98799b0-154b-11e9-9eda-6a85233ec1d5
spec:
  hosts:
  - ratings
  http:
  - fault:
      abort:
        httpStatus: 500
        percent: 100
    match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: ratings
        subset: v1
  - route:
    - destination:
        host: ratings
        subset: v1
```

So he decided to check the book reviews again and boom, the ratings service was not available but everything else works just fine, this only applies for _jason_ everyone else will see the version without stars or the error message.
![img](/images/istio-servicev3.webp){:class="mx-auto"}
<br />

### Notes
Istio seems an it is indeed really powerful, there many more features like:

* Traffic shifting.
* Requests timeouts.
* Circuit breaking.
* Mirroring.
* And a lot more.
<br />

I left aside Policies, Telemetry and Security, if you want to learn more about Istio I highly recommend you to try the examples yourself and read on the [official documentation](https://istio.io/docs/tasks/traffic-management/#collapse24).
<br />

I also spent some time improving the navigation of the blog and some other minor details, but I wanted to keep the articles going so that's why this one is so simple and similar to the documentation.
<br />

### Upcoming topics and ideas
I Want to start creating series of content on different topics, brief articles that can get you started with some new technology or maybe give you an idea of how it works, let me know if you are interested in that kind of content in the comments or via twitter 🐦 (it's a bird, in case you cannot see unicode characters).
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Seguimos explorando Istio y sus funcionalidades",
  author: "Gabriel Garrido",
  description: "Seguimos construyendo con Istio y entendiendo como usarlo...",
  tags: ~w(kubernetes istio),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### **Introducción**

Este artículo se basa en lo que hicimos en el [artículo anterior](/blog/why_do_i_need_a_service_mesh), así que consúltalo antes de comenzar este. Si planeas seguir los ejemplos de la documentación, encontrarás muchas similitudes ya que basé este artículo en eso.

<br />

En este ejemplo usaré [Digital Ocean](https://m.do.co/c/01d040b789de) (ese es mi enlace de referido). Ten en cuenta que no tengo ninguna asociación con Digital Ocean, pero te dan $100 para probar sus productos durante 60 días; si gastas $25, yo obtengo otros $25.

<br />

### **Antes de comenzar, algunos conceptos**

- Un **VirtualService** define las reglas que controlan cómo se enrutan las solicitudes para un servicio dentro de un service mesh de Istio.
- Un **DestinationRule** configura el conjunto de políticas que se aplicarán a una solicitud después de que haya ocurrido el enrutamiento de VirtualService.
- Un **ServiceEntry** se usa comúnmente para habilitar solicitudes a servicios fuera de un service mesh de Istio.
- Un **Gateway** configura un balanceador de carga para tráfico HTTP/TCP, operando más comúnmente en el borde del mesh para habilitar el tráfico de entrada para una aplicación.

Estos conceptos básicos te ayudarán a entender el manifiesto que vamos a ver.

<br />

### **Empecemos**

Ya tenemos el proyecto **bookinfo** desplegado y utilizando las tres versiones del servicio (ratings), pero necesitaremos hacer algunos cambios para probar el enrutamiento basado en la identidad del usuario. Puedes comprobar la configuración con:

```elixir
$ kubectl get destinationrules -o yaml
apiVersion: v1
items:
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"details","namespace":"default"},"spec":{"host":"details","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"}]}}
    creationTimestamp: 2019-01-11T00:58:54Z
    generation: 1
    name: details
    namespace: default
    resourceVersion: "921688"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/details
    uid: 11490656-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: details
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"productpage","namespace":"default"},"spec":{"host":"productpage","subsets":[{"labels":{"version":"v1"},"name":"v1"}]}}
    creationTimestamp: 2019-01-11T00:58:53Z
    generation: 1
    name: productpage
    namespace: default
    resourceVersion: "921684"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/productpage
    uid: 10a42a24-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: productpage
    subsets:
    - labels:
        version: v1
      name: v1
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"ratings","namespace":"default"},"spec":{"host":"ratings","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"},{"labels":{"version":"v2-mysql"},"name":"v2-mysql"},{"labels":{"version":"v2-mysql-vm"},"name":"v2-mysql-vm"}]}}
    creationTimestamp: 2019-01-11T00:58:54Z
    generation: 1
    name: ratings
    namespace: default
    resourceVersion: "921686"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/ratings
    uid: 111299e1-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: ratings
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
    - labels:
        version: v2-mysql
      name: v2-mysql
    - labels:
        version: v2-mysql-vm
      name: v2-mysql-vm
- apiVersion: networking.istio.io/v1alpha3
  kind: DestinationRule
  metadata:
    annotations:
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"networking.istio.io/v1alpha3","kind":"DestinationRule","metadata":{"annotations":{},"name":"reviews","namespace":"default"},"spec":{"host":"reviews","subsets":[{"labels":{"version":"v1"},"name":"v1"},{"labels":{"version":"v2"},"name":"v2"},{"labels":{"version":"v3"},"name":"v3"}]}}
    creationTimestamp: 2019-01-11T00:58:53Z
    generation: 1
    name: reviews
    namespace: default
    resourceVersion: "921685"
    selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/destinationrules/reviews
    uid: 10db9ee2-153c-11e9-9eda-6a85233ec1d5
  spec:
    host: reviews
    subsets:
    - labels:
        version: v1
      name: v1
    - labels:
        version: v2
      name: v2
    - labels:
        version: v3
      name: v3
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""
```

Ahí tenemos todas las reglas de destino, y ahora necesitamos aplicar el nuevo manifiesto que enviará todo a la versión 1 y al usuario _jason_ a la versión 2 del microservicio **reviews**.

<br />

```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/virtual-service-reviews-test-v2.yaml
virtualservice.networking.istio.io "reviews" created

$ kubectl get virtualservice reviews -o yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"reviews","namespace":"default"},"spec":{"hosts":["reviews"],"http":[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"reviews","subset":"v2"}}]},{"route":[{"destination":{"host":"reviews","subset":"v1"}}]}]}}
  creationTimestamp: 2019-01-11T02:30:35Z
  generation: 1
  name: reviews
  namespace: default
  resourceVersion: "930577"
  selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/virtualservices/reviews
  uid: e0701f0d-1548-11e9-9eda-6a85233ec1d5
spec:
  hosts:
  - reviews
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: reviews
        subset: v2
  - route:
    - destination:
        host: reviews
        subset: v1
```

¿Qué está pasando aquí? ¿Cómo sabe Istio qué usuario ha iniciado sesión? Bueno, la aplicación añade un encabezado llamado **end-user** con el valor _jason_; entonces se usará la ruta. Es un truco ingenioso.

<br />

No jason:

![img](/images/istio-servicev1.webp){:class="mx-auto"}

<br />

jason:

![img](/images/istio-servicev2.webp){:class="mx-auto"}

Como puedes ver, la diferencia entre la versión 1 y la versión 2 de la aplicación son las estrellas debajo de las reseñas, pero eso es más que suficiente para indicar que funciona. Esto es realmente útil para los beta testers; no necesitas complicar tu código, solo agregar un encabezado.

<br />

### **Inyectando una falla HTTP abort**

Esta vez inyectaremos una falla para nuestro amigo _jason_:

```elixir
istio-1.0.5/samples/bookinfo $ kubectl apply -f networking/virtual-service-ratings-test-abort.yaml
virtualservice.networking.istio.io "ratings" created

$ kubectl get virtualservice ratings -o yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"ratings","namespace":"default"},"spec":{"hosts":["ratings"],"http":[{"fault":{"abort":{"httpStatus":500,"percent":100}},"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"ratings","subset":"v1"}}]},{"route":[{"destination":{"host":"ratings","subset":"v1"}}]}]}}
  creationTimestamp: 2019-01-11T02:50:59Z
  generation: 1
  name: ratings
  namespace: default
  resourceVersion: "932552"
  selfLink: /apis/networking.istio.io/v1alpha3/namespaces/default/virtualservices/ratings
  uid: b98799b0-154b-11e9-9eda-6a85233ec1d5
spec:
  hosts:
  - ratings
  http:
  - fault:
      abort:
        httpStatus: 500
        percent: 100
    match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: ratings
        subset: v1
  - route:
    - destination:
        host: ratings
        subset: v1
```

Así que decidió revisar las reseñas de libros nuevamente y ¡boom!, el servicio de calificaciones no estaba disponible, pero todo lo demás funciona perfectamente. Esto solo se aplica a _jason_; todos los demás verán la versión sin estrellas o el mensaje de error.

![img](/images/istio-servicev3.webp){:class="mx-auto"}

<br />

### **Notas**

Istio parece y de hecho es realmente poderoso. Hay muchas más características como:

- Cambio de tráfico.
- Tiempos de espera de solicitudes.
- Circuit breaking.
- Mirroring.
- Y mucho más.

<br />

Dejé de lado Políticas, Telemetría y Seguridad. Si deseas aprender más sobre Istio, te recomiendo encarecidamente que pruebes los ejemplos tú mismo y leas la [documentación oficial](https://istio.io/docs/tasks/traffic-management/#collapse24).

<br />

También dediqué algo de tiempo a mejorar la navegación del blog y otros detalles menores, pero quería mantener los artículos en marcha, por eso este es tan simple y similar a la documentación.

<br />

### **Próximos temas e ideas**

Quiero comenzar a crear series de contenido sobre diferentes temas, artículos breves que puedan ayudarte a comenzar con alguna nueva tecnología o tal vez darte una idea de cómo funciona. Déjame saber si estás interesado en ese tipo de contenido en los comentarios o vía Twitter 🐦 (es un pájaro, en caso de que no puedas ver caracteres Unicode).

<br />

### **Errata**

Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />

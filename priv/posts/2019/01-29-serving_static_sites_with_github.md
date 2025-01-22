%{
  title: "Serve your static website in Github",
  author: "Gabriel Garrido",
  description: "GitHub pages offers some great examples that are really easy to follow, but if you want to know how I configured everything for this blog continue reading...",
  tags: ~w(serverless git github),
  published: true,
  image: "serve-github.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![github](/images/serve-github.webp){:class="mx-auto"}

### **Introduction**
GitHub offers static web hosting for you and your apps this is called [GitHub Pages](https://pages.github.com/), you can use markdown ([jekyll](https://jekyllrb.com/) or just plain html), for example for this blog I generate all the files with [Hugo.io](https://gohugo.io/) and that gets deployed to GitHub Pages, the configuration is fairly simple as we will see in the following example (this blog setup).
<br />

GitHub pages offers some great examples that are really easy to follow, but if you want to know how I configured everything for this blog continue reading :), if you like it or have any comment use the disqus box at the bottom of the page.
<br />

### **Pages**
The first step in order to use GH Pages is to create a repo (assuming that you already have an account) with the following name: username.github.io in my case is kainlite.github.io, as we can see in the following screenshot:
![img](/images/github-pages-repository.webp){:class="mx-auto"}
This repo already has the blog files, but as with any github repo you will see the default commands to push something to it, the next step is to configure the pages itself, for that you need to go to [Settings](https://github.com/username/username.github.io/settings) (be sure to replace username in the link), then scroll down to the GitHub Pages section. It will look something like this:
<br />

![img](/images/github-pages-configuration.webp){:class="mx-auto"}
As you can see the configuration is fairly simple, you choose the branch that will be used to serve the site, you can even pick a theme if you are going to go with Jekyll, and you can also have a custom domain and https, in this case as I push the static html files to the master branch I selected that branch, you can have any branch you like but it's common to use gh-pages.
<br />

##### **DNS**
For the custom domain you need to create the following entries in your DNS `dig techsquad.rocks`, you can find these ips in [this page](https://help.github.com/articles/setting-up-an-apex-domain/):
```elixir
techsquad.rocks.        300     IN      A       185.199.110.153
techsquad.rocks.        300     IN      A       185.199.111.153
techsquad.rocks.        300     IN      A       185.199.108.153
techsquad.rocks.        300     IN      A       185.199.109.153
```
After a few minutes it should start working, and whatever you have in that repo will be served as static files, there are some limits but they are really high so you can probably start your site or blog or whatever without having to worry to much about it. If you want to know what those limits are go [here](https://help.github.com/articles/what-is-github-pages/), as of now the repository size limit is 1Gb, and there is a soft bandwidth limit of 100GB per month, also 10 builds per hour.
<br />

##### **Go Hugo**
Now to the interesting part, [Hugo](https://gohugo.io) let's you configure and customize several aspects of the generated files, first be sure to install hugo with your package manager or with go, the steps to create a blog are fairly simple:
```elixir
hugo new site testing-hugo
# OUTPUT:
# Congratulations! Your new Hugo site is created in /home/kainlite/Webs/testing-hugo.
#
# Just a few more steps and you're ready to go:
#
# 1. Download a theme into the same-named folder.
#    Choose a theme from https://themes.gohugo.io/, or
#    create your own with the "hugo new theme <THEMENAME>" command.
# 2. Perhaps you want to add some content. You can add single files
#    with "hugo new <SECTIONNAME>/<FILENAME>.<FORMAT>".
# 3. Start the built-in live server via "hugo server".
#
# Visit https://gohugo.io/ for quickstart guide and full documentation.
```
As I have shown in the tmux article, I like to have 2 panes one small pane where I can see the files being rebuilt at each save and another pane with Vim to edit the source code. You can start the hugo webserver for development with `hugo serve -D` and it will listen by default in the port 1313. It is very common to use themes, so you can go to the [themes page](https://themes.gohugo.io/) and start your project with one of those, there are several ways to install the themes, and you can see the installation steps at the theme page, for example for the blog I started with [Sustain](https://themes.gohugo.io/hugo-sustain/) but then modified it to match my needs.
<br />

##### **Publishing with git push**
The most interesting part of this setup is the simple automation that I use to publish with `git push`, I created the following hook in the blog repo `.git/hooks/pre-push`:
```elixir
#!/bin/bash

COMMIT_MESSAGE=`git log -n 1 --pretty=format:%s ${local_ref}`

hugo -d ~/Webs/kainlite.github.io
ANYTHING_CHANGED=`cd ~/Webs/kainlite.github.io && git diff --exit-code`
if [[ $? -gt 0 ]]; then
    cd ~/Webs/kainlite.github.io && git add . && git commit -m "${COMMIT_MESSAGE}" && git push origin master
fi
```
What this simple hook does is check if there is any change and push the changes with the same commit message than in the original repo, we first grab the commit message from the original repo, and then check if something changed with git, if it did then we just add all files and push that to the repo, that will trigger a build in github pages and once completed our page will be updated and visible (it can take a few seconds sometimes, but in general it's pretty fast).
<br />

And that's how this blog was configured, in the upcoming articles I will show you how to host your static website with S3 and serve it with cloudflare, after that we will use a go lambda function to send the form email, let me know any comments or anything that you might want me to write about.
<br />

##### **Pages Environment**
If you paid attention at the first screenshot you probably noticed that it says _1 Environment_ that means that GH Pages have been already configured and if we click it we can see something like this:
![img](/images/github-pages-environment.webp){:class="mx-auto"}
<br />
For static html sites it would be unlikely to see a failure, but it can happen if you use Jekyll for example and there is any syntax error.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Sirviendo paginas estaticas con Github",
  author: "Gabriel Garrido",
  description: "Como usar GitHub Pages para sitios estaticos...",
  tags: ~w(serverless git github),
  published: true,
  image: "serve-github.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![github](/images/serve-github.webp){:class="mx-auto"}

### **Introducción**
GitHub ofrece alojamiento web estático para vos y tus apps, esto se llama [GitHub Pages](https://pages.github.com/). Podés usar markdown ([jekyll](https://jekyllrb.com/)) o simplemente HTML. Por ejemplo, para este blog genero todos los archivos con [Hugo.io](https://gohugo.io/) y eso se despliega en GitHub Pages. La configuración es bastante simple como veremos en el siguiente ejemplo (la configuración de este blog).
<br />

GitHub Pages ofrece algunos ejemplos muy buenos que son fáciles de seguir, pero si querés saber cómo configuré todo para este blog, seguí leyendo :), si te gusta o tenés algún comentario, podés usar el cuadro de disqus al final de la página.
<br />

### **Pages**
El primer paso para usar GitHub Pages es crear un repositorio (suponiendo que ya tenés una cuenta) con el siguiente nombre: username.github.io, en mi caso es kainlite.github.io, como podés ver en la siguiente captura de pantalla:
![img](/images/github-pages-repository.webp){:class="mx-auto"}
Este repositorio ya tiene los archivos del blog, pero como con cualquier repositorio de GitHub, verás los comandos predeterminados para subir algo. El siguiente paso es configurar las páginas en sí. Para eso, tenés que ir a [Settings](https://github.com/username/username.github.io/settings) (asegurate de reemplazar *username* en el enlace), luego desplazate hasta la sección de GitHub Pages. Se verá algo así:
<br />

![img](/images/github-pages-configuration.webp){:class="mx-auto"}
Como podés ver, la configuración es bastante sencilla. Elegís la rama que se va a usar para servir el sitio. Incluso podés elegir un tema si vas a usar Jekyll, y también podés tener un dominio personalizado y https. En este caso, como subo los archivos HTML estáticos a la rama master, seleccioné esa rama. Podés usar cualquier rama que quieras, pero es común usar *gh-pages*.
<br />

##### **DNS**
Para el dominio personalizado tenés que crear las siguientes entradas en tu DNS con `dig techsquad.rocks`. Podés encontrar estas IPs en [esta página](https://help.github.com/articles/setting-up-an-apex-domain/):
```elixir
techsquad.rocks.        300     IN      A       185.199.110.153
techsquad.rocks.        300     IN      A       185.199.111.153
techsquad.rocks.        300     IN      A       185.199.108.153
techsquad.rocks.        300     IN      A       185.199.109.153
```
Después de unos minutos debería empezar a funcionar, y lo que tengas en ese repositorio se servirá como archivos estáticos. Hay algunos límites, pero son bastante altos, así que probablemente podés comenzar tu sitio o blog sin preocuparte mucho por eso. Si querés saber cuáles son esos límites, mirá [aquí](https://help.github.com/articles/what-is-github-pages/). Actualmente, el límite de tamaño del repositorio es de 1 GB, y hay un límite suave de ancho de banda de 100 GB por mes, además de 10 compilaciones por hora.
<br />

##### **Go Hugo**
Ahora vamos a la parte interesante. [Hugo](https://gohugo.io) te permite configurar y personalizar varios aspectos de los archivos generados. Primero, asegurate de instalar Hugo con tu gestor de paquetes o con Go. Los pasos para crear un blog son bastante simples:
```elixir
hugo new site testing-hugo
# OUTPUT:
# Congratulations! Your new Hugo site is created in /home/kainlite/Webs/testing-hugo.
#
# Just a few more steps and you're ready to go:
#
# 1. Download a theme into the same-named folder.
#    Choose a theme from https://themes.gohugo.io/, or
#    create your own with the "hugo new theme <THEMENAME>" command.
# 2. Perhaps you want to add some content. You can add single files
#    with "hugo new <SECTIONNAME>/<FILENAME>.<FORMAT>".
# 3. Start the built-in live server via "hugo server".
#
# Visit https://gohugo.io/ for quickstart guide and full documentation.
```
Como mostré en el artículo sobre tmux, me gusta tener 2 paneles: un panel pequeño donde puedo ver los archivos siendo reconstruidos en cada guardado y otro panel con Vim para editar el código fuente. Podés iniciar el servidor web de Hugo para desarrollo con `hugo serve -D` y escuchará por defecto en el puerto 1313. Es muy común usar temas, así que podés ir a la [página de temas](https://themes.gohugo.io/) y empezar tu proyecto con uno de ellos. Hay varias formas de instalar los temas, y podés ver los pasos de instalación en la página del tema. Por ejemplo, para el blog, empecé con [Sustain](https://themes.gohugo.io/hugo-sustain/), pero luego lo modifiqué para que se ajuste a mis necesidades.
<br />

##### **Publicar con git push**
La parte más interesante de esta configuración es la simple automatización que uso para publicar con `git push`. Creé el siguiente hook en el repositorio del blog: `.git/hooks/pre-push`:
```elixir
#!/bin/bash

COMMIT_MESSAGE=`git log -n 1 --pretty=format:%s ${local_ref}`

hugo -d ~/Webs/kainlite.github.io
ANYTHING_CHANGED=`cd ~/Webs/kainlite.github.io && git diff --exit-code`
if [[ $? -gt 0 ]]; then
    cd ~/Webs/kainlite.github.io && git add . && git commit -m "${COMMIT_MESSAGE}" && git push origin master
fi
```
Lo que hace este simple hook es verificar si hubo algún cambio y subir los cambios con el mismo mensaje de commit que en el repositorio original. Primero obtenemos el mensaje de commit del repositorio original y luego verificamos si algo cambió con git. Si hubo cambios, simplemente añadimos todos los archivos y subimos eso al repositorio. Eso desencadenará una compilación en GitHub Pages y, una vez completada, nuestra página se actualizará y será visible (a veces puede tardar unos segundos, pero en general es bastante rápido).
<br />

Y así es como se configuró este blog. En los próximos artículos te mostraré cómo alojar tu sitio web estático con S3 y servirlo con Cloudflare. Después, usaremos una función lambda de Go para enviar el formulario de correo electrónico. Déjame saber cualquier comentario o si hay algo sobre lo que te gustaría que escriba.
<br />

##### **Entorno de Pages**
Si prestaste atención a la primera captura de pantalla, probablemente notaste que dice _1 Environment_, eso significa que GitHub Pages ya ha sido configurado, y si hacemos clic en eso, podemos ver algo como esto:
![img](/images/github-pages-environment.webp){:class="mx-auto"}
<br />
Para sitios HTML estáticos es poco probable que veas un fallo, pero puede pasar si usás Jekyll, por ejemplo, y hay algún error de sintaxis.
<br />

### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />

%{
  title: "My local environment",
  author: "Gabriel Garrido",
  description: "This article is about my current configuration, but I'm going to talk only about the terminal and my text editor because those will work in any linux distribution...",
  tags: ~w(linux vim tmux),
  published: true,
  image: "urxvt.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![terminal](/images/terminal.webp"){:class="mx-auto"}

### Introduction
This article is about my current configuration, but I'm going to talk only about the terminal and my text editor because those will work in any linux distribution, I'm currently using **Arch Linux** and **AwesomeWM** (I used Gnome Shell previously, and Gnome 2 before that), you can find my [dotfiles here](https://github.com/kainlite/dotfiles) with all my configurations.
<br />

While my terminal doesn't look exactly like the one from the picture you can get something like that with [GBT](https://github.com/jtyr/gbt).
<br />

### Terminal
My current terminal is **rxvt-unicode** and I'm pretty happy with it, it's relatively easy to configure and use, it looks like this:
![img](/images/urxvt.webp){:class="mx-auto"}
And the configuration file can be [found here](https://github.com/kainlite/dotfiles/blob/master/.Xresources), note that even if you don't like Ponys by any reason, it's useful to test colors in the terminal.
<br />

It's different than other terminals I have tried in the way it manages and uses the configuration, it uses an additional tool called `xrdb` (X server resource database utility) to manage the configuration provided in the configuration file `.Xresources`.
```elixir
# Loads the configuration from Xresources in xrdb
$ xrdb -merge .Xresources

# List the current configuration
$ xrdb -query

# Deletes the current database
$ xrdb -remove
```
<br />


### Theme
My current theme is [gruvbox](https://github.com/morhetz/gruvbox) in Vim and also in my [terminal](https://github.com/morhetz/gruvbox-contrib/blob/master/xresources/gruvbox-dark.xresources), and changing from [solazired](https://ethanschoonover.com/solarized/) to it is what inspired this small article.
<br />

### Tmux
I also use tmux to maintan sessions, some of it's nice features are tiling, tabs. The configuration can be [found here](https://github.com/kainlite/dotfiles/blob/master/.tmux.conf). I move between tabs with control-h and control-l, and between panes with control-a [hjkl].
<br />

### Vim
As my text editor I really like and enjoy using Vim, there is always something to learn but once you make some good habits it pays off in the way you write and move around, you can check some amazing screencasts on vim [here](http://vimcasts.org/) and also the book Practical Vim can be really helpful to get started and/or improve your current vim-fu.
<br />

As a plugin manager I use [Plug](https://github.com/kainlite/dotfiles/blob/master/.vimrc.bundles) even that it's not really necessary with Vim 8, but that is a matter of taste I guess. You can see my full vim configuration [here](https://github.com/kainlite/dotfiles/blob/master/.vimrc).
<br />

It looks something like this, as you can see I have a small tmux pane in the bottom with Hugo _compiling_ the site after every save and live reloading it in my browser:
![img](/images/vim.webp){:class="mx-auto"}
<br />

### Notes
* I'm also using zsh and [oh-my-zsh](https://ohmyz.sh/) with the theme agnoster. I really like zsh it's fast and has some nice features like autocomplete everywhere, but again this is a matter of taste.
* I like to take advantage of all the space in the screen, that's why AwesomeWM fits great (even that I do not use the tiling feature a lot, tabs and full screen apps), with some minor configuration I'm able to do everything from the keyboard, I use the mouse when checking emails and things like that but otherwise the keyboard is more than enough.
* I used cowsay and ponysay in the first screenshot so you can have an idea of how the terminal looks like.
* If you are going to use unicode I recommend you to install the fonts from nerd-fonts.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Mi ambiente local (viejo)",
  author: "Gabriel Garrido",
  description: "Este articulo exploro las herramientas que uso diariamente para trabajar...",
  tags: ~w(linux vim tmux),
  published: true,
  image: "urxvt.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![terminal](/images/terminal.webp"){:class="mx-auto"}

![terminal](/images/terminal.webp"){:class="mx-auto"}

### **Introducción**
Este artículo trata sobre mi configuración actual, pero solo voy a hablar sobre el terminal y mi editor de texto porque funcionarán en cualquier distribución de Linux. Actualmente estoy usando **Arch Linux** y **AwesomeWM** (anteriormente usaba Gnome Shell y antes de eso Gnome 2). Puedes encontrar mis [dotfiles aquí](https://github.com/kainlite/dotfiles) con todas mis configuraciones.
<br />

Aunque mi terminal no se ve exactamente como el de la imagen, puedes obtener algo similar con [GBT](https://github.com/jtyr/gbt).
<br />

### **Terminal**
Mi terminal actual es **rxvt-unicode** y estoy bastante contento con él. Es relativamente fácil de configurar y usar, se ve así:
![img](/images/urxvt.webp){:class="mx-auto"}
Y el archivo de configuración lo puedes [encontrar aquí](https://github.com/kainlite/dotfiles/blob/master/.Xresources). Ten en cuenta que incluso si no te gustan los ponis por alguna razón, es útil para probar colores en el terminal.
<br />

Es diferente a otros terminales que he probado en la forma en que gestiona y utiliza la configuración. Usa una herramienta adicional llamada `xrdb` (utilidad de base de datos de recursos del servidor X) para manejar la configuración proporcionada en el archivo `.Xresources`.

```elixir
# Carga la configuración de Xresources en xrdb
$ xrdb -merge .Xresources

# Lista la configuración actual
$ xrdb -query

# Elimina la base de datos actual
$ xrdb -remove
```
<br />

### **Tema**
Mi tema actual es [gruvbox](https://github.com/morhetz/gruvbox) en Vim y también en mi [terminal](https://github.com/morhetz/gruvbox-contrib/blob/master/xresources/gruvbox-dark.xresources), y cambiar de [solarized](https://ethanschoonover.com/solarized/) a este es lo que inspiró este pequeño artículo.
<br />

### **Tmux**
También uso tmux para mantener sesiones; algunas de sus buenas características son el mosaico y las pestañas. La configuración se puede [encontrar aquí](https://github.com/kainlite/dotfiles/blob/master/.tmux.conf). Me muevo entre pestañas con control-h y control-l, y entre paneles con control-a [hjkl].
<br />

### **Vim**
Como editor de texto, realmente me gusta y disfruto usar Vim; siempre hay algo que aprender, pero una vez que adquieres buenos hábitos, vale la pena en la forma en que escribes y te desplazas. Puedes ver algunos increíbles screencasts sobre Vim [aquí](http://vimcasts.org/) y también el libro Practical Vim puede ser muy útil para comenzar y/o mejorar tu nivel actual de Vim.
<br />

Como gestor de complementos uso [Plug](https://github.com/kainlite/dotfiles/blob/master/.vimrc.bundles), aunque no es realmente necesario con Vim 8, pero supongo que es una cuestión de gustos. Puedes ver mi configuración completa de Vim [aquí](https://github.com/kainlite/dotfiles/blob/master/.vimrc).
<br />

Se ve algo como esto; como puedes ver, tengo un pequeño panel de tmux en la parte inferior con Hugo _compilando_ el sitio después de cada guardado y recargándolo en vivo en mi navegador:
![img](/images/vim.webp){:class="mx-auto"}
<br />

### **Notas**
* También estoy usando zsh y [oh-my-zsh](https://ohmyz.sh/) con el tema agnoster. Realmente me gusta zsh; es rápido y tiene algunas características agradables como autocompletar en todas partes, pero nuevamente esto es una cuestión de gustos.
* Me gusta aprovechar todo el espacio en la pantalla, por eso AwesomeWM encaja perfectamente (aunque no uso mucho la función de mosaico; uso pestañas y aplicaciones a pantalla completa). Con una configuración menor, puedo hacer todo desde el teclado; uso el ratón cuando reviso correos electrónicos y cosas así, pero por lo demás el teclado es más que suficiente.
* Usé cowsay y ponysay en la primera captura de pantalla para que puedas tener una idea de cómo se ve el terminal.
* Si vas a usar Unicode, te recomiendo instalar las fuentes de nerd-fonts.
<br />

### **Errata**
Si encuentras algún error o tienes alguna sugerencia, por favor envíame un mensaje para que pueda corregirlo.

<br />

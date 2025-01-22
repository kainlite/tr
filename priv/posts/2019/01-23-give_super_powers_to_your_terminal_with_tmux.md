%{
  title: "Give super powers to your terminal with tmux",
  author: "Gabriel Garrido",
  description: "In this article I want to introduce you to tmux, you might have used screen in the past or heard about it, what tmux and screen are is terminal multiplexers...",
  tags: ~w(vim tmux linux),
  published: true,
  image: "tmux-terminal.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![tmux](/images/tmux-terminal.webp){:class="mx-auto"}

### **Introduction**
In this article I want to introduce you to `tmux`, you might have used `screen` in the past or heard about it, what tmux and screen are is terminal multiplexers, what does that mean? That you can have many windows/tabs and splits/panes in just one terminal window, this can really make things easier when using it as a development environment for example, you can detach from the terminal and leave things running indefinitely, or share your terminal with a colleague over ssh, for the examples I will be explaining bits of my configuration and how do I use it. The full configuration can be found [here](https://github.com/kainlite/dotfiles/blob/master/.tmux.conf). I'm using ZSH as shell and Vim as text editor.
<br />

### **Tmux**
I also use tmux to maintain sessions, for example I can only have one terminal window open because with the help from ZSH it will attach automatically to a session thanks to [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh) and the plugin tmux, I use tabs aka windows a lot, sometimes I also use splits aka as panes.
<br />

Now you have some basic understanding of what tmux does and how does it name its things, let's examine some bits of the config and how to use it.
<br />

##### **Attach/detach from a session**
In order to create a session and attach to it you need to execute `tmux new -s my-session`, then to detach from it: `CTRL-a d` and to re-attach `tmux a -t my-session`, then kill it `tmux kill-session -t my-session` or logout from all windows.
<br />

##### **Prefix**
I don't use the default prefix that is: `CTRL-b`, I use `CTRL-a` like in screen.
```elixir
# Use ctrl-a instead of ctrl-b
set -g prefix C-a
unbind C-b
bind C-a send-prefix
```
<br />

##### **Example**
You can print the numbers of the panes with `CTRL-a q`, and you can navigate windows and panes as a list with `CTRL-a w`.
![img](/images/tmux-windows-panes.webp){:class="mx-auto"}
<br />

I usually like to have 3 panes, something like this:
![img](/images/tmux-sample-usage.webp){:class="mx-auto"}
I can edit the code or whatever in the pane 0, run commands if I need to in the pane 1, and have the webserver or code compiler, etc in the pane 2. This is very handy because I can write and test things at the same time without leaving the keyboard, or look at 2 different projects/files/etc side by side.
<br />

With `tmux ls` we can list active sessions, also tmux has a command mode (`CTRL-a :`) like Vim, where you can issue some commands or change settings on the fly, for example instead of executing `tmux ls`, you can get the same information doing `CTRL-a :` and then `ls<CR>`.
<br />

##### **Defaults**
Some helpful settings, for example start windows at 1 instead of 0, renumber on exit also makes it easier with windows.
```elixir
# Start window numbers at 1 to match keyboard order with tmux window order
set -g base-index 1

# Scrollback buffer n lines
set -g history-limit 10000

# Renumber tabs on exit
set-option -g renumber-windows on

# Use vi keybindings in copy and choice modes
set-window-option -g mode-keys vi

# Enable mouse, enables you to scroll in the tmux history buffer.
set -g mouse on
```
<br />

##### **Movement**
I move between windows with `CTRL+h` and `CTRL+l`, and between panes with `CTRL-a [hjkl]`.
```elixir
# Move between windows
bind-key -n C-h prev
bind-key -n C-l next

# Move between panes
unbind h
bind h select-pane -L
unbind j
bind j select-pane -D
unbind k
bind k select-pane -U
unbind l
bind l select-pane -R
```
<br />

##### **Configuration**
A handy trick if you are testing the configuration is to reload it from the file with `CTRL-a r`
```elixir
# Force a reload of the config file
unbind r
bind r source-file ~/.tmux.conf \; display "Reloaded!"
```
<br />

##### **Panes**
Everything is nice and shiny, but how do I open a pane or a new window?
```elixir
# Horizontal and vertical splits
unbind |
bind | split-window -h
unbind -
bind - split-window
```
Easy, `CTRL-a |` will give you a vertical pane, and `CTRL-a -` will give you an horizontal pane.
You an also re-order the panes with `CTRL-a SPACE`
<br />

You can also re-order windows with `SHIFT-Left Arrow` and `SHIFT-Right Arrow`.
```elixir
# Swap windows
bind-key -n S-Left swap-window -t -1
bind-key -n S-Right swap-window -t +1
```
<br />

##### **Status bar**
The status bar and the colors, it's fairly simple but I like it.
```elixir
# Status bar has a dim gray background
set-option -g status-bg colour234
set-option -g status-fg colour0
# Left shows the session name, in blue
set-option -g status-left-bg default
set-option -g status-left-fg colour74
# Right is some CPU stats, so terminal green
set-option -g status-right-bg default
set-option -g status-right-fg colour71
# Windows are medium gray; current window is white
set-window-option -g window-status-fg colour244
set-window-option -g window-status-current-fg '#ffffff'
set-window-option -g window-status-current-bg '#000000'
# Beeped windows get a blinding orange background
set-window-option -g window-status-bell-fg '#000000'
set-window-option -g window-status-bell-bg '#d78700'
set-window-option -g window-status-bell-attr none
# Trim window titles to a reasonable length
set-window-option -g window-status-format '#[fg=yellow] #F#I#[default] #W '
set-window-option -g window-status-current-format '#[bg=yellow] #I#[bg=yellow] #W '
```
<br />

##### **Copy/paste**
![img](/images/tmux-vi-mode.webp){:class="mx-auto"}
Tmux also supports the vi-copy mode, you can enter this mode with `CTRL-a ESC`, then pressing `v` for normal selection or `V` for line selection you can mark and copy with `Y` (by default is `ENTER` aka `<CR>`).
<br />

And as you can imagine you can paste with `CTRL-a p`, this is really handy when copying from one pane to another or from one window to another, in Vim I recommend you `:set paste!` before pasting into it, so it doesn't try to format, etc.
<br />

It also copies to the clipboard buffer, using xsel.
```elixir
# Make copy mode more vim like
bind Escape copy-mode
unbind p
bind p paste-buffer
bind-key -T edit-mode-vi Up send-keys -X history-up
bind-key -T edit-mode-vi Down send-keys -X history-down
unbind-key -T copy-mode-vi Space     ;   bind-key -T copy-mode-vi v send-keys -X begin-selection

unbind-key -T copy-mode-vi Enter     ;   bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xsel -i --clipboard"
bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xsel -i --clipboard"

unbind-key -T copy-mode-vi C-v       ;   bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
unbind-key -T copy-mode-vi [         ;   bind-key -T copy-mode-vi [ send-keys -X begin-selection
unbind-key -T copy-mode-vi ]         ;   bind-key -T copy-mode-vi ] send-keys -X copy-selection
```

If you want to learn more about tmux a good place to start is the [Arch Linux wiki](https://wiki.archlinux.org/index.php/tmux).
<br />

##### **notes**
Sometimes you can have issues with the keys `HOME` and `END`, this can help with that.
```elixir
# Home / End patch
bind -n End send-key C-e
bind -n Home send-key C-a
```
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Dale super-poderes a tu terminal con tmux",
  author: "Gabriel Garrido",
  description: "En este articulo vamos a ver como usar y configurar el multiplexor de terminales: tmux...",
  tags: ~w(vim tmux linux),
  published: true,
  image: "tmux-terminal.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![tmux](/images/tmux-terminal.webp){:class="mx-auto"}

### **Introducción**
En este artículo quiero presentarte `tmux`. Tal vez hayas usado `screen` en el pasado o escuchado hablar de él. Lo que tmux y screen son, básicamente, son multiplexores de terminal. ¿Qué significa eso? Que podés tener muchas ventanas/pestañas y divisiones/paneles en una sola ventana de terminal. Esto puede facilitar mucho las cosas cuando lo usás como entorno de desarrollo, por ejemplo, podés desconectarte de la terminal y dejar procesos corriendo indefinidamente o compartir tu terminal con un colega a través de ssh. En los ejemplos te voy a explicar partes de mi configuración y cómo la uso. La configuración completa la podés encontrar [aquí](https://github.com/kainlite/dotfiles/blob/master/.tmux.conf). Estoy usando ZSH como shell y Vim como editor de texto.
<br />

### **Tmux**
También uso tmux para mantener sesiones, por ejemplo, puedo tener una sola ventana de terminal abierta porque, con la ayuda de ZSH, se adjunta automáticamente a una sesión gracias a [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh) y al plugin tmux. Uso mucho las pestañas, que tmux llama ventanas, y a veces también uso divisiones o paneles.
<br />

Ahora que tenés una idea básica de lo que hace tmux y cómo llama a sus elementos, vamos a ver algunas partes de la configuración y cómo usarla.
<br />

##### **Adjuntar/desconectar una sesión**
Para crear una sesión y adjuntarla, necesitás ejecutar `tmux new -s mi-sesion`, luego para desconectarla: `CTRL-a d` y para re-adjuntarla: `tmux a -t mi-sesion`. Para matarla: `tmux kill-session -t mi-sesion` o cerrar todas las ventanas.
<br />

##### **Prefijo**
No uso el prefijo por defecto que es `CTRL-b`, uso `CTRL-a` como en screen.
```elixir
# Usar ctrl-a en lugar de ctrl-b
set -g prefix C-a
unbind C-b
bind C-a send-prefix
```
<br />

##### **Ejemplo**
Podés mostrar los números de los paneles con `CTRL-a q`, y podés navegar entre ventanas y paneles como una lista con `CTRL-a w`.
![img](/images/tmux-windows-panes.webp){:class="mx-auto"}
<br />

Generalmente me gusta tener 3 paneles, algo así:
![img](/images/tmux-sample-usage.webp){:class="mx-auto"}
Puedo editar el código o lo que sea en el panel 0, ejecutar comandos si lo necesito en el panel 1, y tener el servidor web o el compilador de código, etc. en el panel 2. Esto es muy útil porque puedo escribir y probar cosas al mismo tiempo sin salir del teclado, o mirar dos proyectos/archivos diferentes uno al lado del otro.
<br />

Con `tmux ls` podemos listar las sesiones activas. También tmux tiene un modo de comandos (`CTRL-a :`) como Vim, donde podés ejecutar algunos comandos o cambiar configuraciones al vuelo. Por ejemplo, en lugar de ejecutar `tmux ls`, podés obtener la misma información haciendo `CTRL-a :` y luego `ls<CR>`.
<br />

##### **Valores predeterminados**
Algunas configuraciones útiles, como por ejemplo, empezar las ventanas en 1 en lugar de 0, y renumerarlas al salir, también facilita el manejo de las ventanas.
```elixir
# Empezar a numerar las ventanas desde 1 para que coincidan con el orden del teclado
set -g base-index 1

# Buffer de historial de n líneas
set -g history-limit 10000

# Renumerar ventanas al salir
set-option -g renumber-windows on

# Usar teclas vi en modos de copia y selección
set-window-option -g mode-keys vi

# Habilitar mouse, permite hacer scroll en el historial de tmux
set -g mouse on
```
<br />

##### **Movimiento**
Me muevo entre ventanas con `CTRL+h` y `CTRL+l`, y entre paneles con `CTRL-a [hjkl]`.
```elixir
# Moverse entre ventanas
bind-key -n C-h prev
bind-key -n C-l next

# Moverse entre paneles
unbind h
bind h select-pane -L
unbind j
bind j select-pane -D
unbind k
bind k select-pane -U
unbind l
bind l select-pane -R
```
<br />

##### **Configuración**
Un truco útil si estás probando la configuración es recargarla desde el archivo con `CTRL-a r`.
```elixir
# Forzar la recarga del archivo de configuración
unbind r
bind r source-file ~/.tmux.conf \; display "¡Recargado!"
```
<br />

##### **Paneles**
Todo muy lindo, pero ¿cómo abro un panel o una nueva ventana?
```elixir
# Divisiones horizontal y vertical
unbind |
bind | split-window -h
unbind -
bind - split-window
```
Fácil, `CTRL-a |` te dará un panel vertical, y `CTRL-a -` te dará un panel horizontal.
También podés reordenar los paneles con `CTRL-a SPACE`.
<br />

También podés reordenar ventanas con `SHIFT-Flecha Izquierda` y `SHIFT-Flecha Derecha`.
```elixir
# Intercambiar ventanas
bind-key -n S-Left swap-window -t -1
bind-key -n S-Right swap-window -t +1
```
<br />

##### **Barra de estado**
La barra de estado y los colores son bastante simples, pero me gustan.
```elixir
# Barra de estado con fondo gris oscuro
set-option -g status-bg colour234
set-option -g status-fg colour0
# A la izquierda muestra el nombre de la sesión en azul
set-option -g status-left-bg default
set-option -g status-left-fg colour74
# A la derecha algunos stats de la CPU, en verde terminal
set-option -g status-right-bg default
set-option -g status-right-fg colour71
# Las ventanas son gris medio; la ventana actual es blanca
set-window-option -g window-status-fg colour244
set-window-option -g window-status-current-fg '#ffffff'
set-window-option -g window-status-current-bg '#000000'
# Las ventanas con beep tienen fondo naranja intenso
set-window-option -g window-status-bell-fg '#000000'
set-window-option -g window-status-bell-bg '#d78700'
set-window-option -g window-status-bell-attr none
# Limitar el tamaño de los títulos de las ventanas
set-window-option -g window-status-format '#[fg=yellow] #F#I#[default] #W '
set-window-option -g window-status-current-format '#[bg=yellow] #I#[bg=yellow] #W '
```
<br />

##### **Copiar/pegar**
![img](/images/tmux-vi-mode.webp){:class="mx-auto"}
Tmux también soporta el modo vi-copy, podés entrar en este modo con `CTRL-a ESC`. Luego, presionando `v` para selección normal o `V` para selección de líneas, podés marcar y copiar con `Y` (por defecto es `ENTER` o `<CR>`).
<br />

Y como te imaginarás, podés pegar con `CTRL-a p`. Esto es muy útil cuando copiás de un panel a otro o de una ventana a otra. En Vim te recomiendo `:set paste!` antes de pegar, así no intenta formatear el texto, etc.
<br />

También copia al buffer del portapapeles usando xsel.
```elixir
# Hacer el modo copia más parecido a vim
bind Escape copy-mode
unbind p
bind p paste-buffer
bind-key -T edit-mode-vi Up send-keys -X history-up
bind-key -T edit-mode-vi Down send-keys -X history-down
unbind-key -T copy-mode-vi Space     ;   bind-key -T copy-mode-vi v send-keys -X begin-selection

unbind-key -T copy-mode-vi Enter     ;   bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xsel -i --clipboard"
bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xsel -i --clipboard"

unbind-key -T copy-mode-vi C-v       ;   bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
unbind-key -T copy-mode-vi [         ;   bind-key -T copy-mode-vi [ send-keys -X begin-selection
unbind-key -T copy-mode-vi ]         ;   bind-key -T copy-mode-vi ] send-keys -X copy-selection
```

Si querés aprender más sobre tmux, un buen lugar para empezar es la [wiki de Arch Linux](https://wiki.archlinux.org/index.php/tmux).
<br />

##### **Notas**
A veces podés tener problemas con las teclas `HOME` y `END`, esto te puede ayudar con eso.
```elixir
# Parche para Home / End
bind -n End send-key C-e
bind -n Home send-key C-a
```
<br />

### **Errata**
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo corrija.

<br />

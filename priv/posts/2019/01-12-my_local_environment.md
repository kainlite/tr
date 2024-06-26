%{
  title: "My local environment",
  author: "Gabriel Garrido",
  description: "This article is about my current configuration, but I'm going to talk only about the terminal and my text editor because those will work in any linux distribution...",
  tags: ~w(linux vim tmux),
  published: true,
  image: "urxvt.png"
}
---

![terminal](/images/terminal.png"){:class="mx-auto"}

### Introduction
This article is about my current configuration, but I'm going to talk only about the terminal and my text editor because those will work in any linux distribution, I'm currently using **Arch Linux** and **AwesomeWM** (I used Gnome Shell previously, and Gnome 2 before that), you can find my [dotfiles here](https://github.com/kainlite/dotfiles) with all my configurations.
<br />

While my terminal doesn't look exactly like the one from the picture you can get something like that with [GBT](https://github.com/jtyr/gbt).
<br />

### Terminal
My current terminal is **rxvt-unicode** and I'm pretty happy with it, it's relatively easy to configure and use, it looks like this:
![img](/images/urxvt.png){:class="mx-auto"}
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
![img](/images/vim.png){:class="mx-auto"}
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

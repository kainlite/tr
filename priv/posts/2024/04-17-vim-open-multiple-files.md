%{
  title: "How to open multiple files in vim",
  author: "Gabriel Garrido",
  description: "In this article we will quickly see a few different ways of opening multiple files in vim and how to
  navigate these, keep an eye out for the bonus section as it can get complex pretty quickly.",
  tags: ~w(vim tips-and-tricks),
  published: true,
  image: "vim-tips.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

### **Introduction**

This will be a short article exploring the different ways you can open multiple files in vim at once, and the basic ways
to interact with them, as tabs, windows.
<br/> 

The basic options are:
* [tabs](https://vimhelp.org/tabpage.txt.html)
* [windows](https://vimhelp.org/windows.txt.html#windows)

<br/> 

Straight from the vim's help page:
> Summary:
>
>   A buffer is the in-memory text of a file.
>
>   A window is a viewport on a buffer.
>
>   A tab page is a collection of windows.

<br/> 

In the following examples I will be using the 2024 markdown files of this blog to illustrate how it works, how to move
between buffers, tabs and windows, do note that in zsh `**.md` will expand automatically to all files in that folder
with the full relative path, for example for a single file: `priv/posts/2024/02-24-multinode-setup.md`

<br/> 

### How to open multiple files as buffers in vim?

```elixir
> vim priv/posts/2024/**.md 
```
<br />

If we type `:buffers` then we can see the list of buffers opened in our vim instance, using `:bnext` and `:bprev` you
can move between buffers, the symbols show which buffer is active, which one is hidden or inactive: 
```elixir
:buffers
1  h   "02-24-multinode-setup.md"     line 1
2  h   "02-25-upgrading-k3s-with-system-upgrade-controller.md" line 1
3  h   "03-16-getting-started-with-wallaby-integration-tests.md" line 1
4  h   "03-19-rss-is-not-dead-yet.md" line 1
5 #h   "04-14-remote-iex-session.md"  line 1
6 %a   "04-16-migrating-from-cronjobs-to-quantum-core.md" line 1
7  h   "04-16-running-cronjobs-in-kubernetes.md" line 1
8  h   "04-16-vim-open-multiple-files.md" line 1
Press ENTER or type command to continue
```
<br />

### How to open multiple files as tabs in vim?
Similarly if we do `vim -p`, we will get all buffers opened as tabs, then you can list the tabs with `:tabs`, move 
between them with `:tabn` and back with `:tabp`, the main difference here is how the vim window treats a buffer on a single tab vs multiple tabs.
```elixir
vim -p priv/posts/2024/**.md
```
<br />

Here you can see the list of tabs, for vim these tabs can hold multiple contents even split windows, that can't happen
in a single tab buffer kind of window for example.
```elixir
:tabs
Tab page 1
    02-24-multinode-setup.md
Tab page 2
>   02-25-upgrading-k3s-with-system-upgrade-controller.md
Tab page 3
#   03-16-getting-started-with-wallaby-integration-tests.md
Tab page 4
    03-19-rss-is-not-dead-yet.md
Tab page 5
    04-14-remote-iex-session.md
Tab page 6
    04-16-migrating-from-cronjobs-to-quantum-core.md
Tab page 7
    04-16-running-cronjobs-in-kubernetes.md
Tab page 8
    04-16-vim-open-multiple-files.md
Press ENTER or type command to continue
```
<br />

### How to open multiple files as windows in vim?
I guess the window is the tricky concept here, as a window can display a buffer, and multiple windows can be in a tab,
so basically a window is the way we have to represent and see/interact interactively with a buffer.

so if we wanted to open all these files as windows we would have to do `vim -o` to open them horizontally split, `vim -O` 
for vertical split, if you ask me this is the feature I use the least, but it can be handy in some scenarios. 

To move between windows you will need to use `ctrl-w-<hjkl>` depending on the position of the window that you want to jump
or move to.
```elixir
vim -o priv/posts/2024/**.md
vim -O priv/posts/2024/**.md
```
<br />

### Bonus tip
Perform a search and replace in multiple buffers, vim is perfectly capable of doing some advanced replacements, 
here is an example of such task, when I was migrating to this blog I had a lot of content in github gists and wanted to 
make these just local code snippets, so I used the `gist` command-line helper and made almost all replacements automatic 
with just a command:
```elixir
:%s/{{< gist kainlite \(53f54d81934666457a46cb667f8cea58\) >}}/\=printf('```elixir\n%s\n```', substitute(system('gist -r ' . submatch(1)), '\n', '\\n', 'g'))/
```
That's an intimidating search and replace, basically what this does is searches for the 
pattern `{{< gist kainlite \(capture_this_part\) >}}` so we can extract the gist id first, then `\=` tells vim that we 
want to use the expression in the replacement, then with the help of `printf` we build our code snippet using the output
of the command `gist -r gist_id`, then `substitute` is used to run the command and use the output as part of our
replacement.

<br />
So for the sake of the example, the following gist:

```elixir
{{< gist kainlite 53f54d81934666457a46cb667f8cea58 >}}
```
<br />

Would become the next snippet of code after running the previous command (this would be plain unformatted text):
    ```elixir
    ❯ kind create cluster
    Creating cluster "kind" ...
     ✓ Ensuring node image (kindest/node:v1.21.1) 🖼
     ✓ Preparing nodes 📦
     ✓ Writing configuration 📜
     ✓ Starting control-plane 🕹️
     ✓ Installing CNI 🔌
     ✓ Installing StorageClass 💾
    Set kubectl context to "kind-kind"
    You can now use your cluster with:

    kubectl cluster-info --context kind-kind

    Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
    ```

<br />

But what does any of that has to do with buffers and all that? well, you can apply that search and replace to all
buffers using `:bufdo`, so our command would become:
```elixir
:bufdo %s/{{< gist kainlite \(.*\) >}}/\=printf('```elixir\n%s\n```', substitute(system('gist -r ' . submatch(1)), '\n', '\\n', 'g'))/
```
And that will apply the search and replace command to all the opened buffers, also note the change in the capture group
so we actually use the right gist id instead of the example one.

So, it was always a tab? yes! Any questions? Drop a comment 👇

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "How to open multiple files in vim",
  author: "Gabriel Garrido",
  description: "In this article we will quickly see a few different ways of opening multiple files in vim and how to
  navigate these, keep an eye out for the bonus section as it can get complex pretty quickly.",
  tags: ~w(vim tips-and-tricks),
  published: true,
  image: "vim-tips.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

### **Introduction**

This will be a short article exploring the different ways you can open multiple files in vim at once, and the basic ways
to interact with them, as tabs, windows.
<br/> 

The basic options are:
* [tabs](https://vimhelp.org/tabpage.txt.html)
* [windows](https://vimhelp.org/windows.txt.html#windows)

<br/> 

Straight from the vim's help page:
> Summary:
>
>   A buffer is the in-memory text of a file.
>
>   A window is a viewport on a buffer.
>
>   A tab page is a collection of windows.

<br/> 

In the following examples I will be using the 2024 markdown files of this blog to illustrate how it works, how to move
between buffers, tabs and windows, do note that in zsh `**.md` will expand automatically to all files in that folder
with the full relative path, for example for a single file: `priv/posts/2024/02-24-multinode-setup.md`

<br/> 

### How to open multiple files as buffers in vim?

```elixir
> vim priv/posts/2024/**.md 
```
<br />

If we type `:buffers` then we can see the list of buffers opened in our vim instance, using `:bnext` and `:bprev` you
can move between buffers, the symbols show which buffer is active, which one is hidden or inactive: 
```elixir
:buffers
1  h   "02-24-multinode-setup.md"     line 1
2  h   "02-25-upgrading-k3s-with-system-upgrade-controller.md" line 1
3  h   "03-16-getting-started-with-wallaby-integration-tests.md" line 1
4  h   "03-19-rss-is-not-dead-yet.md" line 1
5 #h   "04-14-remote-iex-session.md"  line 1
6 %a   "04-16-migrating-from-cronjobs-to-quantum-core.md" line 1
7  h   "04-16-running-cronjobs-in-kubernetes.md" line 1
8  h   "04-16-vim-open-multiple-files.md" line 1
Press ENTER or type command to continue
```
<br />

### How to open multiple files as tabs in vim?
Similarly if we do `vim -p`, we will get all buffers opened as tabs, then you can list the tabs with `:tabs`, move 
between them with `:tabn` and back with `:tabp`, the main difference here is how the vim window treats a buffer on a single tab vs multiple tabs.
```elixir
vim -p priv/posts/2024/**.md
```
<br />

Here you can see the list of tabs, for vim these tabs can hold multiple contents even split windows, that can't happen
in a single tab buffer kind of window for example.
```elixir
:tabs
Tab page 1
    02-24-multinode-setup.md
Tab page 2
>   02-25-upgrading-k3s-with-system-upgrade-controller.md
Tab page 3
#   03-16-getting-started-with-wallaby-integration-tests.md
Tab page 4
    03-19-rss-is-not-dead-yet.md
Tab page 5
    04-14-remote-iex-session.md
Tab page 6
    04-16-migrating-from-cronjobs-to-quantum-core.md
Tab page 7
    04-16-running-cronjobs-in-kubernetes.md
Tab page 8
    04-16-vim-open-multiple-files.md
Press ENTER or type command to continue
```
<br />

### How to open multiple files as windows in vim?
I guess the window is the tricky concept here, as a window can display a buffer, and multiple windows can be in a tab,
so basically a window is the way we have to represent and see/interact interactively with a buffer.

so if we wanted to open all these files as windows we would have to do `vim -o` to open them horizontally split, `vim -O` 
for vertical split, if you ask me this is the feature I use the least, but it can be handy in some scenarios. 

To move between windows you will need to use `ctrl-w-<hjkl>` depending on the position of the window that you want to jump
or move to.
```elixir
vim -o priv/posts/2024/**.md
vim -O priv/posts/2024/**.md
```
<br />

### Bonus tip
Perform a search and replace in multiple buffers, vim is perfectly capable of doing some advanced replacements, 
here is an example of such task, when I was migrating to this blog I had a lot of content in github gists and wanted to 
make these just local code snippets, so I used the `gist` command-line helper and made almost all replacements automatic 
with just a command:
```elixir
:%s/{{< gist kainlite \(53f54d81934666457a46cb667f8cea58\) >}}/\=printf('```elixir\n%s\n```', substitute(system('gist -r ' . submatch(1)), '\n', '\\n', 'g'))/
```
That's an intimidating search and replace, basically what this does is searches for the 
pattern `{{< gist kainlite \(capture_this_part\) >}}` so we can extract the gist id first, then `\=` tells vim that we 
want to use the expression in the replacement, then with the help of `printf` we build our code snippet using the output
of the command `gist -r gist_id`, then `substitute` is used to run the command and use the output as part of our
replacement.

<br />
So for the sake of the example, the following gist:

```elixir
{{< gist kainlite 53f54d81934666457a46cb667f8cea58 >}}
```
<br />

Would become the next snippet of code after running the previous command (this would be plain unformatted text):
    ```elixir
    ❯ kind create cluster
    Creating cluster "kind" ...
     ✓ Ensuring node image (kindest/node:v1.21.1) 🖼
     ✓ Preparing nodes 📦
     ✓ Writing configuration 📜
     ✓ Starting control-plane 🕹️
     ✓ Installing CNI 🔌
     ✓ Installing StorageClass 💾
    Set kubectl context to "kind-kind"
    You can now use your cluster with:

    kubectl cluster-info --context kind-kind

    Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
    ```

<br />

But what does any of that has to do with buffers and all that? well, you can apply that search and replace to all
buffers using `:bufdo`, so our command would become:
```elixir
:bufdo %s/{{< gist kainlite \(.*\) >}}/\=printf('```elixir\n%s\n```', substitute(system('gist -r ' . submatch(1)), '\n', '\\n', 'g'))/
```
And that will apply the search and replace command to all the opened buffers, also note the change in the capture group
so we actually use the right gist id instead of the example one.

So, it was always a tab? yes! Any questions? Drop a comment 👇

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

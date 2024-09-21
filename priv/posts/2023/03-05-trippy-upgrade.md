%{
  title: "Upgrading to Phoenix 1.7",
  author: "Gabriel Garrido",
  description: "Upgrading phoenix from 1.6 to 1.7...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
It's been a while since I have been doing anything with this small project, but since I'm playing with some new small
projects using Phoenix 1.7.1 I thought the sane thing to do was to upgrade this blog before it pass too much time so
things are relatively fresh, however it was a really big upgrade, I invite you to review the changes in github, because
I won't put the steps to move away from LiveView helpers to Components.
<br />

Before going into this, be sure to check the release page for additional information on what changes, what to expect,
etc, [Phoenix 1.7.0 release notes](https://phoenixframework.org/blog/phoenix-1.7-final-released), then you can dig
through here for the [upgrade notes](https://gist.github.com/chrismccord/00a6ea2a96bc57df0cce526bd20af8a7).
<br />

[Git commit with all the changes!](https://github.com/kainlite/tr/commit/5cfde253f6ac82dcd41434fcbf9cf503d6848148), hope
this helps figure out everything that you need to do in order to get on the new folder structure.
<br />

##### **Upgrading packages**
Upgrade packages manually in `mix.exs`:
```elixir
    {:phoenix, "~> 1.7.1"},
    {:phoenix_live_view, "~> 0.18.3"},
    {:phoenix_live_dashboard, "~> 0.7.2"},
``` 
If you have `phoenix` and `gettext` from your `:compilers` line in `mix.exs` remove it.
<br />

Update your `.formatter.exs`
```elixir
[
  import_deps: [:ecto, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```
<br />

Some things that can get a bit tricky, so these have been copied directly from the upgrade notes:
> Phoenix.LiveView.Helpers has been soft deprecated and all relevant functionality has been migrated. You must import Phoenix.Component where you previously imported Phoenix.LiveView.Helpers when upgrading (such as in your lib/app_web.ex). You may also need to import Phoenix.Component where you also imported Phoenix.LiveView and some of its functions have been moved to Phoenix.Component.

> live_title_tag has also been renamed to live_title as a function component. Update your root.html.heex layout to use the new component:
```elixir
-   <%= live_title_tag assigns[:page_title] || "Onesixfifteen", suffix: " · Phoenix Framework" %>
+   <.live_title suffix=" · Phoenix Framework">
+     <%= assigns[:page_title] || "MyApp" %>
+   </.live_title>
```
<br />

##### **Important**
Some important links:
https://hexdocs.pm/phoenix_view/Phoenix.View.html#module-migrating-to-phoenix-component
https://elixirstream.dev/gendiff

kudos to [jbosse](https://gist.github.com/jbosse) and 
[srikanthkyatham](https://gist.github.com/srikanthkyatham) for the links, and everyone in the comments figuring out
different issues.

and last but not least good luck!
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...

This was based from the steps described in the [official upgrade notes]().
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Upgrading to Phoenix 1.7",
  author: "Gabriel Garrido",
  description: "Upgrading phoenix from 1.6 to 1.7...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

### Traduccion en proceso

##### **Introduction**
It's been a while since I have been doing anything with this small project, but since I'm playing with some new small
projects using Phoenix 1.7.1 I thought the sane thing to do was to upgrade this blog before it pass too much time so
things are relatively fresh, however it was a really big upgrade, I invite you to review the changes in github, because
I won't put the steps to move away from LiveView helpers to Components.
<br />

Before going into this, be sure to check the release page for additional information on what changes, what to expect,
etc, [Phoenix 1.7.0 release notes](https://phoenixframework.org/blog/phoenix-1.7-final-released), then you can dig
through here for the [upgrade notes](https://gist.github.com/chrismccord/00a6ea2a96bc57df0cce526bd20af8a7).
<br />

[Git commit with all the changes!](https://github.com/kainlite/tr/commit/5cfde253f6ac82dcd41434fcbf9cf503d6848148), hope
this helps figure out everything that you need to do in order to get on the new folder structure.
<br />

##### **Upgrading packages**
Upgrade packages manually in `mix.exs`:
```elixir
    {:phoenix, "~> 1.7.1"},
    {:phoenix_live_view, "~> 0.18.3"},
    {:phoenix_live_dashboard, "~> 0.7.2"},
``` 
If you have `phoenix` and `gettext` from your `:compilers` line in `mix.exs` remove it.
<br />

Update your `.formatter.exs`
```elixir
[
  import_deps: [:ecto, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```
<br />

Some things that can get a bit tricky, so these have been copied directly from the upgrade notes:
> Phoenix.LiveView.Helpers has been soft deprecated and all relevant functionality has been migrated. You must import Phoenix.Component where you previously imported Phoenix.LiveView.Helpers when upgrading (such as in your lib/app_web.ex). You may also need to import Phoenix.Component where you also imported Phoenix.LiveView and some of its functions have been moved to Phoenix.Component.

> live_title_tag has also been renamed to live_title as a function component. Update your root.html.heex layout to use the new component:
```elixir
-   <%= live_title_tag assigns[:page_title] || "Onesixfifteen", suffix: " · Phoenix Framework" %>
+   <.live_title suffix=" · Phoenix Framework">
+     <%= assigns[:page_title] || "MyApp" %>
+   </.live_title>
```
<br />

##### **Important**
Some important links:
https://hexdocs.pm/phoenix_view/Phoenix.View.html#module-migrating-to-phoenix-component
https://elixirstream.dev/gendiff

kudos to [jbosse](https://gist.github.com/jbosse) and 
[srikanthkyatham](https://gist.github.com/srikanthkyatham) for the links, and everyone in the comments figuring out
different issues.

and last but not least good luck!
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...

This was based from the steps described in the [official upgrade notes]().
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

%{
  title: "New blog",
  author: "Gabriel Garrido",
  description: "New blog to document and learn about the infamous Web3 world with a dynamic self-hosted blog...",
  tags: ~w(elixir phoenix),
  published: true,
  image: "phoenix.png",
  sponsored: false,
  video: ""
}
---

##### **Introduction**
This is my new blog, I want to run some web3 experiments and this is the place where it will happen and also where it
will be tested and explained, what, how, etc, I will still update and post as usual in my main blog
[here](https://techsquad.rocks) about linux, kubernetes, containers, etc.
<br />

##### **Web3**
Web3 might not be the definitive solution but it does solve some interesting problems, so let's explore here what those
are, and how can we use it in our "Web2" world, that's the idea for this blog, so far you won't see much "Web3" in it,
but sooner or late it will be here, but first let's take a look how all this is working and running here...
<br />

##### **Generating the app**
We need to install hex locally, then the Phoenix generator, and then our app, we also generated a Dockerfile for our
production deployment.
```elixir
mix local.hex
mix archive.install hex phx_new
# Create the app
mix phx.new tr
# Create the Dockerfile
mix phx.gen.release --docker
``` 
<br />

Don't forget about Ecto and the DB:
```elixir
mix ecto.create
mix ecto.migrate
```

You can see all the modified files in this [branch](https://github.com/kainlite/tr/commits/blog).

Then you can follow [this article](https://elixirschool.com/en/lessons/misc/nimble_publisher) to build your own, it's
relatively easy, just be careful with the names.
<br />

##### **What's coming?**
Since the basic stuff is already here, now to improve visuals a bit and start working on some of the experiments, expect
changes on this blog and hopefully many interesting posts, some of the things I want to do for this blog is a comment
system with Web3 authentication (signed messages) for example, and some other things that will come later, for now it's
good enough to get going...

The next article will explore the setup to get here, but that probably belongs to my main blog, since it is fairly
complex I will try to summarize it as much as possible.
<br />

##### **Closing notes**
Let me know if there is anything that you would like to see implemented or tested, explored and what not in here...
<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

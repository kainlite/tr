%{
  title: "Migrating from kubernetes cronjobs to quantum-core",
  author: "Gabriel Garrido",
  description: "In this article we will move our scheduled tasks away from kubernetes and instead we will use
  quantum-core to schedule and run these tasks, we can simplify some things in the tasks themselves as we won't need to
  boot our entire app before running our task.",
  tags: ~w(elixir phoenix tips-and-tricks),
  published: true,
  image: "trickster-clock.png"
}
---

### **Introduction**

![trickster](/images/trickster-clock.png){:class="mx-auto" style="max-height: 450px;"}
In case you are wondering about the image, it is intended to represent the trickster, as I plan to do many posts about
tips and tricks and thought this would be somewhat funny 😄.
<br/> 

In this article we will explore how to move from regular tasks and the classic cron scheduler 
to [quantum-core](https://github.com/quantum-elixir/quantum-core), we will take advantage of the beam that we are
already running to manage scheduled tasks this has some benefits and drawbacks, but for my use case, it should work
fine, currently there are two scenarios that need to be run periodically, one is daily and the second one is hourly,
there are not many changes to these parts of the system so this is perfect for it, also will reduce the amount of
resources in the cluster as everything will be handled by the app.
<br/> 

Do note that you can manage tasks programatically and that's why this library is so flexible, you could manage
everything from a web interface or from iex, however for the sake of simplicity and because that's now how I will be
using it, we will see how to replace the current cronjobs with the regular config approach.
<br/> 

If you want to learn more abour running some elixir tasks in kubernetes you can head out to the previous
article: [running cronjobs in kubernetes](/blog/running-cronjobs-in-kubernetes)
<br/> 

### **Steps**
Some steps are required to make this cron work:
* Add the library to deps in `mix.exs`
* Create your scheduler `lib/tr/scheduler.ex`
* Add it to your children list in the app supervisor `lib/tr/application.ex`
* Configure your scheduled tasks `config/config.ex`
* Restart your server & verify!
<br/> 

#### Add library to the deps in `mix.exs`
```elixir
  {:quantum, "~> 3.5"}
```
Run `mix.deps get` to fetch the new dependency.

#### Create your scheduler `lib/tr/scheduler.ex`
This is key as this will be the app running as the cron.
```elixir
defmodule Tr.Scheduler do
  @moduledoc """
  Cron-like scheduler
  """
  use Quantum, otp_app: :tr
end
```

#### Add it to your children list in the app supervisor `lib/tr/application.ex`
Last but not least, start the app, otherwise our cron won't cron 😅, place it before the Endpoint, usually the Endpoint
always would be the last thing that you want to start, so no client can reach the application before everything has been
started and it is running as expected.
```elixir
    children = [
      # ...
      # Start the scheduler
      Tr.Scheduler,
      # ...
    ]
```

#### Configure your scheduled tasks `config/config.ex`
Okay, that was easy, now the last step, configure the actual tasks, quantum supports several formats but I went with the
classic MFA (Module-Function-Arguments).
```elixir
config :tr, Tr.Scheduler,
       jobs: [
         # Every 30 minutes
         {"*/30 * * * *", {Tr.Tracker, :start, []}},
         # Every 15 minutes
         {"*/15 * * * *", {Tr.Approver, :start, []}}
       ]
```

#### Restart your server & verify!
Excelent! it seems to be working as expected
```elixir
iex -S mix phx.server
[debug]  Loading Initial Jobs from Config
[debug]  Adding job
[debug]  Adding job
[info]  Running TrWeb.Endpoint with Bandit 1.4.2 at 127.0.0.1:4000 (http)
[info]  Access TrWeb.Endpoint at http://localhost:4000
Erlang/OTP 26 [erts-14.2.3] [source] [64-bit] [smp:32:32] [ds:32:32:10] [async-threads:1] [jit:ns]

[watch] build finished, watching for changes...
Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)

Rebuilding...

[debug]  Scheduling job for execution
[debug]  Task for job started on node
[debug]  Execute started for job
[debug]  QUERY OK source="comments" db=0.2ms queue=0.4ms idle=1076.1ms
SELECT c0."id", c0."slug", c0."body", c0."parent_comment_id", c0."approved", c0."inserted_at", c0."updated_at", c0."user_id" FROM "comments" AS c0 WHERE (NOT (c0."approved")) []
↳ Tr.Post.get_unapproved_comments/0, at: lib/tr/post.ex:158
[debug]  Execution ended for job
```

### Key takeways 
As you can see, running your own cron-like scheduler in the BEAM is pretty straight-forward, you have full control, more
flexibility and also it is pretty simple to get started with it.
<br />

But what about our previous code that had to call `Application.load(:app_name)`, and
`Application.ensure_all_started(:app_name)`? Well, that can remain unchanged, yes, if it was already loaded and
started it won't do anything, so if we ever want to rollback to an old fashion external cronjob, we can, if not we can
keep using our new fancy cron 😄.
<br />

Code example below for the Approver task:
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
<br />
A few notes, you could do many things differently for example you might want to set different schedules in different
environments, use the config file that makes sense for you, you can also explore and use the cron with some [runtime
configuration](https://hexdocs.pm/quantum/runtime-configuration.html), in any case that you decide to use, make sure it
does the job that you expect it to do efficiently.

<br/> 
Any questions? Drop a comment 👇, you might need to wait 15 minutes for the job to run before it can be read 😄, but at
least now you know how it works!

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br /> 

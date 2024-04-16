%{
  title: "Remote iex session",
  author: "Gabriel Garrido",
  description: "In this article we will see how to connect to your production instances from a development machine, this
  can be useful for many different reasons, handle with care when doing so but know how in case you need to do some
  manual intervention.",
  tags: ~w(elixir shell phoenix tips-and-tricks),
  published: true,
  image: "trickster.png"
}
---

### **Introduction**

![trickster](/images/trickster.png){:class="mx-auto"}
In case you are wondering about the image, it is intended to represent the trickster, as I plan to do many posts about
tips and tricks.
<br />

In case you are wondering the image was generated using [Gemini](https://gemini.google.com), so basically some times you
need to run a script or validate some information in your productive environment, while connecting directly to the
database is sometimes an option it should be discouraged, you want in most cases to interact with your database from
code that was tested and prepared for certain scenario, but sometimes that code is not easily available so you need a
terminal to be able to run it, but how can we do that in the elixir / beam world?
<br />

Be aware that whilst this is an option you should always strive to use migrations or some tested and automated way if
feasible, in a subsequent article we will explore how to do that with cron jobs in kubernetes.
<br />

#### Options?
* port-forward to the prod instance or cluster
* from one of the machines or pods (if using kubernetes)

there are likely many more options but we will explore these two.
<br />

### **Port-forward**
In this scenario we will use our local stack to connect to the remote instances or cluster, how do we do so? figure that
the port-forward is sorted out or you have a allowlist in place for your IP address or connection, in kubernetes we can
do it like this, first lets validate that we can reach the remote instances:
```elixir
❯ epmd -names
epmd: up and running on port 4369 with data:
name rem-1ed8-tr at port 35229
name tr at port 44091
```
Then you will need the cookie in order to connect to the cluster, you can fetch that from your environment variables or
secrets, the cookie is used as the grouping mechanism rather than a password in a beam cluster, when that is done you
can connect like this:
```elixir
ssh user@remote -L4369:localhost:4369 -L44091:localhost:44091
```
Do note that you need to use the port of the app/node that you want to connect to.

In kubernetes you would need two port-forward commands: 
```elixir
kubectl -n tr port-forward pod/tr-xxxx 4369:4369 &
kubectl -n tr port-forward pod/tr-xxxx 44091:44091 &
```
<br />

Finally, the local shell:
```elixir
iex --name local@127.0.0.1 --cookie my_cookie --remsh tr@127.0.0.1
```
Note: if you can't remember your cookie or find it in your environment connect to any node and run `Node.get_cookie()`.
<br />

Then you can run the `:observer.start()` app with that command, or any module that was loaded in the cluster, while this
is fun and all it is too complex and has many drawbacks, so my recommendation is to stick with the second method, it is
safer, it has less dependencies and it is way simpler to use.
<br />

#### **Important** 

Do notice that there are security implications when connecting via port-forward, as your machine will be part of the
cluster (this can be mitigated by using a docker container for example), but otherwise anyone else connected to the
cluster could gain full access to your machine, so use this as a last resort thing.

You can read more in this great [article](https://broot.ca/erlang-remsh-is-dangerous.html)
<br />

### **Remote machine or pod**
This scenario assumes you have access to the given environment where the application is running, it is really straight
forward in this case assuming that you can jump to the host, for example:
```elixir
❯ kubectl -n tr exec -ti tr-xxxx -- /app/bin/tr remote
Erlang/OTP 26 [erts-14.2.1] [source] [64-bit] [smp:1:1] [ds:1:1:10] [async-threads:1] [jit]

Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)
iex(tr@10.42.0.17)2> Enum.count(Tr.Blog.posts)
49
```
if you are using the release files that can be generated from phoenix helpers (`mix phx.gen.release --docker` and 
`mix release.init`) then you app entrypoint will be located under `/app/bin/app_name`, in this case `tr`, then by using 
remote we can get an `iex` shell and interact with our modules.

if you were in a virtual machine environment just remove everything before `--` and use `ssh` instead.

Any questions? Drop a comment 👇
<br />

##### **Closing notes**
Never expose `epmd` to the internet, nor your node random port, instead use ssh or a host in the destination network,
this way it is easier to isolate the workload and prevent unwanted surprises, I hope it was useful for you as it was for
me.
<br />
##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

defmodule Tr.Labs do
  @moduledoc """
  Registry of interactive labs (challenges embedded in blog posts) and the
  learning tracks that group them.

  Built at compile time from the static challenge JSON definitions in
  `priv/static/challenges` plus a scan of each published post's rendered body
  for the `data-challenge` embeds. Completion is tracked client-side in the
  browser (localStorage), so this module only knows the catalogue, not who has
  finished what.
  """

  alias Tr.Blog

  # --- challenge metadata, read from the static JSON definitions -------------
  @challenges_dir Application.app_dir(:tr, "priv/static/challenges")
  @json_paths Path.wildcard(Path.join(@challenges_dir, "*.json"))
  for path <- @json_paths, do: @external_resource(path)

  @meta (for path <- @json_paths, into: %{} do
           decoded = path |> File.read!() |> Jason.decode!()

           {decoded["id"],
            %{
              id: decoded["id"],
              title: decoded["title"],
              mode: decoded["mode"],
              image: decoded["image"]
            }}
         end)

  # --- where each challenge is embedded: post id + the div id to anchor on ---
  @embed_re ~r/<div\s+id="([^"]+)"[^>]*data-challenge="([^"]+)"/

  @embeds (for post <- Blog.all_posts(), (post.lang || "en") == "en", reduce: %{} do
             acc ->
               @embed_re
               |> Regex.scan(post.body)
               |> Enum.reduce(acc, fn [_, div_id, cid], inner ->
                 Map.put_new(inner, cid, %{
                   post_id: post.id,
                   post_title: post.title,
                   div_id: div_id
                 })
               end)
           end)

  # --- learning tracks (ordered challenge ids) -------------------------------
  @tracks [
    %{
      slug: "linux",
      title: "Learn Linux",
      icon: "🐧",
      desc:
        "Files and permissions, searching with grep, taming processes, and living in the terminal with tmux and vim.",
      labs: ~w(linux-permissions linux-search linux-process tmux-basics vim-edit)
    },
    %{
      slug: "networking",
      title: "Networking & SSH",
      icon: "🔌",
      desc: "SSH tunnels (local, remote, and SOCKS) plus raw TCP plumbing with netcat and socat.",
      labs:
        ~w(ssh-tunnels-local-forward ssh-tunnel-local-forward-real ssh-remote-forward ssh-socks-proxy netcat-socat-relay)
    },
    %{
      slug: "git",
      title: "Learn Git",
      icon: "🌳",
      desc:
        "The everyday workflow and how to rescue work you thought you had lost, as quick command drills and then for real on a Linux box.",
      labs: ~w(git-basics git-workflow-real git-reflog-recovery git-reflog-real)
    },
    %{
      slug: "docker",
      title: "Learn Docker",
      icon: "🐳",
      desc:
        "Run containers, manage images, build from a Dockerfile, persist data with volumes, and wire up Compose and networking.",
      labs:
        ~w(docker-basics container-chroot container-namespaces docker-images dockerfile-build docker-volumes docker-compose docker-networking)
    },
    %{
      slug: "kubernetes",
      title: "Learn Kubernetes",
      icon: "☸️",
      desc:
        "From your first Deployment to Secrets, RBAC, debugging distroless pods, incident response, and Helm.",
      labs: ~w(k8s-fundamentals k8s-secrets k8s-rbac k8s-debug k8s-incident-triage helm-basics)
    },
    %{
      slug: "devops",
      title: "Learn DevOps",
      icon: "🚀",
      desc:
        "A cross-tool path for beginners: version control, containers, infrastructure as code, Kubernetes, and handling incidents.",
      labs:
        ~w(git-basics git-workflow-real docker-basics terraform-basics k8s-fundamentals k8s-incident-triage)
    }
  ]

  @doc "All tracks, each with its `:labs` resolved to full metadata (embedded labs only)."
  def tracks do
    for track <- @tracks do
      labs = track.labs |> Enum.map(&lab/1) |> Enum.reject(&is_nil/1)
      %{track | labs: labs}
    end
    |> Enum.reject(&(&1.labs == []))
  end

  @doc "Lab metadata merged with its embed location, or nil if unknown or not embedded."
  def lab(id) do
    meta = Map.get(@meta, id)
    embed = Map.get(@embeds, id)

    if meta && embed, do: Map.merge(meta, embed), else: nil
  end

  @doc "All embedded labs, sorted by title."
  def all_labs do
    @meta
    |> Map.keys()
    |> Enum.map(&lab/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.title)
  end

  @doc "Labs embedded in a given post id (used for the post badge)."
  def labs_in_post(post_id) do
    Enum.filter(all_labs(), &(&1.post_id == post_id))
  end

  @doc "Total number of embedded labs."
  def count, do: length(all_labs())

  @doc "Embedded labs grouped by their post: a list of %{post_id, post_title, labs}."
  def by_post do
    all_labs()
    |> Enum.group_by(& &1.post_id)
    |> Enum.map(fn {post_id, labs} ->
      %{post_id: post_id, post_title: hd(labs).post_title, labs: labs}
    end)
    |> Enum.sort_by(& &1.post_title)
  end
end

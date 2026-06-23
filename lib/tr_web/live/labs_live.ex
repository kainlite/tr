defmodule TrWeb.LabsLive do
  use TrWeb, :live_view

  alias Tr.Labs

  @impl true
  def mount(_params, _session, socket) do
    locale = Gettext.get_locale(TrWeb.Gettext)

    {
      :ok,
      socket
      |> assign(:page_title, "SegFault - Interactive Labs")
      |> assign(:og_url, TrWeb.Endpoint.url() <> "/#{locale}/labs")
      |> assign(:og_hreflang_en, TrWeb.Endpoint.url() <> "/en/labs")
      |> assign(:og_hreflang_es, TrWeb.Endpoint.url() <> "/es/labs")
      |> assign(:locale, locale)
      |> assign(:tracks, Labs.tracks())
      |> assign(:by_post, Labs.by_post())
      |> assign(:count, Labs.count())
    }
  end

  defp lab_href(locale, lab), do: "/#{locale}/blog/#{lab.post_id}##{lab.div_id}"

  defp mode_label(%{mode: "v86"}), do: "real VM"
  defp mode_label(_), do: "drill"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="labs-root" phx-hook="LabProgress" class="space-y-8">
      <div class="font-mono">
        <span class="text-accent-light dark:text-accent">$</span>
        <span class="text-terminal-400 ml-2">ls /labs</span>
        <h1 class="text-2xl sm:text-3xl font-bold mt-2 text-zinc-900 dark:text-zinc-100">
          {gettext("Interactive Labs")}
        </h1>
        <p class="mt-2 text-zinc-600 dark:text-zinc-300 max-w-2xl">
          {gettext(
            "Hands-on challenges you finish right here in your browser. No signup, no servers: scripted command drills plus real Linux boxes compiled to WebAssembly. Pick a track, or jump straight into any lab."
          )}
        </p>

        <div class="mt-4 flex items-center gap-3 font-mono text-sm max-w-2xl">
          <span class="text-terminal-400">{gettext("progress")}</span>
          <div class="flex-1 h-2 rounded bg-terminal-200 dark:bg-terminal-700 overflow-hidden">
            <div
              data-labs-bar
              class="h-full bg-accent-light dark:bg-accent transition-all duration-500"
              style="width:0%"
            >
            </div>
          </div>
          <span class="text-zinc-700 dark:text-zinc-200 whitespace-nowrap">
            <span data-labs-done>0</span> / <span data-labs-total>{@count}</span>
          </span>
        </div>
      </div>

      <div class="space-y-4">
        <h2 class="font-mono text-lg font-bold text-zinc-900 dark:text-zinc-100">
          {gettext("Tracks")}
        </h2>
        <div class="grid gap-4 sm:grid-cols-2">
          <section
            :for={track <- @tracks}
            data-track={track.slug}
            class="tr-track border border-terminal-300 dark:border-terminal-600 rounded-lg p-4"
          >
            <div class="flex items-center gap-2">
              <span class="text-xl">{track.icon}</span>
              <h3 class="font-mono font-bold text-zinc-900 dark:text-zinc-100">{track.title}</h3>
              <span class="ml-auto font-mono text-xs text-terminal-400" data-track-count>
                0 / {length(track.labs)}
              </span>
            </div>
            <div class="mt-2 h-1.5 rounded bg-terminal-200 dark:bg-terminal-700 overflow-hidden">
              <div
                data-track-bar
                class="h-full bg-accent-light dark:bg-accent transition-all duration-500"
                style="width:0%"
              >
              </div>
            </div>
            <p class="mt-2 text-sm text-zinc-600 dark:text-zinc-300">{track.desc}</p>
            <ol class="mt-3 space-y-1">
              <li :for={{lab, i} <- Enum.with_index(track.labs, 1)}>
                <.link
                  href={lab_href(@locale, lab)}
                  data-lab-id={lab.id}
                  class="tr-lab-row group flex items-center gap-2 font-mono text-sm no-underline text-zinc-700 dark:text-zinc-200 hover:text-accent-light dark:hover:text-accent"
                >
                  <span
                    data-lab-check
                    class="tr-lab-check w-4 shrink-0 text-accent-light dark:text-accent"
                  >
                  </span>
                  <span class="text-terminal-400 shrink-0">{i}.</span>
                  <span class="group-hover:underline">{lab.title}</span>
                  <span class="ml-auto shrink-0 text-[10px] uppercase tracking-wide text-terminal-400">
                    {mode_label(lab)}
                  </span>
                </.link>
              </li>
            </ol>
          </section>
        </div>
      </div>

      <div class="space-y-3">
        <h2 class="font-mono text-lg font-bold text-zinc-900 dark:text-zinc-100">
          {gettext("Posts with labs")}
        </h2>
        <ul class="space-y-2">
          <li :for={group <- @by_post} class="font-mono text-sm">
            <.link
              navigate={~p"/#{@locale}/blog/#{group.post_id}"}
              class="text-accent-light dark:text-accent hover:underline no-underline"
            >
              {group.post_title}
            </.link>
            <span class="text-terminal-400">
              · {length(group.labs)} {if length(group.labs) > 1,
                do: gettext("labs"),
                else: gettext("lab")}
            </span>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end

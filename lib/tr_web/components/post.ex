defmodule TrWeb.PostComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_tag_card(assigns) do
    ~H"""
    <li class="tag-pill list-none mx-1 px-4 py-2 hover:shadow-glow-sm">
      <span class="inline-flex items-center justify-center text-white bg-brand-500 rounded-full w-8 h-8 text-sm
        font-semibold mr-2">
        {Enum.count(Tr.Blog.by_tag(Gettext.get_locale(TrWeb.Gettext), @tag))}
      </span>
      <.link
        navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/tags/#{@tag}"}
        class="inline-flex items-center justify-center text-lg font-semibold text-zinc-700 dark:text-zinc-200 hover:text-brand-500 dark:hover:text-brand-400"
      >
        {@tag}
      </.link>
    </li>
    """
  end

  def render_post_card(assigns) do
    ~H"""
    <div id={@post.id}>
      <div class="relative group">
        <div class="card-tech rounded-xl overflow-hidden w-[39rem] h-[30rem] m-4
            hover:shadow-glow transition-all duration-300">
          <%= if @post.sponsored do %>
            <.link href="https://github.com/sponsors/kainlite#sponsors" class="">
              <.icon
                name="hero-lock-closed-solid"
                class="absolute right-6 top-3 w-7 h-7 text-brand-500 dark:text-brand-400 z-10"
              />
            </.link>
          <% else %>
            <.icon
              name="hero-lock-open-solid"
              class="absolute right-6 top-3 w-7 h-7 text-zinc-400 dark:text-zinc-500 z-10"
            />
          <% end %>
          <.link
            navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@post.id}"}
            class="block relative"
          >
            <img
              src={~p"/images/#{@post.image}"}
              alt="Article Image"
              class="w-full h-32 sm:h-48 object-center object-scale-down group-hover:scale-105 transition-transform duration-300"
            />
            <div class="absolute inset-0 bg-gradient-to-t from-surface-900/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
          </.link>
          <div class="p-6">
            <h2 class="text-xl font-bold mb-2 truncate">
              <.link
                navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@post.id}"}
                class="inline-block text-zinc-900 dark:text-zinc-100 hover:text-brand-500 dark:hover:text-brand-400 transition-colors"
              >
                {@post.title}
              </.link>
              <p class="text-sm float-right font-semibold text-zinc-500 dark:text-zinc-400">
                <time>{@post.date}</time>
              </p>
            </h2>
            <p class="mx-auto text-sm sm:text-base sm:leading-7 text-zinc-600 dark:text-zinc-300">
              {raw(@post.description)}
            </p>
          </div>
          <div class="absolute bottom-3 right-6">
            <.link
              navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/#{@post.id}"}
              class="mt-4 inline-block text-brand-500 dark:text-brand-400 hover:text-brand-600 dark:hover:text-brand-500 float-right text-base font-semibold transition-colors"
            >
              {gettext("Read more...")}
            </.link>
          </div>
          <div class="absolute bottom-0 left-6 flex flex-wrap gap-2">
            <%= for tag <- @post.tags do %>
              <span class="tag-pill text-sm">
                <.link
                  navigate={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog/tags/#{tag}"}
                  class="flex items-center gap-1"
                >
                  <span class="inline-flex items-center justify-center text-white bg-brand-500 rounded-full w-6 h-6 text-xs font-semibold">
                    {Enum.count(Tr.Blog.by_tag(Gettext.get_locale(TrWeb.Gettext), tag))}
                  </span>
                  <span class="text-zinc-700 dark:text-zinc-300">{tag}</span>
                </.link>
              </span>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

defmodule TrWeb.PostComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_tag_card(assigns) do
    ~H"""
    <li class="bg-white dark:bg-zinc-800 dark:text-white shadow-md p-4 mx-1 rounded-lg border-l-solid border-l-[5px]
      border-l-gray-700 max-w-32 max-h-20">
      <span class="inline-flex items-center justify-center text-white bg-emerald-700 rounded-full w-8 h-8 text-sm
        font-semibold">
        <%= Enum.count(Tr.Blog.by_tag(@tag)) %>
      </span>
      <.link
        navigate={~p"/blog/tags/#{@tag}"}
        class="inline-flex items-center justify-center text-lg font-semibold"
      >
        <%= @tag %>
      </.link>
    </li>
    """
  end

  def render_post_card(assigns) do
    ~H"""
    <div id={@post.id}>
      <div class="relative">
        <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
            h-[30rem] m-4">
          <.link navigate={~p"/blog/#{@post.id}"} class="">
            <img
              src={~p"/images/#{@post.image}"}
              alt="Article Image"
              class="w-full h-32 sm:h-48 object-center object-scale-down"
            />
          </.link>
          <div class="p-6">
            <h2 class="text-xl font-bold mb-2 truncate">
              <.link navigate={~p"/blog/#{@post.id}"} class="inline-block">
                <%= @post.title %>
              </.link>
              <p class="text-sm float-right font-semibold">
                <time><%= @post.date %></time>
              </p>
            </h2>
            <p class="mx-auto text-sm sm:text-base sm:leading-7">
              <%= raw(@post.description) %>
            </p>
          </div>
          <div class="absolute bottom-3 right-6">
            <.link
              navigate={~p"/blog/#{@post.id}"}
              class="mt-4 inline-block text-blue-500 float-right text-base font-semibold"
            >
              Read more...
            </.link>
          </div>
          <div class="absolute bottom-0 left-6">
            <%= for tag <- @post.tags do %>
              <li class="bg-white dark:bg-zinc-800 dark:text-gray-200 text-base font-semibold shadow-md p-4 rounded-lg border-l-solid
              border-l-[5px] border-l-gray-700 float-left list-none">
                <.link navigate={~p"/blog/tags/#{tag}"}>
                  <span class="inline-flex items-center justify-center text-white bg-emerald-700 rounded-full w-8 h-8 text-sm
        font-semibold">
                    <%= Enum.count(Tr.Blog.by_tag(tag)) %>
                  </span>
                  <%= tag %>
                </.link>
              </li>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

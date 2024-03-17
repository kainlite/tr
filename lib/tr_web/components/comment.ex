defmodule TrWeb.CommentComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render(assigns) do
    ~H"""
    <li class={@classes}>
      <div class="flex items-start">
        <img class="w-12 h-12 rounded-full mr-4" src={@avatar_url} alt="User Avatar" />
        <div class="flex-1 max-w[50-rem]">
          <div class="flex justify-between items-center">
            <h2 class="text-lg font-semibold">
              <%= @display_name %>
            </h2>
            <span class="text-gray-500 text-sm">
              #<%= @comment.id %> On <%= @comment.updated_at %>
            </span>
          </div>
          <p class="text-gray-800 mt-2 comment-text text-clip md:text-clip break-words line-clamp-1 max-w-3xl">
            <%= @comment.body %>
          </p>
          <.link
            id={@link_id}
            phx-hook="Scroll"
            class="font-semibold text-sm float-right"
            phx-click="prepare_comment_form"
            phx-value-slug={@comment.slug}
            phx-value-comment-id={@comment.id}
          >
            Reply
          </.link>
        </div>
      </div>
    </li>
    """
  end
end

defmodule TrWeb.CommentComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_comment(assigns) do
    ~H"""
    <% body =
      if @comment.approved, do: @comment.body, else: gettext("Comment hidden, awaiting moderation...") %>
    <li class={@classes}>
      <div class="flex">
        <img class="h-12 rounded-full mr-4" src={@avatar_url} alt="User Avatar" />
        <div class="flex-1 max-w[50-rem] min-h-24">
          <div class="flex justify-between items-center">
            <h2 class="text-lg font-semibold">
              {@display_name}
            </h2>
            <span class="text-gray-500 text-sm">
              #{@comment.id} On {@comment.updated_at}
            </span>
          </div>
          <p class="text-gray-800 dark:text-gray-200 mt-2 comment-text text-clip md:text-clip text-lg break-words line-clamp-1
          max-w-3xl min-h-24">
            {body}
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

  def render_comment_input(assigns) do
    ~H"""
    <%= unless is_nil(@parent_comment_id) do %>
      <.link class="font-semibold text-sm float-right mb-0" phx-click="clear_comment_form">
        clear
      </.link>
      <br />
      <p class="text-sm float-right mb-0">
        Replying in thread #{@parent_comment_id} with {@display_name}
      </p>
    <% end %>
    <.simple_form for={@form} id="comment_form" phx-submit="save">
      <.error :if={@check_errors}>
        {gettext("Oops, something went wrong! Please check the errors below.")}
      </.error>

      <.input field={@form[:body]} type="textarea" label="Message" required />
      <.input
        field={@form[:parent_comment_id]}
        type="hidden"
        id="hidden_parent_comment_id"
        value={@parent_comment_id}
      />
      <.input field={@form[:slug]} type="hidden" id="hidden_post_slug" value={@post.id} />

      <:actions>
        <.button id="comment_submit" phx-disable-with={gettext("Saving...")} class="w-full">
          Send
        </.button>
      </:actions>
    </.simple_form>
    """
  end
end

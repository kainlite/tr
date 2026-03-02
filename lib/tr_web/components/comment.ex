defmodule TrWeb.CommentComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_comment(assigns) do
    ~H"""
    <% body =
      if @comment.approved, do: @comment.body, else: gettext("Comment hidden, awaiting moderation...") %>
    <div class={"border-l-2 border-terminal-300 dark:border-terminal-600 pl-4 py-3 mb-2 #{@classes}"}>
      <div class="flex items-start gap-3">
        <img class="w-8 h-8 rounded-full" src={@avatar_url} alt="Avatar" />
        <div class="flex-1 min-w-0">
          <div class="font-mono text-sm text-accent-light dark:text-accent">
            > @{@display_name} ~ $ comment
          </div>
          <p class="mt-1 text-base break-words line-clamp-3">{body}</p>
          <div class="font-mono text-xs text-terminal-400 mt-1">
            -- @{@display_name}, {@comment.updated_at}
            <.link
              id={@link_id}
              phx-hook="Scroll"
              class="ml-4 text-accent-light dark:text-accent hover:underline no-underline"
              phx-click="prepare_comment_form"
              phx-value-slug={@comment.slug}
              phx-value-comment-id={@comment.id}
            >
              [reply]
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def render_comment_input(assigns) do
    ~H"""
    <%= unless is_nil(@parent_comment_id) do %>
      <div class="flex items-center justify-between font-mono text-sm text-terminal-400 mb-2">
        <span>Replying in thread #{@parent_comment_id} as {@display_name}</span>
        <.link
          class="text-accent-light dark:text-accent hover:underline no-underline"
          phx-click="clear_comment_form"
        >
          [clear]
        </.link>
      </div>
    <% end %>
    <div class="mt-4">
      <div class="font-mono text-sm text-accent-light dark:text-accent mb-2">
        > {@display_name} ~ $
      </div>
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
    </div>
    """
  end
end

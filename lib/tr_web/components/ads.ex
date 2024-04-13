defmodule TrWeb.AdsComponent do
  @moduledoc """
  Comment dumb component
  """
  use TrWeb, :html

  def render_large_ad(assigns) do
    ~H"""
    <%= unless @current_user do %>
      <div class="flex">
        <div id="ignored-ad-1" phx-update="ignore" class="m-auto gap-2 space-y-2 py-2">
          <script type="text/plain" data-category="marketing">
            atOptions = {
            'key' : '8fcf8841e28fcaa7155f184fff2e135e',
            'format' : 'iframe',
            'height' : 90,
            'width' : 728,
            'params' : {}
            };
          </script>
          <script
            type="text/javascript"
            src="//www.topcreativeformat.com/8fcf8841e28fcaa7155f184fff2e135e/invoke.js"
            data-category="marketing"
          >
          </script>
        </div>
      </div>
    <% end %>
    """
  end

  def render_box_ad(assigns) do
    ~H"""
    <%= unless @current_user do %>
      <div class="flex">
        <div id="ignored-ad-2" phx-update="ignore" class="m-auto gap-2 space-y-2 py-2">
          rame sync
          <script type="text/plain" data-category="marketing">
            atOptions = {
            'key' : '740dfb141e07353f1263962a865df705',
            'format' : 'iframe',
            'height' : 250,
            'width' : 300,
            'params' : {}
            };
          </script>
          <script
            data-category="marketing"
            type="text/javascript"
            src="//www.topcreativeformat.com/740dfb141e07353f1263962a865df705/invoke.js"
          >
          </script>
        </div>
      </div>
    <% end %>
    """
  end
end

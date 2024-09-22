defmodule TrWeb.RestoreLocale do
  @moduledoc """
    Restore the locale from the session
  """
  def on_mount(:default, %{"locale" => locale}, _session, socket) do
    Gettext.put_locale(TrWeb.Gettext, locale)
    {:cont, socket}
  end

  # catch-all case
  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end

defmodule TrWeb.Plugs.Locale do
  @moduledoc """
    Restore the locale from the session for non-liveviews
  """
  import Plug.Conn

  @locales ["en", "es"]

  def init(default), do: default

  def call(%Plug.Conn{params: %{"locale" => loc}} = conn, _default) when loc in @locales do
    Gettext.put_locale(TrWeb.Gettext, loc)
    assign(conn, :locale, loc)
  end

  def call(conn, default) do
    Gettext.put_locale(TrWeb.Gettext, default)
    assign(conn, :locale, default)
  end
end

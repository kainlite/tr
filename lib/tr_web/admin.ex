defmodule TrWeb.Hooks.AllowAdmin do
  @moduledoc """
  Sandbox configuration for integration tests
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:require_admin_user, _params, session, socket) do
    user = Tr.Accounts.get_user_by_session_token(session["user_token"])

    case user.admin == true do
      true -> {:cont, socket}
      _ -> {:halt, redirect(socket, to: "/")}
    end
  end
end

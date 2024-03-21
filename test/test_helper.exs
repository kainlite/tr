Mimic.copy(Tr.Ollama)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Tr.Repo, :manual)

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, TrWeb.Endpoint.url())

import Tr.AccountsFixtures
import TrWeb.FeatureCase
import Wallaby.Browser

defmodule TrWeb.TestHelpers do
  @moduledoc """
  Helper module for tests
  """
  def log_in({:normal, session}) do
    user_remember_me = "_tr_web_user_remember_me"

    user = confirmed_user_fixture()
    user_token = Tr.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:tr, TrWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(user_remember_me, conn.resp_cookies[user_remember_me][:value])

    {:ok, %{session: session, user: user}}
  end

  def log_in({:admin, session}) do
    user_remember_me = "_tr_web_user_remember_me"

    user = admin_user_fixture()
    user_token = Tr.Accounts.generate_user_session_token(user)

    endpoint_opts = Application.get_env(:tr, TrWeb.Endpoint)
    secret_key_base = Keyword.fetch!(endpoint_opts, :secret_key_base)

    conn =
      %Plug.Conn{secret_key_base: secret_key_base}
      |> Plug.Conn.put_resp_cookie(user_remember_me, user_token, sign: true)

    session
    |> visit("/")
    |> set_cookie(user_remember_me, conn.resp_cookies[user_remember_me][:value])

    {:ok, %{session: session, user: user}}
  end
end

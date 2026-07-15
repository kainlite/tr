defmodule TrWeb.OAuthState do
  @moduledoc """
  CSRF protection for the OAuth login flows.

  A random `state` value is generated and stored in the session before the user
  is redirected to the identity provider, then verified when the provider calls
  back. This prevents login-CSRF, where an attacker tricks a victim into
  completing a login with an attacker-controlled authorization code.
  """
  import Plug.Conn

  @doc """
  Generates a random state, stores it in the session under `key` and returns the
  updated connection together with the state value to embed in the provider URL.
  """
  @spec put(Plug.Conn.t(), atom()) :: {Plug.Conn.t(), String.t()}
  def put(conn, key) do
    state = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {put_session(conn, key, state), state}
  end

  @doc """
  Returns true when the `state` in the callback params matches the value stored
  in the session under `key`. Uses a constant-time comparison.
  """
  @spec valid?(Plug.Conn.t(), atom(), map()) :: boolean()
  def valid?(conn, key, params) do
    expected = get_session(conn, key)
    provided = params["state"]

    is_binary(expected) and is_binary(provided) and
      Plug.Crypto.secure_compare(expected, provided)
  end
end

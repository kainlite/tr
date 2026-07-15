defmodule TrWeb.Plugs.CSP do
  @moduledoc """
  Sets a Content-Security-Policy header on browser responses.

  The policy is deliberately strict on scripts (no `unsafe-inline`, no
  `unsafe-eval`) since inline `<script>` blocks are only ever data
  (`application/json`, `application/ld+json`) and all executable code is either
  bundled (`'self'`) or loaded from a small allowlist of CDNs. Styles allow
  `unsafe-inline` because the templates render inline `style=` attributes.

  Allowlist rationale:
    * cdn.jsdelivr.net       - mermaid, asciinema player, v86 (libv86 + wasm)
    * cdnjs/buymeacoffee.com - "Buy me a coffee" widget + its iframe
    * 'wasm-unsafe-eval'     - v86 compiles the guest VM to WebAssembly
    * img https:             - user avatars (robohash) and post images
    * frame youtube          - embedded videos on sponsored posts
  """
  import Plug.Conn

  @directives [
    {"default-src", ["'self'"]},
    {"script-src",
     [
       "'self'",
       "'wasm-unsafe-eval'",
       # v86 loads its worker from a blob: URL to run the guest Linux VM
       "blob:",
       "https://cdn.jsdelivr.net",
       "https://cdnjs.buymeacoffee.com",
       "https://buymeacoffee.com"
     ]},
    {"style-src", ["'self'", "'unsafe-inline'", "https://cdn.jsdelivr.net"]},
    {"img-src", ["'self'", "data:", "https:"]},
    {"font-src", ["'self'", "data:", "https://cdn.jsdelivr.net"]},
    {"connect-src", ["'self'", "https://cdn.jsdelivr.net"]},
    {"frame-src",
     [
       "'self'",
       "https://www.youtube.com",
       "https://www.youtube-nocookie.com",
       "https://buymeacoffee.com",
       "https://github.com"
     ]},
    {"worker-src", ["'self'", "blob:"]},
    {"object-src", ["'none'"]},
    {"base-uri", ["'self'"]},
    {"frame-ancestors", ["'self'"]},
    {"form-action", ["'self'"]}
  ]

  @header Enum.map_join(@directives, "; ", fn {directive, sources} ->
            "#{directive} #{Enum.join(sources, " ")}"
          end)

  @doc "Returns the assembled Content-Security-Policy header value."
  def header, do: @header

  def init(opts), do: opts

  def call(conn, _opts), do: put_resp_header(conn, "content-security-policy", @header)
end

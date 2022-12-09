[
  import_deps: [:ecto, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs:
    Enum.flat_map(
      ["*.{heex,ex,exs,eex}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{heex,ex,exs,eex}"],
      &Path.wildcard(&1, match_dot: true)
    ) -- ["lib/tr_web/templates/layout/flash.html.heex"],
  subdirectories: ["priv/*/migrations"]
]

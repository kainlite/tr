defmodule Tr.Repo do
  use Ecto.Repo,
    otp_app: :tr,
    adapter: Ecto.Adapters.Postgres
end

defmodule Tr.Repo.Migrations.CreateSponsorsCache do
  use Ecto.Migration

  def change do
    create table(:sponsors_cache) do
      add :github_username, :string
      add :first_seen, :naive_datetime
      add :last_seen, :naive_datetime
      add :amount, :integer

      timestamps()
    end
  end
end

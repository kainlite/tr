defmodule Tr.Repo.Migrations.AddGithubUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :github_username, :string
    end
  end
end

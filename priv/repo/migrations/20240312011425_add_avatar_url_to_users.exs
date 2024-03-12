defmodule Tr.Repo.Migrations.AddAvatarUrlToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_url, :string, default: nil
    end
  end
end

defmodule Tr.Repo.Migrations.CreatePostTracker do
  use Ecto.Migration

  def change do
    create table(:post_tracker) do
      add :slug, :string, unique: true
      add :announced, :boolean, default: false, null: false

      timestamps()

    end

    create unique_index(:post_tracker, [:slug])
  end
end

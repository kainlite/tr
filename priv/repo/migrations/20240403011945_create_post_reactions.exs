defmodule Tr.Repo.Migrations.CreatePostReactions do
  use Ecto.Migration

  def change do
    create table(:post_reactions) do
      add :value, :string
      add :slug, :string
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:post_reactions, [:user_id])
    create index(:post_reactions, [:slug])

    create unique_index(:post_reactions, [:user_id, :slug, :value])
  end
end

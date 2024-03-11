defmodule Tr.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    create table(:comments) do
      add :slug, :string
      add :body, :text
      add :user_id, :integer
      add :parent_comment_id, :integer, default: nil

      timestamps()
    end
  end
end

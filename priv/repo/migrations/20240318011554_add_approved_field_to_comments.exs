defmodule Tr.Repo.Migrations.AddApprovedFieldToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :approved, :boolean, default: false
    end
  end
end

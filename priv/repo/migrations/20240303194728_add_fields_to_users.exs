defmodule Tr.Repo.Migrations.AddFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :accept_emails, :boolean, default: true
    end
  end
end

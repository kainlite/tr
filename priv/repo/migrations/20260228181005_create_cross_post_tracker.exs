defmodule Tr.Repo.Migrations.CreateCrossPostTracker do
  use Ecto.Migration

  def change do
    create table(:cross_post_tracker) do
      add :slug, :string, null: false
      add :linkedin_posted, :boolean, default: false, null: false
      add :linkedin_post_id, :string
      add :linkedin_posted_at, :utc_datetime
      add :substack_drafted, :boolean, default: false, null: false
      add :substack_post_url, :string
      add :substack_drafted_at, :utc_datetime

      timestamps()
    end

    create unique_index(:cross_post_tracker, [:slug])
  end
end

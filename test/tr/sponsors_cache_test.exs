defmodule Tr.SponsorsCacheTest do
  use Tr.DataCase

  alias Tr.SponsorsCache
  alias Tr.Sponsors.Cache

  describe "Cache changeset" do
    test "valid changeset with required fields" do
      changeset =
        Cache.changeset(%Cache{}, %{
          github_username: "testuser",
          first_seen: NaiveDateTime.utc_now(),
          last_seen: NaiveDateTime.utc_now(),
          amount: 10
        })

      assert changeset.valid?
    end

    test "rejects missing fields" do
      changeset = Cache.changeset(%Cache{}, %{})
      refute changeset.valid?

      assert %{
               github_username: ["can't be blank"],
               first_seen: ["can't be blank"],
               last_seen: ["can't be blank"],
               amount: ["can't be blank"]
             } = errors_on(changeset)
    end
  end

  describe "SponsorsCache context" do
    test "register_sponsor/1 inserts a sponsor" do
      assert {:ok, %Cache{} = sponsor} =
               SponsorsCache.register_sponsor(%{
                 github_username: "testuser",
                 first_seen: NaiveDateTime.utc_now(),
                 last_seen: NaiveDateTime.utc_now(),
                 amount: 10
               })

      assert sponsor.github_username == "testuser"
      assert sponsor.amount == 10
    end

    test "register_sponsor/1 with invalid data" do
      assert {:error, %Ecto.Changeset{}} = SponsorsCache.register_sponsor(%{})
    end

    test "sponsor?/1 returns true for existing sponsor" do
      SponsorsCache.register_sponsor(%{
        github_username: "existinguser",
        first_seen: NaiveDateTime.utc_now(),
        last_seen: NaiveDateTime.utc_now(),
        amount: 10
      })

      assert SponsorsCache.sponsor?("existinguser")
    end

    test "sponsor?/1 returns false for non-existing sponsor" do
      refute SponsorsCache.sponsor?("nonexistent")
    end

    test "sponsor?/1 returns false for nil" do
      refute SponsorsCache.sponsor?(nil)
    end
  end
end

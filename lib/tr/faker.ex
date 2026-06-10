defmodule Tr.Faker do
  @moduledoc """
  Minimal in-tree replacement for the parts of the `faker` library this app
  used: random superhero-style display names and avatar image URLs.

  Kept in-tree because faker 0.18 embeds a raw control character that Elixir
  1.20 rejects at compile time, and no released faker version fixes it yet.
  """

  @prefixes ~w(The Amazing Incredible Mighty Captain Doctor Super Iron Dark
               Golden Silver Cosmic Phantom Crimson Shadow Atomic Quantum
               Electric Savage Astral)

  @names ~w(Falcon Viper Comet Titan Phoenix Specter Ranger Sentinel Maverick
            Nomad Vortex Blaze Drifter Striker Warden Hunter Raven Wolf Cobra
            Ghost)

  @suffixes [
    "of Steel",
    "the Brave",
    "the Bold",
    "of the North",
    "the Swift",
    "the Fearless",
    "of Tomorrow",
    "the Eternal",
    "of Light",
    "the Unbroken"
  ]

  @doc ~S(Random superhero-style display name, e.g. "The Amazing Falcon of Steel".)
  def display_name do
    "#{Enum.random(@prefixes)} #{Enum.random(@names)} #{Enum.random(@suffixes)}"
  end

  @doc "Random avatar image URL backed by robohash.org."
  def avatar_url do
    seed = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "https://robohash.org/#{seed}.png"
  end
end

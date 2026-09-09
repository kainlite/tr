defmodule Tr.RateLimiter do
  @moduledoc """
  Fixed-window request counter backed by ETS.

  Counters live in a public table owned by this process so callers never
  serialize through the GenServer; `:ets.update_counter/4` is atomic. Counts
  are per node, which is enough to keep a single abusive client from draining
  the transactional email quota on a small deployment.
  """

  use GenServer

  @table __MODULE__
  @sweep_every :timer.minutes(10)
  @retain_windows 2

  @type key :: term()

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records one hit for `key` and tells whether it stays within `limit` hits per
  `window_ms`. The `:now` option (milliseconds) exists for deterministic tests.
  """
  @spec check(key(), pos_integer(), pos_integer(), keyword()) :: :ok | {:error, :rate_limited}
  def check(key, limit, window_ms, opts \\ []) do
    bucket = bucket_for(Keyword.get(opts, :now, now()), window_ms)
    count = :ets.update_counter(@table, {key, bucket}, {2, 1}, {{key, bucket}, 0})

    if count <= limit, do: :ok, else: {:error, :rate_limited}
  end

  @doc """
  Forgets every bucket recorded for `key`, so its next hit counts from zero.
  """
  @spec reset(key()) :: :ok
  def reset(key) do
    :ets.match_delete(@table, {{key, :_}, :_})
    :ok
  end

  @doc """
  Deletes every bucket older than `@retain_windows` windows of `window_ms`.
  Returns the number of rows removed.
  """
  @spec sweep(pos_integer(), keyword()) :: non_neg_integer()
  def sweep(window_ms, opts \\ []) do
    oldest_kept = bucket_for(Keyword.get(opts, :now, now()), window_ms) - (@retain_windows - 1)

    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", oldest_kept}], [true]}])
  end

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    window_ms = Keyword.get(opts, :sweep_window_ms, :timer.hours(1))
    schedule_sweep()
    {:ok, %{window_ms: window_ms}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(state.window_ms)
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)

  defp bucket_for(now_ms, window_ms), do: div(now_ms, window_ms)

  defp now, do: System.system_time(:millisecond)
end

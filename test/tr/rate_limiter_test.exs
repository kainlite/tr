defmodule Tr.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Tr.RateLimiter

  @window :timer.hours(1)

  defp unique_key(prefix), do: {prefix, System.unique_integer([:positive])}

  describe "check/4" do
    test "allows requests up to the limit inside a window" do
      key = unique_key(:allows)

      assert :ok = RateLimiter.check(key, 3, @window)
      assert :ok = RateLimiter.check(key, 3, @window)
      assert :ok = RateLimiter.check(key, 3, @window)
    end

    test "rejects the request that exceeds the limit" do
      key = unique_key(:rejects)

      for _ <- 1..2, do: assert(:ok = RateLimiter.check(key, 2, @window))

      assert {:error, :rate_limited} = RateLimiter.check(key, 2, @window)
      assert {:error, :rate_limited} = RateLimiter.check(key, 2, @window)
    end

    test "keys are counted independently" do
      first = unique_key(:independent)
      second = unique_key(:independent)

      assert :ok = RateLimiter.check(first, 1, @window)
      assert {:error, :rate_limited} = RateLimiter.check(first, 1, @window)
      assert :ok = RateLimiter.check(second, 1, @window)
    end

    test "the counter resets once the window has elapsed" do
      key = unique_key(:resets)
      now = System.system_time(:millisecond)

      assert :ok = RateLimiter.check(key, 1, @window, now: now)
      assert {:error, :rate_limited} = RateLimiter.check(key, 1, @window, now: now)
      assert :ok = RateLimiter.check(key, 1, @window, now: now + @window)
    end
  end

  describe "reset/1" do
    test "forgets every bucket for the key so the next hit starts from zero" do
      key = unique_key(:reset)

      assert :ok = RateLimiter.check(key, 1, @window)
      assert {:error, :rate_limited} = RateLimiter.check(key, 1, @window)

      assert :ok = RateLimiter.reset(key)
      assert :ok = RateLimiter.check(key, 1, @window)
    end
  end

  describe "sweep/1" do
    test "drops buckets older than the given window and keeps current ones" do
      key = unique_key(:sweep)
      now = System.system_time(:millisecond)

      assert :ok = RateLimiter.check(key, 1, @window, now: now - 3 * @window)
      assert :ok = RateLimiter.check(key, 1, @window, now: now)

      assert 1 = RateLimiter.sweep(@window, now: now)
      assert {:error, :rate_limited} = RateLimiter.check(key, 1, @window, now: now)
    end
  end
end

defmodule FuzzyCatalog.ProviderSchedulerTest do
  use ExUnit.Case, async: true

  alias FuzzyCatalog.ProviderScheduler

  describe "validate_interval/1" do
    test "validates 'disabled' as valid" do
      assert {:ok, "disabled"} = ProviderScheduler.validate_interval("disabled")
    end

    test "validates valid minute intervals" do
      assert {:ok, "1m"} = ProviderScheduler.validate_interval("1m")
      assert {:ok, "15m"} = ProviderScheduler.validate_interval("15m")
      assert {:ok, "30m"} = ProviderScheduler.validate_interval("30m")
      assert {:ok, "45m"} = ProviderScheduler.validate_interval("45m")
    end

    test "validates valid hour intervals" do
      assert {:ok, "1h"} = ProviderScheduler.validate_interval("1h")
      assert {:ok, "2h"} = ProviderScheduler.validate_interval("2h")
      assert {:ok, "6h"} = ProviderScheduler.validate_interval("6h")
      assert {:ok, "12h"} = ProviderScheduler.validate_interval("12h")
      assert {:ok, "24h"} = ProviderScheduler.validate_interval("24h")
    end

    test "validates case insensitive intervals" do
      assert {:ok, "1H"} = ProviderScheduler.validate_interval("1H")
      assert {:ok, "30M"} = ProviderScheduler.validate_interval("30M")
    end

    test "rejects empty string" do
      assert {:error, "Interval cannot be empty"} = ProviderScheduler.validate_interval("")
    end

    test "rejects nil" do
      assert {:error, "Interval cannot be nil"} = ProviderScheduler.validate_interval(nil)
    end

    test "rejects invalid formats" do
      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("invalid")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("1")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("m")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("1hour")
    end

    test "rejects zero values" do
      assert {:error, "invalid number: 0"} = ProviderScheduler.validate_interval("0m")
      assert {:error, "invalid number: 0"} = ProviderScheduler.validate_interval("0h")
    end

    test "rejects negative values" do
      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("-1m")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("-5h")
    end

    test "rejects non-string values" do
      assert {:error, "Interval must be a string"} = ProviderScheduler.validate_interval(123)
      assert {:error, "Interval must be a string"} = ProviderScheduler.validate_interval(:atom)
      assert {:error, "Interval must be a string"} = ProviderScheduler.validate_interval(%{})
    end

    test "rejects unsupported time units" do
      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("1s")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("1d")
    end

    test "rejects decimal numbers" do
      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("1.5h")

      assert {:error, "invalid format - expected format like '1h', '30m', '15m'"} =
               ProviderScheduler.validate_interval("30.5m")
    end
  end
end

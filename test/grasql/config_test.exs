defmodule GraSQL.ConfigTest do
  use ExUnit.Case, async: true

  alias GraSQL.Config

  doctest GraSQL.Config

  describe "validate/1" do
    test "accepts valid configuration" do
      config = %Config{}
      assert {:ok, ^config} = Config.validate(config)
    end

    test "rejects negative cache settings" do
      config = %Config{max_cache_size: -1}
      assert {:error, "Cache settings must be non-negative integers"} = Config.validate(config)
    end

    test "rejects invalid operator map" do
      config = %Config{operators: %{"invalid" => "no_underscore"}}

      assert {:error,
              "Operators must be a map with atom keys and string values starting with '_'"} =
               Config.validate(config)
    end

    test "rejects invalid join type" do
      config = %Config{default_join_type: :invalid}
      assert {:error, "Join settings are invalid"} = Config.validate(config)
    end

    test "rejects invalid naming conventions" do
      config = %Config{aggregate_field_suffix: :not_a_string}
      assert {:error, "Naming convention fields must be strings"} = Config.validate(config)
    end

    test "rejects invalid max_query_depth" do
      config = %Config{max_query_depth: 0}
      assert {:error, "Performance settings must be positive integers"} = Config.validate(config)
    end

    test "validates naming conventions" do
      # Test with invalid aggregate_field_suffix
      assert {:error, "Naming convention fields must be strings"} =
               Config.validate(%Config{aggregate_field_suffix: nil})

      # Test with invalid single_query_param_name
      assert {:error, "Naming convention fields must be strings"} =
               Config.validate(%Config{single_query_param_name: nil})
    end

    test "validates operators" do
      # Test with invalid operators map
      assert {:error,
              "Operators must be a map with atom keys and string values starting with '_'"} =
               Config.validate(%Config{operators: nil})

      # Test with invalid operators values (not starting with _)
      assert {:error,
              "Operators must be a map with atom keys and string values starting with '_'"} =
               Config.validate(%Config{operators: %{eq: "="}})

      # Test with invalid operators values (not a string)
      assert {:error,
              "Operators must be a map with atom keys and string values starting with '_'"} =
               Config.validate(%Config{operators: %{eq: 123}})

      # Test with invalid operators keys
      assert {:error,
              "Operators must be a map with atom keys and string values starting with '_'"} =
               Config.validate(%Config{operators: %{123 => "_eq"}})

      # Test with empty operators map (valid)
      assert {:ok, _} = Config.validate(%Config{operators: %{}})

      # Test with valid operators
      valid_operators = %{
        eq: "_eq",
        gt: "_gt",
        lt: "_lt"
      }

      assert {:ok, _} = Config.validate(%Config{operators: valid_operators})

      # Test with custom operator values
      custom_operators = %{
        eq: "_equals",
        in: "_contains"
      }

      assert {:ok, _} = Config.validate(%Config{operators: custom_operators})
    end

    test "validates cache settings" do
      # Test with invalid max_cache_size
      assert {:error, "Cache settings must be non-negative integers"} =
               Config.validate(%Config{max_cache_size: 0})

      assert {:error, "Cache settings must be non-negative integers"} =
               Config.validate(%Config{max_cache_size: "1000"})

      # Test with invalid cache_ttl
      assert {:error, "Cache settings must be non-negative integers"} =
               Config.validate(%Config{cache_ttl: -1})

      assert {:error, "Cache settings must be non-negative integers"} =
               Config.validate(%Config{cache_ttl: "3600"})

      # Test with valid cache settings
      assert {:ok, _} =
               Config.validate(%Config{max_cache_size: 500, cache_ttl: 1800})

      # Zero TTL is allowed (no expiration)
      assert {:ok, _} = Config.validate(%Config{cache_ttl: 0})
    end

    test "validates join settings" do
      # Test with invalid default_join_type
      assert {:error, "Join settings are invalid"} =
               Config.validate(%Config{default_join_type: :invalid})

      # Test with invalid skip_join_table
      assert {:error, "Join settings are invalid"} =
               Config.validate(%Config{skip_join_table: nil})

      # Test with valid join settings
      assert {:ok, _} =
               Config.validate(%Config{
                 default_join_type: :inner,
                 skip_join_table: false
               })

      assert {:ok, _} =
               Config.validate(%Config{
                 default_join_type: :left_outer,
                 skip_join_table: true
               })
    end

    test "validates performance settings" do
      # Test with invalid max_query_depth
      assert {:error, "Performance settings must be positive integers"} =
               Config.validate(%Config{max_query_depth: 0})

      assert {:error, "Performance settings must be positive integers"} =
               Config.validate(%Config{max_query_depth: "10"})

      # Test with valid max_query_depth
      assert {:ok, _} = Config.validate(%Config{max_query_depth: 5})
    end
  end

  describe "to_native_config/1" do
    test "converts atom operator keys to strings" do
      config = %Config{
        operators: %{
          eq: "_eq",
          neq: "_neq"
        }
      }

      native_config = Config.to_native_config(config)

      assert native_config.operators == %{
               "eq" => "_eq",
               "neq" => "_neq"
             }
    end

    test "preserves other configuration values" do
      config = %Config{
        max_cache_size: 2000,
        cache_ttl: 7200,
        default_join_type: :inner
      }

      native_config = Config.to_native_config(config)

      assert native_config.max_cache_size == 2000
      assert native_config.cache_ttl == 7200
      assert native_config.default_join_type == :inner
    end
  end
end

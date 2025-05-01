defmodule GraSQL.Test do
  use ExUnit.Case, async: true

  doctest GraSQL

  # Instead of using Mock library directly, we'll manually test the behavior
  # This makes it easier to run tests without adding extra dependencies

  describe "init/1" do
    test "init/1 initializes with default config" do
      assert :ok = GraSQL.init()
    end

    test "init/1 initializes with custom config" do
      custom_config = %GraSQL.Config{
        max_cache_size: 2000,
        max_query_depth: 15
      }

      assert :ok = GraSQL.init(custom_config)
    end

    test "init/1 returns error with invalid config" do
      invalid_config = %GraSQL.Config{max_cache_size: -1}
      assert {:error, _} = GraSQL.init(invalid_config)
    end
  end

  describe "generate_sql/5" do
    setup do
      # Initialize with default config for each test
      GraSQL.init()
      :ok
    end

    defmodule InvalidResolver do
      def resolve_table(_table, _ctx), do: %{}
      # Missing resolve_relationship/2
    end

    test "generate_sql/5 validates resolver before parsing query" do
      query = "query { users { id name } }"
      assert {:error, message} = GraSQL.generate_sql(query, %{}, InvalidResolver)
      assert message =~ "must implement required methods"
    end
  end
end

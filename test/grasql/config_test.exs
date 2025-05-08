defmodule GraSQL.ConfigTest do
  use ExUnit.Case

  # Define test modules for module-specific configuration tests
  defmodule TestModule1 do
  end

  defmodule TestModule2 do
  end

  # Define a mock resolver directly in the test file to ensure it's available
  defmodule MockResolver do
    @behaviour GraSQL.SchemaResolver

    @impl true
    def resolve_table(_field_name, _context) do
      %GraSQL.Schema.Table{
        schema: "public",
        name: "users",
        __typename: "User"
      }
    end

    @impl true
    def resolve_relationship(_field_name, _parent_table, _context) do
      %GraSQL.Schema.Relationship{
        source_table: %GraSQL.Schema.Table{schema: "public", name: "users"},
        target_table: %GraSQL.Schema.Table{schema: "public", name: "posts"},
        source_columns: ["id"],
        target_columns: ["user_id"],
        type: :has_many,
        join_table: nil
      }
    end

    @impl true
    def resolve_columns(_table, _context) do
      ["id", "name", "email"]
    end

    @impl true
    def resolve_column_attribute(:sql_type, _column_name, _table, _context) do
      "text"
    end

    def resolve_column_attribute(:is_required, "id", _table, _context), do: true
    def resolve_column_attribute(:is_required, _column_name, _table, _context), do: false

    def resolve_column_attribute(:default_value, _column_name, _table, _context), do: nil
  end

  setup do
    # Reset application environment before each test
    Application.delete_env(:grasql, :__config__)
    Application.delete_env(:grasql, :"__config_GraSQL.ConfigTest.TestModule1__")
    Application.delete_env(:grasql, :"__config_GraSQL.ConfigTest.TestModule2__")

    # Set the MockResolver as the schema resolver for tests
    Application.put_env(:grasql, :schema_resolver, MockResolver)

    :ok
  end

  describe "load_and_validate/0" do
    test "loads and validates global configuration" do
      # Set test configuration
      Application.put_env(:grasql, :max_query_depth, 15)
      Application.put_env(:grasql, :query_cache_max_size, 500)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      # Test loading and validating
      assert {:ok, config} = GraSQL.Config.load_and_validate()
      assert config.max_query_depth == 15
      assert config.query_cache_max_size == 500
      assert config.schema_resolver == MockResolver
    end

    test "returns error when schema resolver is not configured" do
      # Clear schema resolver configuration
      Application.delete_env(:grasql, :schema_resolver)

      # Set valid performance settings to avoid conflicting error
      Application.put_env(:grasql, :max_query_depth, 15)
      Application.put_env(:grasql, :string_interner_capacity, 10_000)

      # Test loading and validating
      assert {:error, reason} = GraSQL.Config.load_and_validate()
      assert reason =~ "Schema resolver must be configured"
    end

    test "returns error for invalid configuration" do
      # Set invalid configuration
      Application.put_env(:grasql, :max_query_depth, -1)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      # Test loading and validating
      assert {:error, reason} = GraSQL.Config.load_and_validate()
      assert reason =~ "Performance settings must be positive integers"
    end
  end

  describe "load_and_validate_for_module/1" do
    test "loads and validates module-specific configuration" do
      # Set global config
      Application.put_env(:grasql, :max_query_depth, 10)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      # Set module-specific config
      Application.put_env(:grasql, TestModule1, max_query_depth: 15)

      # Test loading and validating module config
      assert {:ok, config} = GraSQL.Config.load_and_validate_for_module(TestModule1)
      # Module-specific value
      assert config.max_query_depth == 15

      # Ensure it's cached with the correct key format
      assert Application.get_env(:grasql, :"__config_GraSQL.ConfigTest.TestModule1__") == config
    end

    test "module config overrides global config" do
      # Set global and module config
      Application.put_env(:grasql, :max_query_depth, 10)
      Application.put_env(:grasql, :query_cache_max_size, 500)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      Application.put_env(:grasql, TestModule1,
        max_query_depth: 15,
        schema_resolver: MockResolver
      )

      # Test that module config overrides global
      assert {:ok, config} = GraSQL.Config.load_and_validate_for_module(TestModule1)
      # Module-specific override
      assert config.max_query_depth == 15
      # Global value
      assert config.query_cache_max_size == 500
      assert config.schema_resolver == MockResolver
    end

    test "returns error when schema resolver is not configured in module" do
      # Set global config without resolver
      Application.delete_env(:grasql, :schema_resolver)

      # Set module config without resolver
      Application.put_env(:grasql, TestModule1, max_query_depth: 15)

      # Test error is returned
      assert {:error, reason} = GraSQL.Config.load_and_validate_for_module(TestModule1)
      assert reason =~ "Schema resolver must be configured"
    end

    test "returns error for invalid module configuration" do
      # Set invalid module config
      Application.put_env(:grasql, TestModule1,
        max_query_depth: -1,
        schema_resolver: MockResolver
      )

      # Test error is returned
      assert {:error, reason} = GraSQL.Config.load_and_validate_for_module(TestModule1)
      assert reason =~ "Performance settings must be positive integers"
    end

    test "ignores non-struct fields in configuration" do
      # Set config with invalid field
      Application.put_env(:grasql, TestModule1,
        invalid_field: "value",
        max_query_depth: 15,
        schema_resolver: MockResolver
      )

      # Test that invalid field is ignored
      assert {:ok, config} = GraSQL.Config.load_and_validate_for_module(TestModule1)
      assert config.max_query_depth == 15
      assert Map.get(config, :invalid_field) == nil
    end
  end

  describe "get_config_for/1" do
    test "returns cached config if available" do
      # Set module config
      Application.put_env(:grasql, TestModule1,
        max_query_depth: 15,
        schema_resolver: MockResolver
      )

      # Load config first time
      assert {:ok, config1} = GraSQL.Config.load_and_validate_for_module(TestModule1)

      # Change application env (should be ignored since cached)
      Application.put_env(:grasql, TestModule1,
        max_query_depth: 20,
        schema_resolver: MockResolver
      )

      # Get config should return cached version
      assert {:ok, config2} = GraSQL.Config.get_config_for(TestModule1)
      assert config2.max_query_depth == 15
      assert config1 == config2
    end

    test "loads config if not cached" do
      # Set module config
      Application.put_env(:grasql, TestModule1,
        max_query_depth: 15,
        schema_resolver: MockResolver
      )

      # Get config should load and cache it
      assert {:ok, config} = GraSQL.Config.get_config_for(TestModule1)
      assert config.max_query_depth == 15
      assert Application.get_env(:grasql, :"__config_GraSQL.ConfigTest.TestModule1__") == config
    end
  end

  describe "get_config/0" do
    test "returns cached global config if available" do
      # Set global config
      Application.put_env(:grasql, :max_query_depth, 15)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      # Load config first time
      assert {:ok, config1} = GraSQL.Config.load_and_validate()

      # Cache the config
      Application.put_env(:grasql, :__config__, config1)

      # Change application env (should be ignored since cached)
      Application.put_env(:grasql, :max_query_depth, 20)

      # Get config should return cached version
      assert {:ok, config2} = GraSQL.Config.get_config()
      assert config2.max_query_depth == 15
      assert config1 == config2
    end

    test "loads global config if not cached" do
      # Set global config
      Application.put_env(:grasql, :max_query_depth, 15)
      Application.put_env(:grasql, :schema_resolver, MockResolver)

      # Get config should load and cache it
      assert {:ok, config} = GraSQL.Config.get_config()
      assert config.max_query_depth == 15
    end
  end
end

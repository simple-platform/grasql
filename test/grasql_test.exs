defmodule GraSQLTest do
  use ExUnit.Case
  doctest GraSQL

  alias GraSQL.Config

  # Define a simple resolver for testing
  defmodule TestResolver do
    @behaviour GraSQL.SchemaResolver
    def resolve_table(_table, _ctx), do: %{}
    def resolve_relationship(_relationship, _ctx), do: %{}
  end

  # Define a resolver missing required functions
  defmodule InvalidResolver do
    def resolve_table(_table, _ctx), do: %{}
  end

  setup do
    # Initialize GraSQL with default config before each test
    GraSQL.init()
    :ok
  end

  describe "init/1" do
    test "initializes with default configuration" do
      assert :ok = GraSQL.init()
    end

    test "initializes with custom configuration" do
      custom_config = %Config{
        aggregate_field_suffix: "_aggregate",
        max_cache_size: 2000,
        cache_ttl: 7200
      }

      assert :ok = GraSQL.init(custom_config)
    end

    test "returns error for invalid configuration" do
      invalid_config = %Config{max_cache_size: -1}
      assert {:error, _} = GraSQL.init(invalid_config)
    end
  end

  describe "parse_query/1" do
    setup do
      # Initialize with default config
      assert :ok = GraSQL.init()
      :ok
    end

    test "parses a valid query" do
      query = "query { users { id name email } }"
      assert {:ok, _query_id, :query, false, ""} = GraSQL.parse_query(query)
    end

    test "parses a named query" do
      query = "query GetUsers { users { id name } }"
      assert {:ok, _query_id, :query, true, "GetUsers"} = GraSQL.parse_query(query)
    end
  end

  describe "generate_sql/5" do
    setup do
      # Initialize with default config
      assert :ok = GraSQL.init()
      :ok
    end

    defmodule ValidResolver do
      @behaviour GraSQL.SchemaResolver
      def resolve_table(table, _ctx), do: table
      def resolve_relationship(rel, _ctx), do: rel
    end

    test "validates resolver before parsing query" do
      query = "query { users { id name } }"
      assert {:error, message} = GraSQL.generate_sql(query, %{}, InvalidResolver)
      assert message =~ "must implement required methods"
    end

    test "generates SQL with valid resolver" do
      query = "query { users { id name } }"
      assert {:ok, sql, _params} = GraSQL.generate_sql(query, %{}, ValidResolver)
      assert is_binary(sql)
    end

    test "parses simple query" do
      query = "{ users { id name } }"

      result = GraSQL.generate_sql(query, %{}, TestResolver)
      assert match?({:ok, _sql, _params}, result)
    end

    test "parses query with variables" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
        }
      }
      """

      variables = %{"id" => 123}

      result = GraSQL.generate_sql(query, variables, TestResolver)
      assert match?({:ok, _sql, _params}, result)
    end

    test "handles query with fragments" do
      query = """
      {
        users {
          id
          ...UserFields
        }
      }

      fragment UserFields on User {
        name
        email
      }
      """

      result = GraSQL.generate_sql(query, %{}, TestResolver)
      assert match?({:ok, _sql, _params}, result)
    end
  end
end

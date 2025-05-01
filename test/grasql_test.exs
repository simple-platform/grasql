defmodule GraSQLTest do
  use ExUnit.Case
  doctest GraSQL

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

  describe "parse_query/1" do
    test "parses a valid query" do
      query = "query { users { id name email } }"
      assert {:ok, _query_id, :query, ""} = GraSQL.parse_query(query)
    end

    test "parses a named query" do
      query = "query GetUsers { users { id name } }"
      assert {:ok, _query_id, :query, "GetUsers"} = GraSQL.parse_query(query)
    end
  end

  describe "generate_sql/5" do
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
      result = GraSQL.generate_sql(query, %{}, ValidResolver)
      assert match?({:ok, _sql, _params}, result)
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

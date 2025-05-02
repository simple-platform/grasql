defmodule GraSQLTest do
  use ExUnit.Case
  doctest GraSQL

  describe "parse_query/1" do
    test "parses a valid query" do
      query = "query { users { id name email } }"
      assert {:ok, _query_id, :query, "", _resolution_request} = GraSQL.parse_query(query)
    end

    test "parses a named query" do
      query = "query GetUsers { users { id name } }"
      assert {:ok, _query_id, :query, "GetUsers", _resolution_request} = GraSQL.parse_query(query)
    end
  end

  describe "generate_sql/2" do
    test "generates SQL for a simple query" do
      query = "query { users { id name } }"
      result = GraSQL.generate_sql(query, %{})
      assert match?({:ok, _sql, _params}, result)
    end

    test "parses simple query" do
      query = "{ users { id name } }"
      result = GraSQL.generate_sql(query, %{})
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

      result = GraSQL.generate_sql(query, variables)
      assert match?({:ok, _sql, _params}, result)
    end
  end
end

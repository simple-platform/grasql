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

    test "handles schema resolution errors gracefully" do
      # Create a defective resolver module that will raise an error
      defmodule FailingResolver do
        use GraSQL.SchemaResolver

        @impl true
        def resolve_table(_field_name, _ctx) do
          raise "Simulated schema resolution error"
        end

        @impl true
        def resolve_relationship(_field_name, _parent_table, _ctx) do
          raise "This should not be called"
        end
      end

      # Temporarily override the schema resolver
      original_config = Application.get_env(:grasql, :__config__)

      new_config =
        struct(
          GraSQL.Config,
          Map.from_struct(original_config || %GraSQL.Config{})
          |> Map.put(:schema_resolver, FailingResolver)
        )

      Application.put_env(:grasql, :__config__, new_config)

      try do
        query = "{ users { id } }"
        result = GraSQL.generate_sql(query, %{})

        assert {:error, error_message} = result
        assert String.contains?(error_message, "Schema resolution error")
        assert String.contains?(error_message, "Simulated schema resolution error")
      after
        # Restore the original config
        Application.put_env(:grasql, :__config__, original_config)
      end
    end
  end
end

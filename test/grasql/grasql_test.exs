defmodule GraSQL.Test do
  use ExUnit.Case, async: true

  doctest GraSQL

  # Instead of using Mock library directly, we'll manually test the behavior
  # This makes it easier to run tests without adding extra dependencies

  describe "generate_sql/5" do
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

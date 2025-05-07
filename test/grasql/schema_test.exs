defmodule GraSQL.SchemaTest do
  use ExUnit.Case

  describe "resolve/3" do
    test "uses cached resolver when none is provided" do
      # Create a basic resolution request
      resolution_request = %{
        field_names: ["users", "id", "name"],
        field_paths: [
          # users
          [0],
          # users.id
          [0, 1],
          # users.name
          [0, 2]
        ],
        column_map: %{
          0 => MapSet.new(["id", "name"])
        },
        operation_kind: :query
      }

      # Call resolve with nil resolver (should use cached)
      result = GraSQL.Schema.resolve(resolution_request)

      # Basic validation that it returned something
      assert result == resolution_request
    end

    test "uses provided resolver when specified" do
      # Create a basic resolution request
      resolution_request = %{
        field_names: ["users", "id", "name"],
        field_paths: [
          # users
          [0],
          # users.id
          [0, 1],
          # users.name
          [0, 2]
        ],
        column_map: %{
          0 => MapSet.new(["id", "name"])
        },
        operation_kind: :query
      }

      # Call resolve with explicit resolver
      result = GraSQL.Schema.resolve(resolution_request, GraSQL.TestResolver)

      # Basic validation that it returned something
      assert result == resolution_request
    end
  end
end

defmodule GraSQL.QueryStructureTreeTest do
  use ExUnit.Case
  doctest GraSQL.QueryStructureTree

  alias GraSQL.Field
  alias GraSQL.OperationType
  alias GraSQL.QueryStructureTree
  alias GraSQL.Selection
  alias GraSQL.SourcePosition

  test "new/3 creates a new query structure tree" do
    op_type = OperationType.query()
    root_fields = []
    variables = []

    qst = QueryStructureTree.new(op_type, root_fields, variables)

    assert qst.operation_type == op_type
    assert qst.root_fields == root_fields
    assert qst.variables == variables
  end

  test "add_root_field/2 adds a field to root_fields" do
    qst = %QueryStructureTree{operation_type: OperationType.query()}
    pos = SourcePosition.new(1, 1)
    selection = Selection.new()
    field = Field.new("users", nil, %{}, selection, pos)

    updated = QueryStructureTree.add_root_field(qst, field)

    assert [^field] = updated.root_fields
  end

  test "add_variable/4 adds a variable to variables" do
    qst = %QueryStructureTree{operation_type: OperationType.query()}
    updated = QueryStructureTree.add_variable(qst, "limit", "Int", 10)

    assert [%{name: "limit", type: "Int", default_value: 10}] = updated.variables
  end
end

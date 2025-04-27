defmodule GraSQL.QueryAnalysisTest do
  use ExUnit.Case
  doctest GraSQL.QueryAnalysis

  alias GraSQL.OperationType
  alias GraSQL.QueryAnalysis
  alias GraSQL.QueryStructureTree
  alias GraSQL.SchemaNeeds
  alias GraSQL.TableRef

  test "new/4 creates a new query analysis" do
    qst = %QueryStructureTree{operation_type: OperationType.query()}
    schema_needs = SchemaNeeds.new()
    variable_map = %{"limit" => 10}
    operation_type = OperationType.query()

    analysis = QueryAnalysis.new(qst, schema_needs, variable_map, operation_type)

    assert analysis.qst == qst
    assert analysis.schema_needs == schema_needs
    assert analysis.variable_map == variable_map
  end

  test "get_variable/2 returns the variable value if it exists" do
    analysis = %QueryAnalysis{variable_map: %{"limit" => 10}}
    assert QueryAnalysis.get_variable(analysis, "limit") == 10
  end

  test "get_variable/3 returns the default value if the variable does not exist" do
    analysis = %QueryAnalysis{variable_map: %{}}
    assert QueryAnalysis.get_variable(analysis, "limit", 20) == 20
  end

  test "mutation?/1 returns true for mutation operations" do
    qst = %QueryStructureTree{operation_type: OperationType.mutation()}
    analysis = %QueryAnalysis{qst: qst}
    assert QueryAnalysis.mutation?(analysis) == true
  end

  test "mutation?/1 returns false for query operations" do
    qst = %QueryStructureTree{operation_type: OperationType.query()}
    analysis = %QueryAnalysis{qst: qst}
    assert QueryAnalysis.mutation?(analysis) == false
  end

  test "table_count/1 returns the number of tables in schema_needs" do
    tables = [
      TableRef.new("public", "users", nil),
      TableRef.new("public", "posts", nil)
    ]

    schema_needs = SchemaNeeds.new(tables, [])
    analysis = %QueryAnalysis{schema_needs: schema_needs}

    assert QueryAnalysis.table_count(analysis) == 2
  end
end

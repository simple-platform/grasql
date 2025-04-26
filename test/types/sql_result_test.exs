defmodule GraSQL.SqlResultTest do
  use ExUnit.Case
  doctest GraSQL.SqlResult

  alias GraSQL.ResultStructure
  alias GraSQL.SqlResult

  test "new/4 creates a new SQL result" do
    sql = "SELECT id, name FROM users WHERE id = $1"
    parameters = [1]
    parameter_types = ["integer"]
    result_structure = ResultStructure.new()

    sql_result = SqlResult.new(sql, parameters, parameter_types, result_structure)

    assert sql_result.sql == sql
    assert sql_result.parameters == parameters
    assert sql_result.parameter_types == parameter_types
    assert sql_result.result_structure == result_structure
  end

  test "add_parameter/3 adds a parameter to the SQL result" do
    sql_result = %SqlResult{
      sql: "SELECT * FROM users WHERE id = $1",
      parameters: [],
      parameter_types: []
    }

    updated = SqlResult.add_parameter(sql_result, 1, "integer")

    assert updated.parameters == [1]
    assert updated.parameter_types == ["integer"]
  end

  test "parameter_count/1 returns the number of parameters" do
    sql_result = %SqlResult{parameters: [1, "test"], parameter_types: ["integer", "text"]}
    assert SqlResult.parameter_count(sql_result) == 2
  end

  test "get_parameter/2 returns the parameter at the specified index" do
    sql_result = %SqlResult{parameters: [1, "test"]}
    assert SqlResult.get_parameter(sql_result, 0) == 1
    assert SqlResult.get_parameter(sql_result, 1) == "test"
  end

  test "get_parameter_type/2 returns the parameter type at the specified index" do
    sql_result = %SqlResult{parameter_types: ["integer", "text"]}
    assert SqlResult.get_parameter_type(sql_result, 0) == "integer"
    assert SqlResult.get_parameter_type(sql_result, 1) == "text"
  end
end

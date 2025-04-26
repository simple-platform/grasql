defmodule GraSQL.TableRefTest do
  use ExUnit.Case
  doctest GraSQL.TableRef

  alias GraSQL.TableRef

  test "new/3 creates a new table reference" do
    table_ref = TableRef.new("public", "users", "u")

    assert table_ref.schema == "public"
    assert table_ref.table == "users"
    assert table_ref.alias == "u"
  end

  test "full_table_name/1 returns the fully qualified table name" do
    table_ref = TableRef.new("public", "users", nil)
    assert TableRef.full_table_name(table_ref) == "public.users"
  end

  test "effective_name/1 returns the alias if it exists" do
    table_ref = TableRef.new("public", "users", "u")
    assert TableRef.effective_name(table_ref) == "u"
  end

  test "effective_name/1 returns the table name if no alias exists" do
    table_ref = TableRef.new("public", "users", nil)
    assert TableRef.effective_name(table_ref) == "users"
  end
end

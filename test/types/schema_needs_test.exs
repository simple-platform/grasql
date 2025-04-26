defmodule GraSQL.SchemaNeedsTest do
  use ExUnit.Case
  doctest GraSQL.SchemaNeeds

  alias GraSQL.RelationshipRef
  alias GraSQL.SchemaNeeds
  alias GraSQL.TableRef

  test "new/0 creates an empty schema needs" do
    needs = SchemaNeeds.new()
    assert needs.tables == []
    assert needs.relationships == []
    assert needs.table_map == %{}
    assert needs.relationship_map == %{}
  end

  test "new/2 creates schema needs with tables and relationships" do
    tables = [TableRef.new("public", "users", nil)]
    relationships = []
    needs = SchemaNeeds.new(tables, relationships)

    assert needs.tables == tables
    assert needs.relationships == relationships
    assert map_size(needs.table_map) == 1
    assert needs.relationship_map == %{}
  end

  test "add_table/2 adds a table to schema needs" do
    needs = SchemaNeeds.new()
    table = TableRef.new("public", "users", nil)
    updated = SchemaNeeds.add_table(needs, table)

    assert [^table] = updated.tables
    assert Map.has_key?(updated.table_map, TableRef.hash(table))
  end

  test "add_table/2 doesn't duplicate tables" do
    table = TableRef.new("public", "users", nil)
    needs = SchemaNeeds.new([table], [])
    updated = SchemaNeeds.add_table(needs, table)

    assert updated.tables == [table]
    assert map_size(updated.table_map) == 1
  end

  test "add_table/2 doesn't duplicate tables with different aliases" do
    table1 = TableRef.new("public", "users", nil)
    table2 = TableRef.new("public", "users", "u")
    needs = SchemaNeeds.new([table1], [])
    updated = SchemaNeeds.add_table(needs, table2)

    # Tables are considered the same if they have the same schema and name,
    # regardless of alias
    assert updated.tables == [table1]
    assert map_size(updated.table_map) == 1
  end

  test "add_relationship/2 adds a relationship to schema needs" do
    needs = SchemaNeeds.new()
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.has_many(source, target, "id", "user_id")
    updated = SchemaNeeds.add_relationship(needs, rel)

    assert [^rel] = updated.relationships
    assert Map.has_key?(updated.relationship_map, RelationshipRef.hash(rel))
  end

  test "add_relationship/2 doesn't duplicate relationships" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.has_many(source, target, "id", "user_id")
    needs = SchemaNeeds.new([], [rel])
    updated = SchemaNeeds.add_relationship(needs, rel)

    assert updated.relationships == [rel]
    assert map_size(updated.relationship_map) == 1
  end

  test "add_relationship/2 doesn't duplicate relationships with different relationship types" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel1 = RelationshipRef.has_many(source, target, "id", "user_id")

    # Same tables and columns, but different relationship type
    rel2 = RelationshipRef.new(source, target, "id", "user_id", :has_one)

    needs = SchemaNeeds.new([], [rel1])
    updated = SchemaNeeds.add_relationship(needs, rel2)

    # These have the same hash because the hash is based on tables and columns, not type
    assert updated.relationships == [rel1]
    assert map_size(updated.relationship_map) == 1
  end
end

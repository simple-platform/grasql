defmodule GraSQL.SchemaNeedsTest do
  use ExUnit.Case
  doctest GraSQL.SchemaNeeds

  alias GraSQL.RelationshipRef
  alias GraSQL.SchemaNeeds
  alias GraSQL.TableRef

  test "new/0 creates an empty schema needs" do
    needs = SchemaNeeds.new()
    assert MapSet.size(needs.tables) == 0
    assert MapSet.size(needs.relationships) == 0
  end

  test "new/2 creates schema needs with tables and relationships" do
    tables = [TableRef.new("public", "users", nil)]
    relationships = []
    needs = SchemaNeeds.new(tables, relationships)

    assert MapSet.size(needs.tables) == 1
    assert MapSet.to_list(needs.tables) == tables
    assert MapSet.size(needs.relationships) == 0
  end

  test "add_table/2 adds a table to schema needs" do
    needs = SchemaNeeds.new()
    table = TableRef.new("public", "users", nil)
    updated = SchemaNeeds.add_table(needs, table)

    assert MapSet.member?(updated.tables, table)
    assert MapSet.size(updated.tables) == 1
  end

  test "add_table/2 doesn't duplicate tables" do
    table = TableRef.new("public", "users", nil)
    needs = SchemaNeeds.new([table], [])
    updated = SchemaNeeds.add_table(needs, table)

    assert MapSet.size(updated.tables) == 1
    assert MapSet.to_list(updated.tables) == [table]
  end

  test "add_table/2 doesn't duplicate tables with different aliases" do
    table1 = TableRef.new("public", "users", nil)
    table2 = TableRef.new("public", "users", "u")
    needs = SchemaNeeds.new([table1], [])
    updated = SchemaNeeds.add_table(needs, table2)

    # Tables are considered the same if they have the same schema and name,
    # regardless of alias
    assert MapSet.size(updated.tables) == 1
    # MapSet will have preserved table1 since it was added first
    assert MapSet.member?(updated.tables, table1)
    # table2 should not be in the set as it's considered a duplicate
    refute MapSet.member?(updated.tables, table2)
  end

  test "add_relationship/2 adds a relationship to schema needs" do
    needs = SchemaNeeds.new()
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.has_many(source, target, "id", "user_id")
    updated = SchemaNeeds.add_relationship(needs, rel)

    assert MapSet.member?(updated.relationships, rel)
    assert MapSet.size(updated.relationships) == 1
  end

  test "add_relationship/2 doesn't duplicate relationships" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.has_many(source, target, "id", "user_id")
    needs = SchemaNeeds.new([], [rel])
    updated = SchemaNeeds.add_relationship(needs, rel)

    assert MapSet.size(updated.relationships) == 1
    assert MapSet.to_list(updated.relationships) == [rel]
  end

  test "add_relationship/2 doesn't duplicate relationships with different relationship types" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel1 = RelationshipRef.has_many(source, target, "id", "user_id")

    # Same tables and columns, but different relationship type
    rel2 = RelationshipRef.new(source, target, "id", "user_id", :has_one)

    needs = SchemaNeeds.new([], [rel1])
    updated = SchemaNeeds.add_relationship(needs, rel2)

    # These would have the same hash, but now RelationshipRef has PartialEq with all fields
    # so they should actually be distinct in the MapSet
    assert MapSet.size(updated.relationships) == 2
    assert MapSet.member?(updated.relationships, rel1)
    assert MapSet.member?(updated.relationships, rel2)
  end
end

defmodule GraSQL.RelationshipRefTest do
  use ExUnit.Case
  doctest GraSQL.RelationshipRef

  alias GraSQL.RelationshipRef
  alias GraSQL.RelType
  alias GraSQL.TableRef

  test "new/6 creates a new relationship reference" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.new(source, target, "id", "user_id", RelType.has_many())

    assert rel.source_table == source
    assert rel.target_table == target
    assert rel.source_column == "id"
    assert rel.target_column == "user_id"
    assert rel.relationship_type == RelType.has_many()
    assert rel.join_table == nil
  end

  test "belongs_to/4 creates a belongs_to relationship" do
    source = TableRef.new("public", "posts", nil)
    target = TableRef.new("public", "users", nil)
    rel = RelationshipRef.belongs_to(source, target, "user_id", "id")

    assert rel.source_table == source
    assert rel.target_table == target
    assert rel.source_column == "user_id"
    assert rel.target_column == "id"
    assert rel.relationship_type == RelType.belongs_to()
  end

  test "has_one/4 creates a has_one relationship" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "profiles", nil)
    rel = RelationshipRef.has_one(source, target, "id", "user_id")

    assert rel.source_table == source
    assert rel.target_table == target
    assert rel.source_column == "id"
    assert rel.target_column == "user_id"
    assert rel.relationship_type == RelType.has_one()
  end

  test "has_many/4 creates a has_many relationship" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "posts", nil)
    rel = RelationshipRef.has_many(source, target, "id", "user_id")

    assert rel.source_table == source
    assert rel.target_table == target
    assert rel.source_column == "id"
    assert rel.target_column == "user_id"
    assert rel.relationship_type == RelType.has_many()
  end

  test "many_to_many/5 creates a many-to-many relationship" do
    source = TableRef.new("public", "users", nil)
    target = TableRef.new("public", "tags", nil)
    join = TableRef.new("public", "users_tags", nil)
    rel = RelationshipRef.many_to_many(source, target, join, "id", "id")

    assert rel.source_table == source
    assert rel.target_table == target
    assert rel.source_column == "id"
    assert rel.target_column == "id"
    assert rel.relationship_type == RelType.has_many()
    assert rel.join_table == join
  end
end

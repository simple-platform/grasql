defmodule GraSQL.SchemaNeedsTest do
  use ExUnit.Case
  doctest GraSQL.SchemaNeeds

  alias GraSQL.EntityReference
  alias GraSQL.RelationshipReference
  alias GraSQL.SchemaNeeds

  test "new/0 creates an empty schema needs" do
    needs = SchemaNeeds.new()
    assert needs.entity_references == []
    assert needs.relationship_references == []
  end

  test "new/2 creates schema needs with entity references and relationship references" do
    entity_references = [%EntityReference{graphql_name: "users", alias: nil}]
    relationship_references = []
    needs = SchemaNeeds.new(entity_references, relationship_references)

    assert needs.entity_references == entity_references
    assert needs.relationship_references == []
  end

  test "add_entity_reference/2 adds an entity reference to schema needs" do
    needs = SchemaNeeds.new()
    entity_ref = %EntityReference{graphql_name: "users", alias: nil}
    updated = SchemaNeeds.add_entity(needs, entity_ref)

    assert Enum.member?(updated.entity_references, entity_ref)
    assert length(updated.entity_references) == 1
  end

  test "add_entity_reference/2 doesn't duplicate entity references" do
    entity_ref = %EntityReference{graphql_name: "users", alias: nil}
    needs = SchemaNeeds.new([entity_ref], [])
    updated = SchemaNeeds.add_entity(needs, entity_ref)

    assert length(updated.entity_references) == 1
    assert updated.entity_references == [entity_ref]
  end

  test "add_entity_reference/2 doesn't duplicate entity references with different aliases" do
    entity_ref1 = %EntityReference{graphql_name: "users", alias: nil}
    entity_ref2 = %EntityReference{graphql_name: "users", alias: "u"}
    needs = SchemaNeeds.new([entity_ref1], [])
    updated = SchemaNeeds.add_entity(needs, entity_ref2)

    # Entity references are considered the same if they have the same graphql_name,
    # regardless of alias
    assert length(updated.entity_references) == 1
    # Will have preserved entity_ref1 since it was added first
    assert Enum.member?(updated.entity_references, entity_ref1)
    # entity_ref2 should not be in the list as it's considered a duplicate
    refute Enum.member?(updated.entity_references, entity_ref2)
  end

  test "add_relationship_reference/2 adds a relationship reference to schema needs" do
    needs = SchemaNeeds.new()

    rel_ref = %RelationshipReference{
      parent_name: "users",
      child_name: "posts",
      parent_alias: nil,
      child_alias: nil
    }

    updated = SchemaNeeds.add_relationship(needs, rel_ref)

    assert Enum.member?(updated.relationship_references, rel_ref)
    assert length(updated.relationship_references) == 1
  end

  test "add_relationship_reference/2 doesn't duplicate relationship references" do
    rel_ref = %RelationshipReference{
      parent_name: "users",
      child_name: "posts",
      parent_alias: nil,
      child_alias: nil
    }

    needs = SchemaNeeds.new([], [rel_ref])
    updated = SchemaNeeds.add_relationship(needs, rel_ref)

    assert length(updated.relationship_references) == 1
    assert updated.relationship_references == [rel_ref]
  end

  test "add_relationship_reference/2 doesn't duplicate relationship references with different aliases" do
    rel_ref1 = %RelationshipReference{
      parent_name: "users",
      child_name: "posts",
      parent_alias: nil,
      child_alias: nil
    }

    rel_ref2 = %RelationshipReference{
      parent_name: "users",
      child_name: "posts",
      parent_alias: "u",
      child_alias: "p"
    }

    needs = SchemaNeeds.new([], [rel_ref1])
    updated = SchemaNeeds.add_relationship(needs, rel_ref2)

    # These would have the same parent_name and child_name, but different aliases
    # so they should be distinct
    assert length(updated.relationship_references) == 2
    assert Enum.member?(updated.relationship_references, rel_ref1)
    assert Enum.member?(updated.relationship_references, rel_ref2)
  end
end

defmodule GraSQL.TestResolver do
  @moduledoc """
  Implementation of SchemaResolver for testing purposes.
  """
  @behaviour GraSQL.SchemaResolver

  @impl true
  def resolve_table("users", _context) do
    %GraSQL.Schema.Table{
      schema: "public",
      name: "users",
      __typename: "User"
    }
  end

  @impl true
  def resolve_table("posts", _context) do
    %GraSQL.Schema.Table{
      schema: "public",
      name: "posts",
      __typename: "Post"
    }
  end

  @impl true
  def resolve_table("comments", _context) do
    %GraSQL.Schema.Table{
      schema: "public",
      name: "comments",
      __typename: "Comment"
    }
  end

  @impl true
  def resolve_table(name, _context) do
    %GraSQL.Schema.Table{
      schema: "public",
      name: name,
      __typename: String.capitalize(name)
    }
  end

  @impl true
  def resolve_relationship("posts", parent_table, _context) do
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{schema: "public", name: "posts", __typename: "Post"},
      source_columns: ["id"],
      target_columns: ["user_id"],
      type: :has_many,
      join_table: nil
    }
  end

  @impl true
  def resolve_relationship("comments", %{name: "posts"} = parent_table, _context) do
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{
        schema: "public",
        name: "comments",
        __typename: "Comment"
      },
      source_columns: ["id"],
      target_columns: ["post_id"],
      type: :has_many,
      join_table: nil
    }
  end

  @impl true
  def resolve_relationship("user", %{name: "posts"} = parent_table, _context) do
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{schema: "public", name: "users", __typename: "User"},
      source_columns: ["user_id"],
      target_columns: ["id"],
      type: :belongs_to,
      join_table: nil
    }
  end

  @impl true
  def resolve_relationship(name, parent_table, _context) do
    %GraSQL.Schema.Relationship{
      source_table: parent_table,
      target_table: %GraSQL.Schema.Table{
        schema: "public",
        name: name,
        __typename: String.capitalize(name)
      },
      source_columns: ["id"],
      target_columns: ["#{parent_table.name}_id"],
      type: :has_many,
      join_table: nil
    }
  end

  @impl true
  def resolve_columns(_table, _context) do
    ["id", "name", "email"]
  end

  @impl true
  def resolve_column_attribute(:sql_type, "id", _table, _context), do: "integer"
  def resolve_column_attribute(:sql_type, _column_name, _table, _context), do: "text"

  @impl true
  def resolve_column_attribute(:is_required, "id", _table, _context), do: true
  def resolve_column_attribute(:is_required, _column_name, _table, _context), do: false

  @impl true
  def resolve_column_attribute(:default_value, _column_name, _table, _context), do: nil
end

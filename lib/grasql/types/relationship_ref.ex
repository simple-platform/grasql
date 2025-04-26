defmodule GraSQL.RelationshipRef do
  @moduledoc """
  Represents a relationship between two tables.

  RelationshipRef describes how tables are related in a database schema,
  including the relationship type and the columns used for joining.
  This information is collected during query analysis and used during
  SQL generation to create proper JOIN statements.

  ## Memory Usage

  Relationship references are designed to be lightweight, with string column
  names potentially benefiting from interning in large queries.
  """

  @typedoc "Reference to a relationship between tables"
  @type t :: %__MODULE__{
          source_table: GraSQL.TableRef.t(),
          target_table: GraSQL.TableRef.t(),
          source_column: String.t(),
          target_column: String.t(),
          relationship_type: GraSQL.RelType.t(),
          join_table: GraSQL.TableRef.t() | nil
        }

  defstruct [
    :source_table,
    :target_table,
    :source_column,
    :target_column,
    :relationship_type,
    :join_table
  ]

  @doc """
  Creates a new relationship reference.

  ## Parameters

  - `source_table`: The source table reference
  - `target_table`: The target table reference
  - `source_column`: The column in the source table
  - `target_column`: The column in the target table
  - `relationship_type`: The type of relationship
  - `join_table`: Optional join table for many-to-many relationships

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "posts", nil)
      iex> GraSQL.RelationshipRef.new(source, target, "id", "user_id", :has_many, nil)
      %GraSQL.RelationshipRef{
        source_table: %GraSQL.TableRef{schema: "public", table: "users", alias: nil},
        target_table: %GraSQL.TableRef{schema: "public", table: "posts", alias: nil},
        source_column: "id",
        target_column: "user_id",
        relationship_type: :has_many,
        join_table: nil
      }
  """
  @spec new(
          GraSQL.TableRef.t(),
          GraSQL.TableRef.t(),
          String.t(),
          String.t(),
          GraSQL.RelType.t(),
          GraSQL.TableRef.t() | nil
        ) :: t()
  def new(
        source_table,
        target_table,
        source_column,
        target_column,
        relationship_type,
        join_table \\ nil
      ) do
    %__MODULE__{
      source_table: source_table,
      target_table: target_table,
      source_column: source_column,
      target_column: target_column,
      relationship_type: relationship_type,
      join_table: join_table
    }
  end

  @doc """
  Creates a belongs_to relationship reference.

  ## Parameters

  - `source_table`: The source table reference (the "many" side)
  - `target_table`: The target table reference (the "one" side)
  - `source_column`: The column in the source table (typically foreign key)
  - `target_column`: The column in the target table (typically primary key)

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "posts", nil)
      iex> target = GraSQL.TableRef.new("public", "users", nil)
      iex> GraSQL.RelationshipRef.belongs_to(source, target, "user_id", "id")
      %GraSQL.RelationshipRef{
        source_table: %GraSQL.TableRef{schema: "public", table: "posts", alias: nil},
        target_table: %GraSQL.TableRef{schema: "public", table: "users", alias: nil},
        source_column: "user_id",
        target_column: "id",
        relationship_type: :belongs_to,
        join_table: nil
      }
  """
  @spec belongs_to(GraSQL.TableRef.t(), GraSQL.TableRef.t(), String.t(), String.t()) :: t()
  def belongs_to(source_table, target_table, source_column, target_column) do
    new(source_table, target_table, source_column, target_column, GraSQL.RelType.belongs_to())
  end

  @doc """
  Creates a has_one relationship reference.

  ## Parameters

  - `source_table`: The source table reference
  - `target_table`: The target table reference
  - `source_column`: The column in the source table (typically primary key)
  - `target_column`: The column in the target table (typically foreign key)

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "profiles", nil)
      iex> GraSQL.RelationshipRef.has_one(source, target, "id", "user_id")
      %GraSQL.RelationshipRef{
        source_table: %GraSQL.TableRef{schema: "public", table: "users", alias: nil},
        target_table: %GraSQL.TableRef{schema: "public", table: "profiles", alias: nil},
        source_column: "id",
        target_column: "user_id",
        relationship_type: :has_one,
        join_table: nil
      }
  """
  @spec has_one(GraSQL.TableRef.t(), GraSQL.TableRef.t(), String.t(), String.t()) :: t()
  def has_one(source_table, target_table, source_column, target_column) do
    new(source_table, target_table, source_column, target_column, GraSQL.RelType.has_one())
  end

  @doc """
  Creates a has_many relationship reference.

  ## Parameters

  - `source_table`: The source table reference (the "one" side)
  - `target_table`: The target table reference (the "many" side)
  - `source_column`: The column in the source table (typically primary key)
  - `target_column`: The column in the target table (typically foreign key)

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "posts", nil)
      iex> GraSQL.RelationshipRef.has_many(source, target, "id", "user_id")
      %GraSQL.RelationshipRef{
        source_table: %GraSQL.TableRef{schema: "public", table: "users", alias: nil},
        target_table: %GraSQL.TableRef{schema: "public", table: "posts", alias: nil},
        source_column: "id",
        target_column: "user_id",
        relationship_type: :has_many,
        join_table: nil
      }
  """
  @spec has_many(GraSQL.TableRef.t(), GraSQL.TableRef.t(), String.t(), String.t()) :: t()
  def has_many(source_table, target_table, source_column, target_column) do
    new(source_table, target_table, source_column, target_column, GraSQL.RelType.has_many())
  end

  @doc """
  Creates a many-to-many relationship reference using has_many with a join_table.

  ## Parameters

  - `source_table`: The source table reference
  - `target_table`: The target table reference
  - `join_table`: The join table reference
  - `source_column`: The column in the source table (typically primary key)
  - `target_column`: The column in the target table (typically primary key)

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "tags", nil)
      iex> join = GraSQL.TableRef.new("public", "users_tags", nil)
      iex> GraSQL.RelationshipRef.many_to_many(source, target, join, "id", "id")
      %GraSQL.RelationshipRef{
        source_table: %GraSQL.TableRef{schema: "public", table: "users", alias: nil},
        target_table: %GraSQL.TableRef{schema: "public", table: "tags", alias: nil},
        source_column: "id",
        target_column: "id",
        relationship_type: :has_many,
        join_table: %GraSQL.TableRef{schema: "public", table: "users_tags", alias: nil}
      }
  """
  @spec many_to_many(
          GraSQL.TableRef.t(),
          GraSQL.TableRef.t(),
          GraSQL.TableRef.t(),
          String.t(),
          String.t()
        ) :: t()
  def many_to_many(
        source_table,
        target_table,
        join_table,
        source_column,
        target_column
      ) do
    # Store the join table info in the join_table field
    # We're still using has_many as the relationship type for consistency
    new(
      source_table,
      target_table,
      source_column,
      target_column,
      GraSQL.RelType.has_many(),
      join_table
    )
  end

  @doc """
  Determines if two relationship references refer to the same relationship.

  ## Parameters

  - `rel1`: First relationship reference
  - `rel2`: Second relationship reference

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "posts", nil)
      iex> rel1 = GraSQL.RelationshipRef.has_many(source, target, "id", "user_id")
      iex> rel2 = GraSQL.RelationshipRef.has_many(source, target, "id", "user_id")
      iex> GraSQL.RelationshipRef.same_relationship?(rel1, rel2)
      true
  """
  @spec same_relationship?(t(), t()) :: boolean()
  def same_relationship?(
        %__MODULE__{
          source_table: s1,
          target_table: t1,
          source_column: sc1,
          target_column: tc1,
          relationship_type: rt1,
          join_table: jt1
        },
        %__MODULE__{
          source_table: s2,
          target_table: t2,
          source_column: sc2,
          target_column: tc2,
          relationship_type: rt2,
          join_table: jt2
        }
      ) do
    GraSQL.TableRef.same_table?(s1, s2) &&
      GraSQL.TableRef.same_table?(t1, t2) &&
      sc1 == sc2 &&
      tc1 == tc2 &&
      rt1 == rt2 &&
      (jt1 == jt2 || GraSQL.TableRef.same_table?(jt1, jt2))
  end

  @doc """
  Generates a hash value for the relationship reference.
  Used for efficient comparison in collections.

  ## Parameters

  - `relationship`: The relationship reference

  ## Examples

      iex> source = GraSQL.TableRef.new("public", "users", nil)
      iex> target = GraSQL.TableRef.new("public", "posts", nil)
      iex> rel = GraSQL.RelationshipRef.has_many(source, target, "id", "user_id")
      iex> is_integer(GraSQL.RelationshipRef.hash(rel))
      true
  """
  @spec hash(t()) :: integer()
  def hash(%__MODULE__{
        source_table: source,
        target_table: target,
        source_column: sc,
        target_column: tc,
        join_table: jt
      }) do
    source_hash = GraSQL.TableRef.hash(source)
    target_hash = GraSQL.TableRef.hash(target)
    join_hash = if jt, do: GraSQL.TableRef.hash(jt), else: 0
    :erlang.phash2({source_hash, target_hash, sc, tc, join_hash})
  end
end

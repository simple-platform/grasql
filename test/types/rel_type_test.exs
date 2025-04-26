defmodule GraSQL.RelTypeTest do
  use ExUnit.Case
  doctest GraSQL.RelType

  alias GraSQL.RelType

  test "has_many/0 returns :has_many atom" do
    assert RelType.has_many() == :has_many
  end

  test "has_one/0 returns :has_one atom" do
    assert RelType.has_one() == :has_one
  end

  test "belongs_to/0 returns :belongs_to atom" do
    assert RelType.belongs_to() == :belongs_to
  end

  test "@type t includes all relation types" do
    # Type checking is done at compile time, this is just to verify the types exist
    has_many_val = RelType.has_many()
    has_one_val = RelType.has_one()
    belongs_to_val = RelType.belongs_to()

    # Simple check to ensure the values are atoms
    assert is_atom(has_many_val)
    assert is_atom(has_one_val)
    assert is_atom(belongs_to_val)
  end
end

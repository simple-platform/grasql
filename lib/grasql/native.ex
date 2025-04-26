defmodule GraSQL.Native do
  @moduledoc """
  Rust NIF bindings for GraSQL.

  This module provides the interface between Elixir and Rust implementations,
  offering performance-critical operations implemented in Rust.
  """
  use Rustler, otp_app: :grasql, crate: :grasql

  def add(_a, _b) do
    :erlang.nif_error(:nif_not_loaded)
  end
end

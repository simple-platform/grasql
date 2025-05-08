defmodule GraSQL.Native do
  @moduledoc """
  Native Rust implementation of GraSQL's core functionality.

  This module provides the interface between Elixir and the Rust core
  of GraSQL, exposing NIF functions for performance-critical operations
  such as GraphQL parsing and SQL generation.

  All functions in this module are backed by native Rust code compiled
  through the Rustler library.
  """

  use Rustler,
    otp_app: :grasql,
    crate: :grasql,
    load_data_fun: {GraSQL.Config, :load}

  def parse_query(query), do: do_parse_query(query)

  def generate_sql(resolution_response), do: do_generate_sql(resolution_response)

  def do_parse_query(_query), do: :erlang.nif_error(:nif_not_loaded)

  def do_generate_sql(_resolution_response), do: :erlang.nif_error(:nif_not_loaded)
end

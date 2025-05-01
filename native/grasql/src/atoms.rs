// Atom definitions for Elixir/Erlang interop
//
// This module defines all the atoms used for communication with the Elixir runtime.
// These atoms are used as message identifiers, status codes, and enum values.
rustler::atoms! {
    ok,
    error,
    operators,
    aggregate_field_suffix,
    primary_key_argument_name,
    query_cache_max_size,
    query_cache_ttl_seconds,
    max_query_depth,
    query,
    mutation,
    subscription,
}

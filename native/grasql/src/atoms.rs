// Atom definitions for Elixir/Erlang interop
//
// This module defines all the atoms used for communication with the Elixir runtime.
// These atoms are used as message identifiers, status codes, and enum values.
rustler::atoms! {
    ok,
    error,
    inner,
    left_outer,
    operators,
    aggregate_field_suffix,
    single_query_param_name,
    max_cache_size,
    cache_ttl,
    skip_join_table,
    default_join_type,
    max_query_depth,
    query,
    mutation,
    subscription,
}

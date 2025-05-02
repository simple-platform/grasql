use crate::types::GraphQLOperationKind;
/// Atoms module defines Elixir/Erlang atoms for NIF interaction
///
/// This module contains all the atoms that are used in the NIF interface.
/// These atoms are used for returning data to Elixir.
use rustler::Atom;

rustler::atoms! {
    // Common atoms
    ok,
    error,

    // Error types
    syntax_error,
    cache_miss,

    // Operation kinds
    query,
    mutation,
    subscription,

    // Resolution request keys
    field_names,
    field_paths,
}

/// Convert GraphQLOperationKind to Erlang atom
#[inline(always)]
pub fn operation_kind_to_atom(kind: GraphQLOperationKind) -> Atom {
    match kind {
        GraphQLOperationKind::Query => query(),
        GraphQLOperationKind::Mutation => mutation(),
        GraphQLOperationKind::Subscription => subscription(),
    }
}

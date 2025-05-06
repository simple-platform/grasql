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
    insert_mutation,
    update_mutation,
    delete_mutation,
    subscription,

    // Resolution request keys
    field_names,
    field_paths,
    column_map,
    operation_kind,
}

/// Convert GraphQLOperationKind to Erlang atom
#[inline(always)]
pub fn operation_kind_to_atom(kind: GraphQLOperationKind) -> Atom {
    match kind {
        GraphQLOperationKind::Query => query(),
        GraphQLOperationKind::InsertMutation => insert_mutation(),
        GraphQLOperationKind::UpdateMutation => update_mutation(),
        GraphQLOperationKind::DeleteMutation => delete_mutation(),
        GraphQLOperationKind::Subscription => subscription(),
    }
}

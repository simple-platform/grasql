use rustler::types::atom;
/// Encoder module for converting Rust types to Elixir terms
///
/// This module provides functions to convert the internal Rust data structures
/// to Elixir terms using the rustler library. It handles encoding of query analysis
/// results, schema information, and other data structures used in the GraphQL to SQL
/// conversion process.
use rustler::{Encoder, Env, Term};
use std::collections::HashMap;

use crate::atoms;
use crate::types;

/// Helper function to safely add a key-value pair to a map
///
/// Creates a new map with the key-value pair added to the original map.
/// This function handles the unwrap() internally to make the code more readable.
///
/// # Arguments
///
/// * `map` - The original map
/// * `key` - The key term
/// * `value` - The value term
///
/// # Returns
///
/// A new map with the key-value pair added
pub fn map_put<'a>(map: Term<'a>, key: Term<'a>, value: Term<'a>) -> Term<'a> {
    map.map_put(key, value).unwrap()
}

/// Helper function to create a list from a Vec of Terms
///
/// Creates an Elixir list representation from a vector of rustler Terms.
/// Uses Rustler's term methods to create proper Elixir lists.
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `terms` - Vector of Terms to convert to a list
///
/// # Returns
///
/// An Elixir list (or empty list atom if terms is empty)
pub fn make_term_list<'a>(env: Env<'a>, terms: Vec<Term<'a>>) -> Term<'a> {
    if terms.is_empty() {
        // Return a proper empty Elixir list ([]) instead of nil atom
        return Term::list_new_empty(env);
    }

    // Manually construct the list starting with nil (empty list)
    let mut result = atom::nil().encode(env);

    // Build the list in reverse (since we're prepending elements)
    for term in terms.into_iter().rev() {
        // Using Term's list operations which are safer than using rustler::types directly
        result = result.list_prepend(term);
    }

    result
}

/// Encodes a QueryStructureTree into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `qst` - The QueryStructureTree to encode
///
/// # Returns
///
/// An Elixir map representation of the QueryStructureTree
pub fn encode_query_structure_tree<'a>(env: Env<'a>, qst: &types::QueryStructureTree) -> Term<'a> {
    // Create a map for the QueryStructureTree
    let mut result_map = rustler::types::map::map_new(env);

    // Add operation_type
    let operation_type_term = match qst.operation_type {
        types::OperationType::Query => atoms::query().encode(env),
        types::OperationType::Mutation => atoms::mutation().encode(env),
    };
    result_map = map_put(
        result_map,
        atoms::operation_type().encode(env),
        operation_type_term,
    );

    // Add root_fields
    let root_fields_list = encode_fields(env, &qst.root_fields);
    result_map = map_put(
        result_map,
        atoms::root_fields().encode(env),
        root_fields_list,
    );

    // Add variables - use encode_variables consistently
    let variables_list = encode_variables(env, &qst.variables);
    result_map = map_put(result_map, atoms::variables().encode(env), variables_list);

    result_map
}

/// Encodes a vector of Fields into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `fields` - Vector of Field structs to encode
///
/// # Returns
///
/// An Elixir list representation of the fields
pub fn encode_fields<'a>(env: Env<'a>, fields: &[types::Field]) -> Term<'a> {
    let mut field_terms = Vec::with_capacity(fields.len());

    for field in fields {
        let mut field_map = rustler::types::map::map_new(env);

        // Add name
        field_map = map_put(field_map, atoms::name().encode(env), field.name.encode(env));

        // Add alias if present
        if let Some(ref alias) = field.alias {
            field_map = map_put(field_map, atoms::alias().encode(env), alias.encode(env));
        }

        // Add arguments
        let args_map = encode_arguments(env, &field.arguments);
        field_map = map_put(field_map, atoms::arguments().encode(env), args_map);

        // Add selection
        let selection_term = encode_selection(env, &field.selection);
        field_map = map_put(field_map, atoms::selection().encode(env), selection_term);

        // Add source_position
        let mut pos_map = rustler::types::map::map_new(env);
        pos_map = map_put(
            pos_map,
            atoms::line().encode(env),
            field.source_position.line.encode(env),
        );
        pos_map = map_put(
            pos_map,
            atoms::column().encode(env),
            field.source_position.column.encode(env),
        );

        field_map = map_put(field_map, atoms::source_position().encode(env), pos_map);

        field_terms.push(field_map);
    }

    // Create and return a list from the terms
    make_term_list(env, field_terms)
}

/// Encodes a Selection into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `selection` - The Selection to encode
///
/// # Returns
///
/// An Elixir map representation of the Selection
pub fn encode_selection<'a>(env: Env<'a>, selection: &types::Selection) -> Term<'a> {
    let mut selection_map = rustler::types::map::map_new(env);

    // Add fields - ensure we always create a proper empty list if needed
    let fields_term = encode_fields(env, &selection.fields);
    selection_map = map_put(selection_map, atoms::fields().encode(env), fields_term);

    // We should also encode fragment_spreads and inline_fragments here
    // but since they're not currently used in the encoder, we'll keep it simple for now

    selection_map
}

/// Encodes a HashMap of arguments into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `arguments` - HashMap of argument name to value strings
///
/// # Returns
///
/// An Elixir map representation of the arguments
pub fn encode_arguments<'a>(env: Env<'a>, arguments: &HashMap<String, String>) -> Term<'a> {
    let mut args_map = rustler::types::map::map_new(env);

    for (key, value) in arguments {
        args_map = map_put(args_map, key.encode(env), value.encode(env));
    }

    args_map
}

/// Encodes a vector of variable HashMaps into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `variables` - Vector of variable HashMaps to encode
///
/// # Returns
///
/// An Elixir list representation of the variables
pub fn encode_variables<'a>(env: Env<'a>, variables: &[HashMap<String, String>]) -> Term<'a> {
    let mut var_terms = Vec::with_capacity(variables.len());

    for var in variables {
        let mut var_map = rustler::types::map::map_new(env);

        for (key, value) in var {
            var_map = map_put(var_map, key.encode(env), value.encode(env));
        }

        var_terms.push(var_map);
    }

    // Create and return a list from the terms
    make_term_list(env, var_terms)
}

/// Encodes SchemaNeeds into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `schema_needs` - The SchemaNeeds to encode
///
/// # Returns
///
/// An Elixir map representation of the SchemaNeeds with only entity_references
/// and relationship_references. Concrete table and relationship mappings will
/// be handled by Elixir code.
pub fn encode_schema_needs<'a>(env: Env<'a>, schema_needs: &types::SchemaNeeds) -> Term<'a> {
    let mut schema_needs_map = rustler::types::map::map_new(env);

    // Add entity references - ensure we always create a proper list
    let entity_references_term = encode_entity_references(env, &schema_needs.entity_references);
    schema_needs_map = map_put(
        schema_needs_map,
        atoms::entity_references().encode(env),
        entity_references_term,
    );

    // Add relationship references - ensure we always create a proper list
    let relationship_references_term =
        encode_relationship_references(env, &schema_needs.relationship_references);
    schema_needs_map = map_put(
        schema_needs_map,
        atoms::relationship_references().encode(env),
        relationship_references_term,
    );

    // No longer include concrete tables and relationships implementations
    // Let Elixir code handle the conversion to concrete structures

    schema_needs_map
}

/// Encodes a vector of EntityReference into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `entity_references` - Vector of EntityReference structs to encode
///
/// # Returns
///
/// An Elixir list representation of the entity references
pub fn encode_entity_references<'a>(
    env: Env<'a>,
    entity_references: &[types::EntityReference],
) -> Term<'a> {
    let mut entity_terms = Vec::with_capacity(entity_references.len());

    for entity in entity_references {
        let mut entity_map = rustler::types::map::map_new(env);

        // Add graphql_name
        entity_map = map_put(
            entity_map,
            atoms::graphql_name().encode(env),
            entity.graphql_name.encode(env),
        );

        // Add alias if present
        if let Some(ref alias) = entity.alias {
            entity_map = map_put(entity_map, atoms::alias().encode(env), alias.encode(env));
        }

        entity_terms.push(entity_map);
    }

    // Create and return a list from the terms
    make_term_list(env, entity_terms)
}

/// Encodes a vector of RelationshipReference into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `relationship_references` - Vector of RelationshipReference structs to encode
///
/// # Returns
///
/// An Elixir list representation of the relationship references
pub fn encode_relationship_references<'a>(
    env: Env<'a>,
    relationship_references: &[types::RelationshipReference],
) -> Term<'a> {
    let mut rel_terms = Vec::with_capacity(relationship_references.len());

    for rel in relationship_references {
        let mut rel_map = rustler::types::map::map_new(env);

        // Add parent_name
        rel_map = map_put(
            rel_map,
            atoms::parent_name().encode(env),
            rel.parent_name.encode(env),
        );

        // Add child_name
        rel_map = map_put(
            rel_map,
            atoms::child_name().encode(env),
            rel.child_name.encode(env),
        );

        // Add parent_alias if present
        if let Some(ref alias) = rel.parent_alias {
            rel_map = map_put(
                rel_map,
                atoms::parent_alias().encode(env),
                alias.encode(env),
            );
        }

        // Add child_alias if present
        if let Some(ref alias) = rel.child_alias {
            rel_map = map_put(rel_map, atoms::child_alias().encode(env), alias.encode(env));
        }

        rel_terms.push(rel_map);
    }

    // Create and return a list from the terms
    make_term_list(env, rel_terms)
}

/// Encodes a variable map into an Elixir term
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `variable_map` - The variable map to encode
///
/// # Returns
///
/// An Elixir map representation of the variable map
pub fn encode_variable_map<'a>(env: Env<'a>, variable_map: &HashMap<String, String>) -> Term<'a> {
    let mut var_map = rustler::types::map::map_new(env);

    for (key, value) in variable_map {
        var_map = map_put(var_map, key.encode(env), value.encode(env));
    }

    var_map
}

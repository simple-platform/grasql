/// GraSQL Native Interface
///
/// This module provides the interface between Elixir and the Rust implementation
/// of GraSQL, a library for converting GraphQL queries to SQL. It handles parsing,
/// analysis, and SQL generation through NIFs (Native Implemented Functions).
///
/// The module is structured in two phases:
/// 1. Parse and analyze a GraphQL query to determine schema needs
/// 2. Generate optimized SQL based on the analysis and schema information
use rustler::types::tuple;
use rustler::{Encoder, Env, Term};

mod encoder;
mod parser;
mod types;

// Re-export the error types for access in this module
use crate::parser::error::Error as ParserError;

// Define atoms
mod atoms {
    rustler::atoms! {
        ok,
        error,
        not_implemented,
        graphql_parse_error,
        json_parse_error,
        variable_error,
        conversion_error,
        schema_extraction_error,
        unsupported_operation,
        missing_field,
        parsing_error,

        // Additional atoms needed for encoding
        qst,
        schema_needs,
        variable_map,
        operation_type,
        root_fields,
        variables,
        name,
        alias,
        arguments,
        selection,
        source_position,
        line,
        column,
        fields,
        schema,
        table,
        tables,
        relationships,
        source_table,
        target_table,
        source_column,
        target_column,
        relationship_type,
        join_table,
        query,
        mutation,

        // Atoms for EntityReference and RelationshipReference
        entity_references,
        relationship_references,
        graphql_name,
        parent_name,
        child_name,
        parent_alias,
        child_alias
    }
}

/// Phase 1: Parse and analyze a GraphQL query
///
/// This function parses a GraphQL query string with variables and performs
/// analysis to extract schema requirements for SQL generation.
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `query` - The GraphQL query string
/// * `variables_json` - JSON string of variable values
///
/// # Returns
///
/// * `{:ok, query_analysis}` - On successful parsing and analysis
/// * `{:error, {error_type, error_message}}` - On failure with detailed error information
///
/// # Example (Elixir)
///
/// ```elixir
/// query = "query GetUser($id: ID!) { user(id: $id) { name email } }"
/// variables = "{\"id\": \"123\"}"
/// {:ok, analysis} = GraSQL.Native.parse_and_analyze_query(query, variables)
/// ```
#[rustler::nif]
fn parse_and_analyze_query<'a>(env: Env<'a>, query: &str, variables_json: &str) -> Term<'a> {
    match parser::parse_and_analyze(query, variables_json) {
        Ok(query_analysis) => {
            // Convert QueryAnalysis to Elixir term using encoder functions
            let qst_term = encoder::encode_query_structure_tree(env, &query_analysis.qst);
            let schema_needs_term = encoder::encode_schema_needs(env, &query_analysis.schema_needs);
            let variable_map_term = encoder::encode_variable_map(env, &query_analysis.variable_map);

            // Create the QueryAnalysis map
            let mut result_map = rustler::types::map::map_new(env);

            result_map = encoder::map_put(result_map, atoms::qst().encode(env), qst_term);
            result_map = encoder::map_put(
                result_map,
                atoms::schema_needs().encode(env),
                schema_needs_term,
            );
            result_map = encoder::map_put(
                result_map,
                atoms::variable_map().encode(env),
                variable_map_term,
            );

            // Return {:ok, query_analysis}
            let ok_atom = atoms::ok().encode(env);
            tuple::make_tuple(env, &[ok_atom, result_map])
        }
        Err(err) => {
            // Convert error to appropriate Elixir term
            let (error_type, error_msg) = match err {
                ParserError::GraphQLParseError(e) => (atoms::graphql_parse_error(), e.to_string()),
                ParserError::JsonParseError(e) => (atoms::json_parse_error(), e),
                ParserError::VariableError(e) => (atoms::variable_error(), e),
                ParserError::UnsupportedOperation(e) => (atoms::unsupported_operation(), e),
                ParserError::ParsingError(e) => (atoms::parsing_error(), e),
            };

            // Return {:error, {error_type, error_msg}}
            let error_atom = atoms::error().encode(env);
            let inner_terms = &[error_type.encode(env), error_msg.encode(env)];
            let error_tuple = tuple::make_tuple(env, inner_terms);
            tuple::make_tuple(env, &[error_atom, error_tuple])
        }
    }
}

/// Phase 2: Generate SQL from analysis
///
/// This function takes a query analysis, schema information, and options,
/// and generates optimized SQL for the database.
///
/// # Arguments
///
/// * `env` - The NIF environment
/// * `query_analysis` - Analysis result from Phase 1
/// * `schema_info` - Database schema information
/// * `options` - Optional settings for SQL generation
///
/// # Returns
///
/// Currently returns `{:error, :not_implemented}` as this is a placeholder
/// for future implementation.
///
/// # Note
///
/// This functionality is planned for future implementation.
#[rustler::nif]
fn generate_sql<'a>(
    env: Env<'a>,
    _query_analysis: Term<'a>,
    _schema_info: Term<'a>,
    _options: Term<'a>,
) -> Term<'a> {
    // Placeholder implementation
    // The actual implementation will generate SQL based on the analysis and schema
    let err_atom = atoms::error().encode(env);
    let reason_atom = atoms::not_implemented().encode(env);
    tuple::make_tuple(env, &[err_atom, reason_atom])
}

// Initialize the Rustler NIF module
rustler::init!("Elixir.GraSQL.Native");

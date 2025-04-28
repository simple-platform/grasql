//! GraphQL query parser module for GraSQL
//!
//! This module handles parsing of GraphQL queries using the graphql-query library
//! and converts the resulting AST into GraSQL's internal representation.
//!
//! Features supported:
//! - Query and mutation operations
//! - Field selection with arguments
//! - Nested fields to arbitrary depth
//! - Variables with proper JSON binding
//! - Schema needs extraction

mod ast_converter;
pub mod error;
mod schema_extractor;
mod variable_processor;

#[cfg(test)]
mod tests;

use crate::types::QueryAnalysis;
use graphql_query::ast::{ASTContext, Document, ParseNode};

use self::ast_converter::ASTConverter;
use self::schema_extractor::SchemaExtractor;
use self::variable_processor::VariableProcessor;

// Redefine the error types
use crate::parser::error::Error;
type Result<T> = std::result::Result<T, Error>;

/// Parses a GraphQL query and extracts schema needs.
///
/// This function is the main entry point for parsing GraphQL queries.
/// It uses the graphql-query library to parse the query, then converts
/// the resulting AST into GraSQL's internal representation.
///
/// # Arguments
///
/// * `query` - The GraphQL query string to parse
/// * `variables_json` - JSON string containing variable values
///
/// # Returns
///
/// * `Result<QueryAnalysis>` - The parsed query structure and schema needs on success,
///   or an error if parsing fails
///
/// # Examples
///
/// ```rust,ignore
/// let query = "query { users { id name } }";
/// let variables = "{}";
/// let result = parse_and_analyze(query, variables);
/// ```
pub fn parse_and_analyze(query: &str, variables_json: &str) -> Result<QueryAnalysis> {
    // Log input in debug builds
    #[cfg(debug_assertions)]
    eprintln!("Parsing GraphQL query: {}", query);
    #[cfg(debug_assertions)]
    eprintln!("With variables: {}", variables_json);

    // Parse variables JSON
    let variables_value =
        serde_json::from_str(variables_json).map_err(|e| Error::JsonParseError(e.to_string()))?;

    // Initialize the AST context
    let ast_context = ASTContext::new();

    // Parse the GraphQL query
    let document = Document::parse(&ast_context, query).map_err(|e| {
        #[cfg(debug_assertions)]
        eprintln!("GraphQL parse error: {}", e);
        Error::GraphQLParseError(e)
    })?;

    // Process variables
    let variable_processor = VariableProcessor::new();
    let variable_map = variable_processor.process_variables(&document, &variables_value)?;

    // Convert AST to GraSQL's representation
    let mut ast_converter = ASTConverter::new();
    let qst = ast_converter.convert_document(&document)?;

    // Extract schema needs
    let schema_extractor = SchemaExtractor::new();
    let schema_needs = schema_extractor.extract_schema_needs(&qst)?;

    // Log output in debug builds
    #[cfg(debug_assertions)]
    {
        eprintln!("Parsed operation type: {:?}", qst.operation_type);
        eprintln!("Found {} root fields", qst.root_fields.len());
        eprintln!(
            "Found {} entity references",
            schema_needs.entity_references.len()
        );
        eprintln!(
            "Found {} relationship references",
            schema_needs.relationship_references.len()
        );
    }

    // Create and return the QueryAnalysis
    Ok(QueryAnalysis {
        qst,
        schema_needs,
        variable_map,
    })
}

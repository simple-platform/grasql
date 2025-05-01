/// GraphQL parsing module
///
/// This module provides functionality for parsing GraphQL queries and
/// extracting necessary information for SQL generation.
use crate::types::{GraphQLOperationKind, ParsedQueryInfo};
use graphql_query::ast::{ASTContext, Definition, Document, ParseNode};

/// Parse a GraphQL query string and extract necessary information
///
/// This function parses a GraphQL query string and extracts operation information
/// such as the operation kind (query, mutation, subscription) and name.
#[inline]
pub fn parse_graphql(query: &str) -> Result<ParsedQueryInfo, String> {
    // Create a new AST context
    let ctx = ASTContext::new();

    // Parse the query using the ParseNode trait
    let document = match Document::parse(&ctx, query) {
        Ok(doc) => doc,
        Err(e) => return Err(format!("Failed to parse GraphQL query: {}", e)),
    };

    // Extract operation information
    let mut operation_kind = GraphQLOperationKind::Query; // Default to query
    let mut operation_name = None;

    // Find the first operation definition
    for definition in document.definitions.iter() {
        if let Definition::Operation(op) = definition {
            operation_kind = op.operation.into();

            if let Some(name) = &op.name {
                operation_name = Some(name.name.to_string());
            }

            // For simplicity, we just use the first operation
            break;
        }
    }

    Ok(ParsedQueryInfo {
        operation_kind,
        operation_name,
    })
}

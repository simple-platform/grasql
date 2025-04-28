//! Error handling for GraphQL parsing
//!
//! This module defines error types and conversion functions for GraphQL parsing errors.
//! It provides detailed error types for better diagnostics during GraphQL query parsing.

use graphql_query::error::Error as GraphQLError;
use std::fmt;

/// Custom result type for the parser module
pub type Result<T> = std::result::Result<T, Error>;

/// Error types that can occur during GraphQL parsing and analysis
///
/// This enum provides specific error variants for all the possible failure modes
/// in the parsing and analysis process, with descriptive messages to help
/// diagnose and fix issues.
#[derive(Debug)]
pub enum Error {
    /// Error while parsing GraphQL query syntax
    GraphQLParseError(GraphQLError),

    /// Error while parsing JSON variables
    JsonParseError(String),

    /// Error when an unsupported operation type is encountered
    UnsupportedOperation(String),

    /// Error when processing variables
    VariableError(String),

    /// Generic parsing error
    ParsingError(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::GraphQLParseError(err) => write!(f, "GraphQL parse error: {}", err),
            Error::JsonParseError(msg) => write!(f, "JSON parse error: {}", msg),
            Error::UnsupportedOperation(op) => write!(f, "Unsupported operation: {}", op),
            Error::VariableError(msg) => write!(f, "Variable processing error: {}", msg),
            Error::ParsingError(msg) => write!(f, "Parsing error: {}", msg),
        }
    }
}

impl std::error::Error for Error {}

/// Placeholder struct for GraphQL error location
///
/// This is a minimal implementation that satisfies the needs of the codebase
/// without unused fields.
#[derive(Debug, Clone)]
pub struct ErrorLocation {}

impl From<&graphql_query::error::Location> for ErrorLocation {
    fn from(_location: &graphql_query::error::Location) -> Self {
        ErrorLocation {}
    }
}

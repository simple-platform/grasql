/// Types module containing core data structures
///
/// This module defines the main data types used throughout the GraSQL codebase,
/// including GraphQL operation types and parsed query information.
use graphql_query::ast::OperationKind;

/// Enum to represent GraphQL operation kind
#[derive(Clone, Debug)]
pub enum GraphQLOperationKind {
    /// A query operation that retrieves data
    Query,
    /// A mutation operation that modifies data
    Mutation,
    /// A subscription operation that creates a real-time data stream
    Subscription,
}

impl From<OperationKind> for GraphQLOperationKind {
    fn from(kind: OperationKind) -> Self {
        match kind {
            OperationKind::Query => GraphQLOperationKind::Query,
            OperationKind::Mutation => GraphQLOperationKind::Mutation,
            OperationKind::Subscription => GraphQLOperationKind::Subscription,
        }
    }
}

/// A structure representing the extracted information from a parsed GraphQL query
/// This structure is designed to be thread-safe and not contain any lifetimes
#[derive(Clone, Debug)]
pub struct ParsedQueryInfo {
    /// The operation kind (query, mutation, subscription)
    pub operation_kind: GraphQLOperationKind,

    /// Operation name if present
    pub operation_name: Option<String>,
}

use graphql_query::ast::{ASTContext, Document};
/// GraSQL type definitions
///
/// This module contains type definitions used throughout the GraSQL library.
use lasso::Spur;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::ops::Deref;
use std::sync::Arc;

/// Type alias for interned string ID
pub type SymbolId = Spur;

/// GraphQL operation kind
///
/// This enum represents the different kinds of GraphQL operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GraphQLOperationKind {
    /// Query operation
    Query,
    /// Mutation operation
    Mutation,
    /// Subscription operation
    Subscription,
}

/// A path to a field in the GraphQL query, represented as a sequence of symbol IDs
///
/// Using SmallVec for optimal performance with small paths (which is the common case)
/// with a size of 8 which should cover most paths without heap allocation.
#[derive(Debug, Clone, Hash, PartialEq, Eq)]
pub struct FieldPath(smallvec::SmallVec<[SymbolId; 8]>);

impl FieldPath {
    /// Create a new empty field path
    #[inline(always)]
    pub fn new() -> Self {
        FieldPath(smallvec::SmallVec::new())
    }

    /// Push a field to the path
    #[inline(always)]
    pub fn push(&mut self, symbol_id: SymbolId) {
        self.0.push(symbol_id);
    }

    /// Pop the last field from the path
    #[inline(always)]
    pub fn pop(&mut self) -> Option<SymbolId> {
        self.0.pop()
    }

    /// Get length of the path
    #[inline(always)]
    pub fn len(&self) -> usize {
        self.0.len()
    }

    /// Check if the path is empty
    #[inline(always)]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Create a copy with one more field added
    #[inline(always)]
    pub fn with_field(&self, symbol_id: SymbolId) -> Self {
        let mut new_path = self.clone();
        new_path.push(symbol_id);
        new_path
    }

    /// Clear all fields from the path
    #[inline(always)]
    pub fn clear(&mut self) {
        self.0.clear();
    }

    /// Convert to a Vec of SymbolId
    #[inline(always)]
    pub fn to_vec(&self) -> Vec<SymbolId> {
        self.0.to_vec()
    }
}

impl Deref for FieldPath {
    type Target = [SymbolId];

    #[inline(always)]
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

/// Resolution request to be sent to Elixir
///
/// This type encapsulates the information needed for resolving
/// field paths to actual database tables and relationships.
#[derive(Debug, Clone)]
pub struct ResolutionRequest {
    /// All field names that need resolution (the string table)
    pub field_names: Vec<String>,

    /// Set of unique field paths that need resolution
    /// Each path is a sequence of indices into field_names
    pub field_paths: HashSet<Vec<u32>>,
}

impl ResolutionRequest {
    /// Create a new empty resolution request
    #[inline(always)]
    pub fn new() -> Self {
        ResolutionRequest {
            field_names: Vec::new(),
            field_paths: HashSet::new(),
        }
    }
}

/// Thread-safe version of ParsedQueryInfo for caching
#[derive(Clone, Debug)]
pub struct CachedQueryInfo {
    /// Kind of GraphQL operation
    pub operation_kind: GraphQLOperationKind,

    /// Name of the operation (if any)
    pub operation_name: Option<String>,

    /// Field paths for tables and relationships
    pub field_paths: Option<HashSet<FieldPath>>,

    /// Field path index for O(1) lookup in Phase 3
    pub path_index: Option<HashMap<FieldPath, usize>>,
}

/// Convert ParsedQueryInfo to CachedQueryInfo
impl From<ParsedQueryInfo> for CachedQueryInfo {
    #[inline(always)]
    fn from(info: ParsedQueryInfo) -> Self {
        CachedQueryInfo {
            operation_kind: info.operation_kind,
            operation_name: info.operation_name,
            field_paths: info.field_paths,
            path_index: info.path_index,
        }
    }
}

/// Information about a parsed GraphQL query
///
/// This struct holds information extracted from a GraphQL query during parsing.
/// It includes the operation type, field paths, and other data needed for SQL generation.
#[derive(Clone)]
pub struct ParsedQueryInfo {
    /// Kind of GraphQL operation
    pub operation_kind: GraphQLOperationKind,

    /// Name of the operation (if any)
    pub operation_name: Option<String>,

    /// Field paths for tables and relationships (added for Phase 1)
    pub field_paths: Option<HashSet<FieldPath>>,

    /// Field path index for O(1) lookup in Phase 3 (added for Phase 1)
    pub path_index: Option<HashMap<FieldPath, usize>>,

    /// Store the original AST context for future use
    pub ast_context: Option<Arc<ASTContext>>,

    /// Store the document with static lifetime for Phase 3
    pub document: Option<Arc<Document<'static>>>,
}

// Manual Debug implementation to avoid ASTContext not implementing Debug
impl fmt::Debug for ParsedQueryInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ParsedQueryInfo")
            .field("operation_kind", &self.operation_kind)
            .field("operation_name", &self.operation_name)
            .field("field_paths", &self.field_paths)
            .field("path_index", &self.path_index)
            .field("ast_context", &"<ASTContext>")
            .field("document", &"<Document>")
            .finish()
    }
}

impl fmt::Display for GraphQLOperationKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GraphQLOperationKind::Query => write!(f, "query"),
            GraphQLOperationKind::Mutation => write!(f, "mutation"),
            GraphQLOperationKind::Subscription => write!(f, "subscription"),
        }
    }
}

/// Implement From<graphql_query::ast::OperationKind> for GraphQLOperationKind
impl From<graphql_query::ast::OperationKind> for GraphQLOperationKind {
    #[inline(always)]
    fn from(kind: graphql_query::ast::OperationKind) -> Self {
        match kind {
            graphql_query::ast::OperationKind::Query => GraphQLOperationKind::Query,
            graphql_query::ast::OperationKind::Mutation => GraphQLOperationKind::Mutation,
            graphql_query::ast::OperationKind::Subscription => GraphQLOperationKind::Subscription,
        }
    }
}

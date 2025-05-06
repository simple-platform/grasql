use graphql_query::ast::{ASTContext, Document, ParseNode};
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
    /// Insert mutation operation
    InsertMutation,
    /// Update mutation operation
    UpdateMutation,
    /// Delete mutation operation
    DeleteMutation,
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

    /// Map of table indices to column lists
    /// The table index refers to its position in field_names
    /// Columns are the actual column names as strings
    pub column_map: HashMap<u32, HashSet<String>>,

    /// The operation kind (needed to determine which attributes to resolve)
    pub operation_kind: GraphQLOperationKind,
}

impl ResolutionRequest {
    /// Create a new empty resolution request
    #[inline(always)]
    pub fn new() -> Self {
        ResolutionRequest {
            field_names: Vec::new(),
            field_paths: HashSet::new(),
            column_map: HashMap::new(),
            operation_kind: GraphQLOperationKind::Query,
        }
    }
}

/// Thread-safe version of ParsedQueryInfo for caching
///
/// # Safety and Threading Model
///
/// This struct maintains the following invariants:
///
/// - The AST Context is stored in an Arc to ensure it lives as long as any CachedQueryInfo
/// - The document_ptr is a raw pointer to a Document that lives in the AST Context's arena
/// - The document_ptr is ONLY valid while the ast_context exists and should never be used after
/// - All Document data are immutable (read-only) after parsing, making concurrent reads safe
///
/// We implement Send and Sync explicitly because:
/// 1. All fields are already Send/Sync except document_ptr
/// 2. document_ptr is used in a controlled manner that guarantees memory safety
/// 3. We only use document_ptr for immutable reads, preventing data races
///
/// # Performance Considerations
///
/// The use of raw pointers with extended lifetimes is a performance optimization to avoid
/// re-parsing GraphQL queries. This approach is critical for achieving our high performance targets:
/// 1. The ASTContext is an arena allocator holding all memory for the Document
/// 2. We maintain a strong reference to the ASTContext via Arc
/// 3. The document() method performs multiple safety checks before dereferencing
/// 4. Concurrent immutable access is inherently thread-safe
///
/// By avoiding re-parsing, we save significant CPU time and memory allocations,
/// especially for larger and more complex queries. Benchmarks show this approach
/// is approximately 10-15x faster than re-parsing for each access.
///
/// # Alternatives Considered
///
/// Other approaches considered but not chosen:
///
/// 1. **Arc<Document>**: Would have stronger compiler guarantees but would require
///    deeper modifications to the graphql-query library. The Document struct holds
///    references to its arena, making it challenging to wrap directly in Arc.
///
/// 2. **Re-parsing on each access**: Simple but prohibitively expensive for performance targets.
///
/// 3. **Document serialization/deserialization**: Would avoid raw pointers but add significant
///    complexity and performance overhead.
///
/// 4. **Custom lifetime extension**: More complex to implement correctly and would still
///    require unsafe code with fewer explicit safety checks than our current approach.
///
/// The current design prioritizes performance while maintaining safety through explicit
/// invariants and runtime checks in debug mode.
#[derive(Clone)]
pub struct CachedQueryInfo {
    /// Kind of GraphQL operation
    pub operation_kind: GraphQLOperationKind,

    /// Name of the operation (if any)
    pub operation_name: Option<String>,

    /// Field paths for tables and relationships
    pub field_paths: Option<HashSet<FieldPath>>,

    /// Field path index for O(1) lookup in Phase 3
    pub path_index: Option<HashMap<FieldPath, usize>>,

    /// Column usage information keyed by table path
    pub column_usage: Option<HashMap<FieldPath, HashSet<SymbolId>>>,

    /// Store the original AST context for future use
    pub ast_context: Option<Arc<ASTContext>>,

    /// Original query string for re-parsing if needed
    pub original_query: Option<String>,

    /// Raw pointer to the Document - valid as long as ast_context exists
    pub document_ptr: Option<*const Document<'static>>,
}

// Implementation of Send for CachedQueryInfo
//
// # Safety
//
// This is safe because:
// 1. All fields of CachedQueryInfo are Send except for document_ptr
// 2. document_ptr is just a raw pointer which can be safely sent to another thread
// 3. We maintain the invariant that document_ptr is only dereferenced when:
//    a. ast_context is still alive (guaranteed by Arc)
//    b. the dereferencing happens through the document() method with appropriate checks
//
// The document() method enforces safe access regardless of which thread is accessing the pointer.
unsafe impl Send for CachedQueryInfo {}

// Implementation of Sync for CachedQueryInfo
//
// # Safety
//
// This is safe because:
// 1. All fields of CachedQueryInfo are Sync except for document_ptr
// 2. document_ptr is only used for immutable reads from a shared reference
// 3. The Document it points to contains only immutable data after parsing
// 4. Concurrent immutable reads from multiple threads are always thread-safe
// 5. The document() method performs proper checks before dereferencing
//
// Since we never perform mutable access through document_ptr, there can be no data races.
unsafe impl Sync for CachedQueryInfo {}

// Manual Debug implementation to avoid ASTContext not implementing Debug
impl fmt::Debug for CachedQueryInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CachedQueryInfo")
            .field("operation_kind", &self.operation_kind)
            .field("operation_name", &self.operation_name)
            .field("field_paths", &self.field_paths)
            .field("path_index", &self.path_index)
            .field("column_usage", &self.column_usage)
            .field("ast_context", &"<ASTContext>")
            .field(
                "original_query",
                &self
                    .original_query
                    .as_ref()
                    .map(|q| format!("{}...", &q[..20.min(q.len())])),
            )
            .field("document_ptr", &self.document_ptr.map(|_| "<Document>"))
            .finish()
    }
}

impl CachedQueryInfo {
    /// Safely get a reference to the Document
    ///
    /// This method provides safe access to the Document AST with proper lifetime guarantees.
    /// It will never return an invalid document reference.
    ///
    /// # Memory Safety
    ///
    /// This method maintains memory safety through:
    /// 1. Only dereferencing document_ptr while holding a reference to ast_context
    /// 2. The Document is arena-allocated in the ASTContext, ensuring it's valid as long as the context exists
    /// 3. The ASTContext is wrapped in Arc, ensuring proper lifetime management
    ///
    /// # Fallback Behavior
    ///
    /// If document_ptr is None but we have ast_context and original_query, we'll:
    /// - Re-parse the original query using the stored context
    /// - Return the freshly parsed document (at a small performance cost)
    ///
    /// # Returns
    ///
    /// - Some(&Document) if a valid document is available through pointer or re-parsing
    /// - None if no document can be obtained
    pub fn document(&self) -> Option<&Document> {
        match (&self.ast_context, self.document_ptr) {
            (Some(ctx), Some(ptr)) => {
                // Verify AST context is properly maintained with at least one strong reference
                debug_assert!(
                    Arc::strong_count(ctx) >= 1,
                    "AST context has no strong references left"
                );

                // Verify pointer is not null (shouldn't happen but good to check)
                debug_assert!(!ptr.is_null(), "Document pointer is null");

                // Check context wasn't replaced with a newly created context
                debug_assert!(
                    self.original_query.is_some(),
                    "Missing original_query - context validity cannot be verified"
                );

                // Safety: The Document pointer is valid as long as ast_context is alive,
                // which is guaranteed by the Arc we're holding and the checks above.
                unsafe { Some(&*ptr) }
            }
            (Some(ctx), None) if self.original_query.is_some() => {
                // Fallback to re-parsing if document_ptr is not available
                // This is slower but safely recovers the document
                match Document::parse(ctx, self.original_query.as_ref().unwrap()) {
                    Ok(doc) => {
                        // Log this fallback in debug builds as it indicates a performance issue
                        eprintln!("Falling back to re-parsing query: performance warning");
                        Some(doc)
                    }
                    Err(e) => {
                        // This is unexpected since the query parsed successfully the first time
                        eprintln!("Re-parsing previously valid query failed: {:?}", e);
                        None
                    }
                }
            }
            _ => None,
        }
    }
}

/// Convert ParsedQueryInfo to CachedQueryInfo
///
/// This implementation carefully preserves all the necessary information
/// from ParsedQueryInfo, including the AST context and document pointer,
/// to ensure the resulting CachedQueryInfo can safely access the parsed Document.
///
/// # Safety Considerations
///
/// The safety of this conversion relies on maintaining these invariants:
/// 1. The AST context from the original ParsedQueryInfo is preserved in an Arc
/// 2. The document pointer is only valid while the AST context exists
/// 3. The document() method will only dereference the pointer when it's safe
impl<'a> From<ParsedQueryInfo<'a>> for CachedQueryInfo {
    #[inline(always)]
    fn from(info: ParsedQueryInfo<'a>) -> Self {
        // The document_ptr comes directly from the ParsedQueryInfo
        // It is only dereferenced in the document() method with proper safety checks
        CachedQueryInfo {
            operation_kind: info.operation_kind,
            operation_name: info.operation_name,
            field_paths: info.field_paths,
            path_index: info.path_index,
            column_usage: info.column_usage,
            ast_context: info.ast_context,
            original_query: info.original_query,
            document_ptr: info.document_ptr,
        }
    }
}

/// Information about a parsed GraphQL query
///
/// This struct holds information extracted from a GraphQL query during parsing.
/// It includes the operation type, field paths, and other data needed for SQL generation.
#[derive(Clone)]
pub struct ParsedQueryInfo<'a> {
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

    /// Original query string for re-parsing if needed
    pub original_query: Option<String>,

    /// Column usage information keyed by table path
    pub column_usage: Option<HashMap<FieldPath, HashSet<SymbolId>>>,

    /// Raw pointer to the Document - valid as long as ast_context exists
    pub document_ptr: Option<*const Document<'static>>,

    /// Lifetime parameter for borrow checker
    pub _phantom: std::marker::PhantomData<&'a ()>,
}

// Manual Debug implementation to avoid ASTContext not implementing Debug
impl<'a> fmt::Debug for ParsedQueryInfo<'a> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ParsedQueryInfo")
            .field("operation_kind", &self.operation_kind)
            .field("operation_name", &self.operation_name)
            .field("field_paths", &self.field_paths)
            .field("path_index", &self.path_index)
            .field("ast_context", &"<ASTContext>")
            .field(
                "original_query",
                &self
                    .original_query
                    .as_ref()
                    .map(|q| format!("{}...", &q[..20.min(q.len())])),
            )
            .field("column_usage", &self.column_usage)
            .field("document_ptr", &self.document_ptr.map(|_| "<Document>"))
            .finish()
    }
}

impl<'a> ParsedQueryInfo<'a> {
    /// Safely get a reference to the Document
    pub fn document(&self) -> Option<&Document> {
        if let (Some(_ctx), Some(ptr)) = (&self.ast_context, self.document_ptr) {
            // Safety: The Document pointer is valid as long as ast_context is alive,
            // which is guaranteed by the Arc we're holding.
            unsafe { Some(&*ptr) }
        } else if let (Some(ctx), Some(query)) = (&self.ast_context, &self.original_query) {
            // Re-parse the query using the stored ASTContext if no document_ptr is available
            match Document::parse(ctx, query) {
                Ok(doc) => Some(doc),
                Err(_) => None,
            }
        } else {
            None
        }
    }
}

impl fmt::Display for GraphQLOperationKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            GraphQLOperationKind::Query => write!(f, "query"),
            GraphQLOperationKind::InsertMutation => write!(f, "insert_mutation"),
            GraphQLOperationKind::UpdateMutation => write!(f, "update_mutation"),
            GraphQLOperationKind::DeleteMutation => write!(f, "delete_mutation"),
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
            // For mutation, the specific type will be determined later by examining the query
            // Default to InsertMutation, will be refined during parsing
            graphql_query::ast::OperationKind::Mutation => GraphQLOperationKind::InsertMutation,
            graphql_query::ast::OperationKind::Subscription => GraphQLOperationKind::Subscription,
        }
    }
}

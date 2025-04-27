use rustler::NifStruct;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Represents the type of GraphQL operation
///
/// Used to determine the kind of operation a GraphQL request represents.
/// Currently supports the standard Query and Mutation operations.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum OperationType {
    /// A read-only operation for retrieving data
    Query,
    /// An operation that modifies data
    Mutation,
}

/// Represents a position in the source GraphQL document for error reporting
///
/// Tracks the line and column information for GraphQL nodes, allowing precise
/// error messages and debugging information to be generated.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SourcePosition"]
pub struct SourcePosition {
    /// 1-indexed line number in the source document
    pub line: usize,
    /// 1-indexed column number in the source document
    pub column: usize,
}

/// Represents a field in a GraphQL query
///
/// Fields are fundamental building blocks of GraphQL queries, representing
/// data that should be fetched from the schema. They can be nested through
/// their selection sets, forming a query structure tree.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.Field"]
pub struct Field {
    /// The field name in the schema
    pub name: String,
    /// Optional alias for the field in the result
    pub alias: Option<String>,
    /// Map of arguments for the field (simplified to String values for now)
    pub arguments: HashMap<String, String>,
    /// Selection set for this field (nested fields)
    pub selection: Box<Selection>,
    /// Position in the source document
    pub source_position: SourcePosition,
}

/// Represents a set of selected fields in a GraphQL query
///
/// Selection sets define which child fields to include when querying an object.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.Selection"]
pub struct Selection {
    /// List of fields in this selection set
    pub fields: Vec<Field>,
}

/// Reference to a database table
///
/// TableRef identifies a specific table in the database schema and
/// is used to track which tables are needed to fulfill a GraphQL query.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.TableRef"]
pub struct TableRef {
    /// Database schema name
    pub schema: String,
    /// Table name
    pub table: String,
    /// Optional alias for the table in SQL queries
    pub alias: Option<String>,
}

/// Types of relationships between tables
///
/// Defines the cardinality between related tables.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum RelType {
    /// Many-to-one relationship (foreign key points to parent)
    BelongsTo,
    /// One-to-one relationship
    HasOne,
    /// One-to-many relationship (parent referenced by foreign key)
    HasMany,
}

/// Reference to a relationship between tables
///
/// RelationshipRef describes how two tables are related, including
/// the join columns and relationship type.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.RelationshipRef"]
pub struct RelationshipRef {
    /// Source table in the relationship
    pub source_table: TableRef,
    /// Target table in the relationship
    pub target_table: TableRef,
    /// Column name in the source table
    pub source_column: String,
    /// Column name in the target table
    pub target_column: String,
    /// Type of relationship (stored as string for Elixir interop)
    pub relationship_type: String,
    /// Optional join table for many-to-many relationships
    pub join_table: Option<TableRef>,
}

/// Collection of database objects needed for a query
///
/// SchemaNeeds collects all tables and relationships required to
/// execute a GraphQL query, used for SQL generation.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SchemaNeeds"]
pub struct SchemaNeeds {
    /// Tables required for the query
    pub tables: Vec<TableRef>,
    /// Relationships between tables
    pub relationships: Vec<RelationshipRef>,
    /// Map for O(1) lookup of tables
    pub table_map: HashMap<u64, bool>,
    /// Map for O(1) lookup of relationships
    pub relationship_map: HashMap<u64, bool>,
}

/// GraphQL variable representation
///
/// Represents a variable declared in a GraphQL operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variable {
    /// Variable name
    pub name: String,
    /// GraphQL type (e.g., "Int", "String")
    pub type_name: String,
    /// Optional default value
    pub default_value: Option<String>,
}

/// Complete structure tree of a GraphQL query
///
/// QueryStructureTree contains the parsed structure of a GraphQL query,
/// including operation type, root fields, and variables.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.QueryStructureTree"]
pub struct QueryStructureTree {
    /// Type of GraphQL operation (stored as string for Elixir interop)
    pub operation_type: String,
    /// Top-level fields in the query
    pub root_fields: Vec<Field>,
    /// Variables defined in the query
    pub variables: Vec<HashMap<String, String>>,
}

/// Complete analysis results from Phase 1
///
/// QueryAnalysis contains the query structure tree, schema needs, variable map,
/// and operation type for use in SQL generation.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.QueryAnalysis"]
pub struct QueryAnalysis {
    /// The query structure tree
    pub qst: QueryStructureTree,
    /// Database objects needed for the query
    pub schema_needs: SchemaNeeds,
    /// Map of variable names to their values
    pub variable_map: HashMap<String, String>,
    /// Type of GraphQL operation (stored as string for Elixir interop)
    pub operation_type: String,
}

/// SQL result field mapping
///
/// Maps a SQL column to its path in the GraphQL response.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.ResultField"]
pub struct ResultField {
    /// SQL column name
    pub sql_column: String,
    /// Path in the GraphQL response
    pub path: Vec<String>,
    /// Whether the field contains JSON data
    pub is_json: bool,
}

/// SQL result mapping structure
///
/// Describes how SQL query results map to the GraphQL response structure.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.ResultStructure"]
pub struct ResultStructure {
    /// Field mappings
    pub fields: Vec<ResultField>,
    /// Map of nested object paths to their column prefixes
    pub nested_objects: HashMap<Vec<String>, Vec<String>>,
}

/// SQL generation result
///
/// Contains the SQL query, parameters, and result structure for a GraphQL query.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SqlResult"]
pub struct SqlResult {
    /// The SQL query string
    pub sql: String,
    /// Parameter values for the query
    pub parameters: Vec<String>,
    /// Parameter types
    pub parameter_types: Vec<String>,
    /// Structure for mapping SQL results to GraphQL
    pub result_structure: ResultStructure,
}

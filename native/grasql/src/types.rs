use rustler::{Decoder, Encoder, NifStruct, Term};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Represents the type of GraphQL operation
///
/// Used to determine the kind of operation a GraphQL request represents.
/// Currently supports the standard Query and Mutation operations.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum OperationType {
    Query,
    Mutation,
}

// Define atoms for operation types
rustler::atoms! {
    query,
    mutation,
}

// Implement rustler encoding/decoding for OperationType
impl<'a> Decoder<'a> for OperationType {
    fn decode(term: Term<'a>) -> Result<Self, rustler::Error> {
        if term.atom_to_string()? == "query" {
            Ok(OperationType::Query)
        } else if term.atom_to_string()? == "mutation" {
            Ok(OperationType::Mutation)
        } else {
            Err(rustler::Error::BadArg)
        }
    }
}

impl Encoder for OperationType {
    fn encode<'a>(&self, env: rustler::Env<'a>) -> Term<'a> {
        match self {
            OperationType::Query => query().encode(env),
            OperationType::Mutation => mutation().encode(env),
        }
    }
}

/// Represents a position in the source GraphQL document for error reporting
///
/// Tracks the line and column information for GraphQL nodes, allowing precise
/// error messages and debugging information to be generated.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SourcePosition"]
pub struct SourcePosition {
    pub line: usize,
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
    pub name: String,
    pub alias: Option<String>,
    pub arguments: HashMap<String, String>,
    pub selection: Box<Selection>,
    pub source_position: SourcePosition,
}

/// Represents a set of selected fields in a GraphQL query
///
/// Selection sets define which child fields to include when querying an object.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.Selection"]
pub struct Selection {
    pub fields: Vec<Field>,
}

/// Reference to a database table
///
/// TableRef identifies a specific table in the database schema and
/// is used to track which tables are needed to fulfill a GraphQL query.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.TableRef"]
pub struct TableRef {
    pub schema: String,
    pub table: String,
    pub alias: Option<String>,
}

/// Types of relationships between tables
///
/// Defines the cardinality between related tables.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum RelType {
    BelongsTo,
    HasOne,
    HasMany,
}

/// Reference to a relationship between tables
///
/// RelationshipRef describes how two tables are related, including
/// the join columns and relationship type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.RelationshipRef"]
pub struct RelationshipRef {
    pub source_table: TableRef,
    pub target_table: TableRef,
    pub source_column: String,
    pub target_column: String,
    pub relationship_type: String,
    pub join_table: Option<TableRef>,
}

/// Collection of database objects needed for a query
///
/// SchemaNeeds collects all tables and relationships required to
/// execute a GraphQL query, used for SQL generation.
///
/// Note: While this uses Vec for serialization compatibility, the implementation
/// uses HashSet internally to avoid duplicates efficiently.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SchemaNeeds"]
pub struct SchemaNeeds {
    pub tables: Vec<TableRef>,
    pub relationships: Vec<RelationshipRef>,
}

/// GraphQL variable representation
///
/// Represents a variable declared in a GraphQL operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variable {
    pub name: String,
    pub type_name: String,
    pub default_value: Option<String>,
}

/// Complete structure tree of a GraphQL query
///
/// QueryStructureTree contains the parsed structure of a GraphQL query,
/// including operation type, root fields, and variables.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.QueryStructureTree"]
pub struct QueryStructureTree {
    pub operation_type: OperationType,
    pub root_fields: Vec<Field>,
    pub variables: Vec<HashMap<String, String>>,
}

/// Complete analysis results from Phase 1
///
/// QueryAnalysis contains the query structure tree, schema needs, variable map,
/// and operation type for use in SQL generation.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.QueryAnalysis"]
pub struct QueryAnalysis {
    pub qst: QueryStructureTree,
    pub schema_needs: SchemaNeeds,
    pub variable_map: HashMap<String, String>,
    pub operation_type: OperationType,
}

/// SQL result field mapping
///
/// Maps a SQL column to its path in the GraphQL response.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.ResultField"]
pub struct ResultField {
    pub sql_column: String,
    pub path: Vec<String>,
    pub is_json: bool,
}

/// SQL result mapping structure
///
/// Describes how SQL query results map to the GraphQL response structure.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.ResultStructure"]
pub struct ResultStructure {
    pub fields: Vec<ResultField>,
    pub nested_objects: HashMap<Vec<String>, Vec<String>>,
}

/// SQL generation result
///
/// Contains the SQL query, parameters, and result structure for a GraphQL query.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SqlResult"]
pub struct SqlResult {
    pub sql: String,
    pub parameters: Vec<String>,
    pub parameter_types: Vec<String>,
    pub result_structure: ResultStructure,
}

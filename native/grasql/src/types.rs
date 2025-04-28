use rustler::{NifStruct, NifUnitEnum};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::hash::{Hash, Hasher};

/// Represents the type of GraphQL operation
///
/// Used to determine the kind of operation a GraphQL request represents.
/// Currently supports the standard Query and Mutation operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, NifUnitEnum)]
pub enum OperationType {
    Query,
    Mutation,
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

/// Represents a GraphQL directive on a field
///
/// Directives affect how fields are processed during execution
/// (e.g., @include, @skip)
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.Directive"]
pub struct Directive {
    pub name: String,
    pub arguments: HashMap<String, String>,
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
    pub directives: Vec<Directive>,
}

/// Represents a type condition for fragments
///
/// Type conditions specify which object type a fragment applies to
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.TypeCondition"]
pub struct TypeCondition {
    pub type_name: String,
}

/// Represents a fragment spread in a GraphQL query
///
/// Fragment spreads reference a named fragment definition to be included
/// in the selection set.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.FragmentSpread"]
pub struct FragmentSpread {
    pub name: String,
    pub directives: Vec<Directive>,
}

/// Represents an inline fragment in a GraphQL query
///
/// Inline fragments allow selections to be conditionally included based on
/// the object's type, or to include directives.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.InlineFragment"]
pub struct InlineFragment {
    pub type_condition: Option<TypeCondition>,
    pub directives: Vec<Directive>,
    pub selection: Box<Selection>,
}

/// Represents a named fragment definition in a GraphQL query
///
/// Fragment definitions are reusable units of selection sets that can be
/// included in queries via fragment spreads.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.FragmentDefinition"]
pub struct FragmentDefinition {
    pub name: String,
    pub type_condition: TypeCondition,
    pub directives: Vec<Directive>,
    pub selection: Box<Selection>,
}

/// Represents a set of selected fields in a GraphQL query
///
/// Selection sets define which child fields to include when querying an object.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.Selection"]
pub struct Selection {
    pub fields: Vec<Field>,
    pub fragment_spreads: Vec<FragmentSpread>,
    pub inline_fragments: Vec<InlineFragment>,
}

/// Reference to an entity from GraphQL query
///
/// EntityReference identifies a GraphQL field that represents an entity
/// and is used to track which entities are needed to fulfill a query.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.EntityReference"]
pub struct EntityReference {
    pub graphql_name: String,
    pub alias: Option<String>,
}

/// Reference to a relationship between entities from GraphQL query
///
/// RelationshipReference describes how GraphQL fields are related in a query,
/// without making assumptions about database structure.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.RelationshipReference"]
pub struct RelationshipReference {
    pub parent_name: String,
    pub child_name: String,
    pub parent_alias: Option<String>,
    pub child_alias: Option<String>,
}

/// Collection of database objects needed for a query
///
/// SchemaNeeds collects all entity and relationship references required to
/// execute a GraphQL query, used for schema resolution before SQL generation.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.SchemaNeeds"]
pub struct SchemaNeeds {
    pub entity_references: Vec<EntityReference>,
    pub relationship_references: Vec<RelationshipReference>,
}

/// Reference to a database table
///
/// TableRef identifies a specific table in the database schema and
/// is used to track which tables are needed to fulfill a GraphQL query.
#[derive(Debug, Clone, Serialize, Deserialize, NifStruct)]
#[module = "GraSQL.TableRef"]
pub struct TableRef {
    pub schema: String,
    pub table: String,
    pub alias: Option<String>,
}

// Custom implementations for TableRef to ensure tables with aliases are considered unique
impl PartialEq for TableRef {
    fn eq(&self, other: &Self) -> bool {
        self.schema == other.schema && 
        self.table == other.table && 
        // If both have aliases, compare them
        // If one has an alias and the other doesn't, they're different
        // If neither has an alias, compare the tables
        match (&self.alias, &other.alias) {
            (Some(a1), Some(a2)) => a1 == a2,
            (None, None) => true,
            _ => false,
        }
    }
}

impl Eq for TableRef {}

impl Hash for TableRef {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.schema.hash(state);
        self.table.hash(state);
        // Hash the alias if present, otherwise hash a sentinel value
        match &self.alias {
            Some(alias) => {
                1.hash(state);
                alias.hash(state);
            },
            None => {
                0.hash(state);
            }
        }
    }
}

/// Types of relationships between tables
///
/// Defines the cardinality between related tables.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
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
    pub fragment_definitions: HashMap<String, FragmentDefinition>,
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

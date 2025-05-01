# Query Structure Tree (QST)

## Introduction

The Query Structure Tree (QST) is the internal representation used by GraSQL to represent GraphQL queries in a form that can be efficiently translated into SQL.

The QST serves several critical purposes:

1. **Structured representation**: QST provides a structured, tree-like representation of a GraphQL query that preserves the original query's hierarchical nature.

2. **Intermediate format**: QST serves as an intermediate format between the parsed GraphQL query and the generated SQL, enabling a clean separation of concerns.

3. **Schema resolution**: QST includes fields for tracking both the original query information and the resolved schema information, making schema resolution explicit and traceable.

4. **Optimization-ready**: QST is designed to facilitate efficient SQL generation, with structures that map naturally to SQL constructs like joins, filters, and aggregations.

5. **Complete parameterization**: All values in the query (both user-provided variables and inline literals) are converted to parameters, enhancing security, performance, and maintainability.

## Overall Structure

At the highest level, a QST consists of:

- **Operation type**: Whether this is a query or mutation
- **Root fields**: Top-level fields in the GraphQL query
- **Variables**: Both user-provided and auto-generated variables from the GraphQL query

The QST uses a recursive structure to represent nested relationships, with each field potentially containing:

- **Selection**: The fields to be selected from this entity
- **Arguments**: Query arguments like filters, sorting, and pagination
- **Relationships**: Links to other entities, each with their own selection and arguments

This recursive structure allows QST to represent arbitrarily nested GraphQL queries while maintaining the relationships between entities.

## Detailed Component Reference

### QueryStructureTree

The top-level structure that represents a complete GraphQL query.

```rust
struct QueryStructureTree {
    operation_type: OperationType,             // Query or Mutation
    root_fields: Vec<RootField>,               // Top-level fields in the GraphQL query
    variables: HashMap<String, VariableValue>, // All variables (user-provided and auto-generated)
}
```

### OperationType

An enum representing the type of operation.

```rust
enum OperationType {
    Query,
    Mutation
}
```

### RootField

Represents a top-level field in the GraphQL query.

```rust
struct RootField {
    name: String,                       // Original field name from the GraphQL query
    alias: Option<String>,              // Alias if provided in the query

    // Original parsing information
    target_table: String,               // Raw table name from the query

    // Resolved schema information (filled by SchemaResolver)
    resolved_schema: Option<String>,    // Resolved schema name
    resolved_table: Option<String>,     // Resolved fully-qualified table name

    cardinality: Cardinality,           // One or Many
    is_aggregate: bool,                 // Whether this is an aggregate query
    selection: Selection,               // Fields to select
    arguments: Arguments,               // Query arguments
}
```

### Cardinality

Indicates whether a query returns a single object or multiple objects.

```rust
enum Cardinality {
    One,    // Returns a single object (or null)
    Many    // Returns an array of objects
}
```

### Selection

A collection of fields to be selected from an entity.

```rust
struct Selection {
    fields: Vec<Field>,                // Regular fields to select
    relationships: Vec<Relationship>    // Related entities to include
}
```

### Field

A regular field to be selected from an entity.

```rust
struct Field {
    name: String,                       // Original field name from the GraphQL query
    alias: Option<String>,              // Alias if provided in the query

    // For aggregate fields
    is_aggregate: bool,                 // Whether this is an aggregate field
    aggregate_function: Option<AggregateFunction>,  // Function if this is an aggregate
    aggregate_field: Option<String>,    // Field to aggregate if not COUNT(*)

    // Resolved information (filled by SchemaResolver)
    resolved_column: Option<String>,    // Resolved column name
}
```

### AggregateFunction

Types of aggregate functions supported.

```rust
enum AggregateFunction {
    Count,
    CountDistinct,
    Sum,
    Avg,
    Min,
    Max
}
```

### Relationship

A relationship to another entity.

```rust
struct Relationship {
    name: String,                      // Original relationship name from the GraphQL query
    alias: Option<String>,             // Alias if provided in the query

    // Original parsing information
    target_table: String,              // Raw related table name

    // Resolved schema information (filled by SchemaResolver)
    relationship_info: Option<RelationshipInfo>,  // Resolved relationship details

    cardinality: Cardinality,          // One or Many
    is_aggregate: bool,                // Whether this is an aggregate relationship
    selection: Selection,              // Fields to select from the related entity
    arguments: Arguments,              // Query arguments for the related entity
}
```

### RelationshipInfo

Information about a relationship between two tables.

```rust
struct RelationshipInfo {
    source_schema: String,             // Schema of the source table
    source_table: String,              // Source table name
    source_columns: Vec<String>,       // Column(s) in the source table

    target_schema: String,             // Schema of the target table
    target_table: String,              // Target table name
    target_columns: Vec<String>,       // Column(s) in the target table

    relationship_type: RelationshipType, // Type of relationship

    // For many-to-many relationships
    join_table: Option<JoinTableInfo>,  // Information about the join table, if any

    join_type: JoinType,               // Type of join to use
}
```

### RelationshipType

Type of relationship between tables.

```rust
enum RelationshipType {
    OneToOne,    // One source record relates to one target record
    OneToMany,   // One source record relates to many target records
    ManyToOne,   // Many source records relate to one target record
    ManyToMany   // Many source records relate to many target records through a join table
}
```

### JoinTableInfo

Information about a join table for many-to-many relationships.

```rust
struct JoinTableInfo {
    schema: String,                    // Schema of the join table
    table: String,                     // Join table name
    source_columns: Vec<String>,       // Column(s) linking to the source table
    target_columns: Vec<String>,       // Column(s) linking to the target table
}
```

### JoinType

Type of join to use for a relationship.

```rust
enum JoinType {
    Inner,
    LeftOuter
}
```

### Arguments

Query arguments like filters, sorting, and pagination.

```rust
struct Arguments {
    filter: Option<Filter>,            // Where conditions
    order_by: Vec<OrderBy>,            // Sorting criteria
    limit: Option<String>,             // Limit variable name (e.g., "$limit" or "$v0")
    offset: Option<String>,            // Offset variable name (e.g., "$offset" or "$v1")
    distinct_on: Option<Vec<String>>,  // Fields to distinct on
    include_join_table: Option<bool>,  // Whether to include join table data in results (for many-to-many)
}
```

### Filter

Represents a filter condition.

```rust
enum Filter {
    Comparison(ComparisonFilter),      // Simple comparison like =, >, < etc.
    And(Vec<Filter>),                  // AND of multiple conditions
    Or(Vec<Filter>),                   // OR of multiple conditions
    Not(Box<Filter>),                  // Negation of a condition
    Exists(Box<Relationship>, Box<Filter>)  // EXISTS condition on a relationship
}
```

### ComparisonFilter

A simple comparison filter.

```rust
struct ComparisonFilter {
    field: String,                     // Field to compare
    operator: ComparisonOperator,      // Operator to use
    value: Value,                      // Variable reference for the comparison value

    // Resolved information (filled by SchemaResolver)
    resolved_column: Option<String>,   // Resolved column name
}
```

### ComparisonOperator

Types of comparison operators.

```rust
enum ComparisonOperator {
    Eq,         // =
    NotEq,      // !=
    Lt,         // <
    Lte,        // <=
    Gt,         // >
    Gte,        // >=
    In,         // IN
    NotIn,      // NOT IN
    Like,       // LIKE
    ILike,      // ILIKE (case insensitive)
    Regex,      // ~ (regex match)
    IRegex,     // ~* (case insensitive regex)
    IsNull,     // IS NULL
    IsNotNull,  // IS NOT NULL
    Contains,   // @> (JSONB contains)
    ContainedIn, // <@ (JSONB contained in)
    HasKey,     // ? (JSONB has key)
    HasKeyAny,  // ?| (JSONB has any key)
    HasKeyAll,  // ?& (JSONB has all keys)
}
```

### OrderBy

Sorting criteria.

```rust
struct OrderBy {
    field: String,                     // Field to sort by
    direction: SortDirection,          // Direction (ASC/DESC)
    nulls: NullsOrder,                 // How to order nulls

    // Resolved information (filled by SchemaResolver)
    resolved_column: Option<String>,   // Resolved column name
}
```

### SortDirection

Direction for sorting.

```rust
enum SortDirection {
    Asc,
    Desc
}
```

### NullsOrder

How to order nulls in sorting.

```rust
enum NullsOrder {
    First,
    Last
}
```

### Value

A value in a filter condition or argument. All values are represented as variable references.

```rust
enum Value {
    Variable(String),                  // A variable reference (e.g., "$user", "$v0")
    List(Vec<Value>),                  // A list of values (which themselves are variables)
    Object(HashMap<String, Value>)     // An object (map of key-value pairs)
}
```

### VariableValue

Stores information about a variable, including its type and actual value.

```rust
struct VariableValue {
    type_name: String,                // GraphQL type name
    is_nullable: bool,                // Whether the variable can be null
    value: Option<ScalarValue>,       // Actual value (None for user-provided variables with no default)
    is_auto_generated: bool,          // Whether this was auto-generated from an inline literal
}
```

### ScalarValue

A scalar value stored in the variables map.

```rust
enum ScalarValue {
    String(String),
    Int(i64),
    Float(f64),
    Boolean(bool),
    Null
}
```

## Processing Workflow

The QST is processed through three main phases in the GraSQL library:

### Phase 1: Query Scanning

In this phase:

1. The GraphQL query string is parsed into an AST using the graphql-query crate
2. Essential query information is extracted to identify what needs resolution:
   - Operation type (query/mutation)
   - Fields and their arguments
   - Nested field structures
   - Variables
3. The parsed query is stored in an internal cache with a unique query ID
4. A resolution request containing all information needed for schema resolution is created
5. The query ID and resolution request are returned to Elixir

At the end of this phase, we have identified everything that needs resolution without building a complete QST yet.

### Phase 2: Schema Resolution

In this phase:

1. The resolution request from Phase 1 is processed by user-implemented resolvers
2. The resolver provides database-specific information:
   - Table names are resolved to fully qualified schema.table names
   - Relationships between tables are resolved with join information
   - Permissions and access control are applied
3. The resolved information is collected and returned to the NIF

At the end of this phase, we have all the database-specific information needed to build a complete QST and generate SQL.

### Phase 3: QST Building and SQL Generation

In this phase:

1. The query ID, resolved information, and variables are passed to the SQL Compiler
2. The compiler retrieves the cached parsed query using the query ID
3. A complete QST is built by combining the parsed query with the resolved information
4. SQL is generated based on the QST:
   - Root fields are translated into SELECT queries
   - Relationships are translated into LATERAL JOINs
   - Filters are applied at the appropriate levels
   - Aggregations are handled with aggregate functions
   - JSON construction functions are used to shape the output
5. The parsed query is removed from the cache to free memory
6. The final SQL query string and the variables map are returned

This workflow avoids parsing the GraphQL query twice, significantly improving performance for complex queries. The cached parsed query is only used internally and does not affect the structure of the final QST or generated SQL.

## Examples

### Simple Query

GraphQL:

```graphql
query {
  users {
    id
    name
    email
  }
}
```

QST (simplified):

```rust
QueryStructureTree {
    operation_type: OperationType::Query,
    root_fields: [
        RootField {
            name: "users",
            alias: None,
            target_table: "users",
            cardinality: Cardinality::Many,
            is_aggregate: false,
            selection: Selection {
                fields: [
                    Field { name: "id", ... },
                    Field { name: "name", ... },
                    Field { name: "email", ... }
                ],
                relationships: []
            },
            arguments: Arguments { ... }
        }
    ],
    variables: {}
}
```

### Nested Query with Relationships

GraphQL:

```graphql
query {
  users {
    id
    name
    posts {
      id
      title
      comments {
        id
        text
      }
    }
  }
}
```

QST (simplified):

```rust
QueryStructureTree {
    operation_type: OperationType::Query,
    root_fields: [
        RootField {
            name: "users",
            alias: None,
            target_table: "users",
            cardinality: Cardinality::Many,
            is_aggregate: false,
            selection: Selection {
                fields: [
                    Field { name: "id", ... },
                    Field { name: "name", ... }
                ],
                relationships: [
                    Relationship {
                        name: "posts",
                        target_table: "posts",
                        cardinality: Cardinality::Many,
                        selection: Selection {
                            fields: [
                                Field { name: "id", ... },
                                Field { name: "title", ... }
                            ],
                            relationships: [
                                Relationship {
                                    name: "comments",
                                    target_table: "comments",
                                    cardinality: Cardinality::Many,
                                    selection: Selection {
                                        fields: [
                                            Field { name: "id", ... },
                                            Field { name: "text", ... }
                                        ],
                                        relationships: []
                                    },
                                    arguments: Arguments { ... }
                                }
                            ]
                        },
                        arguments: Arguments { ... }
                    }
                ]
            },
            arguments: Arguments { ... }
        }
    ],
    variables: {}
}
```

### Query with Filters

GraphQL:

```graphql
query {
  users(
    where: {
      name: { _eq: "John" }
      _or: [
        { email: { _like: "%example.com" } }
        { roles: { role: { name: { _eq: "admin" } } } }
      ]
    }
  ) {
    id
    name
    email
  }
}
```

QST (simplified):

```rust
QueryStructureTree {
    operation_type: OperationType::Query,
    root_fields: [
        RootField {
            name: "users",
            alias: None,
            target_table: "users",
            cardinality: Cardinality::Many,
            is_aggregate: false,
            selection: Selection {
                fields: [
                    Field { name: "id", ... },
                    Field { name: "name", ... },
                    Field { name: "email", ... }
                ],
                relationships: []
            },
            arguments: Arguments {
                filter: Some(Filter::And([
                    Filter::Comparison(ComparisonFilter {
                        field: "name",
                        operator: ComparisonOperator::Eq,
                        value: Value::Variable("$v0")
                    }),
                    Filter::Or([
                        Filter::Comparison(ComparisonFilter {
                            field: "email",
                            operator: ComparisonOperator::Like,
                            value: Value::Variable("$v1")
                        }),
                        Filter::Exists(
                            Box::new(Relationship {
                                name: "roles",
                                target_table: "user_roles",
                                ...
                            }),
                            Box::new(Filter::Exists(
                                Box::new(Relationship {
                                    name: "role",
                                    target_table: "roles",
                                    ...
                                }),
                                Box::new(Filter::Comparison(ComparisonFilter {
                                    field: "name",
                                    operator: ComparisonOperator::Eq,
                                    value: Value::Variable("$v2")
                                }))
                            ))
                        )
                    ])
                ])),
                order_by: [],
                limit: None,
                offset: None
            }
        }
    ],
    variables: {
        "$v0": VariableValue {
            name: "$v0",
            type_name: "String",
            is_nullable: false,
            value: Some(ScalarValue::String("John")),
            is_auto_generated: true
        },
        "$v1": VariableValue {
            name: "$v1",
            type_name: "String",
            is_nullable: false,
            value: Some(ScalarValue::String("%example.com")),
            is_auto_generated: true
        },
        "$v2": VariableValue {
            name: "$v2",
            type_name: "String",
            is_nullable: false,
            value: Some(ScalarValue::String("admin")),
            is_auto_generated: true
        }
    }
}
```

### Aggregation Query

GraphQL:

```graphql
query {
  users_aggregate {
    aggregate {
      count
      avg {
        age
      }
    }
    nodes {
      id
      name
    }
  }
}
```

QST (simplified):

```rust
QueryStructureTree {
    operation_type: OperationType::Query,
    root_fields: [
        RootField {
            name: "users_aggregate",
            alias: None,
            target_table: "users",
            cardinality: Cardinality::Many,
            is_aggregate: true,
            selection: Selection {
                fields: [],
                relationships: [
                    Relationship {
                        name: "aggregate",
                        selection: Selection {
                            fields: [
                                Field {
                                    name: "count",
                                    is_aggregate: true,
                                    aggregate_function: Some(AggregateFunction::Count),
                                    aggregate_field: None
                                },
                                Field {
                                    name: "avg",
                                    selection: Selection {
                                        fields: [
                                            Field {
                                                name: "age",
                                                is_aggregate: true,
                                                aggregate_function: Some(AggregateFunction::Avg),
                                                aggregate_field: Some("age")
                                            }
                                        ],
                                        relationships: []
                                    }
                                }
                            ],
                            relationships: []
                        }
                    },
                    Relationship {
                        name: "nodes",
                        selection: Selection {
                            fields: [
                                Field { name: "id", ... },
                                Field { name: "name", ... }
                            ],
                            relationships: []
                        }
                    }
                ]
            },
            arguments: Arguments { ... }
        }
    ],
    variables: {}
}
```

### Query with User-Provided Variables

GraphQL:

```graphql
query GetUsers($name: String!, $limit: Int, $offset: Int) {
  users(where: { name: { _eq: $name } }, limit: $limit, offset: $offset) {
    id
    name
  }
}
```

QST (simplified):

```rust
QueryStructureTree {
    operation_type: OperationType::Query,
    root_fields: [
        RootField {
            name: "users",
            alias: None,
            target_table: "users",
            cardinality: Cardinality::Many,
            is_aggregate: false,
            selection: Selection {
                fields: [
                    Field { name: "id", ... },
                    Field { name: "name", ... }
                ],
                relationships: []
            },
            arguments: Arguments {
                filter: Some(Filter::Comparison(ComparisonFilter {
                    field: "name",
                    operator: ComparisonOperator::Eq,
                    value: Value::Variable("$name")
                })),
                order_by: [],
                limit: Some("$limit"),
                offset: Some("$offset")
            }
        }
    ],
    variables: {
        "$name": VariableValue {
            name: "$name",
            type_name: "String",
            is_nullable: false,
            value: None,  // User-provided, no default value
            is_auto_generated: false
        },
        "$limit": VariableValue {
            name: "$limit",
            type_name: "Int",
            is_nullable: true,
            value: None,  // User-provided, no default value
            is_auto_generated: false
        },
        "$offset": VariableValue {
            name: "$offset",
            type_name: "Int",
            is_nullable: true,
            value: None,  // User-provided, no default value
            is_auto_generated: false
        }
    }
}
```

## Advantages of the Parameterized QST Structure

The parameterized QST structure offers several key advantages:

1. **Security**: Using parameters instead of embedding literal values directly in the SQL helps prevent SQL injection attacks.

2. **Performance**: Parameterized queries can be better optimized by the database as prepared statements, allowing the query plan to be cached and reused.

3. **Simplified permission handling**: Permission checking logic can reside solely in the SQL generation phase, avoiding duplication of logic between Elixir and Rust components.

4. **Consistency**: By converting all literal values to parameters during the parsing phase, we maintain a consistent approach for both user-provided variables and inline literals.

5. **Type safety**: Variable types are explicitly tracked, making it easier to ensure correct type handling in the generated SQL.

6. **Support for deep nesting**: The recursive structure naturally supports arbitrarily deep nesting of relationships, making it easy to represent complex GraphQL queries.

7. **Natural filter handling**: The ExistsFilter approach for relationship-based filters eliminates the need for complex filter push-down logic, avoiding bugs that plagued previous implementations.

8. **Clear separation of concerns**: The QST separates the original parsed information from the resolved schema information, making it clear what information is available at each stage.

9. **Direct mapping to SQL**: The QST structure naturally maps to SQL generation using CTEs, LATERAL joins, and JSON functions, resulting in efficient SQL that directly produces the desired JSON structure.

These advantages make the parameterized QST an ideal intermediate representation for translating GraphQL queries into efficient, secure, and performant SQL.

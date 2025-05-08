use crate::interning::intern_str;
use crate::types::{FieldPath, SymbolId};
use graphql_query::ast::{Document, Field, ObjectValue, OperationDefinition, Value};
use graphql_query::visit::{VisitFlow, VisitInfo, VisitNode, Visitor};
use std::collections::{HashMap, HashSet};

/// Visitor for extracting field paths from GraphQL AST
pub struct FieldPathExtractor {
    /// Set of unique field paths (for deduplication)
    field_paths: HashSet<FieldPath>,

    /// Current path being built during traversal
    current_path: FieldPath,

    /// Map of table paths to column sets
    /// This tracks column usage per table
    column_usage: HashMap<FieldPath, HashSet<SymbolId>>,
}

impl FieldPathExtractor {
    /// Creates a new field extractor
    #[inline(always)]
    pub fn new() -> Self {
        FieldPathExtractor {
            field_paths: HashSet::new(),
            current_path: FieldPath::new(),
            column_usage: HashMap::new(),
        }
    }

    /// Extract field paths from a GraphQL document
    #[inline(always)]
    pub fn extract(
        &mut self,
        document: &Document,
    ) -> Result<(HashSet<FieldPath>, HashMap<FieldPath, HashSet<SymbolId>>), String> {
        // Process all operations in the document
        let mut has_operation = false;

        for definition in &document.definitions {
            if let graphql_query::ast::Definition::Operation(operation) = definition {
                has_operation = true;

                // Create empty context for visit
                let mut ctx = ();

                // Visit the selection set to extract table/relationship paths
                operation.selection_set.visit(&mut ctx, self);

                // Extract tables/relationships from filters
                self.extract_filter_paths(operation)?;

                // Extract columns from selection sets
                self.extract_columns_from_selection_sets(operation)?;
            }
        }

        // Ensure we found at least one operation
        if !has_operation {
            return Err("No operation found in document".to_string());
        }

        Ok((
            std::mem::take(&mut self.field_paths),
            std::mem::take(&mut self.column_usage),
        ))
    }

    /// Extract tables/relationships from filter expressions
    #[inline(always)]
    fn extract_filter_paths(&mut self, operation: &OperationDefinition) -> Result<(), String> {
        for selection in &operation.selection_set.selections {
            if let Some(field) = selection.field() {
                // Start with empty path for root fields
                self.current_path.clear();

                // Process field arguments recursively
                self.process_field_arguments(field)?;
            }
        }

        Ok(())
    }

    /// Extract columns from selection sets
    #[inline(always)]
    fn extract_columns_from_selection_sets(
        &mut self,
        operation: &OperationDefinition,
    ) -> Result<(), String> {
        for selection in &operation.selection_set.selections {
            if let Some(field) = selection.field() {
                // Start with empty path for root fields
                self.current_path.clear();

                // Process field and its columns recursively
                self.process_field_and_columns(field)?;
            }
        }

        Ok(())
    }

    /// Process a field and its columns recursively
    #[inline(always)]
    fn process_field_and_columns(&mut self, field: &Field) -> Result<(), String> {
        // Add current field to path
        let field_id = intern_str(field.name);
        self.current_path.push(field_id);

        // Only process fields with selection sets (tables/relationships)
        if !field.selection_set.is_empty() {
            // Store this path as a table/relationship
            self.field_paths.insert(self.current_path.clone());

            // Process child fields (columns or nested relationships)
            for selection in &field.selection_set.selections {
                if let Some(child_field) = selection.field() {
                    if child_field.selection_set.is_empty() {
                        // This is a column
                        let column_id = intern_str(child_field.name);

                        // Get or create the column set for this table
                        let columns = self
                            .column_usage
                            .entry(self.current_path.clone())
                            .or_insert_with(HashSet::new);

                        // Add this column to the set
                        columns.insert(column_id);
                    } else {
                        // Handle common GraphQL patterns like aggregations, returning clauses, etc.
                        match child_field.name {
                            "aggregate" | "returning" | "nodes" => {
                                // These are special fields that contain columns for the parent table
                                // Process them in the context of the current table
                                for selection in &child_field.selection_set.selections {
                                    if let Some(grandchild_field) = selection.field() {
                                        if grandchild_field.selection_set.is_empty() {
                                            // This is a column for aggregation
                                            let column_id = intern_str(grandchild_field.name);

                                            // Get or create the column set for this table
                                            let columns = self
                                                .column_usage
                                                .entry(self.current_path.clone())
                                                .or_insert_with(HashSet::new);

                                            // Add this column to the set
                                            columns.insert(column_id);
                                        }
                                    }
                                }

                                // Also process the special field as a relationship
                                self.process_field_and_columns(child_field)?;
                            }
                            _ => {
                                // This is a nested relationship, process recursively
                                self.process_field_and_columns(child_field)?;
                            }
                        }
                    }
                }
            }
        }

        // Remove field from path before returning
        self.current_path.pop();

        Ok(())
    }

    /// Process arguments of a field to extract filter paths
    #[inline(always)]
    fn process_field_arguments(&mut self, field: &Field) -> Result<(), String> {
        // Add current field to path
        let field_id = intern_str(field.name);
        self.current_path.push(field_id);

        // Only add to our set if this is a table/relationship (has selection set)
        if !field.selection_set.is_empty() {
            self.field_paths.insert(self.current_path.clone());
        }

        // Get config to check for mutation prefixes
        let config = match crate::config::CONFIG.lock() {
            Ok(cfg_guard) => match &*cfg_guard {
                Some(cfg) => cfg.clone(),
                None => return Err("GraSQL not initialized; missing config".to_string()),
            },
            Err(_) => return Err("Failed to acquire config lock".to_string()),
        };

        // Process arguments depending on operation type
        for arg in &field.arguments.children {
            if arg.name == "where" {
                // Extract paths from "where" condition (for queries and mutations)
                self.extract_filter_paths_from_value(&arg.value)?;
            } else if field.name.starts_with(&config.insert_prefix)
                && (arg.name == "objects" || arg.name == "object")
            {
                // Extract column information from INSERT mutation objects
                self.extract_mutation_objects(&arg.value, arg.name == "object")?;
            } else if field.name.starts_with(&config.update_prefix) && arg.name == "_set" {
                // Extract column information from UPDATE mutation _set parameter
                self.extract_update_set(&arg.value)?;
            }
        }

        // Process nested fields recursively
        for selection in &field.selection_set.selections {
            if let Some(nested_field) = selection.field() {
                self.process_field_arguments(nested_field)?;
            }
        }

        // Remove field from path before returning
        self.current_path.pop();

        Ok(())
    }

    /// Extract mutation object fields for INSERT operations
    ///
    /// This method processes the "objects" or "object" parameter in INSERT mutations and
    /// extracts column names from all objects. It handles both single objects and arrays of objects,
    /// as well as variable references.
    ///
    /// # Arguments
    ///
    /// * `value` - The Value of the objects parameter, either an Object, List of Objects, or Variable
    /// * `is_single_object` - Whether this is an "object" parameter (true) or "objects" parameter (false)
    ///
    /// # Returns
    ///
    /// * `Ok(())` if processing was successful
    /// * `Err(String)` with an error message if an error occurred
    ///
    /// # Example
    ///
    /// For a mutation like:
    /// ```graphql
    /// mutation {
    ///   insert_users(objects: { name: "John", email: "john@example.com" }) {
    ///     returning { id }
    ///   }
    /// }
    /// ```
    ///
    /// This method will extract "name" and "email" as columns for the "users" table.
    fn extract_mutation_objects(
        &mut self,
        value: &Value,
        is_single_object: bool,
    ) -> Result<(), String> {
        match value {
            Value::Object(obj) => {
                // Extract columns from this object
                self.extract_object_columns(obj)?;
                // Make sure this path is marked as a table/relationship
                self.field_paths.insert(self.current_path.clone());
                Ok(())
            }
            Value::List(list) => {
                if is_single_object {
                    return Err("Expected a single object but got an array".to_string());
                }

                // Process each item in the list (batch case)
                for item in &list.children {
                    self.extract_mutation_objects(item, true)?;
                }
                // Make sure this path is marked as a table/relationship
                self.field_paths.insert(self.current_path.clone());
                Ok(())
            }
            Value::Variable(_var_name) => {
                // For variables, we trust the user knows what they're doing
                // We don't attempt to extract column information from variables

                // Even though we can't extract columns from the variable,
                // we still need to add the current path to field_paths
                // so that the table/relationship is recognized
                self.field_paths.insert(self.current_path.clone());
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Extract columns from an object value
    ///
    /// Extracts each field name in the object as a column and adds it to
    /// the column_usage map for the current table path.
    ///
    /// # Arguments
    ///
    /// * `obj` - The ObjectValue to extract columns from
    ///
    /// # Returns
    ///
    /// * `Ok(())` if processing was successful
    /// * `Err(String)` with an error message if an error occurred
    fn extract_object_columns(&mut self, obj: &ObjectValue) -> Result<(), String> {
        for field in &obj.children {
            let column_id = intern_str(field.name);

            // Get or create the column set for the current table
            let columns = self
                .column_usage
                .entry(self.current_path.clone())
                .or_insert_with(HashSet::new);

            // Add this column to the set
            columns.insert(column_id);

            // TODO: Recursive handling of nested objects if needed
            // This would require understanding the schema structure
        }
        Ok(())
    }

    /// Extract columns from _set parameter in UPDATE mutations
    ///
    /// This method processes the "_set" parameter in UPDATE mutations and
    /// extracts each field name as a column that needs to be updated.
    ///
    /// # Arguments
    ///
    /// * `value` - The Value of the _set parameter, typically an Object or Variable
    ///
    /// # Returns
    ///
    /// * `Ok(())` if processing was successful
    /// * `Err(String)` with an error message if an error occurred
    ///
    /// # Example
    ///
    /// For a mutation like:
    /// ```graphql
    /// mutation {
    ///   update_users(
    ///     where: { id: { _eq: 1 } },
    ///     _set: { name: "Updated Name", status: "active" }
    ///   ) {
    ///     returning { id }
    ///   }
    /// }
    /// ```
    ///
    /// This method will extract "name" and "status" as columns for the "users" table.
    fn extract_update_set(&mut self, value: &Value) -> Result<(), String> {
        match value {
            Value::Object(obj) => {
                // Extract columns from the _set object
                for field in &obj.children {
                    let column_id = intern_str(field.name);

                    // Get or create the column set for the current table
                    let columns = self
                        .column_usage
                        .entry(self.current_path.clone())
                        .or_insert_with(HashSet::new);

                    // Add this column to the set
                    columns.insert(column_id);
                }
                // Make sure this path is marked as a table/relationship
                self.field_paths.insert(self.current_path.clone());
                Ok(())
            }
            Value::Variable(_var_name) => {
                // For variables, we trust the user knows what they're doing
                // We don't attempt to extract column information from variables

                // Even though we can't extract columns from the variable,
                // we still need to add the current path to field_paths
                // so that the table/relationship is recognized
                self.field_paths.insert(self.current_path.clone());
                Ok(())
            }
            _ => {
                // _set should always be an object
                Err("_set parameter must be an object".to_string())
            }
        }
    }

    /// Extract filter paths from a value (recursively for objects)
    #[inline(always)]
    fn extract_filter_paths_from_value(&mut self, value: &Value) -> Result<(), String> {
        match value {
            Value::Object(obj) => {
                for field in &obj.children {
                    if field.name.starts_with('_') {
                        // Special handling for _and and _or operators
                        if field.name == "_and" || field.name == "_or" {
                            // These operators typically contain arrays of conditions
                            if let Value::List(list) = &field.value {
                                // Process each item in the list
                                for item in &list.children {
                                    self.extract_filter_paths_from_value(item)?;
                                }
                            }
                        }
                        // Skip other operator fields that start with underscore
                        continue;
                    }

                    // Add field to path
                    let field_id = intern_str(field.name);
                    self.current_path.push(field_id);

                    // Process based on value type
                    match &field.value {
                        Value::Object(inner_obj) => {
                            // This is a nested object which could be either:
                            // 1. A relationship: posts: { title: { _eq: ... } }
                            // 2. An operator: name: { _eq: ... }

                            // Check if this field itself is directly an operator (starts with '_')
                            let is_direct_operator = field.name.starts_with('_');

                            // Check if this object contains operator fields
                            let contains_operator_fields = inner_obj
                                .children
                                .iter()
                                .any(|child| child.name.starts_with('_'));

                            // If this is not a direct operator field, it could be a relationship
                            // Add it to field_paths regardless of whether it contains operator fields
                            if !is_direct_operator {
                                self.field_paths.insert(self.current_path.clone());
                            }

                            // If it contains operator fields, also handle it as a column
                            if contains_operator_fields && self.current_path.len() > 1 {
                                // Get the table path (all but last element)
                                let mut table_path = FieldPath::new();
                                for i in 0..self.current_path.len() - 1 {
                                    table_path.push(self.current_path[i]);
                                }

                                // Add this column to the table's columns
                                let columns = self
                                    .column_usage
                                    .entry(table_path)
                                    .or_insert_with(HashSet::new);

                                columns.insert(field_id);
                            }

                            // Process nested objects recursively
                            self.extract_filter_paths_from_value(&field.value)?;
                        }
                        _ => {
                            // Simple value - add as column to the parent path (without current field)
                            if self.current_path.len() > 1 {
                                let mut table_path = FieldPath::new();
                                for i in 0..self.current_path.len() - 1 {
                                    table_path.push(self.current_path[i]);
                                }

                                let columns = self
                                    .column_usage
                                    .entry(table_path)
                                    .or_insert_with(HashSet::new);

                                columns.insert(field_id);
                            }
                        }
                    }

                    // Remove field from path
                    self.current_path.pop();
                }
            }
            Value::List(list) => {
                // Process each item in the list
                for item in &list.children {
                    self.extract_filter_paths_from_value(item)?;
                }
            }
            _ => {} // Ignore other value types
        }

        Ok(())
    }
}

impl<'a> Visitor<'a> for FieldPathExtractor {
    #[inline(always)]
    fn enter_field(&mut self, _ctx: &mut (), field: &'a Field<'a>, _info: &VisitInfo) -> VisitFlow {
        // Add field to current path
        let field_id = intern_str(field.name);
        self.current_path.push(field_id);

        // Only add this path to our set if it has a selection set
        // (indicating it's a table/relationship, not a column)
        if !field.selection_set.is_empty() {
            self.field_paths.insert(self.current_path.clone());
        }

        VisitFlow::Next
    }

    #[inline(always)]
    fn leave_field(
        &mut self,
        _ctx: &mut (),
        _field: &'a Field<'a>,
        _info: &VisitInfo,
    ) -> VisitFlow {
        // Remove from path before returning
        self.current_path.pop();

        VisitFlow::Next
    }
}

/// Builds an index for O(1) path lookups in Phase 3
#[inline(always)]
pub fn build_path_index(field_paths: &HashSet<FieldPath>) -> HashMap<FieldPath, usize> {
    let mut index = HashMap::with_capacity(field_paths.len());

    for (i, path) in field_paths.iter().enumerate() {
        index.insert(path.clone(), i);
    }

    index
}

/// Convert a set of FieldPaths with SymbolIds to indices for Elixir
#[inline(always)]
pub fn convert_paths_to_indices(
    field_paths: &HashSet<FieldPath>,
    symbol_to_index: &HashMap<SymbolId, u32>,
) -> HashSet<Vec<u32>> {
    field_paths
        .iter()
        .map(|path| {
            path.iter()
                .map(|&symbol_id| {
                    *symbol_to_index
                        .get(&symbol_id)
                        .expect("symbol id missing in index; corrupted ResolutionRequest")
                })
                .collect()
        })
        .collect()
}

/// Convert column usage from FieldPath/SymbolId format to table indices with column strings
///
/// This function takes:
/// - column_usage: Map of table paths to column symbol IDs
/// - field_paths: Set of all field paths
/// - path_to_index: Map from field paths to their indices
/// - all_strings: Map from symbol IDs to their string representations
///
/// Returns a map from table indices to sets of column names
#[inline(always)]
pub fn convert_column_usage_to_indices(
    column_usage: &HashMap<FieldPath, HashSet<SymbolId>>,
    field_paths: &HashSet<FieldPath>,
    symbol_to_index: &HashMap<SymbolId, u32>,
) -> HashMap<u32, HashSet<String>> {
    let mut result = HashMap::new();

    // Create a map from FieldPath to index
    let mut path_to_index = HashMap::with_capacity(field_paths.len());
    for path in field_paths {
        let index_vec = path
            .iter()
            .map(|symbol_id| *symbol_to_index.get(symbol_id).unwrap())
            .collect::<Vec<u32>>();

        // Use the first element of index_vec as the table index
        if !index_vec.is_empty() {
            path_to_index.insert(path.clone(), index_vec[0]);
        }
    }

    // Convert column usage to table indices with column strings
    for (path, columns) in column_usage {
        // Only process paths that represent tables
        if let Some(&table_idx) = path_to_index.get(path) {
            // Convert column SymbolIds to strings
            let column_strings = columns
                .iter()
                .filter_map(|symbol_id| {
                    // Using intern_str creates a circular dependency,
                    // so we rely on the caller to provide string mapping
                    crate::interning::resolve_str(*symbol_id)
                })
                .collect::<HashSet<_>>();

            // Only add if there are columns to resolve
            if !column_strings.is_empty() {
                result.insert(table_idx, column_strings);
            }
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::interning::intern_str;
    use graphql_query::ast::{ASTContext, Document, ParseNode};

    fn initialize_for_test() {
        let _ = crate::types::initialize_for_test();
    }

    #[test]
    fn test_field_extraction_simple() {
        // Initialize GraSQL config
        initialize_for_test();

        let query = "{ users { id name email } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let (field_paths, _column_usage) = extractor.extract(&document).unwrap();

        // Should only have "users" path since it's the only table
        assert_eq!(field_paths.len(), 1);

        // Check that we have the correct path for "users"
        let users_id = intern_str("users");
        let mut users_path = FieldPath::new();
        users_path.push(users_id);
        assert!(field_paths.contains(&users_path));
    }

    #[test]
    fn test_field_extraction_with_relationships() {
        // Initialize GraSQL config
        initialize_for_test();

        let query = "{ users { id profile { avatar } posts { title } } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let (field_paths, _column_usage) = extractor.extract(&document).unwrap();

        // Should have "users", "users.profile", and "users.posts" paths
        assert_eq!(field_paths.len(), 3);

        // Check for expected paths
        let users_id = intern_str("users");
        let profile_id = intern_str("profile");
        let posts_id = intern_str("posts");

        let mut users_path = FieldPath::new();
        users_path.push(users_id);
        assert!(field_paths.contains(&users_path));

        let mut users_profile_path = FieldPath::new();
        users_profile_path.push(users_id);
        users_profile_path.push(profile_id);
        assert!(field_paths.contains(&users_profile_path));

        let mut users_posts_path = FieldPath::new();
        users_posts_path.push(users_id);
        users_posts_path.push(posts_id);
        assert!(field_paths.contains(&users_posts_path));
    }

    #[test]
    fn test_field_extraction_with_filters() {
        // Initialize GraSQL config
        initialize_for_test();

        let query = "{ users(where: { profile: { avatar: \"something\" } }) { id } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let (field_paths, _column_usage) = extractor.extract(&document).unwrap();

        // Should have "users" and "users.profile" paths
        assert_eq!(field_paths.len(), 2);

        // Check for expected paths
        let users_id = intern_str("users");
        let profile_id = intern_str("profile");

        let mut users_path = FieldPath::new();
        users_path.push(users_id);
        assert!(field_paths.contains(&users_path));

        let mut users_profile_path = FieldPath::new();
        users_profile_path.push(users_id);
        users_profile_path.push(profile_id);
        assert!(field_paths.contains(&users_profile_path));
    }
}

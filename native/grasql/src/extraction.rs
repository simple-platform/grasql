use crate::interning::intern_str;
use crate::types::{FieldPath, SymbolId};
use graphql_query::ast::{Document, Field, OperationDefinition, Value};
use graphql_query::visit::{VisitFlow, VisitInfo, VisitNode, Visitor};
use std::collections::{HashMap, HashSet};

/// Visitor for extracting field paths from GraphQL AST
pub struct FieldPathExtractor {
    /// Set of unique field paths (for deduplication)
    field_paths: HashSet<FieldPath>,

    /// Current path being built during traversal
    current_path: FieldPath,
}

impl FieldPathExtractor {
    /// Creates a new field extractor
    #[inline(always)]
    pub fn new() -> Self {
        FieldPathExtractor {
            field_paths: HashSet::new(),
            current_path: FieldPath::new(),
        }
    }

    /// Extract field paths from a GraphQL document
    #[inline(always)]
    pub fn extract(&mut self, document: &Document) -> Result<HashSet<FieldPath>, String> {
        // Find the operation
        let operation = document
            .operation(None)
            .map_err(|e| format!("Error finding operation: {}", e))?;

        // Create empty context for visit
        let mut ctx = ();

        // Visit the selection set to extract table/relationship paths
        operation.selection_set.visit(&mut ctx, self);

        // Extract tables/relationships from filters
        self.extract_filter_paths(operation)?;

        Ok(std::mem::take(&mut self.field_paths))
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

        // Process "where" argument if it exists
        for arg in &field.arguments.children {
            if arg.name == "where" {
                self.extract_filter_paths_from_value(&arg.value)?;
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

                    // Add to our set if this is a nested object (potential relationship)
                    // This is a heuristic - we assume that nested objects in filters
                    // represent relationships
                    if let Value::Object(_) = field.value {
                        self.field_paths.insert(self.current_path.clone());
                    }

                    // Recursively process nested objects
                    self.extract_filter_paths_from_value(&field.value)?;

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::interning::intern_str;
    use graphql_query::ast::{ASTContext, Document, ParseNode};

    #[test]
    fn test_field_extraction_simple() {
        let query = "{ users { id name email } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let field_paths = extractor.extract(&document).unwrap();

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
        let query = "{ users { id profile { avatar } posts { title } } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let field_paths = extractor.extract(&document).unwrap();

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
        let query = "{ users(where: { profile: { avatar: \"something\" } }) { id } }";
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).unwrap();

        let mut extractor = FieldPathExtractor::new();
        let field_paths = extractor.extract(&document).unwrap();

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

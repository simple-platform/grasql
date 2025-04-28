//! AST converter for converting graphql-query AST to GraSQL types
//!
//! This module handles the conversion between the graphql-query library's AST
//! and GraSQL's internal representation.

use crate::types::{
    Directive, Field, FragmentDefinition, FragmentSpread, InlineFragment, OperationType,
    QueryStructureTree, Selection, SourcePosition, TypeCondition,
};
use graphql_query::ast::{
    Definition as GraphQLDefinition, Document, FragmentDefinition as GraphQLFragmentDefinition,
    OperationKind, PrintNode, Selection as GraphQLSelection, Value as GraphQLValue,
};
use std::collections::HashMap;

use super::error::{Error, Result};

/// Converter for transforming graphql-query AST to GraSQL types
pub struct ASTConverter {}

impl ASTConverter {
    /// Creates a new AST converter
    pub fn new() -> Self {
        ASTConverter {}
    }

    /// Converts a graphql-query Document to a GraSQL QueryStructureTree
    ///
    /// # Arguments
    ///
    /// * `document` - The graphql-query Document to convert
    ///
    /// # Returns
    ///
    /// * `Result<QueryStructureTree>` - The converted QueryStructureTree or an error
    pub fn convert_document(&mut self, document: &Document) -> Result<QueryStructureTree> {
        // Get the operation (query/mutation) from the document
        let operation = document
            .operation(None)
            .map_err(|e| Error::ParsingError(format!("Failed to get operation: {}", e)))?;

        // Convert operation type
        let operation_type = match operation.operation {
            OperationKind::Query => OperationType::Query,
            OperationKind::Mutation => OperationType::Mutation,
            OperationKind::Subscription => {
                return Err(Error::UnsupportedOperation(
                    "Subscription operations are not supported".to_string(),
                ));
            }
        };

        // Process fragment definitions first
        let fragment_definitions = self.convert_fragment_definitions(document)?;

        // Convert root fields
        let mut root_fields = Vec::new();

        // If the selection set has selections, process them
        // Otherwise, it's an empty query which is valid
        if !operation.selection_set.selections.is_empty() {
            for selection in operation.selection_set.selections.iter() {
                match selection {
                    // Handle regular field
                    GraphQLSelection::Field(field) => {
                        root_fields.push(self.convert_field(
                            field,
                            document,
                            &fragment_definitions,
                        )?);
                    }
                    // Handle fragment spread
                    GraphQLSelection::FragmentSpread(fragment_spread) => {
                        // Find the fragment definition
                        let fragment_name = fragment_spread.name.name;
                        let fragment_def =
                            fragment_definitions.get(fragment_name).ok_or_else(|| {
                                Error::ParsingError(format!(
                                    "Fragment '{}' not found in document",
                                    fragment_name
                                ))
                            })?;

                        // Add the fields from the fragment
                        self.merge_fragment_fields(
                            &mut root_fields,
                            fragment_def,
                            document,
                            &fragment_definitions,
                        )?;
                    }
                    // Handle inline fragment
                    GraphQLSelection::InlineFragment(inline_fragment) => {
                        // Convert the inline fragment fields
                        let selection = self.convert_selection_set(
                            &inline_fragment.selection_set,
                            document,
                            &fragment_definitions,
                        )?;

                        // Add fields from the inline fragment to the root fields
                        for field in selection.fields {
                            root_fields.push(field);
                        }
                    }
                }
            }
        }

        // Convert variables
        let variables = self.convert_variables(&operation.variable_definitions)?;

        // Create and return the QueryStructureTree
        Ok(QueryStructureTree {
            operation_type,
            root_fields,
            variables,
            fragment_definitions,
        })
    }

    /// Converts fragment definitions in a document to GraSQL's representation
    ///
    /// # Arguments
    ///
    /// * `document` - The graphql-query Document containing fragment definitions
    ///
    /// # Returns
    ///
    /// * `Result<HashMap<String, FragmentDefinition>>` - Map of fragment names to their definitions
    fn convert_fragment_definitions(
        &mut self,
        document: &Document,
    ) -> Result<HashMap<String, FragmentDefinition>> {
        let mut fragments = HashMap::new();

        for definition in document.definitions.iter() {
            if let GraphQLDefinition::Fragment(fragment) = definition {
                let fragment_def = self.convert_fragment_definition(fragment, document)?;
                fragments.insert(fragment.name.name.to_string(), fragment_def);
            }
        }

        Ok(fragments)
    }

    /// Converts a GraphQL fragment definition to GraSQL's representation
    ///
    /// # Arguments
    ///
    /// * `fragment` - The GraphQL fragment definition to convert
    /// * `document` - The parent document
    ///
    /// # Returns
    ///
    /// * `Result<FragmentDefinition>` - The converted fragment definition
    fn convert_fragment_definition(
        &mut self,
        fragment: &GraphQLFragmentDefinition,
        document: &Document,
    ) -> Result<FragmentDefinition> {
        // Empty fragment definitions map for initial conversion
        // Full map will be used for fragment spreads within this fragment
        let empty_fragments = HashMap::new();

        // Convert the selection set
        let selection =
            self.convert_selection_set(&fragment.selection_set, document, &empty_fragments)?;

        // Convert directives
        let directives = self.convert_directives(&fragment.directives)?;

        // Create type condition
        let type_condition = TypeCondition {
            type_name: fragment.type_condition.name.to_string(),
        };

        // Create and return the FragmentDefinition
        Ok(FragmentDefinition {
            name: fragment.name.name.to_string(),
            type_condition,
            directives,
            selection: Box::new(selection),
        })
    }

    /// Merges fields from a fragment into a field list
    ///
    /// # Arguments
    ///
    /// * `fields` - The list of fields to merge into
    /// * `fragment` - The fragment definition to merge from
    /// * `document` - The parent document
    /// * `fragments` - Map of all fragment definitions
    ///
    /// # Returns
    ///
    /// * `Result<()>` - Success or error
    fn merge_fragment_fields(
        &mut self,
        fields: &mut Vec<Field>,
        fragment: &FragmentDefinition,
        document: &Document,
        fragments: &HashMap<String, FragmentDefinition>,
    ) -> Result<()> {
        // Add all fields from the fragment to the field list
        for field in &fragment.selection.fields {
            fields.push(field.clone());
        }

        // Process any nested fragment spreads within this fragment
        for fragment_spread in &fragment.selection.fragment_spreads {
            let nested_fragment = fragments.get(&fragment_spread.name).ok_or_else(|| {
                Error::ParsingError(format!(
                    "Nested fragment '{}' not found in document",
                    fragment_spread.name
                ))
            })?;

            self.merge_fragment_fields(fields, nested_fragment, document, fragments)?;
        }

        // Process any inline fragments within this fragment
        for inline_fragment in &fragment.selection.inline_fragments {
            for field in &inline_fragment.selection.fields {
                fields.push(field.clone());
            }
        }

        Ok(())
    }

    /// Converts a graphql-query Field to a GraSQL Field
    ///
    /// # Arguments
    ///
    /// * `field` - The graphql-query Field to convert
    /// * `document` - The parent document (for fragment resolution)
    /// * `fragments` - Map of all fragment definitions
    ///
    /// # Returns
    ///
    /// * `Result<Field>` - The converted Field or an error
    fn convert_field(
        &mut self,
        field: &graphql_query::ast::Field,
        document: &Document,
        fragments: &HashMap<String, FragmentDefinition>,
    ) -> Result<Field> {
        // Create source position
        let source_position = SourcePosition {
            line: 0,   // graphql-query doesn't expose source position in a stable way
            column: 0, // We'll use 0,0 as a default
        };

        // Convert arguments
        let mut arguments = HashMap::new();
        for arg in field.arguments.children.iter() {
            // Convert the value to a string representation for now
            // A more robust implementation would convert to proper typed values
            let value_str = arg.value.print();
            arguments.insert(arg.name.to_string(), value_str);
        }

        // Convert selection set
        let selection = self.convert_selection_set(&field.selection_set, document, fragments)?;

        // Convert directives
        let directives = self.convert_directives(&field.directives)?;

        // Create and return the Field
        Ok(Field {
            name: field.name.to_string(),
            alias: field.alias.map(|a| a.to_string()),
            arguments,
            selection: Box::new(selection),
            source_position,
            directives,
        })
    }

    /// Converts GraphQL directives to GraSQL directives
    ///
    /// # Arguments
    ///
    /// * `directives` - The GraphQL directives to convert
    ///
    /// # Returns
    ///
    /// * `Result<Vec<Directive>>` - The converted directives
    fn convert_directives(
        &self,
        directives: &graphql_query::ast::Directives,
    ) -> Result<Vec<Directive>> {
        let mut result = Vec::new();

        for directive in directives.children.iter() {
            let mut arguments = HashMap::new();
            for arg in directive.arguments.children.iter() {
                let value_str = arg.value.print();
                arguments.insert(arg.name.to_string(), value_str);
            }

            result.push(Directive {
                name: directive.name.to_string(),
                arguments,
            });
        }

        Ok(result)
    }

    /// Converts a graphql-query SelectionSet to a GraSQL Selection
    ///
    /// # Arguments
    ///
    /// * `selection_set` - The graphql-query SelectionSet to convert
    /// * `document` - The parent document (for fragment resolution)
    /// * `fragments` - Map of all fragment definitions
    ///
    /// # Returns
    ///
    /// * `Result<Selection>` - The converted Selection or an error
    fn convert_selection_set(
        &mut self,
        selection_set: &graphql_query::ast::SelectionSet,
        document: &Document,
        fragments: &HashMap<String, FragmentDefinition>,
    ) -> Result<Selection> {
        let mut fields = Vec::new();
        let mut fragment_spreads = Vec::new();
        let mut inline_fragments = Vec::new();

        // Process each selection in the set
        for selection in selection_set.selections.iter() {
            match selection {
                // Handle regular field
                GraphQLSelection::Field(field) => {
                    fields.push(self.convert_field(field, document, fragments)?);
                }
                // Handle fragment spread
                GraphQLSelection::FragmentSpread(fragment_spread) => {
                    // Convert the fragment spread
                    let directives = self.convert_directives(&fragment_spread.directives)?;
                    let spread = FragmentSpread {
                        name: fragment_spread.name.name.to_string(),
                        directives,
                    };
                    fragment_spreads.push(spread);

                    // Also merge the fragment fields for easier processing
                    if let Some(fragment_def) = fragments.get(fragment_spread.name.name) {
                        self.merge_fragment_fields(&mut fields, fragment_def, document, fragments)?;
                    } else {
                        return Err(Error::ParsingError(format!(
                            "Fragment '{}' not found in document",
                            fragment_spread.name.name
                        )));
                    }
                }
                // Handle inline fragment
                GraphQLSelection::InlineFragment(inline_fragment) => {
                    // Convert the selection set
                    let selection = self.convert_selection_set(
                        &inline_fragment.selection_set,
                        document,
                        fragments,
                    )?;

                    // Convert the directives
                    let directives = self.convert_directives(&inline_fragment.directives)?;

                    // Create type condition if present
                    let type_condition = inline_fragment.type_condition.map(|tc| TypeCondition {
                        type_name: tc.name.to_string(),
                    });

                    // Create the inline fragment
                    let fragment = InlineFragment {
                        type_condition,
                        directives,
                        selection: Box::new(selection.clone()),
                    };
                    inline_fragments.push(fragment);

                    // Also merge the inline fragment fields for easier processing
                    for field in selection.fields {
                        fields.push(field);
                    }
                }
            }
        }

        Ok(Selection {
            fields,
            fragment_spreads,
            inline_fragments,
        })
    }

    /// Converts graphql-query VariableDefinitions to GraSQL variables
    ///
    /// # Arguments
    ///
    /// * `var_defs` - The graphql-query VariableDefinitions to convert
    ///
    /// # Returns
    ///
    /// * `Result<Vec<HashMap<String, String>>>` - The converted variables or an error
    fn convert_variables(
        &self,
        var_defs: &graphql_query::ast::VariableDefinitions,
    ) -> Result<Vec<HashMap<String, String>>> {
        let mut variables = Vec::new();

        for var_def in var_defs.children.iter() {
            let mut var_map = HashMap::new();
            var_map.insert("name".to_string(), var_def.variable.name.to_string());
            var_map.insert("type".to_string(), var_def.of_type.print());

            // Add default value if present (as a string representation)
            if let GraphQLValue::Null = var_def.default_value {
                // No default value
            } else {
                var_map.insert("default_value".to_string(), var_def.default_value.print());
            }

            variables.push(var_map);
        }

        Ok(variables)
    }
}

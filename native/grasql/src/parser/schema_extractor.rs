//! Schema extractor for determining database tables and relationships
//!
//! This module extracts schema needs from a GraphQL query, determining which
//! database tables and relationships are required to fulfill the query.

use crate::types::{
    EntityReference, Field, FragmentDefinition, QueryStructureTree, RelationshipReference,
    SchemaNeeds,
};
use std::collections::{HashMap, HashSet};

use super::error::Result;

/// Schema needs extractor
///
/// Extracts the schema requirements from a GraphQL query by analyzing
/// its structure and dependencies.
pub struct SchemaExtractor {
    // Configuration could be added here
}

impl SchemaExtractor {
    /// Creates a new schema extractor with default configuration
    pub fn new() -> Self {
        SchemaExtractor {}
    }

    /// Extracts schema needs from a GraphQL query
    ///
    /// This function analyzes a GraphQL Query Structure Tree to determine
    /// what entities and relationships are required. It returns references
    /// to GraphQL fields and their relationships without making assumptions
    /// about database structure.
    ///
    /// # Arguments
    ///
    /// * `qst` - The Query Structure Tree to analyze
    ///
    /// # Returns
    ///
    /// * `Result<SchemaNeeds>` - The extracted schema requirements
    pub fn extract_schema_needs(&self, qst: &QueryStructureTree) -> Result<SchemaNeeds> {
        let mut entity_references = Vec::new();
        let mut relationship_references = Vec::new();

        // Process root fields
        for field in &qst.root_fields {
            // Root fields become entity references
            let entity = EntityReference {
                graphql_name: field.name.clone(),
                alias: field.alias.clone(),
            };
            entity_references.push(entity);

            // Extract nested entities and relationships
            self.extract_nested_needs(
                field,
                &field.name,
                field.alias.as_deref(),
                &mut entity_references,
                &mut relationship_references,
                &qst.fragment_definitions,
            )?;
        }

        // Print entities and relationships in debug mode
        #[cfg(debug_assertions)]
        {
            eprintln!("Extracted entity references:");
            for entity in &entity_references {
                eprintln!(" - {} (alias: {:?})", entity.graphql_name, entity.alias);
            }
            eprintln!("Extracted relationship references:");
            for rel in &relationship_references {
                eprintln!(
                    " - {} -> {} (aliases: {:?} -> {:?})",
                    rel.parent_name, rel.child_name, rel.parent_alias, rel.child_alias
                );
            }
        }

        // Return the schema needs
        Ok(SchemaNeeds {
            entity_references,
            relationship_references,
        })
    }

    /// Extracts nested entities and relationships from a field
    ///
    /// # Arguments
    ///
    /// * `field` - The field to extract nested needs from
    /// * `parent_name` - The parent field name
    /// * `parent_alias` - The parent field alias (if any)
    /// * `entity_references` - The set of entity references to add to
    /// * `relationship_references` - The set of relationship references to add to
    /// * `fragment_definitions` - Map of all fragment definitions
    ///
    /// # Returns
    ///
    /// * `Result<()>` - Success or an error
    fn extract_nested_needs(
        &self,
        field: &Field,
        parent_name: &str,
        parent_alias: Option<&str>,
        entity_references: &mut Vec<EntityReference>,
        relationship_references: &mut Vec<RelationshipReference>,
        fragment_definitions: &HashMap<String, FragmentDefinition>,
    ) -> Result<()> {
        // Process nested fields
        for nested_field in &field.selection.fields {
            // Skip if not an object (simple scalar field)
            if !self.is_object_field(nested_field) {
                continue;
            }

            // Create entity reference for the nested field
            let entity = EntityReference {
                graphql_name: nested_field.name.clone(),
                alias: nested_field.alias.clone(),
            };

            // Debug output
            #[cfg(debug_assertions)]
            eprintln!(
                "Processing nested field {} under {}",
                entity.graphql_name, parent_name
            );

            // Add the entity to our references
            entity_references.push(entity);

            // Create and add relationship reference
            let relationship = RelationshipReference {
                parent_name: parent_name.to_string(),
                child_name: nested_field.name.clone(),
                parent_alias: parent_alias.map(String::from),
                child_alias: nested_field.alias.clone(),
            };
            relationship_references.push(relationship);

            // Recursively process this field's nested fields
            self.extract_nested_needs(
                nested_field,
                &nested_field.name,
                nested_field.alias.as_deref(),
                entity_references,
                relationship_references,
                fragment_definitions,
            )?;
        }

        // Process fragment spreads in the selection
        for fragment_spread in &field.selection.fragment_spreads {
            if let Some(fragment_def) = fragment_definitions.get(&fragment_spread.name) {
                let mut visited = HashSet::new();
                self.extract_fragment_needs(
                    fragment_def,
                    parent_name,
                    parent_alias,
                    entity_references,
                    relationship_references,
                    fragment_definitions,
                    &mut visited,
                )?;
            }
        }

        // Process inline fragments in the selection
        for inline_fragment in &field.selection.inline_fragments {
            for nested_field in &inline_fragment.selection.fields {
                if !self.is_object_field(nested_field) {
                    continue;
                }

                // Create entity reference for the nested field
                let entity = EntityReference {
                    graphql_name: nested_field.name.clone(),
                    alias: nested_field.alias.clone(),
                };
                entity_references.push(entity);

                // Create relationship reference
                let relationship = RelationshipReference {
                    parent_name: parent_name.to_string(),
                    child_name: nested_field.name.clone(),
                    parent_alias: parent_alias.map(String::from),
                    child_alias: nested_field.alias.clone(),
                };
                relationship_references.push(relationship);

                // Process nested fields recursively
                self.extract_nested_needs(
                    nested_field,
                    &nested_field.name,
                    nested_field.alias.as_deref(),
                    entity_references,
                    relationship_references,
                    fragment_definitions,
                )?;
            }

            // Process fragment spreads in the inline fragment
            for fragment_spread in &inline_fragment.selection.fragment_spreads {
                if let Some(fragment_def) = fragment_definitions.get(&fragment_spread.name) {
                    let mut visited = HashSet::new();
                    self.extract_fragment_needs(
                        fragment_def,
                        parent_name,
                        parent_alias,
                        entity_references,
                        relationship_references,
                        fragment_definitions,
                        &mut visited,
                    )?;
                }
            }
        }

        Ok(())
    }

    /// Extracts entities and relationships from a fragment definition
    ///
    /// # Arguments
    ///
    /// * `fragment` - The fragment definition to extract from
    /// * `parent_name` - The parent field name
    /// * `parent_alias` - The parent field alias (if any)
    /// * `entity_references` - The set of entity references to add to
    /// * `relationship_references` - The set of relationship references to add to
    /// * `fragment_definitions` - Map of all fragment definitions for recursive processing
    /// * `visited` - Set of fragment names that have already been processed to prevent cycles
    ///
    /// # Returns
    ///
    /// * `Result<()>` - Success or an error
    fn extract_fragment_needs(
        &self,
        fragment: &FragmentDefinition,
        parent_name: &str,
        parent_alias: Option<&str>,
        entity_references: &mut Vec<EntityReference>,
        relationship_references: &mut Vec<RelationshipReference>,
        fragment_definitions: &HashMap<String, FragmentDefinition>,
        visited: &mut HashSet<String>,
    ) -> Result<()> {
        if !visited.insert(fragment.name.clone()) {
            return Ok(()); // already processed, break the cycle
        }

        // Process fields in the fragment
        for field in &fragment.selection.fields {
            if !self.is_object_field(field) {
                continue;
            }

            // Create entity reference for the field
            let entity = EntityReference {
                graphql_name: field.name.clone(),
                alias: field.alias.clone(),
            };
            entity_references.push(entity);

            // Create relationship reference
            let relationship = RelationshipReference {
                parent_name: parent_name.to_string(),
                child_name: field.name.clone(),
                parent_alias: parent_alias.map(String::from),
                child_alias: field.alias.clone(),
            };
            relationship_references.push(relationship);

            // Process nested fields recursively
            self.extract_nested_needs(
                field,
                &field.name,
                field.alias.as_deref(),
                entity_references,
                relationship_references,
                fragment_definitions,
            )?;
        }

        // Process fragment spreads in this fragment
        for fragment_spread in &fragment.selection.fragment_spreads {
            if let Some(nested_fragment) = fragment_definitions.get(&fragment_spread.name) {
                self.extract_fragment_needs(
                    nested_fragment,
                    parent_name,
                    parent_alias,
                    entity_references,
                    relationship_references,
                    fragment_definitions,
                    visited,
                )?;
            }
        }

        // Process inline fragments in this fragment
        for inline_fragment in &fragment.selection.inline_fragments {
            for field in &inline_fragment.selection.fields {
                if !self.is_object_field(field) {
                    continue;
                }

                // Create entity reference for the field
                let entity = EntityReference {
                    graphql_name: field.name.clone(),
                    alias: field.alias.clone(),
                };
                entity_references.push(entity);

                // Create relationship reference
                let relationship = RelationshipReference {
                    parent_name: parent_name.to_string(),
                    child_name: field.name.clone(),
                    parent_alias: parent_alias.map(String::from),
                    child_alias: field.alias.clone(),
                };
                relationship_references.push(relationship);

                // Process nested fields recursively
                self.extract_nested_needs(
                    field,
                    &field.name,
                    field.alias.as_deref(),
                    entity_references,
                    relationship_references,
                    fragment_definitions,
                )?;
            }
        }

        Ok(())
    }

    /// Helper method to check if a field is an object (has nested selections)
    fn is_object_field(&self, field: &Field) -> bool {
        !field.selection.fields.is_empty()
            || !field.selection.fragment_spreads.is_empty()
            || !field.selection.inline_fragments.is_empty()
    }
}

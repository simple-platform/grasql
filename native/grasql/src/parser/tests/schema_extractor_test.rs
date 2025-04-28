#[cfg(test)]
mod schema_extractor_tests {
    use crate::parser::schema_extractor::SchemaExtractor;
    use crate::types::{Field, OperationType, QueryStructureTree, Selection, SourcePosition};
    use std::collections::{HashMap, HashSet};

    // Helper to create a field
    fn create_field(name: &str, alias: Option<&str>, nested_fields: Vec<Field>) -> Field {
        let selection = Selection {
            fields: nested_fields,
            fragment_spreads: Vec::new(),
            inline_fragments: Vec::new(),
        };

        Field {
            name: name.to_string(),
            alias: alias.map(|s| s.to_string()),
            arguments: HashMap::new(),
            selection: Box::new(selection),
            source_position: SourcePosition { line: 0, column: 0 },
            directives: Vec::new(),
        }
    }

    #[test]
    fn test_extract_single_table() {
        // Initialize schema extractor
        let extractor = SchemaExtractor::new();

        // Create a simple QST with a single root field (users)
        let user_field = create_field("user", None, vec![]);

        let qst = QueryStructureTree {
            operation_type: OperationType::Query,
            root_fields: vec![user_field],
            variables: Vec::new(),
            fragment_definitions: HashMap::new(),
        };

        // Extract schema needs
        let schema_needs = extractor.extract_schema_needs(&qst).unwrap();

        // Verify entity references
        assert_eq!(schema_needs.entity_references.len(), 1);
        assert_eq!(schema_needs.entity_references[0].graphql_name, "user");
        assert_eq!(schema_needs.entity_references[0].alias, None);

        // Verify no relationships (single table)
        assert_eq!(schema_needs.relationship_references.len(), 0);
    }

    #[test]
    fn test_extract_nested_tables_and_relationships() {
        // Initialize schema extractor
        let extractor = SchemaExtractor::new();

        // Create a QST with user -> posts -> comments
        // Add scalar fields to make them proper objects
        let comment_field = create_field(
            "comment",
            None,
            vec![
                create_field("id", None, vec![]),
                create_field("text", None, vec![]),
            ],
        );

        let post_field = create_field(
            "post",
            None,
            vec![
                create_field("id", None, vec![]),
                create_field("title", None, vec![]),
                comment_field,
            ],
        );

        let user_field = create_field(
            "user",
            None,
            vec![
                create_field("id", None, vec![]),
                create_field("name", None, vec![]),
                post_field,
            ],
        );

        let qst = QueryStructureTree {
            operation_type: OperationType::Query,
            root_fields: vec![user_field],
            variables: Vec::new(),
            fragment_definitions: HashMap::new(),
        };

        // Extract schema needs
        let schema_needs = extractor.extract_schema_needs(&qst).unwrap();

        // Print actual entities for debugging
        #[cfg(debug_assertions)]
        {
            println!("Entities found:");
            for entity in &schema_needs.entity_references {
                println!(" - {} (alias: {:?})", entity.graphql_name, entity.alias);
            }
            println!("Relationships found:");
            for rel in &schema_needs.relationship_references {
                println!(
                    " - {} -> {} (aliases: {:?} -> {:?})",
                    rel.parent_name, rel.child_name, rel.parent_alias, rel.child_alias
                );
            }
        }

        // We should have at least these entities
        let expected_entities = HashSet::from([
            "user".to_string(),
            "post".to_string(),
            "comment".to_string(),
        ]);

        // Check that all expected entities are present
        let actual_entities: HashSet<String> = schema_needs
            .entity_references
            .iter()
            .map(|e| e.graphql_name.clone())
            .collect();

        for entity in &expected_entities {
            assert!(
                actual_entities.contains(entity),
                "Expected entity '{}' not found. Found entities: {:?}",
                entity,
                actual_entities
            );
        }

        // Check that we have at least 2 relationships (user->post, post->comment)
        assert!(
            schema_needs.relationship_references.len() >= 2,
            "Expected at least 2 relationships, found {}",
            schema_needs.relationship_references.len()
        );

        // Check relationship references
        let relationship_pairs: HashSet<(String, String)> = schema_needs
            .relationship_references
            .iter()
            .map(|r| (r.parent_name.clone(), r.child_name.clone()))
            .collect();

        assert!(
            relationship_pairs.contains(&("user".to_string(), "post".to_string())),
            "Missing user->post relationship"
        );
        assert!(
            relationship_pairs.contains(&("post".to_string(), "comment".to_string())),
            "Missing post->comment relationship"
        );
    }

    #[test]
    fn test_extract_multiple_root_tables() {
        // Initialize schema extractor
        let extractor = SchemaExtractor::new();

        // Create a QST with multiple root fields (users, posts)
        let user_field = create_field("user", None, vec![]);
        let post_field = create_field("post", None, vec![]);

        let qst = QueryStructureTree {
            operation_type: OperationType::Query,
            root_fields: vec![user_field, post_field],
            variables: Vec::new(),
            fragment_definitions: HashMap::new(),
        };

        // Extract schema needs
        let schema_needs = extractor.extract_schema_needs(&qst).unwrap();

        // Verify entity references (user, post)
        assert_eq!(schema_needs.entity_references.len(), 2);

        // Convert to HashSet for easier verification
        let entity_names: HashSet<String> = schema_needs
            .entity_references
            .iter()
            .map(|e| e.graphql_name.clone())
            .collect();

        assert!(entity_names.contains("user"));
        assert!(entity_names.contains("post"));

        // Verify no relationships (independent root entities)
        assert_eq!(schema_needs.relationship_references.len(), 0);
    }

    #[test]
    fn test_extract_deeply_nested_tables() {
        // Initialize schema extractor
        let extractor = SchemaExtractor::new();

        // Create a deeply nested structure
        // user -> profile -> address -> geo
        // Add scalar fields to make them proper objects
        let geo_field = create_field(
            "geo",
            None,
            vec![
                create_field("latitude", None, vec![]),
                create_field("longitude", None, vec![]),
            ],
        );

        let address_field = create_field(
            "address",
            None,
            vec![
                create_field("street", None, vec![]),
                create_field("city", None, vec![]),
                geo_field,
            ],
        );

        let profile_field = create_field(
            "profile",
            None,
            vec![
                create_field("bio", None, vec![]),
                create_field("avatar", None, vec![]),
                address_field,
            ],
        );

        let user_field = create_field(
            "user",
            None,
            vec![
                create_field("id", None, vec![]),
                create_field("name", None, vec![]),
                profile_field,
            ],
        );

        let qst = QueryStructureTree {
            operation_type: OperationType::Query,
            root_fields: vec![user_field],
            variables: Vec::new(),
            fragment_definitions: HashMap::new(),
        };

        // Extract schema needs
        let schema_needs = extractor.extract_schema_needs(&qst).unwrap();

        // We should have these entities
        let expected_entities = HashSet::from([
            "user".to_string(),
            "profile".to_string(),
            "address".to_string(),
            "geo".to_string(),
        ]);

        // Check entity names
        let entity_names: HashSet<String> = schema_needs
            .entity_references
            .iter()
            .map(|e| e.graphql_name.clone())
            .collect();

        for entity in &expected_entities {
            assert!(
                entity_names.contains(entity),
                "Expected entity '{}' not found",
                entity
            );
        }

        // Check relationship count (should be at least 3)
        assert!(
            schema_needs.relationship_references.len() >= 3,
            "Expected at least 3 relationships, found {}",
            schema_needs.relationship_references.len()
        );

        // Check specific relationships
        let relationship_pairs: HashSet<(String, String)> = schema_needs
            .relationship_references
            .iter()
            .map(|r| (r.parent_name.clone(), r.child_name.clone()))
            .collect();

        assert!(
            relationship_pairs.contains(&("user".to_string(), "profile".to_string())),
            "Missing user->profile relationship"
        );
        assert!(
            relationship_pairs.contains(&("profile".to_string(), "address".to_string())),
            "Missing profile->address relationship"
        );
        assert!(
            relationship_pairs.contains(&("address".to_string(), "geo".to_string())),
            "Missing address->geo relationship"
        );
    }

    #[test]
    fn test_table_aliases() {
        // Initialize schema extractor
        let extractor = SchemaExtractor::new();

        // Create a QST with aliases
        let user_field = create_field("user", Some("u"), vec![]);

        let qst = QueryStructureTree {
            operation_type: OperationType::Query,
            root_fields: vec![user_field],
            variables: Vec::new(),
            fragment_definitions: HashMap::new(),
        };

        // Extract schema needs
        let schema_needs = extractor.extract_schema_needs(&qst).unwrap();

        // Verify entity references with aliases
        assert_eq!(schema_needs.entity_references.len(), 1);
        assert_eq!(schema_needs.entity_references[0].graphql_name, "user");
        assert_eq!(
            schema_needs.entity_references[0].alias,
            Some("u".to_string())
        );
    }
}

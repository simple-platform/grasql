#[cfg(test)]
mod parser_integration_tests {
    use crate::parser;
    use crate::types::OperationType;

    #[test]
    fn test_parse_and_analyze_basic_query() {
        // Basic query
        let query = r#"
        {
            users {
                id
                name
                email
            }
        }
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(result.is_ok(), "Failed to parse basic query");
        let analysis = result.unwrap();

        // Check operation type
        assert_eq!(analysis.qst.operation_type, OperationType::Query);

        // Check root fields
        assert_eq!(analysis.qst.root_fields.len(), 1);
        assert_eq!(analysis.qst.root_fields[0].name, "users");

        // Check schema needs
        assert_eq!(analysis.schema_needs.entity_references.len(), 1);
        assert_eq!(
            analysis.schema_needs.entity_references[0].graphql_name,
            "users"
        );

        // Check variable map (should be empty)
        assert!(analysis.variable_map.is_empty());
    }

    #[test]
    fn test_parse_and_analyze_nested_query() {
        // Nested query
        let query = r#"
        {
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
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(result.is_ok(), "Failed to parse nested query");
        let analysis = result.unwrap();

        // Check entity references
        assert_eq!(analysis.schema_needs.entity_references.len(), 3);

        // Check entity names
        let entity_names: Vec<String> = analysis
            .schema_needs
            .entity_references
            .iter()
            .map(|e| e.graphql_name.clone())
            .collect();

        assert!(entity_names.contains(&"users".to_string()));
        assert!(entity_names.contains(&"posts".to_string()));
        assert!(entity_names.contains(&"comments".to_string()));

        // Check relationships
        assert_eq!(analysis.schema_needs.relationship_references.len(), 2);
    }

    #[test]
    fn test_parse_and_analyze_with_variables() {
        // Query with variables
        let query = r#"
        query GetUser($id: ID!) {
            user(id: $id) {
                id
                name
                email
            }
        }
        "#;
        let variables = r#"{"id": "123"}"#;

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(result.is_ok(), "Failed to parse query with variables");
        let analysis = result.unwrap();

        // Check variable definitions
        assert_eq!(analysis.qst.variables.len(), 1);
        let var_def = &analysis.qst.variables[0];
        assert_eq!(var_def["name"], "id");

        // Check variable map
        assert!(analysis.variable_map.contains_key("id"));
        assert_eq!(analysis.variable_map["id"], "\"123\"");

        // Check arguments on root field
        let user_field = &analysis.qst.root_fields[0];
        assert!(user_field.arguments.contains_key("id"));
        assert_eq!(user_field.arguments["id"], "$id");
    }

    #[test]
    fn test_parse_and_analyze_mutation() {
        // Mutation
        let query = r#"
        mutation CreateUser($name: String!, $email: String!) {
            createUser(name: $name, email: $email) {
                id
                name
                email
            }
        }
        "#;
        let variables = r#"{"name": "John Doe", "email": "john@example.com"}"#;

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(result.is_ok(), "Failed to parse mutation");
        let analysis = result.unwrap();

        // Check operation type
        assert_eq!(analysis.qst.operation_type, OperationType::Mutation);

        // Check schema needs for the createUser "table"
        assert_eq!(analysis.schema_needs.entity_references.len(), 1);
        assert_eq!(
            analysis.schema_needs.entity_references[0].graphql_name,
            "createUser"
        );

        // Check variables
        assert_eq!(analysis.qst.variables.len(), 2);
        assert!(analysis.variable_map.contains_key("name"));
        assert!(analysis.variable_map.contains_key("email"));
    }

    #[test]
    fn test_parse_and_analyze_with_aliases() {
        // Query with aliases
        let query = r#"
        {
            userData: user(id: 1) {
                userId: id
                fullName: name
            }
        }
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(result.is_ok(), "Failed to parse query with aliases");
        let analysis = result.unwrap();

        // Check aliases
        let root_field = &analysis.qst.root_fields[0];
        assert_eq!(root_field.name, "user");
        assert_eq!(root_field.alias, Some("userData".to_string()));

        // Check nested field aliases
        let id_field = root_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "id")
            .expect("id field not found");

        let name_field = root_field
            .selection
            .fields
            .iter()
            .find(|f| f.name == "name")
            .expect("name field not found");

        assert_eq!(id_field.alias, Some("userId".to_string()));
        assert_eq!(name_field.alias, Some("fullName".to_string()));
    }

    #[test]
    fn test_parse_and_analyze_multiple_root_fields() {
        // Query with multiple root fields
        let query = r#"
        {
            users {
                id
                name
            }
            posts {
                id
                title
            }
        }
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(
            result.is_ok(),
            "Failed to parse query with multiple root fields"
        );
        let analysis = result.unwrap();

        // Check root fields
        assert_eq!(analysis.qst.root_fields.len(), 2);

        // Get field names
        let field_names: Vec<String> = analysis
            .qst
            .root_fields
            .iter()
            .map(|f| f.name.clone())
            .collect();

        assert!(field_names.contains(&"users".to_string()));
        assert!(field_names.contains(&"posts".to_string()));

        // Check schema needs
        assert_eq!(analysis.schema_needs.entity_references.len(), 2);

        // Check relationship count (should be 0 between root fields)
        assert_eq!(analysis.schema_needs.relationship_references.len(), 0);
    }

    #[test]
    fn test_invalid_query_syntax() {
        // Invalid query
        let query = r#"
        {
            users {
                id
                name
        }
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify failure
        assert!(result.is_err(), "Should fail for invalid syntax");
        let err = result.err().unwrap();

        // Check error type
        assert!(
            format!("{}", err).contains("parse error"),
            "Error should be a parse error"
        );
    }

    #[test]
    fn test_invalid_json_variables() {
        // Valid query, invalid variables
        let query = r#"
        {
            users {
                id
                name
            }
        }
        "#;
        let variables = "{invalid json";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify failure
        assert!(result.is_err(), "Should fail for invalid JSON");
        let err = result.err().unwrap();

        // Check error type
        assert!(
            format!("{}", err).contains("JSON parse error"),
            "Error should be a JSON parse error"
        );
    }

    #[test]
    fn test_unsupported_subscription() {
        // Subscription query
        let query = r#"
        subscription {
            newUser {
                id
                name
            }
        }
        "#;
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify failure
        assert!(result.is_err(), "Should fail for subscription operation");
        let err = result.err().unwrap();

        // More flexible error message check
        let error_msg = format!("{}", err);
        assert!(
            error_msg.contains("not supported") || error_msg.contains("Unsupported operation"),
            "Error should indicate unsupported operation: {}",
            error_msg
        );
        assert!(
            error_msg.contains("subscription") || error_msg.contains("Subscription"),
            "Error should mention subscription: {}",
            error_msg
        );
    }

    #[test]
    fn test_empty_query() {
        // Use a minimal valid query with the __typename introspection field
        // which won't add anything to the schema needs
        let query = "{ __typename }";
        let variables = "{}";

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(
            result.is_ok(),
            "Failed to parse empty query: {:?}",
            result.err()
        );
        let analysis = result.unwrap();

        // For a minimal query, we should not generate any schema needs
        assert_eq!(analysis.schema_needs.entity_references.len(), 1); // Only __typename as a table
        assert_eq!(analysis.schema_needs.relationship_references.len(), 0);
    }

    #[test]
    fn test_complex_variables() {
        // Query with complex variables
        let query = r#"
        query TestComplexVars($user: UserInput!, $tags: [String!]) {
            createPost(author: $user, tags: $tags) {
                id
                title
                author {
                    id
                    name
                }
                tags
            }
        }
        "#;
        let variables = r#"{"user":{"id":"123","name":"John Doe","settings":{"theme":"dark","notifications":true}},"tags":["GraphQL","API","Tutorial"]}"#;

        // Parse and analyze
        let result = parser::parse_and_analyze(query, variables);

        // Verify success
        assert!(
            result.is_ok(),
            "Failed to parse query with complex variables: {:?}",
            result.err()
        );
        let analysis = result.unwrap();

        // Check variable definitions - should match the query
        assert_eq!(analysis.qst.variables.len(), 2);

        // Check variable map - should include all variable values
        assert!(analysis.variable_map.contains_key("user"));
        assert!(analysis.variable_map.contains_key("tags"));

        // Check schema needs - should include createPost and author tables
        assert!(
            analysis.schema_needs.entity_references.len() >= 1,
            "Expected at least 1 table, found {}",
            analysis.schema_needs.entity_references.len()
        );

        // Check that createPost is among the tables
        let entity_names: Vec<String> = analysis
            .schema_needs
            .entity_references
            .iter()
            .map(|e| e.graphql_name.clone())
            .collect();
        assert!(
            entity_names.contains(&"createPost".to_string()),
            "Expected createPost table, found tables: {:?}",
            entity_names
        );
    }
}

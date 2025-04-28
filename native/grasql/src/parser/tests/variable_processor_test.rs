#[cfg(test)]
mod variable_processor_tests {
    use crate::parser::variable_processor::VariableProcessor;
    use graphql_query::ast::{ASTContext, Document, ParseNode};
    use serde_json::json;

    #[test]
    fn test_process_simple_variables() {
        // Set up test GraphQL query with variables
        let query = r#"
        query GetUser($id: ID!) {
            user(id: $id) {
                id
                name
            }
        }
        "#;

        // Variables JSON
        let variables_json = json!({
            "id": "123"
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check variable value
        assert!(var_map.contains_key("id"), "Variable 'id' not found");
        assert_eq!(var_map["id"], "\"123\"");
    }

    #[test]
    fn test_process_multiple_variables() {
        // Set up test GraphQL query with multiple variables
        let query = r#"
        query GetUsers($limit: Int!, $active: Boolean, $name: String) {
            users(limit: $limit, active: $active, nameContains: $name) {
                id
                name
                isActive
            }
        }
        "#;

        // Variables JSON
        let variables_json = json!({
            "limit": 10,
            "active": true,
            "name": "John"
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check variable values
        assert!(var_map.contains_key("limit"), "Variable 'limit' not found");
        assert!(
            var_map.contains_key("active"),
            "Variable 'active' not found"
        );
        assert!(var_map.contains_key("name"), "Variable 'name' not found");

        assert_eq!(var_map["limit"], "10");
        assert_eq!(var_map["active"], "true");
        assert_eq!(var_map["name"], "\"John\"");
    }

    #[test]
    fn test_process_nested_object_variables() {
        // Set up test GraphQL query with object variable
        let query = r#"
        query CreateUser($user: UserInput!) {
            createUser(input: $user) {
                id
                name
            }
        }
        "#;

        // Variables JSON with nested object
        let variables_json = json!({
            "user": {
                "name": "John Doe",
                "email": "john@example.com",
                "preferences": {
                    "theme": "dark",
                    "notifications": true
                }
            }
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check variable value
        assert!(var_map.contains_key("user"), "Variable 'user' not found");

        // Parse the JSON string to verify nested structure
        let user_json: serde_json::Value =
            serde_json::from_str(&var_map["user"]).expect("Failed to parse user JSON");
        assert_eq!(user_json["name"], "John Doe");
        assert_eq!(user_json["email"], "john@example.com");
        assert_eq!(user_json["preferences"]["theme"], "dark");
        assert_eq!(user_json["preferences"]["notifications"], true);
    }

    #[test]
    fn test_process_array_variables() {
        // Set up test GraphQL query with array variable
        let query = r#"
        query GetUsers($ids: [ID!]!) {
            users(ids: $ids) {
                id
                name
            }
        }
        "#;

        // Variables JSON with array
        let variables_json = json!({
            "ids": ["1", "2", "3"]
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check variable value
        assert!(var_map.contains_key("ids"), "Variable 'ids' not found");

        // Parse the JSON string to verify array structure
        let ids_json: serde_json::Value =
            serde_json::from_str(&var_map["ids"]).expect("Failed to parse ids JSON");
        assert!(ids_json.is_array());
        assert_eq!(ids_json.as_array().unwrap().len(), 3);
        assert_eq!(ids_json[0], "1");
        assert_eq!(ids_json[1], "2");
        assert_eq!(ids_json[2], "3");
    }

    #[test]
    fn test_process_null_variables() {
        // Set up test GraphQL query with nullable variable
        let query = r#"
        query GetUser($id: ID) {
            user(id: $id) {
                id
                name
            }
        }
        "#;

        // Variables JSON with null value
        let variables_json = json!({
            "id": null
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check null variable value
        assert!(var_map.contains_key("id"), "Variable 'id' not found");
        assert_eq!(var_map["id"], "null");
    }

    #[test]
    fn test_handle_empty_variables() {
        // Set up test GraphQL query with no variables
        let query = r#"
        query GetUsers {
            users {
                id
                name
            }
        }
        "#;

        // Empty variables JSON
        let variables_json = json!({});

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check empty variable map
        assert!(var_map.is_empty(), "Variable map should be empty");
    }

    #[test]
    fn test_handle_null_variables_json() {
        // Set up test GraphQL query with variables
        let query = r#"
        query GetUser($id: ID = "default") {
            user(id: $id) {
                id
                name
            }
        }
        "#;

        // Null variables JSON
        let variables_json = serde_json::Value::Null;

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check empty variable map (default values handled elsewhere)
        assert!(
            var_map.is_empty(),
            "Variable map should be empty for null JSON"
        );
    }

    #[test]
    fn test_handle_variables_with_defaults() {
        // Set up test GraphQL query with default variables
        let query = r#"
        query GetUsers($limit: Int = 10, $active: Boolean = true) {
            users(limit: $limit, active: $active) {
                id
                name
            }
        }
        "#;

        // Variables JSON overriding only one default
        let variables_json = json!({
            "limit": 20
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result
        assert!(result.is_ok(), "Variable processing failed");
        let var_map = result.unwrap();

        // Check provided value overrides default
        assert!(var_map.contains_key("limit"), "Variable 'limit' not found");
        assert_eq!(var_map["limit"], "20");

        // Note: Default values for $active would be handled in the GraphQL execution,
        // not in the variable processing phase, so we don't check for it here
    }

    #[test]
    fn test_process_variables_without_operation() {
        // Set up test GraphQL query without operation
        let query = r#"
        fragment UserFields on User {
            id
            name
        }
        "#;

        // Variables JSON
        let variables_json = json!({
            "id": "123"
        });

        // Parse the query with graphql-query
        let ctx = ASTContext::new();
        let document = Document::parse(&ctx, query).expect("Failed to parse query");

        // Create a variable processor and process the variables
        let processor = VariableProcessor::new();
        let result = processor.process_variables(&document, &variables_json);

        // Verify the result fails because there's no operation
        assert!(result.is_err(), "Should fail without an operation");

        // Check error message mentions failing to get operation
        let err = result.err().unwrap();
        assert!(
            format!("{}", err).contains("Failed to get operation"),
            "Error should mention failed to get operation"
        );
    }
}

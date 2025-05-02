defmodule GraSQL.ParserTest do
  use ExUnit.Case, async: true
  doctest GraSQL

  describe "parse_query/1 with various query types" do
    test "parses simple query" do
      query = "{ users { id name email } }"
      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      # Extract resolution request fields
      {field_names_key, field_names, field_paths_key, field_paths} = resolution_request
      assert field_names_key == :field_names
      assert field_paths_key == :field_paths

      # Verify expected field names and paths
      assert Enum.member?(field_names, "users")
      assert is_list(field_paths)
      assert length(field_paths) >= 1
    end

    test "parses named query" do
      query = "query GetUsers { users { id name } }"

      assert {:ok, _query_id, :query, "GetUsers", resolution_request} =
               GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, field_paths} = resolution_request
      assert Enum.member?(field_names, "users")
      assert is_list(field_paths)
      assert length(field_paths) >= 1
    end

    test "parses query with nested relationships" do
      query = """
      {
        users {
          id
          name
          profile {
            avatar
            settings {
              theme
            }
          }
          posts {
            id
            title
          }
        }
      }
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, field_paths} = resolution_request

      # Verify all expected field names
      ["users", "profile", "settings", "posts"]
      |> Enum.each(fn name -> assert Enum.member?(field_names, name) end)

      # Should have at least 3 paths: users, users.profile, users.posts
      assert length(field_paths) >= 3
    end

    test "parses deeply nested query" do
      query = """
      {
        organizations {
          id
          name
          departments {
            id
            name
            teams {
              id
              name
              projects {
                id
                name
                tasks {
                  id
                  name
                  subtasks {
                    id
                    name
                    assignee {
                      id
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, field_paths} = resolution_request

      # Verify all expected field names
      ["organizations", "departments", "teams", "projects", "tasks", "subtasks", "assignee"]
      |> Enum.each(fn name -> assert Enum.member?(field_names, name) end)

      # Should have at least 6 paths for the deeply nested structure
      assert length(field_paths) >= 6
    end

    test "parses query with filters" do
      query = """
      {
        users(where: {
          name: { _eq: "John" },
          email: { _like: "%example.com" }
        }) {
          id
          name
        }
      }
      """

      assert {:ok, _query_id, :query, "", _resolution_request} = GraSQL.Native.parse_query(query)
    end

    test "parses query with complex filters" do
      query = """
      {
        users(where: {
          _and: [
            { name: { _like: "%John%" } },
            { email: { _ilike: "%example.com" } },
            {
              _or: [
                { age: { _gt: 18 } },
                { status: { _eq: "ACTIVE" } }
              ]
            },
            {
              profile: {
                _and: [
                  { verified: { _eq: true } },
                  {
                    location: {
                      city: { _eq: "New York" }
                    }
                  }
                ]
              }
            }
          ]
        }) {
          id
          name
        }
      }
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, _field_paths} = resolution_request

      # Verify profile field is extracted from filter
      assert Enum.member?(field_names, "profile")
      assert Enum.member?(field_names, "location")
    end

    test "parses query with aggregations" do
      query = """
      {
        users_aggregate {
          aggregate {
            count
            sum {
              age
              score
            }
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
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, _field_paths} = resolution_request

      # Verify aggregate field names
      assert Enum.member?(field_names, "users_aggregate")
    end

    test "parses query with pagination and sorting" do
      query = """
      {
        users(
          limit: 10,
          offset: 20,
          order_by: { name: asc, created_at: desc }
        ) {
          id
          name
        }
      }
      """

      assert {:ok, _query_id, :query, "", _resolution_request} = GraSQL.Native.parse_query(query)
    end

    test "parses mutation" do
      query = """
      mutation CreateUsers {
        insert_users(
          objects: [
            { name: "John", email: "john@example.com" },
            { name: "Jane", email: "jane@example.com" }
          ]
        ) {
          returning {
            id
            name
          }
          affected_rows
        }
      }
      """

      assert {:ok, _query_id, :mutation, "CreateUsers", resolution_request} =
               GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, _field_paths} = resolution_request

      # Verify insert_users and returning paths
      assert Enum.member?(field_names, "insert_users")
      assert Enum.member?(field_names, "returning")
    end

    test "parses query with variables" do
      query = """
      query GetUser($id: ID!, $includeProfile: Boolean!) {
        user(id: $id) {
          id
          name
          email
          profile {
            avatar
            bio
          }
        }
      }
      """

      assert {:ok, _query_id, :query, "GetUser", _resolution_request} =
               GraSQL.Native.parse_query(query)
    end

    test "parses query with aliases" do
      query = """
      {
        active_users: users(where: { status: { _eq: "ACTIVE" } }) {
          id
          full_name: name
          contact_info: profile {
            email
            phone
          }
        }
      }
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, _field_paths} = resolution_request

      # Aliases should be handled correctly with the original field names extracted
      assert Enum.member?(field_names, "users")
      assert Enum.member?(field_names, "profile")
    end

    test "parses combined features query" do
      query = """
      {
        users(
          where: {
            posts: {
              comments_aggregate: {
                aggregate: {
                  count: { _gt: 5 }
                }
              }
            }
          },
          limit: 10,
          offset: 20,
          order_by: { name: asc }
        ) {
          id
          name
          posts(limit: 3, order_by: { created_at: desc }) {
            title
            comments_aggregate {
              aggregate {
                count
              }
            }
          }
          profile {
            avatar
          }
        }
      }
      """

      assert {:ok, _query_id, :query, "", resolution_request} = GraSQL.Native.parse_query(query)

      {_field_names_key, field_names, _field_paths_key, field_paths} = resolution_request

      # Verify complex nested fields are extracted
      ["users", "posts", "comments_aggregate", "profile"]
      |> Enum.each(fn name -> assert Enum.member?(field_names, name) end)

      # Should have paths for users, posts, and complex nested relationships
      assert length(field_paths) >= 4
    end

    test "handles invalid queries" do
      invalid_queries = [
        "{ users { missing closing brace",
        "query { invalid syntax @#$ }",
        "",
        " ",
        "{}"
      ]

      for query <- invalid_queries do
        result = GraSQL.Native.parse_query(query)
        assert match?({:error, _}, result), "Query '#{query}' should be invalid"
      end
    end
  end

  describe "parsing and regeneration consistency" do
    test "same query parsed multiple times has same query ID" do
      query = "{ users { id name email } }"

      {:ok, query_id1, _, _, _} = GraSQL.Native.parse_query(query)
      {:ok, query_id2, _, _, _} = GraSQL.Native.parse_query(query)

      assert query_id1 == query_id2
    end
  end
end

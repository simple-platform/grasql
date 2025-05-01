ExUnit.start()
# Start GraSQL application explicitly for tests
Application.ensure_all_started(:grasql)

# Add test/support directory to the code path for tests
Code.require_file("support/simple_resolver.ex", __DIR__)

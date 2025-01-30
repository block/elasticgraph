require "pathname"

ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1

  # This registers the elasticgraph-query_registry extension, which can be used to reject queries that
  # clients have not registered (and to reject queries that differ from what a client has registered).
  # In addition, every registered query is validated against the schema in the CI build, giving you
  # confidence as you evolve your schema that you're not breaking client queries.
  #
  # If you don't want to use this extension, you can remove these lines.
  require(query_registry_path = "elastic_graph/query_registry/graphql_extension")
  schema.register_graphql_extension ElasticGraph::QueryRegistry::GraphQLExtension, defined_at: query_registry_path
end

parent_dir = Pathname("#{__dir__}/..").expand_path

# Here we go through all the Ruby files in the `config/schema` directory and load them.
# The assumption is that any Ruby file in these directories is part of your schema
# definition (except for the special cases skipped below). If you have many Ruby files
# that are not part of your schema under `config/schema`, you may want to change this
# to individually `load` the desired schema files.
Dir["#{parent_dir}/**/*.rb"].each do |schema_def_file|
  full_path = Pathname(schema_def_file).expand_path

  # Skip reloading this file (otherwise we'd recurse infinitely...)
  next if full_path == Pathname(__FILE__).expand_path

  # Skip loading query RSpec tests.
  next if %r{queries/\S+/\S+_spec.rb}.match?(full_path.to_s)

  # Must use `load`, not `require` so that if the schema is evaluated multiple times it works.
  load full_path
end

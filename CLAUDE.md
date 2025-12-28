# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ElasticGraph is a schema-driven, scalable, cloud-native, batteries-included GraphQL platform backed by Elasticsearch/OpenSearch. It's designed as a modular system with a small core and numerous built-in extensions, organized as a Ruby monorepo containing 20+ gems.

## Common Commands

### Testing
- `script/run_specs` - Run entire test suite (uses flatware for parallelization)
- `script/run_gem_specs [gem_name]` - Run tests for a specific gem (e.g., `elasticgraph-support`)
- `bundle exec rspec [path]` - Run specific test file or directory
- `bundle exec rspec --only-failures` - Run only previously failed tests
- `bundle exec rspec --next-failure` - Run failures one at a time (for iterative debugging)
- `script/flatware_rspec [path]` - Run tests in parallel (faster for large test runs, slower for small subsets)

**Important**: Integration/acceptance tests require a running datastore:
```bash
bundle exec rake elasticsearch:test:boot
# or
bundle exec rake opensearch:test:boot
```

### Build & Validation
- `script/quick_build` - Run abridged CI build (recommended before opening PRs)
- `script/lint` - Run linter (Standard Ruby)
- `script/lint --fix` - Auto-fix linting issues
- `script/type_check` - Run Steep type checker
- `script/spellcheck` - Check spelling (uses codespell)
- `script/spellcheck -w` - Auto-fix spelling issues

### Schema & Artifacts
- `bundle exec rake schema_artifacts:dump` - Regenerate schema artifacts after schema definition changes
- Schema definition files: `config/schema.rb` and `config/schema/*.rb`

### Local Development
- `bundle exec rake boot_locally` - Boot ElasticGraph locally (from a new project)
- `bundle exec rake site:serve` - Serve project website locally at http://localhost:4000/elasticgraph/
- `bundle exec rake site:preview_docs:[gem_name]` - Preview API docs for a specific gem (faster feedback loop)

### Documentation
- API documentation uses YARD
- Website source: `config/site/`
- Example queries: `config/site/examples/*/queries/`
- When writing links in documentation, use permalinks (links to a specific commit/version)
- Prefer relative links to ElasticGraph documentation over external links to ruby-doc.org

## Architecture

### Monorepo Structure
All gems follow the pattern: `elasticgraph-[name]/` containing:
- `lib/elastic_graph/[name]/` - Source code
- `spec/` - RSpec test suite
- `Gemfile` - Symlinked from root `Gemfile`
- `[name].gemspec` - Gem specification

### Gem Categories

**Core Libraries** (8 gems): Always included in production deployments
- `elasticgraph-admin`: Datastore administration
- `elasticgraph-datastore_core`: Core datastore logic
- `elasticgraph-graphql`: GraphQL query engine
- `elasticgraph-indexer`: Data indexing
- `elasticgraph-schema_artifacts`: Schema artifact access
- `elasticgraph-support`: Shared utilities
- `elasticgraph-rack`: Rack server
- `elasticgraph-graphiql`: GraphiQL IDE

**Local Development Libraries** (3 gems):
- `elasticgraph`: Project bootstrapping
- `elasticgraph-local`: Local development support
- `elasticgraph-schema_definition`: Schema definition DSL

**Datastore Adapters** (2 gems):
- `elasticgraph-elasticsearch`: Elasticsearch client wrapper
- `elasticgraph-opensearch`: OpenSearch client wrapper

**Extensions** (5 gems): Optional functionality
- `elasticgraph-apollo`: Apollo Federation support
- `elasticgraph-health_check`: Health checks
- `elasticgraph-query_interceptor`: Query interception
- `elasticgraph-query_registry`: Source-controlled query registry
- `elasticgraph-warehouse`: Data warehouse ingestion

**AWS Lambda Integration** (5 gems):
- `elasticgraph-admin_lambda`, `elasticgraph-graphql_lambda`, `elasticgraph-indexer_lambda`, `elasticgraph-indexer_autoscaler_lambda`, `elasticgraph-lambda_support`

### Key Components

**Query Engine** (`elasticgraph-graphql`):
- `ElasticGraph::GraphQL::DatastoreQuery`: Intermediate query representation
- `ElasticGraph::GraphQL::Aggregation`: Aggregation query handling
- `filter_node_interpreter.rb`: Filter operator mapping

**Schema Definition** (`elasticgraph-schema_definition`):
- `SchemaElementNames`: Customizable GraphQL schema element names
- `config/schema.rb`: Main schema entry point
- `config/schema/*.rb`: Schema definition files (e.g., `teams.rb`, `widgets.rb`)

**Test Infrastructure**:
- `spec_support/`: Shared test utilities
- Test coverage maintained at 100%
- Uses FactoryBot for test data

## Development Workflow

### Adding Query API Features

When adding filtering predicates or aggregation functions:

1. **Design Phase**: Create GitHub Discussion, research datastore capabilities, design GraphQL API following ElasticGraph's guiding principles
2. **Schema Definition**: Update `SchemaElementNames`, built-in types, and test coverage
3. **Query Translation**: Implement GraphQL → datastore query translation with unit, integration, and acceptance tests
4. **Documentation**: Add user-facing docs with working examples to `config/site/`

### Test Strategy

Three layers of testing:
- **Unit tests**: Build and inspect `DatastoreQuery` without execution
- **Integration tests**: Build and execute `DatastoreQuery` directly (skips GraphQL layer)
- **Acceptance tests**: End-to-end GraphQL queries with real datastore

### Bundle Management

The repo uses a symlinked `Gemfile` approach:
- Root `Gemfile` defines development, site, and test dependencies
- Each gem has a symlinked `Gemfile` that includes its `.gemspec` and recursively resolves ElasticGraph gem dependencies from the repo

Custom gems can be added via `Gemfile-custom` (see `Gemfile-custom.example`), then run `source script/enable_custom_gemfile`.

## Code Standards

- **Linter**: Standard Ruby (see `.standard.yml`)
- **Type Checker**: Steep (`Steepfile`)
- **Test Framework**: RSpec
- **Coverage**: 100% required (enforced by SimpleCov)
- **Ruby Version**: 3.4.x or 4.0.x
- **Standard Comment Header**: Required on most Ruby files (copyright notice)

### Ruby Idioms

- Prefer `filter_map` over `.select { ... }.map { ... }` chains. For example, instead of:
  ```ruby
  items.select { |item| item.value }.map { |item| item.value }
  ```
  Use:
  ```ruby
  items.filter_map { |item| item.value }
  ```
- Prefer `::Data.define` over `::Struct.new` for immutable data classes. Use `Struct` only when mutability is required.
- Don't rely on exceptions for control flow (exceptions are slow). Handle edge cases explicitly instead (e.g., check for `nil` before calling a method that would raise `ArgumentError`).
- For constants accessed from multiple EG gems, define them in `elasticgraph-support/lib/elastic_graph/constants.rb`.

### RBS Type Signatures

- When defining RBS signatures for extension modules, prefer declaring the concrete type a module extends rather than defining custom interfaces. For example, use `module IndexExtension : ::ElasticGraph::SchemaDefinition::Indexing::Index` instead of creating a custom `_IndexExtensionInterface`.

### Testing

- Avoid duplicate tests. If two tests will always pass/fail together, keep only one.

## Important Patterns

### Schema Artifacts
After schema definition changes, always run:
```bash
bundle exec rake schema_artifacts:dump
```

This updates:
- Generated GraphQL schema
- Datastore mappings
- Runtime metadata
- Datastore scripts (including auto-updating `INDEX_DATA_UPDATE_SCRIPT_ID` constant)

### Datastore Configuration
Test datastore ports configured in `config/settings/test.yaml.template`. The `Rakefile` automatically clears `ClusterConfigurationManager` state files when booting test datastores.

### Flatware Parallelization
Tests run in parallel via flatware when beneficial. The build scripts automatically determine when to use it based on test suite size.

## Troubleshooting

- **Datastore in bad state**: Kill and restart `rake [elasticsearch|opensearch]:test:boot`
- **Schema artifact issues**: Run `rake schema_artifacts:dump` twice if updating `update_index_data.painless` script
- **Memory resets between datastore boots**: The `boot_prep_for_tests` task clears `ClusterConfigurationManager` state files

## Repository Files

- `Rakefile`: Main task definitions, schema artifact automation, test prep hooks
- `script/`: Build and development scripts
- `config/schema.rb`: Schema entry point
- `config/settings/`: Environment configurations
- `spec_support/`: Shared test infrastructure
- `CODEBASE_OVERVIEW.md`: Detailed architecture and dependency diagrams
- `CONTRIBUTING.md`: Contribution guidelines and detailed feature development walkthrough
- `MAINTAINERS_RUNBOOK.md`: Maintenance tasks (releases, etc.)
- `.goosehints`: Hints for Goose AI agent (adaptable for other AI tools)
- `ai-memory/`: AI agent memory bank (if using AI assistants)

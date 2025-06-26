# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "script/list_eg_gems"

target :elasticgraph_gems do
  exclude_dirs = %w[
    spec_support
  ].to_set

  ::ElasticGraphGems.list.each do |dir|
    next unless Dir.exist?("#{dir}/sig") && Dir.exist?("#{dir}/lib")
    next if exclude_dirs.include?(dir)

    signature "#{dir}/sig"
    check "#{dir}/lib"
  end

  # elasticgraph-admin: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-admin/lib/elastic_graph/admin/datastore_client_dry_run_decorator.rb
    elasticgraph-admin/lib/elastic_graph/admin/rake_tasks.rb
  ])

  # elasticgraph-graphql: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-graphql/lib/elastic_graph/graphql/datastore_query.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/datastore_query/document_paginator.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/datastore_response/search_response.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/datastore_search_router.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/resolvers/get_record_field_value.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/resolvers/list_records.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/resolvers/nested_relationships.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/schema.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/schema/field.rb
    elasticgraph-graphql/lib/elastic_graph/graphql/schema/type.rb
  ])

  # elasticgraph-indexer: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-indexer/lib/elastic_graph/indexer/spec_support/event_matcher.rb
  ])

  # elasticgraph-local: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-local/lib/elastic_graph/local/spec_support/common_project_specs.rb
  ])

  # elasticgraph-schema_artifacts: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-schema_artifacts/lib/elastic_graph/schema_artifacts/runtime_metadata/schema_element_names.rb
  ])

  # elasticgraph-schema_definition: existing files that don't type check yet.
  ignore(*%w[
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/indexing/index.rb
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/mixins/has_indices.rb
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/built_in_types.rb
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/enums_for_indexed_types.rb
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/field.rb
    elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/union_type.rb
  ])

  library "logger",
    "base64",
    "date",
    "delegate",
    "did_you_mean",
    "digest",
    "fileutils",
    "forwardable",
    "json",
    "open3",
    "pathname",
    "shellwords",
    "tmpdir",
    "tempfile",
    "time",
    "uri"

  configure_code_diagnostics(::Steep::Diagnostic::Ruby.all_error) do |config|
    # Setting these to :hint for now, as some branches are unreachable by steep
    # due to the way `Array#[]` and `Hash#[]` work.
    # For more detail: https://github.com/soutaro/steep/wiki/Release-Note-1.5#better-flow-sensitive-typing-analysis
    config[::Steep::Diagnostic::Ruby::UnreachableBranch] = :hint
    config[::Steep::Diagnostic::Ruby::UnreachableValueBranch] = :hint
  end
end

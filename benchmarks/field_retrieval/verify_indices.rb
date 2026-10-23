# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/graphql/field_retrieval"
require "json"
require "optparse"

# Read-only prerequisite for the experiment, not proof of historical data equivalence.
module FieldRetrievalIndexVerification
  def self.problems(actual, expected, fields)
    problems = []
    mapping = actual.fetch("mappings", {})
    expected_mapping = expected.fetch("mappings")
    problems << "root mapping disables field indexing" if mapping["enabled"] == false
    source = mapping.fetch("_source", {}).reject { |key, value| key == "enabled" && value == true }
    problems << "source configuration differs from the generated mapping" unless source == expected_mapping.fetch("_source", {})
    settings = actual.fetch("settings", {})
    limit = settings.fetch("index.max_docvalue_fields_search", 100).to_i
    problems << "doc-value search limit is below 100" if limit < ElasticGraph::GraphQL::FieldRetrieval::Automatic::MAX_DOCVALUE_FIELDS
    %w[coerce ignore_malformed].each do |option|
      key = "index.mapping.#{option}"
      default = (option == "coerce") ? "true" : "false"
      if settings.fetch(key, default).to_s != expected.fetch("settings").fetch(key).to_s
        problems << "#{key} differs from generated settings"
      end
    end
    problems << "index-wide keyword ignoring needs separate validation" if settings.key?("index.mapping.ignore_above")
    problems << "synthetic source is unsupported" if settings.fetch("index.mapping.source.mode", "stored") != "stored"
    problems << "derived source is unsupported" if settings.fetch("index.derived_source.enabled", false).to_s != "false"

    fields.each do |field|
      physical = mapping.fetch("properties", {}).fetch(field, {})
      declared = expected_mapping.fetch("properties").fetch(field)
      unless physical["type"] == declared.fetch("type") && physical.fetch("doc_values", true) == true &&
          (physical.keys - %w[type index doc_values store]).empty? && !mapping.fetch("runtime", {}).key?(field)
        problems << "#{field}: missing or incompatible physical mapping"
      end
    end
    problems
  end

  def self.verify(core)
    artifacts = core.schema_artifacts.datastore_config
    checks = []
    core.index_definitions_by_name.each_value do |index|
      next unless index.accessible_from_queries?
      fields = index.fields_by_path.filter_map { |name, field| name if name != "id" && field.doc_values_eligible }
      next if fields.empty?

      client = core.clients_by_name.fetch(index.cluster_to_query)
      expected = if index.rollover_index_template?
        artifacts.fetch("index_templates").fetch(index.name).fetch("template")
      else
        artifacts.fetch("indices").fetch(index.name)
      end
      configurations = if index.rollover_index_template?
        [["template", index.name, client.get_index_template(index.name).fetch("template", {})]]
      else
        []
      end
      # Enumerate the search wildcard directly: related_rollover_indices omits old
      # generations with unrecognized suffixes that can still participate in searches.
      names = client.list_indices_matching(index.index_expression_for_search)
      configurations.concat(names.sort.map { |name| ["index", name, client.get_index(name)] })
      if names.empty?
        checks << {"cluster" => index.cluster_to_query, "name" => index.name, "kind" => "index",
                   "problems" => ["no physical indices; populate a representative staging dataset before the pilot"]}
      end
      configurations.each do |kind, name, config|
        checks << {"cluster" => index.cluster_to_query, "name" => name, "kind" => kind,
                   "eligible_fields" => fields.size, "problems" => problems(config, expected, fields)}
      end
    end
    raise "No eligible payload fields found; regenerate artifacts and check query-cluster settings" if checks.empty?

    {"compatible" => checks.all? { |check| check.fetch("problems").empty? }, "checks" => checks,
     "data_parity_verified" => false}
  end

  def self.run(arguments)
    settings = nil
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: bundle exec ruby verify_indices.rb --settings FILE > index-verification.json"
      opts.on("--settings FILE") { |value| settings = value }
    end
    parser.parse!(arguments)
    raise ArgumentError, parser.to_s unless settings && arguments.empty?

    core = ElasticGraph::DatastoreCore.from_yaml_file(settings)
    report = verify(core)
    puts JSON.pretty_generate(report)
    warn "Mapping verification does not validate historical values. Complete the data and GraphQL comparisons in ROLLOUT.md."
    report.fetch("compatible")
  end
end

if $PROGRAM_NAME == __FILE__
  exit(FieldRetrievalIndexVerification.run(ARGV) ? 0 : 1)
end

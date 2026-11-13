# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "benchmark"
require "elastic_graph/graphql"

# Uses the application's schema, extensions, resolvers, and datastore connections.
module GraphQLRetrievalBenchmark
  class RecordingRouter < Data.define(:router, :counts)
    def msearch(queries, query_tracker:, **options)
      router.msearch(queries, query_tracker: query_tracker, **options).tap do
        counts.replace(query_tracker.extension_data.fetch("field_retrieval_counts", {}))
      end
    end
  end

  def self.instances(base)
    %w[source automatic].to_h do |mode|
      config = base.config.with(experimental_field_retrieval: mode)
      instance = ElasticGraph::GraphQL.new(config: config, datastore_core: base.datastore_core)
      recorder = RecordingRouter.new(router: instance.datastore_search_router, counts: {})
      measured = ElasticGraph::GraphQL.new(config: config, datastore_core: base.datastore_core, datastore_search_router: recorder)
      [mode, [measured, recorder]]
    end
  end

  def self.measure(instances, query, variables: {}, warmup: 20, iterations: 100, seed: 1110)
    random = Random.new(seed)
    samples = instances.to_h { |mode, _| [mode, []] }
    plans = instances.to_h { |mode, _| [mode, {}] }
    baseline = nil
    (warmup + iterations).times do |iteration|
      instances.keys.shuffle(random: random).each do |mode|
        instance, recorder = instances.fetch(mode)
        recorder.counts.clear
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = instance.graphql_query_executor.execute(query, variables: variables).to_h
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        raise "GraphQL execution returned errors; check the query against the application's schema" if result.fetch("errors", []).any?
        baseline ||= result
        raise "GraphQL results differ; use stable data, deterministic sorting, and deterministic resolvers" unless result == baseline
        next if iteration < warmup

        samples.fetch(mode) << elapsed
        recorder.counts.each do |reason, count|
          totals = plans.fetch(mode)
          totals[reason] = totals.fetch(reason, 0) + count
        end
      end
    end
    {"automatic_path_exercised" => plans.fetch("automatic").key?("doc_values"),
     "variants" => samples.to_h { |mode, timings|
       [mode, {"wall_ms" => FieldRetrievalBenchmark.summary(timings), "samples_ms" => timings, "field_retrieval_counts" => plans.fetch(mode)}]
     }}
  end

  def self.run(arguments)
    options = {warmup: 20, iterations: 100, seed: 1110}
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: bundle exec ruby graphql_benchmark.rb --settings FILE --queries DIRECTORY > results.json"
      opts.on("--settings FILE") { |value| options[:settings] = value }
      opts.on("--queries DIRECTORY") { |value| options[:queries] = value }
      %i[warmup iterations seed].each do |name|
        opts.on("--#{name} N", Integer) { |value| options[name] = value }
      end
    end
    parser.parse!(arguments)
    raise ArgumentError, parser.to_s unless arguments.empty? && options[:settings] && options[:queries]
    raise ArgumentError, "warmup must be nonnegative and iterations positive" unless options[:warmup] >= 0 && options[:iterations] > 0
    paths = Dir[File.join(options.fetch(:queries), "*.graphql")].sort
    raise ArgumentError, "No .graphql files found" if paths.empty?

    base = ElasticGraph::GraphQL.from_yaml_file(options.fetch(:settings)) do |settings|
      settings.merge("logger" => settings.fetch("logger", {}).merge("device" => File::NULL))
    end
    measured = instances(base)
    # Build schemas outside the timed portion, even for smoke runs with no warmup.
    measured.each_value { |instance, _| instance.schema }
    results = paths.to_h do |path|
      query = File.read(path)
      operations = ::GraphQL.parse(query).definitions.grep(::GraphQL::Language::Nodes::OperationDefinition)
      raise ArgumentError, "Each file must contain exactly one query operation" unless operations.size == 1 && operations.first.operation_type == "query"
      variables_path = path.sub(/\.graphql\z/, ".variables.json")
      variables = File.exist?(variables_path) ? JSON.parse(File.read(variables_path)) : {}
      raise ArgumentError, "Variables must be a JSON object" unless variables.is_a?(Hash)
      report = measure(measured, query, variables: variables, **options.slice(:warmup, :iterations, :seed))
      warn "#{File.basename(path)}: automatic path exercised=#{report.fetch("automatic_path_exercised")}; " + report.fetch("variants").map { |mode, data| "#{mode}=#{data.dig("wall_ms", "median").round(3)}ms" }.join(", ")
      [File.basename(path), report]
    end
    puts JSON.pretty_generate({"ruby" => RUBY_DESCRIPTION, "elasticgraph_version" => ElasticGraph::VERSION,
                               "settings" => options.slice(:warmup, :iterations, :seed), "queries" => results})
  end
end

GraphQLRetrievalBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__

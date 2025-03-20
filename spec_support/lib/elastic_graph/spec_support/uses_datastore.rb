# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "digest/md5"
require "elastic_graph/elasticsearch/client"
require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/support/hash_util"
require "logger"
require "yaml"

require_relative "cluster_configuration_manager"
require_relative "profiling"

datastore_url = YAML.safe_load_file(ElasticGraph::CommonSpecHelpers::TEST_SETTINGS_FILE_TEMPLATE, aliases: true).fetch("datastore").fetch("clusters").fetch("main").fetch("url")
datastore_logs = "#{ElasticGraph::CommonSpecHelpers::REPO_ROOT}/log/datastore_client.test.log"

module ElasticGraph
  # A `Logger` implementation that internally delegates to multiple underlying loggers so that we can both observe/assert on the logs
  # and still produce the logs to an actual log file.
  class SplitLogger < ::BasicObject
    def initialize(test_in_memory_logger, file_logger)
      @test_in_memory_logger = test_in_memory_logger
      @file_logger = file_logger
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method level do |message, &block|
        # The Elasticsearch and OpenSearch clients log 404 responses as warnings, but 404s are often completely expected: our
        # idempotent delete logic expects to get a 404 when the resource it's deleting has previously been deleted. We don't want
        # these messages to get logged to `@test_in_memory_logger` because that would cause them to show up in `logged_warnings`,
        # which our tests assert on. It simplifies everything if we just ignore/exclude these messages from the test in memory logger.
        unless message.to_s.include?("resource_not_found_exception") || message.to_s.include?('"found":false')
          @test_in_memory_logger.public_send(level, message, &block)
        end

        @file_logger.public_send(level, message, &block)
      end

      define_method :"#{level}?" do
        @test_in_memory_logger.public_send(:"#{level}?")
      end
    end
  end
end

class RequestTracker
  def initialize(app, request_accumulator)
    @app = app
    @request_accumulator = request_accumulator
  end

  def call(env)
    request = Request.new(env.method, env.url, env.body, env.request.timeout)
    @request_accumulator << request

    ElasticGraphProfiler.record("datastore (overall)", skip_frames: 3) do
      ElasticGraphProfiler.record(request.profiling_id, skip_frames: 4) do
        @app.call(env)
      end
    end
  end

  Request = ::Data.define(:http_method, :url, :body, :timeout) do
    def profiling_id
      # The time a request takes is entirely different if VCR is involved, so mention it
      # in the profiling id if we are planing back.
      # :nocov: -- which branch executes depends on `NO_VCR` env var, and a single test  run will never cover all branches.
      vcr_playing_back =
        if !defined?(::VCR)
          false
        elsif (cassette = ::VCR.current_cassette)
          !cassette.recording?
        else
          false
        end
      # :nocov:

      # Use the first path segment to identify the Datastore action into a broad category.
      # (Note that due to the leading `/` we have to take the first 2 split parts to actually get
      # the first path segment).
      # Also, group all `unique_index` resources as one since the unique index name is different every time.
      resource = url.path.split("/").first(2).join("/").sub(/unique_index_\w+/, "unique_index_*")

      # :nocov: -- `vcr_playing_back` depends on `NO_VCR` env var, and a single test run will never cover all branches.
      "datastore--#{http_method.upcase} #{resource}#{" (w/ VCR playback)" if vcr_playing_back}"
      # :nocov:
    end

    def description
      # we don't care about protocol, host, port, etc.
      path_and_query = url.to_s.sub(%r{^https?://}, "").sub(%r{[^/]*}, "")

      "#{http_method.to_s.upcase} #{path_and_query}"
    end
  end
end

UnsupportedAWSOpenSearchOperationError = Class.new(StandardError)

#   Unfortunately, managed AWS OpenSearch does not support all operations that the open source OpenSearch
#   distribution we use in our test suite does. Since ElasticGraph supports using managed AWS OpenSearch,
#   we want to limit the operations we use to the ones it supports.
#
#   AWS documents the supported operations here:
#   https://docs.aws.amazon.com/opensearch-service/latest/developerguide/supported-operations.html#version_opensearch_2.11
#
#   We have used this page to generate the `SUPPORTED_OPERATIONS` set below, using console javascript like:
#   document.querySelectorAll("table#w569aac27c13b9b5 td li code").forEach(x => { if (x.innerText.startsWith("/_")) console.log(x.innerText) })
#
#   If you get an `UnsupportedAWSOpenSearchOperationError`, you can check the AWS docs to see if
#   it is an operation that newer releases support. Please update the set below as needed.
class DisallowUnsupportedAWSOperations
  SUPPORTED_OPERATIONS = %w[
    /_alias /_aliases /_all /_analyze /_bulk /_cat /_cat/nodeattrs /_cluster/allocation/explain /_cluster/health
    /_cluster/pending_tasks /_cluster/settings /_cluster/state /_cluster/stats /_count /_delete_by_query /_explain
    /_field_caps /_field_stats /_flush /_index_template /_ingest/pipeline /_mapping /_mget /_msearch /_mtermvectors /_nodes
    /_opendistro/_alerting /_opendistro/_anomaly_detection /_opendistro/_ism /_opendistro/_ppl /_opendistro/_security /_opendistro/_sql
    /_percolate /_plugin/kibana /_rank_eval /_refresh /_reindex /_render /_resolve/index /_rollover /_scripts /_search /_search profile
    /_shard_stores /_shrink /_snapshot /_split /_stats /_status /_tasks /_template /_update_by_query /_validate
  ].to_set

  def initialize(app)
    @app = app
  end

  def call(env)
    # :nocov: -- normally only the `supported_operation?` branch is taken.
    return @app.call(env) if supported_operation?(env.url.path)
    raise UnsupportedAWSOpenSearchOperationError, "Operation is unsupported on AWS: #{env.url.path}."
    # :nocov:
  end

  def supported_operation?(path)
    # paths that do not start with `/_` are operations on specific indices, and are automatically supported.
    return true unless path.start_with?("/_")
    # ...otherwise we need to see if the SUPPORTED_OPERATIONS set contains the operation.
    path_parts = path.split("/")

    # The supported operations have different numbers of parts. The fewest parts is two
    # (e.g. "/_alias" translates into parts like: ["", "_alias"]), so we start there
    # and continue checking more parts until we've checked the entire path.
    2.upto(path_parts.size).any? do |num_parts|
      SUPPORTED_OPERATIONS.include?(path_parts.first(num_parts).join("/"))
    end
  end
end

RSpec.shared_context "datastore support", :capture_logs do
  # Provides a unique index name, so that a test can have an index that no other test interacts with.
  # The index name is derived from the unique id RSpec assigns to each example.
  #
  # This can allow us to avoid the need to frequently delete indices, leading to faster test runs.
  #
  # This can also be used as a prefix for an index name, and tests that use this to create a new
  # index or template do not have to cleanup after themselves; all indices that use this will be cleaned
  # up at the start of each test run automatically.
  let(:unique_index_name) do |example|
    # `example.id` is a string like:
    # "./spec/path/to/file_spec.rb[1:2:1]".
    # Here we turn it into a valid index name.
    "unique_index_#{example.id.gsub(/\W+/, "_").delete_prefix("_").delete_suffix("_")}"
  end

  # tracks datastore requests so we can assert on them.
  def datastore_requests_by_cluster_name
    @datastore_requests_by_cluster_name ||= Hash.new { |h, k| h[k] = [] }
  end

  let(:main_datastore_client) { new_datastore_client("main") }
  let(:other1_datastore_client) { new_datastore_client("other1") }
  let(:other2_datastore_client) { new_datastore_client("other2") }
  let(:other3_datastore_client) { new_datastore_client("other3") }

  prepend_before do |ex|
    if ex.metadata[:type] == :unit
      # :nocov: -- on a successful test run this'll never get executed.
      fail "`:uses_datastore` is only appropriate on integration and acceptance tests, but it is being used by a unit test. Please move the test to `spec/integration` or remove the `:uses_datastore` tag."
      # :nocov:
    end

    # flush everything to give us a clean slate between tests
    # We do this in a `prepend_before` hook to ensure it runs _before_
    # other `before` hooks (which may index data intended to be in the datastore for the test)
    # Note: we do not need to use `other_datastore_client` since it talks to the same datastore server.
    main_datastore_client.delete_all_documents
  end

  def datastore_requests(cluster_name)
    datastore_requests_by_cluster_name[cluster_name]
  end

  def datastore_write_requests(cluster_name)
    datastore_requests(cluster_name).reject do |req|
      req.http_method == :get || req.http_method == :head
    end
  end

  def datastore_msearch_requests(cluster_name)
    datastore_requests(cluster_name).select do |req|
      req.url.path.end_with?("/_msearch")
    end
  end

  def count_of_searches_in(msearch_request)
    # Each search within an msearch request uses 2 lines: header line and body line.
    msearch_request.body.split("\n").size / 2
  end

  def performed_search_metadata(cluster_name)
    datastore_msearch_requests(cluster_name).flat_map do |req|
      req.body.split("\n").each_slice(2).map do |header_line, _body_line|
        JSON.parse(header_line)
      end
    end
  end

  def index_search_expressions_from_queries(cluster_name)
    performed_search_metadata(cluster_name).map do |headers|
      headers.fetch("index")
    end
  end

  def indices_excluded_from_searches(cluster_name)
    index_search_expressions_from_queries(cluster_name).map do |index_search_expression|
      index_search_expression.split(",").select do |index_expression|
        index_expression.start_with?("-")
      end.map do |index_expression|
        index_expression.delete_prefix("-")
      end
    end
  end

  def unrefreshed_bulk_calls(cluster_name)
    datastore_write_requests(cluster_name)
      .select { |req| req.url.path == "/_bulk" }
      .reject { |req| req.url.query.to_s.include?("refresh=true") }
  end

  after do |ex|
    # We need to be careful with our use of the `routing` feature. If we ever
    # pass a `routing` option on a search when it's not correct to do so, the
    # search response might silently be missing documents that it should have
    # included. However, our existing test suite alone isn't sufficient to guard
    # against this, for a couple reasons:
    #
    #   1) Most of our indices have only 1 shard, in which case the routing value
    #      effectively has no impact on search behavior, as all routing values (or
    #      none!) would route to the one and only shard.
    #   2) For indices where we have multiple shards, we can't control what documents
    #      wind up on which shards (it's an internal detail of the datastore). Therefore,
    #      it's entirely possible for a test that runs a particular search to get "lucky"
    #      and get the expected documents in the response even if a routing value was
    #      used when it should not have been.
    #
    # Given these issues, we want to be careful to ensure that `routing` is only used
    # when we are sure that it should be. To assist with this, this `after` hook automatically
    # adds an assertion to every test that uses the datastore that `routing` was not used on
    # any searches. For the few tests that are meant to include searches that do use `routing`,
    # they can opt-out of this check by tagging themselves with `:expect_search_routing` (and
    # the test should then assert on what routing was used).
    unless ex.metadata[:expect_search_routing]
      expect(performed_search_metadata("main")).to all exclude("routing")
      expect(performed_search_metadata("other1")).to all exclude("routing")
      expect(performed_search_metadata("other2")).to all exclude("routing")
      expect(performed_search_metadata("other3")).to all exclude("routing")
    end

    # Similarly, we have to be careful with index exclusions: it's possible to have a query that
    # wrongly excludes indices and have a passing test by "luck", so here we force tests that expect
    # index exclusions to be tagged with `:expect_index_exclusions`. They can (and should) use
    # `expect_to_have_excluded_indices` to specify what the expected exclusions are.
    unless ex.metadata[:expect_index_exclusions]
      expect(indices_excluded_from_searches("main").flatten).to eq []
      expect(indices_excluded_from_searches("other1").flatten).to eq []
      expect(indices_excluded_from_searches("other2").flatten).to eq []
      expect(indices_excluded_from_searches("other3").flatten).to eq []
    end

    # Verify that all queries specify what indices to search. If the index search expression is `""`,
    # the datastore will search ALL indices which is undesirable.
    expect(index_search_expressions_from_queries("main")).to exclude("")
    expect(index_search_expressions_from_queries("other1")).to exclude("")
    expect(index_search_expressions_from_queries("other2")).to exclude("")
    expect(index_search_expressions_from_queries("other3")).to exclude("")

    expect(
      unrefreshed_bulk_calls("main") +
      unrefreshed_bulk_calls("other1") +
      unrefreshed_bulk_calls("other2") +
      unrefreshed_bulk_calls("other3")
    ).to be_empty, "One or more `/_bulk` calls made from this test lack `?refresh=true`, but it is required on " \
      "all `/_bulk` calls from tests to prevent the non-deterministic leaking of data between tests. Our " \
      "strategy for giving each test a clean slate (empty indices) is to use a `/_delete_by_query` call to delete " \
      "all documents that are findable by a query. If a `/_bulk` call is made without `?refresh=true`, the indexed " \
      "documents may not be visible in the index until AFTER the next `/_delete_by_query` call (but BEFORE the next " \
      "test runs a query), leading to the documents polluting the results of the next test that runs. Please pass " \
      "`refresh: true` in the `/_bulk` call."
  end

  def index_into(indexer, *records)
    # to aid in migrating existing tests, allow them to pass their graphql instance here...
    if indexer.is_a?(ElasticGraph::GraphQL)
      indexer = build_indexer(datastore_core: indexer.datastore_core)
    end

    operations = Faker::Base.shuffle(records).flat_map do |record|
      event = ElasticGraph::Indexer::TestSupport::Converters.upsert_event_for(ElasticGraph::Support::HashUtil.stringify_keys(record))
      update_target = indexer
        .schema_artifacts
        .runtime_metadata
        .object_types_by_name
        .fetch(event.fetch("type"))
        .update_targets
        .find { |t| t.type == event.fetch("type") }

      indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type")).map do |index_def|
        if !index_def.name.include?(unique_index_name) && index_def.rollover_index_template?
          expect(index_def.frequency).to eq(:yearly),
            "Expected #{index_def} to have :yearly rollover frequency, but had #{index_def.frequency}. " \
            ":yearly frequency is required when indexing documents so that the set of indices is deterministic " \
            "and consistent--we don't want individual tests to dynamically create indices which could interact " \
            "with later tests that run."
        end

        ElasticGraph::Indexer::Operation::Update.new(
          event: event,
          prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
            event.fetch("type"),
            event.fetch("record")
          ),
          destination_index_def: index_def,
          update_target: update_target,
          doc_id: event.fetch("id"),
          destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
        )
      end
    end

    # we `refresh: true` so the newly indexed records are immediately available in the search index,
    # so our tests can deterministically search for them.
    indexer.datastore_router.bulk(operations, refresh: true)
    records
  end

  def edges_of(*edges)
    {"edges" => edges}
  end

  def node_of(*args, **options)
    {"node" => string_hash_of(*args, **options)}
  end

  def string_hash_of(source_hash, *direct_fields, **fields_with_values)
    source_hash = ElasticGraph::Support::HashUtil.stringify_keys(source_hash)

    {}.tap do |hash|
      direct_fields.each do |field|
        hash[field.to_s] = source_hash.fetch(field.to_s)
      end

      fields_with_values.each do |key, value|
        hash[key.to_s] = value
      end
    end
  end

  def query_datastore(cluster_name, n)
    change { datastore_requests(cluster_name).count }.by(n).tap do |matcher|
      matcher.extend QueryDatastoreMatcherFluency
    end
  end

  def expect_to_have_routed_to_shards_with(cluster_name, *index_routing_value_pairs)
    expect(performed_search_metadata(cluster_name).last(index_routing_value_pairs.size).map { |m| [m["index"].gsub("_camel", ""), m["routing"]] }).to eq(index_routing_value_pairs)
  end

  def expect_to_have_excluded_indices(cluster_name, *excluded_indices_for_last_n_queries)
    expect(indices_excluded_from_searches(cluster_name).last(excluded_indices_for_last_n_queries.size)).to eq(excluded_indices_for_last_n_queries)
  end

  def make_datastore_calls(cluster_name, *methods_and_paths)
    datastore_requests(cluster_name).clear
    change { datastore_requests(cluster_name).map(&:description) }.from([])
  end

  def make_no_datastore_calls(cluster_name)
    maintain { datastore_requests(cluster_name).map(&:description) }
  end

  def make_no_datastore_write_calls(cluster_name)
    maintain { datastore_write_requests(cluster_name).map(&:description) }
  end

  def make_datastore_write_calls(cluster_name, *request_descriptions)
    datastore_requests(cluster_name).clear
    change { datastore_write_requests(cluster_name).map(&:description) }
      .from([])
      .to(a_collection_containing_exactly(*request_descriptions))
  end

  def index_records(*records)
    events = ElasticGraph::Indexer::TestSupport::Converters.upsert_events_for_records(records)
    indexer.processor.process(events, refresh_indices: true)
    events
  end

  # Helper method that forces the `known_related_query_rollover_indices` and `searches_could_hit_incomplete_docs?`
  # to be computed and cached. This is useful since some tests strictly verify what datastore requests are
  # made and `known_related_query_rollover_indices` is called as part of preparing to query the datastore. Since
  # it caches the result it can non-determnistically trigger a new datastore request in the middle of a test
  # that is unexpected. We can use this in such a test to make it deterministic.
  def pre_cache_index_state(graphql)
    graphql.datastore_core.index_definitions_by_name.values.each do |i|
      # :nocov: -- which side of the conditional is executed depends on the order the tests run in.
      i.remove_instance_variable(:@known_related_query_rollover_indices) if i.instance_variable_defined?(:@known_related_query_rollover_indices)
      i.remove_instance_variable(:@search_could_hit_incomplete_docs) if i.instance_variable_defined?(:@search_could_hit_incomplete_docs)
      # :nocov:

      i.known_related_query_rollover_indices
      i.searches_could_hit_incomplete_docs?
    end
  end
end

module QueryDatastoreMatcherFluency
  def times
    self
  end

  def time
    self
  end
end

module DatastoreSpecSupport
  # this method must be prepended so that we can force `main_datastore_client` so
  # that any call to `build_datastore_core` in groups tagged with `:uses_datastore
  # uses our configured datastore client.
  def build_datastore_core(**options)
    clients_by_name = options.fetch(:clients_by_name) do
      {
        "main" => main_datastore_client,
        "other1" => other1_datastore_client,
        "other2" => other2_datastore_client,
        "other3" => other3_datastore_client
      }
    end

    super(clients_by_name: clients_by_name, **options)
  end
end

RSpec.configure do |config|
  curl_output = `curl -is #{datastore_url}`

  # :nocov: -- only executed when the datastore isn't running.
  unless /200 OK/.match?(curl_output)
    abort <<~EOS
      The datastore does not appear to be running at `#{datastore_url}`.  Correct this by running one of these:

      - bundle exec rake elasticsearch:test:boot
      - bundle exec rake opensearch:test:boot

      ...and then try running the test suite again.
    EOS
  end
  # :nocov:

  version_info = JSON.parse(curl_output.sub(/\A[^{]+/, "")).fetch("version")
  version = version_info.fetch("number")
  backend = version_info.fetch("distribution") { "elasticsearch" }.to_sym
  require "elastic_graph/#{backend}/client"

  # Force the datastore backend used for this test suite run, so that it matches the datastore that is running.
  ElasticGraph::CommonSpecHelpers.datastore_backend = backend

  config.before(:suite) do |ex|
    datastore_state = ElasticGraph::ClusterConfigurationManager
      .new(version: version, datastore_backend: backend)
      .manage_cluster

    # :nocov: -- only executes if VCR is loaded, which is optional
    if defined?(::VCR)
      # Add suffix to the VCR cassette library directory based on the state of the datastore
      # index configuration. This ensures that we don't playback VCR cassettes that were recorded
      # against a datastore with a different configuration. If we allowed that kind of playback,
      # it could lead to false confidence, where the tests pass because of responses recorded against
      # a different datastore configuration, but do not pass against the configuration we are
      # currently using.
      VCR.configuration.cassette_library_dir += "/#{Digest::MD5.hexdigest(datastore_state)[0..7]}"

      puts "Using VCR cassette directory: #{VCR.configuration.cassette_library_dir}."
    end
    # :nocov:
  end

  DatastoreSpecSupport.module_eval do
    define_method(:datastore_backend) { backend }
    define_method(:datastore_version) { version }

    define_method :manage_cluster_for do |**args|
      ElasticGraph::ClusterConfigurationManager.new(
        version: version,
        datastore_backend: datastore_backend,
        **args
      ).manage_cluster
    end

    define_method :new_datastore_client do |name| # use `define_method` so we have access to `datastore_url` and `datastore_logs` locals.
      # :nocov: -- on a given test run only one side of this ternary gets covered.
      client_class = (datastore_backend == :opensearch) ? ElasticGraph::OpenSearch::Client : ElasticGraph::Elasticsearch::Client
      # :nocov:

      client_class.new(name, faraday_adapter: :httpx, url: datastore_url, logger: ElasticGraph::SplitLogger.new(logger, Logger.new(datastore_logs))) do |conn|
        conn.use DisallowUnsupportedAWSOperations
        conn.use RequestTracker, datastore_requests_by_cluster_name[name]
      end
    end
  end

  config.prepend DatastoreSpecSupport, :uses_datastore
  config.include_context "datastore support", :uses_datastore

  # The datastore is quite slow in tests--it takes a couple seconds to store _anything_
  # in it within a test, for reasons I don't understand. Luckily, it speaks HTTP, so we can
  # use VCR to cache responses and speed things up.
  #
  # Here we hook up VCR to automatically wrap any example tagged with `:uses_datastore`
  # so that any examples that use the datastore automatically get a speed up when you
  # re-run them.
  #
  # See `support/vcr.rb` for more on the VCR setup.
  config.define_derived_metadata(:uses_datastore) do |meta|
    # Note: we MUST consider the `body` when matching requests, because the body is
    # part of the core identity of requests to the datastore.
    meta[:vcr] = {match_requests_on: [:method, :uri, :body_ignoring_bulk_version]} unless meta.key?(:vcr)
    meta[:builds_indexer] = true
  end
end

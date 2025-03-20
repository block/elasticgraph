# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"

module ElasticGraph
  module ParallelSpecRunner
    # To safely run our tests in parallel, we need to make sure that each test worker has independent interactions with the datastore
    # that can't interfere with each other. For example, we can't have a test in one worker deleting all documents from all indices
    # while a test in another worker is querying the datastore expecting a document to be there.
    #
    # Our solution is to intercept all calls to the datastore via this adapter, and scope all operations to indices which have a prefix
    # based on the `test_env_number`. Specifically:
    #
    # * In any request which references an index, we prepend the `test_env_#{test_env_number}_` to the index name or expression.
    # * On any response which references an index, we remove the prepended index prefix since our tests don't expect it.
    # * We've also modified the configuration of `action.auto_create_index`. The `Admin::ClusterConfigurator::ClusterSettingsManager`
    #   usually disables the auto-creation of our rollover indices, to guard against a race condition that can happen when indexing
    #   into a rollover index is happening at the same time we're configuring the indices. But if we allow that behavior in our
    #   parallel tests, then it can cause problems during parallel test runs.
    #
    # Note: here we use a `SimpleDelegator` rather than a module that we prepend on to the client class because we need to be able to preserve
    # the behavior of the existing client class for when we run the unit specs of that client class. Using a `SimpleDelegator` allows us to
    # selectively modify the behavior of _some_ instances of the client class (that is, every other instance besides the ones used for
    # those unit tests!).
    class DatastoreClientAdapter < ::SimpleDelegator
      # Cluster APIs

      def put_persistent_cluster_settings(settings)
        if (index_patterns = settings["action.auto_create_index"]) && !index_patterns.include?(ROLLOVER_INDEX_INFIX_MARKER)
          settings = settings.merge({
            "action.auto_create_index" => index_patterns + ",+*#{ROLLOVER_INDEX_INFIX_MARKER}*"
          })
        end

        super(settings)
      end

      # Index Template APIs

      def get_index_template(index_template_name)
        with_updated_index_patterns_for_test_env(
          super(index_expression_for_test_env(index_template_name))
        ) { |pattern| pattern.delete_prefix(ParallelSpecRunner.index_prefix) }
      end

      def put_index_template(name:, body:)
        name = index_expression_for_test_env(name)
        body = with_updated_index_patterns_for_test_env(body) { |pattern| ParallelSpecRunner.index_prefix + pattern }
        super(name: name, body: body)
      end

      def delete_index_template(index_template_name)
        super(index_expression_for_test_env(index_template_name))
      end

      # Index APIs

      def get_index(index_name)
        super(index_expression_for_test_env(index_name))
      end

      def list_indices_matching(index_expression)
        super(index_expression_for_test_env(index_expression)).map do |index_name|
          index_name.delete_prefix(ParallelSpecRunner.index_prefix)
        end
      end

      def create_index(index:, body:)
        super(index: index_expression_for_test_env(index), body: body)
      end

      def put_index_mapping(index:, body:)
        super(index: index_expression_for_test_env(index), body: body)
      end

      def put_index_settings(index:, body:)
        super(index: index_expression_for_test_env(index), body: body)
      end

      def delete_indices(*index_names)
        super(*index_names.map { |index_name| index_expression_for_test_env(index_name) })
      end

      # Document APIs

      def msearch(body:, headers: nil)
        body = body.each_slice(2).flat_map do |(search_metadata, search_body)|
          search_metadata = search_metadata.merge(index: index_expression_for_test_env(search_metadata.fetch(:index)))
          [search_metadata, search_body]
        end

        msearch_response = super(body: body, headers: headers)

        responses = msearch_response.fetch("responses").map do |response|
          if (hits_hits = response.dig("hits", "hits"))
            hits_hits = hits_hits.map do |hit|
              hit.merge("_index" => hit.fetch("_index").delete_prefix(ParallelSpecRunner.index_prefix))
            end

            response.merge("hits" => response.fetch("hits").merge("hits" => hits_hits))
          else
            response
          end
        end

        msearch_response.merge({"responses" => responses})
      end

      def bulk(body:, refresh: false)
        body = body.each_slice(2).flat_map do |(op_metadata, op_body)|
          op_key, op_meta = op_metadata.to_a.first
          op_meta = op_meta.merge(_index: index_expression_for_test_env(op_meta.fetch(:_index)))

          [{op_key => op_meta}, op_body]
        end

        super(body: body, refresh: refresh)
      end

      def delete_all_documents
        super(index: index_expression_for_test_env("*"))
      end

      private

      def index_expression_for_test_env(index_expression)
        index_expression.split(",").map do |index_sub_expression|
          prefix = index_sub_expression.start_with?("-") ? "-" : ""
          "#{prefix}#{ParallelSpecRunner.index_prefix}#{index_sub_expression.delete_prefix("-")}"
        end.join(",")
      end

      def with_updated_index_patterns_for_test_env(body, &adjust_pattern)
        return body if body.empty?
        patterns = body.fetch("index_patterns").map(&adjust_pattern)
        body.merge({"index_patterns" => patterns})
      end
    end
  end
end

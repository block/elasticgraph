# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/support/from_yaml_file"
require "pathname"
require "rake/tasklib"

module ElasticGraph
  module QueryRegistry
    class RakeTasks < ::Rake::TaskLib
      # @dynamic self.from_yaml_file
      extend Support::FromYamlFile::ForRakeTasks.new(ElasticGraph::GraphQL)

      def initialize(registered_queries_by_client_dir, require_eg_latency_slo_directive: false, output: $stdout, &load_graphql)
        @registered_queries_by_client_dir = Pathname.new(registered_queries_by_client_dir)
        @require_eg_latency_slo_directive = require_eg_latency_slo_directive
        @output = output
        @load_graphql = load_graphql

        define_tasks
      end

      private

      def define_tasks
        namespace :query_registry do
          desc "Validates the queries registered in `#{@registered_queries_by_client_dir}`"
          task :validate_queries do
            perform_query_validation
          end

          desc "Updates the registered information about query variables for a specific client (and optionally, a specific query)."
          task :dump_variables, :client, :query do |_, args|
            dump_variables("#{args.fetch(:client)}/#{args.fetch(:query, "*")}.graphql")
          end

          namespace :dump_variables do
            desc "Updates the registered information about query variables for all clients."
            task :all do
              dump_variables("*/*.graphql")
            end
          end
        end
      end

      def dump_variables(query_glob)
        # We defer the loading of these dependencies until the task is running. As a general rule,
        # we want rake tasks to only load their dependencies when they are run--that way, `rake -T`
        # stays snappy, and when we run a rake task, only that task's dependencies are loaded
        # instead of dependencies for all rake tasks.
        require "elastic_graph/query_registry/variable_dumper"
        require "yaml"

        variable_dumper = VariableDumper.new(graphql.schema)

        @registered_queries_by_client_dir.glob(query_glob) do |file|
          dumped_variables = variable_dumper.dump_variables_for_query(file.read)
          variables_file = variable_file_name_for(file.to_s)
          ::File.write(variables_file, variable_file_docs(variables_file) + ::YAML.dump(dumped_variables))
          @output.puts "- Dumped `#{variables_file}`."
        end
      end

      def variable_file_name_for(query_file_name)
        query_file_name.delete_suffix(".graphql") + ".variables.yaml"
      end

      def variable_file_docs(file_name)
        client_name = file_name[%r{/([^/]+)/[^/]+\.variables\.yaml}, 1]
        query_name = file_name[%r{/[^/]+/([^/]+)\.variables\.yaml}, 1]

        <<~EOS
          # Generated by `rake "query_registry:dump_variables[#{client_name}, #{query_name}]"`.
          # DO NOT EDIT BY HAND. Any edits will be lost the next time the rake task is run.
          #
          # This file exists to allow `elasticgraph-query_registry` to track the structure of
          # the variables for the `#{client_name}/#{query_name}` query, so that we can detect
          # when the schema structure of an object or enum variable changes in a way that might
          # break the client.
        EOS
      end

      def perform_query_validation
        # We defer the loading of these dependencies until the task is running. As a general rule,
        # we want rake tasks to only load their dependencies when they are run--that way, `rake -T`
        # stays snappy, and when we run a rake task, only that task's dependencies are loaded
        # instead of dependencies for all rake tasks.
        require "elastic_graph/query_registry/query_validator"
        require "json"
        require "yaml"

        validator = QueryValidator.new(
          graphql.schema,
          require_eg_latency_slo_directive: @require_eg_latency_slo_directive
        )

        all_errors = @registered_queries_by_client_dir.children.sort.flat_map do |client_dir|
          @output.puts "For client `#{client_dir.basename}`:"
          validate_client_queries(validator, client_dir).tap do
            @output.puts
          end
        end

        unless all_errors.empty?
          raise "Found #{count_description(all_errors, "validation error")} total across all queries."
        end
      end

      def validate_client_queries(validator, client_dir)
        # @type var file_name_by_operation_name: ::Hash[::String, ::Pathname]
        file_name_by_operation_name = {}

        client_dir.glob("*.graphql").sort.flat_map do |query_file|
          previously_dumped_variables = previously_dumped_variables_for(query_file.to_s)
          errors_by_operation_name = validator.validate(
            query_file.read,
            client_name: client_dir.basename.to_s,
            query_name: query_file.basename.to_s.delete_suffix(".graphql"),
            previously_dumped_variables: previously_dumped_variables
          )

          @output.puts "  - #{query_file.basename} (#{count_description(errors_by_operation_name, "operation")}):"

          errors_by_operation_name.flat_map do |op_name, errors|
            if (conflicting_file_name = file_name_by_operation_name[op_name.to_s])
              errors += [conflicting_operation_name_error(client_dir, op_name, conflicting_file_name)]
            else
              file_name_by_operation_name[op_name.to_s] = query_file
            end

            op_name ||= "(no operation name)"
            if errors.empty?
              @output.puts "    - #{op_name}: ✅"
            else
              @output.puts "    - #{op_name}: 🛑. Got #{count_description(errors, "validation error")}:\n"

              errors.each_with_index do |error, index|
                @output.puts format_error(query_file, index, error)
              end
            end

            errors
          end
        end
      end

      def previously_dumped_variables_for(query_file_name)
        file_name = variable_file_name_for(query_file_name)
        return nil unless ::File.exist?(file_name)
        ::YAML.safe_load_file(file_name)
      end

      def conflicting_operation_name_error(client_dir, operation_name, conflicting_file_name)
        message = "A `#{operation_name}` query already exists for `#{client_dir.basename}` in " \
          "`#{conflicting_file_name.basename}`. Each query operation must have a unique name."

        {"message" => message}
      end

      def format_error(file_name, index, error_hash)
        file_locations = (error_hash["locations"] || []).map do |location|
          "   source: #{file_name}:#{location["line"]}:#{location["column"]}"
        end

        path = error_hash["path"]&.join(".")

        detail_lines = (error_hash["extensions"] || {})
          .merge(error_hash.except("message", "locations", "path", "extensions"))
          .map { |key, value| "   #{key}: #{value}" }

        [
          "      #{index + 1}) #{error_hash["message"]}",
          ("   path: #{path}" if path),
          *file_locations,
          *detail_lines
        ].compact.join("\n      ") + "\n\n"
      end

      def count_description(collection, noun)
        return "1 #{noun}" if collection.size == 1
        "#{collection.size} #{noun}s"
      end

      def graphql
        @graphql ||= @load_graphql.call
      end
    end
  end
end

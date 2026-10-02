# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion"
require "open3"
require "tempfile"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Uses the Buf CLI to detect breaking changes between two protobuf schemas.
      #
      # @private
      class BufBreakingChangeDetector
        BREAKING_CONFIG_JSON = %({"version":"v2","breaking":{"use":["FILE"]}})

        def initialize(buf_command: "buf", temporary_directory: ::Dir.pwd)
          @buf_command = buf_command
          @temporary_directory = temporary_directory
        end

        # Returns Buf's diagnostics if the current schema breaks the prior schema, or `nil` if it
        # is compatible.
        def breaking_changes(current_schema:, against_schema:)
          with_built_images(current_schema, against_schema) do |current_image_path, against_image_path, proto_path|
            output, status = run_buf(
              "breaking",
              current_image_path,
              "--against",
              against_image_path,
              "--exclude-imports",
              "--config",
              BREAKING_CONFIG_JSON
            )

            return nil if status.success?
            return normalized_output(output, proto_path) if status.exitstatus == 100

            raise Errors::SchemaError, buf_failure_message("compare the protobuf schemas", output)
          end
        rescue ::Errno::ENOENT
          raise Errors::SchemaError, <<~EOS.strip
            The Buf CLI is required to check `schema.proto` for breaking changes, but the `#{@buf_command}` command could not be found.
            Install Buf from https://buf.build/docs/installation and run `bundle exec rake schema_artifacts:dump` again.
          EOS
        end

        private

        def with_built_images(current_schema, against_schema)
          ::Tempfile.create(["elasticgraph-schema", ".proto"], @temporary_directory) do |proto_file|
            ::Tempfile.create(["elasticgraph-current-schema", ".binpb"], @temporary_directory) do |current_image_file|
              build_image(current_schema, "current", proto_file, current_image_file)

              ::Tempfile.create(["elasticgraph-against-schema", ".binpb"], @temporary_directory) do |against_image_file|
                build_image(against_schema, "against", proto_file, against_image_file)
                yield current_image_file.path, against_image_file.path, proto_file.path
              end
            end
          end
        end

        def build_image(schema, label, proto_file, image_file)
          proto_file.rewind
          proto_file.truncate(0)
          proto_file.write(schema)
          proto_file.flush
          image_file.close

          output, status = run_buf("build", proto_file.path, "--output", image_file.path)
          return if status.success?

          raise Errors::SchemaError, buf_failure_message("compile the #{label} protobuf schema", output)
        end

        def run_buf(*arguments)
          stdout, stderr, status = ::Open3.capture3(@buf_command, *arguments)
          output = [stdout, stderr].reject(&:empty?).join("\n").strip
          [output, status]
        end

        def buf_failure_message(action, output)
          details = output.empty? ? "Buf did not provide any diagnostics." : output
          "Buf was unable to #{action}:\n\n#{details}"
        end

        def normalized_output(output, proto_path)
          output.gsub(proto_path, PROTO_SCHEMA_FILE).gsub(::File.basename(proto_path), PROTO_SCHEMA_FILE)
        end
      end
    end
  end
end

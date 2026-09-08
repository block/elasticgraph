# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "google/protobuf/descriptor_pb"
require "open3"
require "tmpdir"

module ElasticGraph
  module ProtoIngestion
    module CompiledProtoSupport
      # Compile the actual public contract, independently of the Ruby runtime converter.
      # Each schema gets its own pool so evolving schemas can coexist in the same process.
      def with_compiled_proto(results)
        Dir.mktmpdir("elasticgraph-proto") do |directory|
          File.write(File.join(directory, "schema.proto"), results.proto_schema)
          File.write(File.join(directory, "indexing_events.proto"), results.proto_envelope_schema)
          compile_proto_files(directory) { |pool, path| yield pool, path }
        end
      end

      def compile_proto_files(directory)
        path = File.join(directory, "schema.pb")
        output, status = Open3.capture2e(ENV.fetch("PROTOC", "protoc"), "--proto_path=#{directory}", "--include_imports", "--descriptor_set_out=#{path}", "schema.proto", "indexing_events.proto")
        raise output unless status.success?
        pool = Google::Protobuf::DescriptorPool.new
        Google::Protobuf::FileDescriptorSet.decode(File.binread(path)).file.each do |file|
          pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))
        end
        # Generated Ruby code registers every message class; emulate that for the publisher.
        Google::Protobuf::FileDescriptorSet.decode(File.binread(path)).file.each do |file|
          file.message_type.each { |message| pool.lookup([file.package, message.name].reject(&:empty?).join(".")).msgclass }
        end
        yield pool, path
      end
    end
  end
end

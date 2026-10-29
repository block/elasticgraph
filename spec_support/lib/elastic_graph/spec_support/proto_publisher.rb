# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/runtime_metadata/schema"
require "elastic_graph/spec_support/protoc"
require "google/protobuf/descriptor_pb"
require "json"
require "open3"
require "tmpdir"

module ElasticGraph
  module SpecSupport
    # Publishes factory events through the generated schema and real protobuf binary encoding.
    # This intentionally walks descriptors independently of the production record converter.
    class ProtoPublisher
      def initialize(schema_artifacts)
        config = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |extension|
          extension.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
        end.extension_ref.fetch("config")
        @metadata = ProtoIngestion::RuntimeMetadata::Schema.from_hash(config)
        @pool = Google::Protobuf::DescriptorPool.new
        source = if schema_artifacts.respond_to?(:proto_schema)
          schema_artifacts.proto_schema
        else
          File.read(File.join(schema_artifacts.artifacts_dir, "schema.proto"))
        end
        Dir.mktmpdir("elasticgraph-proto") do |directory|
          File.write(File.join(directory, "schema.proto"), source)
          path = File.join(directory, "schema.pb")
          output, status = Open3.capture2e(Protoc::PROTOC_BINARY, "--proto_path=#{directory}", "--include_imports", "--descriptor_set_out=#{path}", "schema.proto", chdir: directory)
          raise output unless status.success?
          files = Google::Protobuf::FileDescriptorSet.decode(File.binread(path)).file
          files.each do |file|
            @pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))
          end
          files.each { |file| materialize_messages(file.package, file.message_type) }
        end
        @envelope = @pool.lookup("#{@metadata.package_name}.ElasticGraphEventEnvelope")
        @batch_class = @pool.lookup("#{@metadata.package_name}.ElasticGraphEventBatch").msgclass
      end

      def encode(event)
        alternative = @envelope.lookup_oneof("record").find { |field| type_name(field.subtype) == event.type }
        attrs = {
          "op" => event.op, "id" => event.id, "version" => event.version.to_s,
          "latency_timestamps" => event.latency_timestamps,
          alternative.name => message_value(alternative.subtype, event.record)
        }
        envelope = @envelope.msgclass.decode_json(JSON.generate(attrs))
        @batch_class.encode(@batch_class.new(events: [envelope]))
      end

      def round_trip(event, publisher: self)
        payload = publisher.encode(event)
        decoded = @batch_class.decode(payload).events.fetch(0)
        alternative = @envelope.lookup_oneof("record").find { |field| type_name(field.subtype) == event.type }
        latency_timestamps = decoded.latency_timestamps.map do |name, value|
          [name, JSON.parse(Google::Protobuf.encode_json(value))]
        end.to_h
        event.with(
          op: decoded.op, id: decoded.id, version: decoded.version,
          record: alternative.get(decoded), schema_version: nil, ingestion_format: "proto",
          latency_timestamps: latency_timestamps
        )
      end

      private

      def materialize_messages(namespace, messages)
        messages.each do |message|
          name = [namespace, message.name].reject(&:empty?).join(".")
          @pool.lookup(name).msgclass
          materialize_messages(name, message.nested_type)
        end
      end

      def type_name(descriptor)
        descriptor.name.delete_prefix("#{@metadata.package_name}.")
      end

      def message_value(descriptor, value)
        if (oneof = descriptor.lookup_oneof("value"))
          alternative = oneof.find { |field| type_name(field.subtype) == value.fetch("__typename") }
          return {alternative.name => message_value(alternative.subtype, value)}
        end
        overrides = @metadata.types_by_name[type_name(descriptor)]&.fields_by_name || {}
        descriptor.filter_map do |field|
          next unless value.key?(field.name) && !value[field.name].nil?
          [field.name, field_value(field, value.fetch(field.name), overrides[field.name])]
        end.to_h
      end

      def field_value(field, value, overrides)
        return value.map { |item| single_value(field, item, overrides) } if field.label == :repeated
        single_value(field, value, overrides)
      end

      def single_value(field, value, overrides)
        return value.to_s if %i[int64 sint64 uint64 fixed64 sfixed64].include?(field.type)
        scalar = @metadata.types_by_name.fetch(overrides.type).scalar if overrides&.type
        return JSON.generate(value) if scalar == "Untyped"
        if field.type == :enum
          enum = field.subtype
          names = @metadata.types_by_name[type_name(enum)]&.non_standard_enum_values_by_name || {}
          prefix = enum.lookup_value(0).to_s.delete_suffix("_UNSPECIFIED")
          return names.key(value) || "#{prefix}_#{value}"
        end
        if field.type == :message && !scalar && field.subtype.name.start_with?("#{@metadata.package_name}.")
          return {"values" => field_value(field.subtype.lookup("values"), value, overrides)} if value.is_a?(Array)
          return message_value(field.subtype, value)
        end
        value
      end
    end
  end
end

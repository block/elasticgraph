# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "base64"
require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/runtime_schema"
require "google/protobuf/descriptor_pb"

module ElasticGraph
  module ProtoIngestion
    # Decodes generated protobuf event batches, or raw domain messages with transport metadata.
    # Configure `format` as `envelope` (default) or `raw`, and `encoding` as `binary` (default)
    # or `base64` for text transports such as SQS. Descriptor sets must include imports.
    class IndexingEventDecoder
      # @param config [Hash<String, Object>] descriptor_set_file, format, encoding and optional metadata_fields
      # @param schema_artifacts [SchemaArtifacts::FromDisk] generated schema artifacts
      # @param logger [Logger] indexing logger
      def initialize(config:, schema_artifacts:, logger:)
        @schema = RuntimeSchema.new(schema_artifacts)
        @format = config.fetch("format", "envelope")
        @encoding = config.fetch("encoding", "binary")
        unless %w[envelope raw].include?(@format) && %w[binary base64].include?(@encoding)
          raise Errors::ConfigError, "Protobuf decoder format must be envelope or raw, and encoding must be binary or base64."
        end
        @metadata_fields = {"op" => "eg_op", "type" => "eg_type", "id" => "eg_id", "version" => "eg_version"}.merge(config["metadata_fields"] || {})
        @pool = Google::Protobuf::DescriptorPool.new
        path = config.fetch("descriptor_set_file")
        descriptors = Google::Protobuf::FileDescriptorSet.decode(File.binread(path))
        descriptors.file.each { |file| @pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file)) }
        # Materialize message classes before decoding references from repeated/oneof fields.
        descriptors.file.each do |file|
          file.message_type.each do |message|
            descriptor = @pool.lookup([file.package, message.name].reject(&:empty?).join(".")) # : Google::Protobuf::Descriptor
            descriptor.msgclass
          end
        end
        @batch_class = message_class("ElasticGraphEventBatch") if @format == "envelope"
      end

      # @param payload [String] binary protobuf payload, optionally base64 encoded
      # @return [Array<Hash<String, Object>>] unversioned protobuf indexing events
      def decode(payload)
        decode_with_metadata(payload, metadata: {})
      end

      # Decodes a raw message using transport headers, or an envelope batch.
      # @param payload [String] encoded payload
      # @param metadata [Hash<String, String>] transport headers/properties
      # @return [Array<Hash<String, Object>>] decoded indexing events
      def decode_with_metadata(payload, metadata:)
        payload = Base64.strict_decode64(payload) if @encoding == "base64"
        if @format == "raw"
          event = @metadata_fields.to_h { |name, header| [name, metadata[header]] }
          version = event["version"]
          event["version"] = version.to_i if version.is_a?(String) && /\A[0-9]+\z/.match?(version)
          event[INGESTION_FORMAT_KEY] = "proto"
          event["record"] = message_class(event.fetch("type")).decode(payload)
          [event]
        else
          @batch_class.decode(payload).events.map do |envelope|
            variant = envelope.class.descriptor.lookup_oneof("record").find { |field| field.has?(envelope) }
            {
              INGESTION_FORMAT_KEY => "proto",
              "op" => envelope.op,
              "type" => variant&.subtype&.name&.split(".")&.last,
              "id" => envelope.id,
              "version" => envelope.version,
              "record" => variant&.get(envelope),
              "latency_timestamps" => envelope.latency_timestamps.to_h
            }
          end
        end
      end

      private

      def message_class(type)
        descriptor = @pool.lookup("#{@schema.package_name}.#{type}")
        unless descriptor&.respond_to?(:msgclass)
          raise Errors::ConfigError, "No protobuf message #{@schema.package_name}.#{type} in the configured descriptor set."
        end
        descriptor.msgclass
      end
    end
  end
end

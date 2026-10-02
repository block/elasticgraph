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
require "json"

module ElasticGraph
  module ProtoIngestion
    # Decodes generated protobuf event batches, or raw domain messages with transport metadata.
    # Configure `format` as `envelope` (default) or `raw`, and `encoding` as `binary` (default)
    # or `base64` for text transports. Descriptor sets must include imports.
    class IndexingEventDecoder
      # @param config [Hash<String, Object>] descriptor_set_file, format, encoding and optional metadata_fields
      # @param schema_artifacts [SchemaArtifacts::FromDisk] generated schema artifacts
      def initialize(config:, schema_artifacts:)
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
        # Materialize nested classes too: repeated message fields need their subtype classes loaded.
        descriptors.file.each { |file| materialize_messages(file.package, file.message_type) }
        if @format == "envelope"
          @batch_class = message_class("ElasticGraphEventBatch")
          @envelope_class = message_class("ElasticGraphEventEnvelope")
          @record_field_numbers = @envelope_class.descriptor.lookup_oneof("record")&.map(&:number) || []
          @metadata_field_numbers = @envelope_class.descriptor.map(&:number) - @record_field_numbers
        end
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
          return [] if @schema.deleted_type?(event["type"].to_s)
          event[INGESTION_FORMAT_KEY] = "proto"
          proto_type = @schema.proto_type_name_for(event.fetch("type"))
          event["record"] = message_class(proto_type).decode(payload)
          event["type"] = @schema.public_type_name_for(proto_type)
          [event]
        else
          # Re-encoding decoded envelopes loses ordering and duplicate oneof occurrences. Inspect
          # the original bytes so a deleted record cannot hide an unsupported or live alternative.
          wire_fields(payload).filter_map do |number, wire_type, bytes|
            next unless number == 1
            raise Google::Protobuf::ParseError, "Batch events must be length-delimited messages." unless wire_type == 2
            decode_envelope(bytes)
          end
        end
      end

      private

      def decode_envelope(bytes)
        envelope = @envelope_class.decode(bytes)
        records = wire_fields(bytes).reject { |number, _, _| @metadata_field_numbers.include?(number) }
        retired_type = records.size == 1 && @schema.reserved_envelope_fields[records.first.fetch(0).to_s]
        if retired_type && records.first.fetch(1) == 2 && @schema.deleted_type?(retired_type)
          return nil
        end

        variant = envelope.class.descriptor.lookup_oneof("record")&.find { |field| field.has?(envelope) }
        event = {
          INGESTION_FORMAT_KEY => "proto",
          "op" => envelope.op,
          "type" => variant && @schema.public_type_name_for(variant.subtype.name.delete_prefix("#{@schema.package_name}.")),
          "id" => envelope.id,
          "version" => envelope.version,
          "record" => variant&.get(envelope),
          "latency_timestamps" => envelope.latency_timestamps.map { |name, timestamp| [name, JSON.parse(Google::Protobuf.encode_json(timestamp))] }.to_h
        } # : ::Hash[::String, untyped]
        supported_record = records.size == 1 && records.first.fetch(1) == 2 && @record_field_numbers.include?(records.first.fetch(0))
        unless records.empty? || supported_record
          event["envelope_error"] = "Envelope must contain exactly one supported record alternative."
        end
        event
      end

      # Reads only the transport messages' fields; opaque record bytes remain protobuf's concern.
      # Tags, uint64 varints and lengths are bounded before offsets advance. Generated contracts
      # use no groups, so group wire types are not accepted by this transport scanner.
      def wire_fields(bytes)
        fields = [] # : ::Array[[::Integer, ::Integer, ::String]]
        offset = 0
        while offset < bytes.bytesize
          tag, offset = read_varint(bytes, offset)
          number, wire_type = tag >> 3, tag & 7
          unless (1..536_870_911).cover?(number)
            raise Google::Protobuf::ParseError, "Invalid protobuf field number."
          end
          value = "".b
          case wire_type
          when 0
            _, offset = read_varint(bytes, offset)
          when 1
            offset += 8
          when 2
            length, offset = read_varint(bytes, offset)
            finish = offset + length
            raise Google::Protobuf::ParseError, "Truncated protobuf field." if finish > bytes.bytesize
            value = bytes.byteslice(offset, length) # : ::String
            offset = finish
          when 5
            offset += 4
          else
            raise Google::Protobuf::ParseError, "Unsupported protobuf wire type."
          end
          raise Google::Protobuf::ParseError, "Truncated protobuf field." if offset > bytes.bytesize
          fields << [number, wire_type, value]
        end
        fields
      end

      def read_varint(bytes, offset)
        value = 0
        index = 0
        loop do
          byte = bytes.getbyte(offset + index)
          if byte.nil? || index >= 10 || (index == 9 && byte > 1)
            raise Google::Protobuf::ParseError, "Invalid protobuf varint."
          end
          value |= (byte & 127) << (7 * index)
          return [value, offset + index + 1] if byte < 128
          index += 1
        end
      end

      def materialize_messages(namespace, messages)
        messages.each do |message|
          name = [namespace, message.name].reject(&:empty?).join(".")
          descriptor = @pool.lookup(name) # : Google::Protobuf::Descriptor
          descriptor.msgclass
          materialize_messages(name, message.nested_type)
        end
      end

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

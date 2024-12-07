# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class Indexer
    class RecordPreparer
      # Provides the ability to get a `RecordPreparer` for a specific JSON schema version.
      class Factory
        def initialize(schema_artifacts)
          @schema_artifacts = schema_artifacts

          scalar_types_by_name = schema_artifacts.runtime_metadata.scalar_types_by_name
          indexing_preparer_by_scalar_type_name = ::Hash.new do |hash, type_name|
            hash[type_name] = scalar_types_by_name[type_name]&.load_indexing_preparer&.extension_class
          end

          @preparers_by_json_schema_version = ::Hash.new do |hash, version|
            hash[version] = RecordPreparer.new(
              indexing_preparer_by_scalar_type_name,
              build_type_metas_from(@schema_artifacts.json_schemas_for(version))
            )
          end
        end

        # Gets the `RecordPreparer` for the given JSON schema version.
        def for_json_schema_version(json_schema_version)
          @preparers_by_json_schema_version[json_schema_version] # : RecordPreparer
        end

        # Gets the `RecordPreparer` for the latest JSON schema version. Intended primarily
        # for use in tests for convenience.
        def for_latest_json_schema_version
          for_json_schema_version(@schema_artifacts.latest_json_schema_version)
        end

        private

        def build_type_metas_from(json_schemas)
          json_schemas.fetch("$defs").filter_map do |type, type_def|
            next if type == EVENT_ENVELOPE_JSON_SCHEMA_NAME

            properties = type_def.fetch("properties") do
              {} # : ::Hash[::String, untyped]
            end # : ::Hash[::String, untyped]

            required_fields = type_def.fetch("required") do
              [] # : ::Array[::String]
            end # : ::Array[::String]

            eg_meta_by_field_name = properties.filter_map do |prop_name, prop|
              eg_meta = prop["ElasticGraph"]
              [prop_name, eg_meta] if eg_meta
            end.to_h

            TypeMetadata.new(
              name: type,
              requires_typename: required_fields.include?("__typename"),
              eg_meta_by_field_name: eg_meta_by_field_name
            )
          end
        end
      end

      # An alternate `RecordPreparer` implementation that implements the identity function:
      # it just echoes back the record it is given.
      #
      # This is intended only for use where a `RecordPreparer` is required but the data is not
      # ultimately going to be sent to the datastore. For example, when an event is invalid, we
      # still build operations for it, and the operations require a `RecordPreparer`, but we do
      # not send them to the datastore.
      module Identity
        def self.prepare_for_index(type_name, record)
          record
        end
      end

      def initialize(indexing_preparer_by_scalar_type_name, type_metas)
        @indexing_preparer_by_scalar_type_name = indexing_preparer_by_scalar_type_name
        @eg_meta_by_field_name_by_concrete_type = type_metas.to_h do |meta|
          [meta.name, meta.eg_meta_by_field_name]
        end

        @types_requiring_typename = type_metas.filter_map do |meta|
          meta.name if meta.requires_typename
        end.to_set
      end

      # Prepares the given payload for being indexed into the named index.
      # This allows any value or field name conversion to happen before we index
      # the data, to support the few cases where we expect differences between
      # the payload received by the ElasticGraph indexer, and the payload we
      # send to the datastore.
      #
      # As part of preparing the data, we also drop any `record` fields that
      # are not defined in our schema. This allows us to handle events that target
      # multiple indices (e.g. v1 and v2) for the same type. The event can contain
      # the set union of fields and this will take care of dropping any unsupported
      # fields before we attempt to index the record.
      #
      # Note: this method does not mutate the given `record`. Instead it returns a
      # copy with any updates applied to it.
      def prepare_for_index(type_name, record)
        prepare_value_for_indexing(record, type_name)
      end

      private

      def prepare_value_for_indexing(value, type_name)
        type_name = type_name.delete_suffix("!")

        return nil if value.nil?

        if (preparer = @indexing_preparer_by_scalar_type_name[type_name])
          return (_ = preparer).prepare_for_indexing(value)
        end

        case value
        when ::Array
          element_type_name = type_name.delete_prefix("[").delete_suffix("]")
          value.map { |v| prepare_value_for_indexing(v, element_type_name) }
        when ::Hash
          # `@eg_meta_by_field_name_by_concrete_type` does not have abstract types in it (e.g. type unions).
          # Instead, it'll have each concrete subtype in it.
          #
          # If `type_name` is an abstract type, we need to look at the `__typename` field to see
          # what the concrete subtype is. `__typename` is required on abstract types and indicates that.
          eg_meta_by_field_name = @eg_meta_by_field_name_by_concrete_type.fetch(value["__typename"] || type_name)

          value.filter_map do |field_name, field_value|
            if field_name == "__typename"
              # We only want to include __typename if it we're dealing with a type that requires it.
              # (This is the case for an abstract type, so it can differentiate between which subtype we have
              [field_name, field_value] if @types_requiring_typename.include?(type_name)
            elsif (eg_meta = eg_meta_by_field_name[field_name])
              [eg_meta.fetch("nameInIndex"), prepare_value_for_indexing(field_value, eg_meta.fetch("type"))]
            end
          end.to_h
        else
          # We won't have a registered preparer for enum types, since those aren't dumped in
          # runtime metadata `scalar_types_by_name`, and we can just return the value as-is in
          # this case.
          value
        end
      end

      TypeMetadata = ::Data.define(
        # The name of the type this metadata object is for.
        :name,
        # Indicates if this type requires a `__typename` field.
        :requires_typename,
        # The per-field ElasticGraph metadata, keyed by field name.
        :eg_meta_by_field_name
      )
    end
  end
end

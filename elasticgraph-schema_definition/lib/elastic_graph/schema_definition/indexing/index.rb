# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/index_definition"
require "elastic_graph/schema_artifacts/runtime_metadata/index_field"
require "elastic_graph/schema_definition/indexing/derived_indexed_type"
require "elastic_graph/schema_definition/indexing/list_counts_mapping"
require "elastic_graph/schema_definition/indexing/rollover_config"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/field_path"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    # Contains schema definition logic specific to indexing (such as JSON schema and mapping generation).
    module Indexing
      # Represents an index in a datastore. Defined within an indexed type. Modeled as a separate object to facilitate
      # further customization of the index.
      #
      # @!attribute [r] name
      #   @return [String] name of the index
      # @!attribute [r] default_sort_pairs
      #   @return [Array<(String, Symbol)>] (field name, direction) pairs for the default sort
      # @!attribute [r] settings
      #   @return [Hash<(String, Object)>] datastore settings for the index
      # @!attribute [r] schema_def_state
      #   @return [State] schema definition state
      # @!attribute [r] indexed_type
      #   @return [SchemaElements::ObjectType, SchemaElements::InterfaceType, SchemaElements::UnionType] type backed by this index
      # @!attribute [r] routing_field_path
      #   @return [Array<String>] path to the field used for shard routing
      # @!attribute [r] rollover_config
      #   @return [RolloverConfig, nil] rollover configuration for the index
      class Index < Struct.new(:name, :default_sort_pairs, :settings, :schema_def_state, :indexed_type, :routing_field_path, :rollover_config)
        include Mixins::HasReadableToSAndInspect.new { |i| i.name }

        # @param name [String] name of the index
        # @param settings [Hash<(String, Object)>] datastore settings for the index
        # @param schema_def_state [State] schema definition state
        # @param indexed_type [SchemaElements::ObjectType, SchemaElements::InterfaceType, SchemaElements::UnionType] type backed by this index
        # @yield [Index] the index, for further customization
        # @api private
        def initialize(name, settings, schema_def_state, indexed_type)
          if name.include?(ROLLOVER_INDEX_INFIX_MARKER)
            raise Errors::SchemaError, "`#{name}` is an invalid index definition name since it contains " \
              "`#{ROLLOVER_INDEX_INFIX_MARKER}` which ElasticGraph treats as special."
          end

          settings = DEFAULT_SETTINGS.merge(Support::HashUtil.flatten_and_stringify_keys(settings, prefix: "index"))

          super(name, [], settings, schema_def_state, indexed_type, nil, nil)

          schema_def_state.after_user_definition_complete do
            # `id` is the field Elasticsearch/OpenSearch use for routing by default:
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-routing-field.html
            # By using it here, it will cause queries to pass a `routing` parameter when
            # searching with id filtering on an index that does not use custom shard routing, giving
            # us a nice efficiency boost.
            self.routing_field_path = public_field_path("id", explanation: "indexed types must have an `id` field")
          end

          yield self if block_given?
        end

        # Specifies how documents in this index should sort by default, when no `orderBy` argument is provided to the GraphQL query.
        #
        # @note the field name strings can be a dot-separated nested fields, but all referenced
        #   fields must exist when this is called.
        #
        # @param field_name_direction_pairs [Array<(String, Symbol)>] pairs of field names and `:asc` or `:desc`
        # @return [void]
        #
        # @example Sort on `name` (ascending) with `createdAt` (descending) as a tie-breaker
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.field "name", "String"
        #       t.field "createdAt", "DateTime"
        #
        #       t.index "campaigns"do |i|
        #         i.default_sort "name", :asc, "createdAt", :desc
        #       end
        #     end
        #   end
        def default_sort(*field_name_direction_pairs)
          self.default_sort_pairs = field_name_direction_pairs
        end

        # Causes this index to "rollover" at the provided `frequency` based on the value of the provided `timestamp_field_path_name`.
        # This is particularly useful for time-series data. Partitioning the data into `hourly`, `daily`, `monthly` or `yearly` buckets
        # allows for different index configurations, and can be necessary when a dataset is too large to fit in one dataset given
        # Elasticsearch/OpenSearch limitations on the number of shards in one index. In addition, ElasticGraph optimizes queries which
        # filter on the timestamp field to target the subset of the indices in which matching documents could reside.
        #
        # @note the timestamp field specified here **must be immutable**. To understand why, consider a `:yearly` rollover
        #   index used for data based on `createdAt`; if ElasticGraph ingests record `123` with a createdAt of `2023-12-31T23:59:59Z`, it
        #   will be indexed in the `2023` index. Later if it receives an update event for record `123` with a `createdAt` of
        #   `2024-01-01T00:00:00Z` (a mere one second later!), ElasticGraph will store the new version of the payment in the `2024` index,
        #   and leave the old copy of the payment in the `2023` index unchanged. It’ll have duplicates for that document.
        # @note changing the `rollover` configuration on an existing index that already has data will result in duplicate documents
        #
        # @param frequency [:yearly, :monthly, :daily, :hourly] how often to rollover the index
        # @param timestamp_field_path_name [String] dot-separated path to the timestamp field used for rollover. Note: all referenced
        #   fields must exist when this is called.
        # @return [void]
        #
        # @example Define a `campaigns` index to rollover yearly based on `createdAt`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.field "name", "String"
        #       t.field "createdAt", "DateTime"
        #
        #       t.index "campaigns"do |i|
        #         i.rollover :yearly, "createdAt"
        #       end
        #     end
        #   end
        def rollover(frequency, timestamp_field_path_name)
          schema_def_state.after_user_definition_complete do
            timestamp_field_path = public_field_path(timestamp_field_path_name, explanation: "it is referenced as an index `rollover` field")

            unless date_and_datetime_types.include?(timestamp_field_path.type.fully_unwrapped.name)
              date_or_datetime_description = date_and_datetime_types.map { |t| "`#{t}`" }.join(" or ")
              raise Errors::SchemaError, "rollover field `#{timestamp_field_path.full_description}` cannot be used for rollover since it is not a #{date_or_datetime_description} field."
            end

            if timestamp_field_path.type.list?
              raise Errors::SchemaError, "rollover field `#{timestamp_field_path.full_description}` cannot be used for rollover since it is a list field."
            end

            timestamp_field_path.path_parts.each { |f| f.json_schema nullable: false }

            self.rollover_config = RolloverConfig.new(
              frequency: frequency,
              timestamp_field_path: timestamp_field_path
            )
          end
        end

        # Configures the index to [route documents to shards](https://www.elastic.co/guide/en/elasticsearch/reference/8.15/mapping-routing-field.html)
        # based on the specified field. ElasticGraph optimizes queries that filter on the shard routing field so that they only run on a
        # subset of nodes instead of all nodes. This can make a big difference in query performance if queries usually filter on a certain
        # field. Using an appropriate field for shard routing is often essential for horizontal scaling, as it avoids having every query
        # hit every node, allowing additional nodes to increase query throughput.
        #
        # @note it is essential that the shards are well-balanced. If the data’s distribution is lopsided, using this feature can make
        #   performance worse.
        # @note the routing field specified here **must be immutable**. If ElasticGraph receives an updated version of a document with a
        #   different routing value, it’ll write the new version of the document to a different shard and leave the copy on the old shard
        #   unchanged, leading to duplicates.
        # @note changing the shard routing configuration on an existing index that already has data will result in duplicate documents
        #
        # @param routing_field_path_name [String] dot-separated path to the field used for shard routing. Note: all referenced
        #   fields must exist when this is called.
        # @return [void]
        #
        # @example Define a `campaigns` index to shard on `organizationId`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.field "name", "String"
        #       t.field "organizationId", "ID"
        #
        #       t.index "campaigns"do |i|
        #         i.route_with "organizationId"
        #       end
        #     end
        #   end
        def route_with(routing_field_path_name)
          schema_def_state.after_user_definition_complete do
            routing_field_path = public_field_path(routing_field_path_name, explanation: "it is referenced as an index `route_with` field")

            unless routing_field_path.type.leaf?
              raise Errors::SchemaError, "shard routing field `#{routing_field_path.full_description}` cannot be used for routing since it is not a leaf field."
            end

            self.routing_field_path = routing_field_path

            routing_field_path.path_parts[0..-2].each { |f| f.json_schema nullable: false }
            routing_field_path.last_part.json_schema nullable: false, pattern: HAS_NON_WHITE_SPACE_REGEX
            indexed_type.append_to_documentation "For more performant queries on this type, please filter on `#{routing_field_path_name}` if possible."
          end
        end

        # @see #route_with
        # @return [Boolean] whether or not this index uses custom shard routing
        def uses_custom_routing?
          routing_field_path.path_in_index != "id"
        end

        # @return [Hash<String, Object>] datastore configuration for this index for when it does not use rollover
        def to_index_config
          {
            "aliases" => {},
            "mappings" => mappings,
            "settings" => settings
          }.compact
        end

        # @return [Hash<String, Object>] datastore configuration for the index template that will be defined if rollover is used
        def to_index_template_config
          {
            "index_patterns" => ["#{name}#{ROLLOVER_INDEX_INFIX_MARKER}*"],
            "template" => {
              "aliases" => {},
              "mappings" => mappings,
              "settings" => settings
            }
          }
        end

        # @return [SchemaArtifacts::RuntimeMetadata::IndexDefinition] runtime metadata for this index
        def runtime_metadata
          SchemaArtifacts::RuntimeMetadata::IndexDefinition.new(
            route_with: routing_field_path.path_in_index,
            rollover: rollover_config&.runtime_metadata,
            current_sources: indexed_type.current_sources,
            fields_by_path: indexed_type.index_field_runtime_metadata_tuples.to_h,
            default_sort_fields: default_sort_pairs.each_slice(2).map do |(graphql_field_path_name, direction)|
              SchemaArtifacts::RuntimeMetadata::SortField.new(
                field_path: public_field_path(graphql_field_path_name, explanation: "it is referenced as an index `default_sort` field").path_in_index,
                direction: direction
              )
            end
          )
        end

        private

        # A regex that requires at least one non-whitespace character.
        # Note: this does not use the `/S` character class because it's recommended to use a small subset
        # of Regex syntax:
        #
        # > The regular expression syntax used is from JavaScript (ECMA 262, specifically). However, that
        # > complete syntax is not widely supported, therefore it is recommended that you stick to the subset
        # > of that syntax described below.
        #
        # (From https://json-schema.org/understanding-json-schema/reference/regular_expressions.html)
        HAS_NON_WHITE_SPACE_REGEX = "[^ \t\n]+"

        DEFAULT_SETTINGS = {
          "index.mapping.ignore_malformed" => false,
          "index.mapping.coerce" => false,
          "index.number_of_replicas" => 1,
          "index.number_of_shards" => 1
        }

        def mappings
          field_mappings = indexed_type
            .to_indexing_field_type
            .to_mapping
            .except("type") # `type` is invalid at the mapping root because it always has to be an object.
            .then { |mapping| ListCountsMapping.merged_into(mapping, for_type: indexed_type) }
            .then do |fm|
              Support::HashUtil.deep_merge(fm, {"properties" => {
                "__sources" => {"type" => "keyword"},
                "__versions" => {
                  "type" => "object",
                  # __versions is map keyed by relationship name, with values that are maps keyed by id. Since it's not
                  # a static object with known fields, we need to use dynamic here. Passing `false` allows some level
                  # of dynamicness. As per https://www.elastic.co/guide/en/elasticsearch/reference/8.7/dynamic.html#dynamic-parameters:
                  #
                  # > New fields are ignored. These fields will not be indexed or searchable, but will still appear in the _source
                  # > field of returned hits. These fields will not be added to the mapping, and new fields must be added explicitly.
                  #
                  # We need `__versions` to be in `_source` (so that our update scripts can operate on it), but
                  # have no need for it to be searchable (as it's just an internal data structure used for indexing).
                  #
                  # Note: we intentionally set false as a string here, because that's how the datastore echoes it back
                  # to us when you query the mapping (even if you set it as a boolean). Our checks for index mapping
                  # consistency fail validation if we set it as a boolean since the datastore doesn't echo it back as
                  # a boolean.
                  "dynamic" => "false"
                }
              }})
            end

          {"dynamic" => "strict"}.merge(field_mappings).tap do |hash|
            # If we are using custom shard routing, we want to require a `routing` value to be provided
            # in every single index, get, delete or update request; otherwise the request might be
            # made against the wrong shard.
            hash["_routing"] = {"required" => true} if uses_custom_routing?
            hash["_size"] = {"enabled" => true} if schema_def_state.index_document_sizes?
          end
        end

        def public_field_path(public_path_string, explanation:)
          parent_is_not_list = ->(parent_field) { !parent_field.type.list? }
          resolver = schema_def_state.field_path_resolver
          resolved_path = resolver.resolve_public_path(indexed_type, public_path_string, &parent_is_not_list)
          return resolved_path if resolved_path

          path_parts = public_path_string.split(".")
          error_msg = "Field `#{indexed_type.name}.#{public_path_string}` cannot be resolved, but #{explanation}."

          # If it is a nested field path, the problem could be that a type has been referenced which does not exist, so mention that.
          if path_parts.size > 1
            error_msg += " Verify that all fields and types referenced by `#{public_path_string}` are defined."
          end

          # If the first part of the path doesn't resolve, the problem could be that the field is defined after the `index` call
          # but it needs to be defined before it, so mention that.
          if resolver.resolve_public_path(indexed_type, path_parts.first, &parent_is_not_list).nil?
            error_msg += " Note: the `#{indexed_type.name}.#{path_parts.first}` definition must come before the `index` call."
          end

          raise Errors::SchemaError, error_msg
        end

        def date_and_datetime_types
          @date_and_datetime_types ||= %w[Date DateTime].map do |type|
            schema_def_state.type_namer.name_for(type)
          end
        end
      end
    end
  end
end

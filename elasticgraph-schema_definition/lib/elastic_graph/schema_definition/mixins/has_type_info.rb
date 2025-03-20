# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_schema/meta_schema_validator"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Mixin used to specify non-GraphQL type info (datastore index and JSON schema type info).
      # Exists as a mixin so we can apply the same consistent API to every place we need to use this.
      # Currently it's used in 3 places:
      #
      # - {SchemaElements::ScalarType}: allows specification of how scalars are represented in JSON schema and the index.
      # - {SchemaElements::TypeWithSubfields}: allows customization of how an object type is represented in JSON schema and the index.
      # - {SchemaElements::Field}: allows customization of a specific field over the field type's standard JSON schema and the index mapping.
      module HasTypeInfo
        # @return [Hash<Symbol, Object>] datastore mapping options
        def mapping_options
          @mapping_options ||= {}
        end

        # @return [Hash<Symbol, Object>] JSON schema options
        def json_schema_options
          @json_schema_options ||= {}
        end

        # Set of mapping parameters that it makes sense to allow customization of, based on
        # [the Elasticsearch docs](https://www.elastic.co/guide/en/elasticsearch/reference/8.15/mapping-params.html).
        CUSTOMIZABLE_DATASTORE_PARAMS = Set[
          :analyzer,
          :eager_global_ordinals,
          :enabled,
          :fields,
          :format,
          :index,
          :meta, # not actually in the doc above. Added to support some `index_configurator` tests on 7.9+.
          :norms,
          :null_value,
          :search_analyzer,
          :type,
        ]

        # Defines the Elasticsearch/OpenSearch [field mapping type](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/mapping-types.html)
        # and [mapping parameters](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/mapping-params.html) for a field or type.
        # The options passed here will be included in the generated `datastore_config.yaml` artifact that ElasticGraph uses to configure
        # Elasticsearch/OpenSearch.
        #
        # Can be called multiple times; each time, the options will be merged into the existing options.
        #
        # This is required on a {SchemaElements::ScalarType}; without it, ElasticGraph would have no way to know how the datatype should be
        # indexed in the datastore.
        #
        # On a {SchemaElements::Field}, this can be used to customize how a field is indexed. For example, `String` fields are normally
        # indexed as [keywords](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/keyword.html); to instead index a `String`
        # field for full text search, you’d need to configure `mapping type: "text"`.
        #
        # On a {SchemaElements::ObjectType}, this can be used to use a specific Elasticsearch/OpenSearch data type for something that is
        # modeled as an object in GraphQL. For example, we use it for the `GeoLocation` type so they get indexed in Elasticsearch using the
        # [geo_point type](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/geo-point.html).
        #
        # @param options [Hash<Symbol, Object>] mapping options--must be limited to {CUSTOMIZABLE_DATASTORE_PARAMS}
        # @return [void]
        #
        # @example Define the mapping of a custom scalar type
        #   ElasticGraph.define_schema do |schema|
        #     schema.scalar_type "URL" do |t|
        #       t.mapping type: "keyword"
        #       t.json_schema type: "string", format: "uri"
        #     end
        #   end
        #
        # @example Customize the mapping of a field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Card" do |t|
        #       t.field "id", "ID!"
        #
        #       t.field "cardholderName", "String" do |f|
        #         # index this field for full text search
        #         f.mapping type: "text"
        #       end
        #
        #       t.field "expYear", "Int" do |f|
        #         # Use a smaller numeric type to save space in the datastore
        #         f.mapping type: "short"
        #         f.json_schema minimum: 2000, maximum: 2099
        #       end
        #
        #       t.field "expMonth", "Int" do |f|
        #         # Use a smaller numeric type to save space in the datastore
        #         f.mapping type: "byte"
        #         f.json_schema minimum: 1, maximum: 12
        #       end
        #
        #       t.index "cards"
        #     end
        #   end
        def mapping(**options)
          param_diff = (options.keys.to_set - CUSTOMIZABLE_DATASTORE_PARAMS).to_a

          unless param_diff.empty?
            raise Errors::SchemaError, "Some configured mapping overrides are unsupported: #{param_diff.inspect}"
          end

          mapping_options.update(options)
        end

        # Defines the [JSON schema](https://json-schema.org/understanding-json-schema/) validations for this field or type. Validations
        # defined here will be included in the generated `json_schemas.yaml` artifact, which is used by the ElasticGraph indexer to
        # validate events before indexing their data in the datastore. In addition, the publisher may use `json_schemas.yaml` for code
        # generation and to apply validation before publishing an event to ElasticGraph.
        #
        # Can be called multiple times; each time, the options will be merged into the existing options.
        #
        # This is _required_ on a {SchemaElements::ScalarType} (since we don’t know how a custom scalar type should be represented in
        # JSON!). On a {SchemaElements::Field}, this is optional, but can be used to make the JSON schema validation stricter then it
        # would otherwise be. For example, you could use `json_schema maxLength: 30` on a `String` field to limit the length.
        #
        # You can use any of the JSON schema validation keywords here. In addition, `nullable: false` is supported to configure the
        # generated JSON schema to disallow `null` values for the field. Note that if you define a field with a non-nullable GraphQL type
        # (e.g. `Int!`), the JSON schema will automatically disallow nulls. However, as explained in the
        # {SchemaElements::TypeWithSubfields#field} documentation, we generally recommend against defining non-nullable GraphQL fields.
        # `json_schema nullable: false` will disallow `null` values from being indexed, while still keeping the field nullable in the
        # GraphQL schema. If you think you might want to make a field non-nullable in the GraphQL schema some day, it’s a good idea to use
        # `json_schema nullable: false` now to ensure every indexed record has a non-null value for the field.
        #
        # @note We recommend using JSON schema validations in a limited fashion. Validations that are appropriate to apply when data is
        #   entering the system-of-record are often not appropriate on a secondary index like ElasticGraph. Events that violate a JSON
        #   schema validation will fail to index (typically they will be sent to the dead letter queue and page an oncall engineer). If an
        #   ElasticGraph instance is meant to contain all the data of some source system, you probably don’t want it applying stricter
        #   validations than the source system itself has. We recommend limiting your JSON schema validations to situations where
        #   violations would prevent ElasticGraph from operating correctly.
        #
        # @param options [Hash<Symbol, Object>] JSON schema options
        # @return [void]
        #
        # @example Define the JSON schema validations of a custom scalar type
        #   ElasticGraph.define_schema do |schema|
        #     schema.scalar_type "URL" do |t|
        #       t.mapping type: "keyword"
        #
        #       # JSON schema has a built-in URI format validator:
        #       # https://json-schema.org/understanding-json-schema/reference/string.html#resource-identifiers
        #       t.json_schema type: "string", format: "uri"
        #     end
        #   end
        #
        # @example Define additional validations on a field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Card" do |t|
        #       t.field "id", "ID!"
        #
        #       t.field "expYear", "Int" do |f|
        #         # Use JSON schema to ensure the publisher is sending us 4 digit years, not 2 digit years.
        #         f.json_schema minimum: 2000, maximum: 2099
        #       end
        #
        #       t.field "expMonth", "Int" do |f|
        #         f.json_schema minimum: 1, maximum: 12
        #       end
        #
        #       t.index "cards"
        #     end
        #   end
        def json_schema(**options)
          validatable_json_schema = Support::HashUtil.stringify_keys(options)

          if (error_msg = JSONSchema.strict_meta_schema_validator.validate_with_error_message(validatable_json_schema))
            raise Errors::SchemaError, "Invalid JSON schema options set on #{self}:\n\n#{error_msg}"
          end

          json_schema_options.update(options)
        end
      end
    end
  end
end

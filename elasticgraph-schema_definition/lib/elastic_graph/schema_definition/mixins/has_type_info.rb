# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Mixin used to specify non-GraphQL type info on schema elements.
      # Exists as a mixin so we can apply the same consistent API to every place we need to use this.
      # Currently it's used in 3 places:
      #
      # - {SchemaElements::ScalarType}: allows specification of how scalars are represented in the datastore index.
      # - {SchemaElements::TypeWithSubfields}: allows customization of how an object type is represented in the datastore index.
      # - {SchemaElements::Field}: allows customization of a specific field over the field type's standard index mapping.
      module HasTypeInfo
        # @return [Hash<Symbol, Object>] datastore mapping options
        def mapping_options
          @mapping_options ||= {}
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
          :type
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
        #       t.json_schema type: "string"
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
      end
    end
  end
end

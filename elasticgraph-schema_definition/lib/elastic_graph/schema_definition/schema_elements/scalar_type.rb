# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/scalar_type"
require "elastic_graph/schema_definition/indexing/field_type/scalar"
require "elastic_graph/schema_definition/warehouse_config/field_type/scalar"
require "elastic_graph/schema_definition/mixins/can_be_graphql_only"
require "elastic_graph/schema_definition/mixins/has_derived_graphql_type_customizations"
require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/has_type_info"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#scalar_type}
      #
      # @example Define a scalar type
      #   ElasticGraph.define_schema do |schema|
      #     schema.scalar_type "URL" do |t|
      #       t.mapping type: "keyword"
      #       t.json_schema type: "string", format: "uri"
      #     end
      #   end
      #
      # @!attribute [r] schema_def_state
      #   @return [State] schema definition state
      # @!attribute [rw] type_ref
      #   @private
      # @!attribute [rw] mapping_type
      #   @private
      # @!attribute [rw] runtime_metadata
      #   @private
      # @!attribute [rw] aggregated_values_customizations
      #   @private
      # @!attribute [rw] filter_input_customizations
      #   @private
      class ScalarType < Struct.new(
        :schema_def_state,
        :type_ref,
        :mapping_type,
        :runtime_metadata,
        :aggregated_values_customizations,
        :filter_input_customizations
      )
        # `Struct.new` provides the following methods:
        # @dynamic type_ref, runtime_metadata
        prepend Mixins::VerifiesGraphQLName
        include Mixins::CanBeGraphQLOnly
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasDerivedGraphQLTypeCustomizations
        include Mixins::HasReadableToSAndInspect.new { |t| t.name }

        # `HasTypeInfo` provides the following methods:
        # @dynamic mapping_options, json_schema_options
        include Mixins::HasTypeInfo

        # @dynamic graphql_only?

        # @private
        def initialize(schema_def_state, name)
          super(schema_def_state, schema_def_state.type_ref(name).to_final_form)

          # Default the runtime metadata before yielding, so it can be overridden as needed.
          self.runtime_metadata = SchemaArtifacts::RuntimeMetadata::ScalarType.new(
            coercion_adapter_ref: SchemaArtifacts::RuntimeMetadata::ScalarType::DEFAULT_COERCION_ADAPTER_REF,
            indexing_preparer_ref: SchemaArtifacts::RuntimeMetadata::ScalarType::DEFAULT_INDEXING_PREPARER_REF
          )

          yield self

          missing = [
            ("`mapping`" if mapping_options.empty?),
            ("`json_schema`" if json_schema_options.empty?)
          ].compact

          if missing.any?
            raise Errors::SchemaError, "Scalar types require `mapping` and `json_schema` to be configured, but `#{name}` lacks #{missing.join(" and ")}."
          end
        end

        # @return [String] name of the scalar type
        def name
          type_ref.name
        end

        # (see Mixins::HasTypeInfo#mapping)
        def mapping(**options)
          self.mapping_type = options.fetch(:type) do
            raise Errors::SchemaError, "Must specify a mapping `type:` on custom scalars but was missing on the `#{name}` type."
          end

          super
        end

        # Specifies the scalar coercion adapter that should be used for this scalar type. The scalar coercion adapter is responsible
        # for validating and coercing scalar input values, and converting scalar return values to a form suitable for JSON serialization.
        #
        # @note For examples of scalar coercion adapters, see `ElasticGraph::GraphQL::ScalarCoercionAdapters`.
        # @note If the `defined_at` require path requires any directories be put on the Ruby `$LOAD_PATH`, you are responsible for doing
        #   that before booting {ElasticGraph::GraphQL}.
        #
        # @param adapter_name [String] fully qualified Ruby class name of the adapter
        # @param defined_at [String] the `require` path of the adapter
        # @return [void]
        #
        # @example Register a coercion adapter
        #   ElasticGraph.define_schema do |schema|
        #     schema.scalar_type "PhoneNumber" do |t|
        #       t.mapping type: "keyword"
        #       t.json_schema type: "string", pattern: "^\\+[1-9][0-9]{1,14}$"
        #       t.coerce_with "CoercionAdapters::PhoneNumber", defined_at: "./coercion_adapters/phone_number"
        #     end
        #   end
        def coerce_with(adapter_name, defined_at:)
          self.runtime_metadata = runtime_metadata.with(coercion_adapter_ref: {
            "name" => adapter_name,
            "require_path" => defined_at
          }).tap(&:load_coercion_adapter) # verify the adapter is valid.
        end

        # Specifies an indexing preparer that should be used for this scalar type. The indexing preparer is responsible for preparing
        # scalar values before indexing them, performing any desired formatting or normalization.
        #
        # @note For examples of scalar coercion adapters, see `ElasticGraph::Indexer::IndexingPreparers`.
        # @note If the `defined_at` require path requires any directories be put on the Ruby `$LOAD_PATH`, you are responsible for doing
        #   that before booting {ElasticGraph::GraphQL}.
        #
        # @param preparer_name [String] fully qualified Ruby class name of the indexing preparer
        # @param defined_at [String] the `require` path of the preparer
        # @return [void]
        #
        # @example Register an indexing preparer
        #   ElasticGraph.define_schema do |schema|
        #     schema.scalar_type "PhoneNumber" do |t|
        #       t.mapping type: "keyword"
        #       t.json_schema type: "string", pattern: "^\\+[1-9][0-9]{1,14}$"
        #
        #       t.prepare_for_indexing_with "IndexingPreparers::PhoneNumber",
        #         defined_at: "./indexing_preparers/phone_number"
        #     end
        #   end
        def prepare_for_indexing_with(preparer_name, defined_at:)
          self.runtime_metadata = runtime_metadata.with(indexing_preparer_ref: {
            "name" => preparer_name,
            "require_path" => defined_at
          }).tap(&:load_indexing_preparer) # verify the preparer is valid.
        end

        # @return [String] the GraphQL SDL form of this scalar
        def to_sdl
          "#{formatted_documentation}scalar #{name} #{directives_sdl}"
        end

        # Registers a block which will be used to customize the derived `*AggregatedValues` object type.
        #
        # @private
        def customize_aggregated_values_type(&block)
          self.aggregated_values_customizations = block
        end

        # Registers a block which will be used to customize the derived `*FilterInput` object type.
        #
        # @private
        def customize_filter_input_type(&block)
          self.filter_input_customizations = block
        end

        # @private
        def aggregated_values_type
          if aggregated_values_customizations
            type_ref.as_aggregated_values
          else
            schema_def_state.type_ref("NonNumeric").as_aggregated_values
          end
        end

        # @private
        def to_indexing_field_type
          Indexing::FieldType::Scalar.new(scalar_type: self)
        end

        def to_warehouse_field_type
          WarehouseConfig::FieldType::Scalar.new(scalar_type: self)
        end

        # @private
        def derived_graphql_types
          return [] if graphql_only?

          pagination_types =
            if schema_def_state.paginated_collection_element_types.include?(name)
              schema_def_state.factory.build_relay_pagination_types(name, include_total_edge_count: true)
            else
              [] # : ::Array[ObjectType]
            end

          (to_input_filters + pagination_types).tap do |derived_types|
            if (aggregated_values_type = to_aggregated_values_type)
              derived_types << aggregated_values_type
            end
          end
        end

        # @private
        def indexed?
          false
        end

        private

        EQUAL_TO_ANY_OF_DOC = <<~EOS
          Matches records where the field value is equal to any of the provided values.
          This works just like an IN operator in SQL.

          When `null` is passed, matches all documents. When an empty list is passed,
          this part of the filter matches no documents. When `null` is passed in the
          list, this part of the filter matches records where the field value is `null`.
        EOS

        GT_DOC = <<~EOS
          Matches records where the field value is greater than (>) the provided value.

          When `null` is passed, matches all documents.
        EOS

        GTE_DOC = <<~EOS
          Matches records where the field value is greater than or equal to (>=) the provided value.

          When `null` is passed, matches all documents.
        EOS

        LT_DOC = <<~EOS
          Matches records where the field value is less than (<) the provided value.

          When `null` is passed, matches all documents.
        EOS

        LTE_DOC = <<~EOS
          Matches records where the field value is less than or equal to (<=) the provided value.

          When `null` is passed, matches all documents.
        EOS

        def to_input_filters
          # Note: all fields on inputs should be nullable, to support parameterized queries where
          # the parameters are allowed to be set to `null`. We also now support nulls within lists.

          # For floats, we may want to remove the `equal_to_any_of` operator at some point.
          # In many languages. checking exact equality with floats is problematic.
          # For example, in IRB:
          #
          # 2.7.1 :003 > 0.3 == (0.1 + 0.2)
          # => false
          #
          # However, it's not yet clear if that issue will come up with GraphQL, because
          # float values are serialized on the wire as JSON, using an exact decimal
          # string representation. So for now we are keeping `equal_to_any_of`.
          schema_def_state.factory.build_standard_filter_input_types_for_index_leaf_type(name) do |t|
            # Normally, we use a nullable type for `equal_to_any_of`, to allow a filter expression like this:
            #
            # filter: {optional_field: {equal_to_any_of: [null]}}
            #
            # That filter expression matches documents where `optional_field == null`. However,
            # we cannot support this:
            #
            # filter: {tags: {any_satisfy: {equal_to_any_of: [null]}}}
            #
            # We can't support that because we implement filtering on `null` using an `exists` query:
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.10/query-dsl-exists-query.html
            #
            # ...but that works based on the field existing (or not), and does not let us filter on the
            # presence or absence of `null` within a list.
            #
            # So, here we make the field non-null if we're in an `any_satisfy` context (as indicated by
            # the type ending with `ListElementFilterInput`).
            equal_to_any_of_type = t.type_ref.list_element_filter_input? ? "[#{name}!]" : "[#{name}]"

            t.field schema_def_state.schema_elements.equal_to_any_of, equal_to_any_of_type do |f|
              f.documentation EQUAL_TO_ANY_OF_DOC
            end

            if mapping_type_efficiently_comparable?
              t.field schema_def_state.schema_elements.gt, name do |f|
                f.documentation GT_DOC
              end

              t.field schema_def_state.schema_elements.gte, name do |f|
                f.documentation GTE_DOC
              end

              t.field schema_def_state.schema_elements.lt, name do |f|
                f.documentation LT_DOC
              end

              t.field schema_def_state.schema_elements.lte, name do |f|
                f.documentation LTE_DOC
              end
            end

            filter_input_customizations&.call(t)
          end
        end

        def to_aggregated_values_type
          return nil unless (customization_block = aggregated_values_customizations)
          schema_def_state.factory.new_aggregated_values_type_for_index_leaf_type(name, &customization_block)
        end

        # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html
        # https://www.elastic.co/guide/en/elasticsearch/reference/7.13/number.html#number
        NUMERIC_TYPES = %w[long integer short byte double float half_float scaled_float unsigned_long].to_set
        DATE_TYPES = %w[date date_nanos].to_set
        # The Elasticsearch/OpenSearch docs do not exhaustively give a list of types on which range queries are efficient,
        # but the docs are clear that it is efficient on numeric and date types, and is inefficient on string
        # types: https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-range-query.html
        COMPARABLE_TYPES = NUMERIC_TYPES | DATE_TYPES

        def mapping_type_efficiently_comparable?
          COMPARABLE_TYPES.include?(mapping_type)
        end
      end
    end
  end
end

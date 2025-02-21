# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Responsible for enumerating the SDL strings for all GraphQL types, both explicitly defined and derived.
      #
      # @private
      class GraphQLSDLEnumerator
        include ::Enumerable
        # @dynamic schema_def_state
        attr_reader :schema_def_state

        def initialize(schema_def_state, all_types_except_root_query_type)
          @schema_def_state = schema_def_state
          @all_types_except_root_query_type = all_types_except_root_query_type
        end

        # Yields the SDL for each GraphQL type, including both explicitly defined
        # GraphQL types and derived GraphqL types.
        def each(&block)
          all_types = enumerate_all_types.sort_by(&:name)
          all_type_names = all_types.map(&:name).to_set

          all_types.each do |type|
            next if STOCK_GRAPHQL_SCALARS.include?(type.name)
            yield type.to_sdl { |arg| all_type_names.include?(arg.value_type.fully_unwrapped.name) }
          end
        end

        private

        def enumerate_all_types
          [root_query_type].compact + @all_types_except_root_query_type
        end

        def aggregation_efficiency_hints_for(derived_indexed_types)
          return nil if derived_indexed_types.empty?

          hints = derived_indexed_types.map do |type|
            derived_indexing_type = @schema_def_state.types_by_name.fetch(type.destination_type_ref.name)
            alternate_field_name = (_ = derived_indexing_type).plural_root_query_field_name
            grouping_field = type.id_source

            "  - The root `#{alternate_field_name}` field groups by `#{grouping_field}`"
          end

          <<~EOS
            Note: aggregation queries are relatively expensive, and some fields have been pre-aggregated to allow
            more efficient queries for some common aggregation cases:

            #{hints.join("\n")}
          EOS
        end

        def root_query_type
          # Some of our tests need to define their own root `Query` type, so here we avoid
          # generating `Query` if an sdl part exists that already defines it.
          return nil if @schema_def_state.sdl_parts.flat_map { |sdl| sdl.lines }.any? { |line| line.start_with?("type Query") }

          new_built_in_object_type "Query" do |t|
            t.documentation "The query entry point for the entire schema."

            @schema_def_state.types_by_name.values.select(&:indexed?).sort_by(&:name).each do |type|
              # @type var indexed_type: Mixins::HasIndices & _Type
              indexed_type = _ = type

              t.relates_to_many(
                indexed_type.plural_root_query_field_name,
                indexed_type.name,
                via: "ignore",
                dir: :in,
                singular: indexed_type.singular_root_query_field_name
              ) do |f|
                f.documentation "Fetches `#{indexed_type.name}`s based on the provided arguments."
                indexed_type.root_query_fields_customizations.each do |customization|
                  customization.call(f)
                end
              end

              # Add additional efficiency hints to the aggregation field documentation if we have any such hints.
              # This needs to be outside the `relates_to_many` block because `relates_to_many` adds its own "suffix" to
              # the field documentation, and here we add another one.
              if (agg_efficiency_hint = aggregation_efficiency_hints_for(indexed_type.derived_indexed_types))
                agg_name = @schema_def_state.schema_elements.normalize_case("#{indexed_type.singular_root_query_field_name}_aggregations")
                agg_field = t.graphql_fields_by_name.fetch(agg_name)
                agg_field.documentation "#{agg_field.doc_comment}\n\n#{agg_efficiency_hint}"
              end
            end
          end
        end

        def new_built_in_object_type(name, &block)
          new_object_type name do |type|
            @schema_def_state.built_in_types_customization_blocks.each do |customization_block|
              customization_block.call(type)
            end

            block.call(type)
          end
        end

        def new_object_type(name, &block)
          @schema_def_state.factory.new_object_type(name, &block)
        end
      end
    end
  end
end

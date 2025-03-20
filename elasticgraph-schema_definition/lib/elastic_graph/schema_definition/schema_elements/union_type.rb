# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/index"
require "elastic_graph/schema_definition/mixins/can_be_graphql_only"
require "elastic_graph/schema_definition/mixins/has_derived_graphql_type_customizations"
require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_indices"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/has_subtypes"
require "elastic_graph/schema_definition/mixins/supports_filtering_and_aggregation"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#union_type}
      #
      # @example Define a union type
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Card" do |t|
      #       # ...
      #     end
      #
      #     schema.object_type "BankAccount" do |t|
      #       # ...
      #     end
      #
      #     schema.object_type "BitcoinWallet" do |t|
      #       # ...
      #     end
      #
      #     schema.union_type "FundingSource" do |t|
      #       t.subtype "Card"
      #       t.subtypes "BankAccount", "BitcoinWallet"
      #     end
      #   end
      #
      # @!attribute [r] schema_def_state
      #   @return [State] state of the schema
      # @!attribute [rw] type_ref
      #   @private
      # @!attribute [rw] subtype_refs
      #   @private
      class UnionType < Struct.new(:schema_def_state, :type_ref, :subtype_refs)
        prepend Mixins::VerifiesGraphQLName
        include Mixins::CanBeGraphQLOnly
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::SupportsFilteringAndAggregation
        include Mixins::HasIndices
        include Mixins::HasSubtypes
        include Mixins::HasDerivedGraphQLTypeCustomizations
        include Mixins::HasReadableToSAndInspect.new { |t| t.name }

        # @private
        def initialize(schema_def_state, name)
          super(schema_def_state, schema_def_state.type_ref(name).to_final_form, Set.new) do
            yield self
          end
        end

        # @return [String] the name of the union type
        def name
          type_ref.name
        end

        # Defines a subtype of this union type.
        #
        # @param name [String] the name of an object type which is a member of this union type
        # @return [void]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Card" do |t|
        #       # ...
        #     end
        #
        #     schema.union_type "FundingSource" do |t|
        #       t.subtype "Card"
        #     end
        #   end
        def subtype(name)
          type_ref = schema_def_state.type_ref(name.to_s).to_final_form

          if subtype_refs.include?(type_ref)
            raise Errors::SchemaError, "Duplicate subtype on UnionType #{self.name}: #{name}"
          end

          subtype_refs << type_ref
        end

        # Defines multiple subtypes of this union type.
        #
        # @param names [Array<String>] names of object types which are members of this union type
        # @return [void]
        #
        # @example Define a union type
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "BankAccount" do |t|
        #       # ...
        #     end
        #
        #     schema.object_type "BitcoinWallet" do |t|
        #       # ...
        #     end
        #
        #     schema.union_type "FundingSource" do |t|
        #       t.subtypes "BankAccount", "BitcoinWallet"
        #     end
        #   end
        def subtypes(*names)
          names.flatten.each { |n| subtype(n) }
        end

        # @return [String] the formatted GraphQL SDL of the union type
        def to_sdl
          if subtype_refs.empty?
            raise Errors::SchemaError, "UnionType type #{name} has no subtypes, but must have at least one."
          end

          "#{formatted_documentation}union #{name} #{directives_sdl(suffix_with: " ")}= #{subtype_refs.map(&:name).to_a.join(" | ")}"
        end

        # @private
        def verify_graphql_correctness!
          # Nothing to verify. `verify_graphql_correctness!` will be called on each subtype automatically.
        end

        # Various things check `mapping_options` on indexed types (usually object types, but can also happen on union types).
        # We need to implement `mapping_options` here to satisfy those method calls, but we will never use custom mapping on
        # a union type so we hardcode it to return nil.
        #
        # @private
        def mapping_options
          {}
        end

        private

        def resolve_subtypes
          subtype_refs.map do |ref|
            ref.as_object_type || raise(
              Errors::SchemaError, "The subtype `#{ref}` of the UnionType `#{name}` is not a defined object type."
            )
          end
        end
      end
    end
  end
end

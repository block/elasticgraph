# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"
require "elastic_graph/errors"
require "elastic_graph/spec_support/example_extensions/graphql_resolvers"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #graphql_resolvers_by_name" do
      include_context "RuntimeMetadata support"

      it "includes the standard ElasticGraph resolvers" do
        result = graphql_resolvers_by_name

        expect(result.keys).to contain_exactly(
          :get_record_field_value,
          :list_records,
          :nested_relationships,
          :object_with_lookahead,
          :object_without_lookahead
        )
      end

      it "includes a registered `needs_lookahead: true` custom resolver when a field is defined that uses the resolver" do
        result = graphql_resolvers_by_name do |schema|
          schema.register_graphql_resolver :resolver1,
            GraphQLResolverWithLookahead,
            defined_at: "elastic_graph/spec_support/example_extensions/graphql_resolvers",
            param: 15

          schema.on_root_query_type do |t|
            t.field "foo", "Int" do |f|
              f.resolver = :resolver1
            end
          end
        end

        expect(result.fetch(:resolver1)).to eq(
          graphql_resolver_with(
            needs_lookahead: true,
            resolver_ref: graphql_resolver_with_lookahead(param: 15).to_dumpable_hash
          )
        )
      end

      it "includes a registered `needs_lookahead: false` custom resolver when a field is defined that uses the resolver" do
        result = graphql_resolvers_by_name do |schema|
          schema.register_graphql_resolver :resolver1,
            GraphQLResolverWithoutLookahead,
            defined_at: "elastic_graph/spec_support/example_extensions/graphql_resolvers",
            param: 15

          schema.on_root_query_type do |t|
            t.field "foo", "Int" do |f|
              f.resolver = :resolver1
            end
          end
        end

        expect(result.fetch(:resolver1)).to eq(
          graphql_resolver_with(
            needs_lookahead: false,
            resolver_ref: graphql_resolver_without_lookahead(param: 15).to_dumpable_hash
          )
        )
      end

      it "verifies the registered resolver to confirm it confirms to the resolver interface" do
        expect {
          graphql_resolvers_by_name do |schema|
            schema.register_graphql_resolver :missing_args,
              MissingArgumentsResolver,
              defined_at: "elastic_graph/spec_support/example_extensions/graphql_resolvers"
          end
        }.to raise_error Errors::InvalidExtensionError
      end

      it "verifies that all referenced resolvers exist" do
        expect {
          graphql_resolvers_by_name do |schema|
            schema.on_root_query_type do |t|
              t.field "foo1", "Int" do |f|
                f.resolver = :resolver1
              end

              t.field "foo2", "Int" do |f|
                f.resolver = :get_record_field_value
              end

              t.field "foo3", "Int" do |f|
                f.resolver = :resolver1
              end
            end

            schema.object_type "MyType" do |t|
              t.field "bar", "Int" do |f|
                f.resolver = :resolver2
              end
            end
          end
        }.to raise_error Errors::SchemaError do |error|
          expect(error.message).to eq <<~EOS
            GraphQL resolver `:resolver1` is unregistered but is assigned to 2 field(s):

              - Query.foo1
              - Query.foo3

            GraphQL resolver `:resolver2` is unregistered but is assigned to 1 field(s):

              - MyType.bar

            To continue, register the named resolvers with `schema.register_graphql_resolver`
            or update the fields listed above to use one of the other registered resolvers:

              - :get_record_field_value
              - :list_records
              - :nested_relationships
              - :object_with_lookahead
              - :object_without_lookahead
          EOS
        end
      end

      it "warns when resolvers are registered but never used" do
        output = StringIO.new

        graphql_resolvers_by_name(output: output) do |schema|
          schema.register_graphql_resolver :resolver1,
            GraphQLResolverWithLookahead,
            defined_at: "elastic_graph/spec_support/example_extensions/graphql_resolvers"

          schema.register_graphql_resolver :resolver2,
            GraphQLResolverWithoutLookahead,
            defined_at: "elastic_graph/spec_support/example_extensions/graphql_resolvers"
        end

        expect(output.string).to eq(<<~EOS)
          WARNING: 2 GraphQL resolver(s) have been registered but are unused:
            - resolver1
            - resolver2
          These resolvers can be removed.
        EOS
      end

      def graphql_resolvers_by_name(...)
        define_schema(...).runtime_metadata.graphql_resolvers_by_name
      end
    end
  end
end

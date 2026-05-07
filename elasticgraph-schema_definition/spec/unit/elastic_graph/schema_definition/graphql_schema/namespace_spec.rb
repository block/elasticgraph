# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "#namespace_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "generates a plain GraphQL object type with the given fields" do
          result = namespace_type "OlapQuery" do |t|
            t.field "name", "String" do |f|
              f.resolve_with :constant_value, value: "olap"
            end
          end

          expect(result).to eq(<<~EOS)
            type OlapQuery {
              name: String
            }
          EOS
        end

        it "supports documentation on the type and its fields" do
          result = namespace_type "OlapQuery", include_docs: true do |t|
            t.documentation "Namespace for OLAP query fields."

            t.field "name", "String" do |f|
              f.documentation "The namespace's name."
              f.resolve_with :constant_value, value: "olap"
            end
          end

          expect(result).to eq(<<~EOS)
            """
            Namespace for OLAP query fields.
            """
            type OlapQuery {
              """
              The namespace's name.
              """
              name: String
            }
          EOS
        end

        it "does not generate a Query field for a namespace type (it is not directly queryable)" do
          result = define_schema do |schema|
            schema.namespace_type "OlapQuery" do |t|
              t.field "name", "String" do |f|
                f.resolve_with :constant_value, value: "olap"
              end
            end

            schema.on_root_query_type do |t|
              t.field "olap", "OlapQuery!"
            end
          end

          expect(type_def_from(result, "Query")).to eq(<<~EOS.strip)
            type Query {
              olap: OlapQuery!
            }
          EOS
        end

        it "does not generate connection/edge/aggregation derived types for a namespace type" do
          result = define_schema do |schema|
            schema.namespace_type "OlapQuery" do |t|
              t.field "name", "String" do |f|
                f.resolve_with :constant_value, value: "olap"
              end
            end
          end

          expect(connection_type_from(result, "OlapQuery")).to eq nil
          expect(edge_type_from(result, "OlapQuery")).to eq nil
          expect(aggregation_type_from(result, "OlapQuery")).to eq nil
          expect(aggregation_connection_type_from(result, "OlapQuery")).to eq nil
          expect(sort_order_type_from(result, "OlapQuery")).to eq nil
        end

        it "raises a clear error when `index` is called on a namespace type" do
          expect {
            define_schema do |schema|
              schema.namespace_type "OlapQuery" do |t|
                t.field "id", "ID"
                t.index "olap_queries"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("OlapQuery", "cannot be both an indexed type and a namespace type"))
        end

        def namespace_type(name, *args, include_docs: false, &block)
          result = define_schema do |api|
            api.namespace_type(name, *args, &block)
          end

          # We add a line break to match the expectations which use heredocs.
          type_def_from(result, name, include_docs: include_docs) + "\n"
        end
      end
    end
  end
end

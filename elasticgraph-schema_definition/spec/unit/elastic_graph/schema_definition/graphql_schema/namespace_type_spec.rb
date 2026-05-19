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
              f.resolve_with :get_record_field_value
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
              f.resolve_with :get_record_field_value
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
            schema.namespace_type "OlapQuery"

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

        it "does not generate any derived types for a namespace type" do
          result = define_schema do |schema|
            schema.namespace_type "OlapQuery"
          end

          # Only `OlapQuery` itself appears in the schema -- no `*Connection`, `*Edge`, `*FilterInput`,
          # `*Aggregation`, `*SortOrderInput`, etc. This is what sets namespace types apart from
          # indexed object types, which generate a constellation of derived types.
          expect(types_defined_in(result).grep(/OlapQuery/)).to contain_exactly("OlapQuery")
        end

        it "omits fields that reference a namespace type from derived types of an indexed type" do
          result = define_schema do |schema|
            schema.namespace_type "OlapQuery"

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              # `olap` references a namespace type. It should appear on `Widget` in the GraphQL schema,
              # but never on any `Widget*` derived type (filter, sort, aggregation, highlights, etc.)
              # because there's nothing in the datastore to filter/sort/group/highlight on.
              t.field "olap", "OlapQuery"
              t.index "widgets"
            end

            schema.on_root_query_type do |t|
              t.field "olap", "OlapQuery!"
            end
          end

          # `olap` is a field on `Widget`.
          expect(type_def_from(result, "Widget")).to include("olap: OlapQuery")

          # But it doesn't appear on any derived type of `Widget`.
          widget_derived_types = types_defined_in(result).grep(/\AWidget/) - ["Widget"]
          expect(widget_derived_types.size).to be >= 5

          widget_derived_types.each do |derived_type_name|
            derived_type_sdl = type_def_from(result, derived_type_name)
            expect(derived_type_sdl).not_to include("olap"),
              "Expected derived type `#{derived_type_name}` to exclude `olap`, but its SDL was:\n#{derived_type_sdl}"
          end
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

        it "raises a clear error if `Field#type_is_namespace?` is called before user definition is complete" do
          expect {
            define_schema do |schema|
              schema.namespace_type "OlapQuery"

              schema.object_type "Widget" do |t|
                t.field "olap", "OlapQuery" do |f|
                  f.type_is_namespace?
                end
              end
            end
          }.to raise_error(
            Errors::SchemaError,
            "Cannot call `type_is_namespace?` until the schema definition is complete."
          )
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

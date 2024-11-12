# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/schema/enum_value"

module ElasticGraph
  class GraphQL
    class Schema
      RSpec.describe EnumValue, :ensure_no_orphaned_types do
        it "inspects well" do
          enum_value = define_schema do |s|
            s.enum_type "ColorSpace" do |t|
              t.value "rgb"
            end
          end.enum_value_named(:ColorSpace, :rgb)

          expect(enum_value.inspect).to eq "#<ElasticGraph::GraphQL::Schema::EnumValue ColorSpace.rgb>"
        end

        describe "#name" do
          it "returns the name as a symbol" do
            enum_value = define_schema do |s|
              s.enum_type "ColorSpace" do |t|
                t.value "rgb"
              end
            end.enum_value_named(:ColorSpace, :rgb)

            expect(enum_value.name).to eq :rgb
          end
        end

        def define_schema(&schema_definition)
          build_graphql(schema_definition: schema_definition).schema
        end
      end
    end
  end
end

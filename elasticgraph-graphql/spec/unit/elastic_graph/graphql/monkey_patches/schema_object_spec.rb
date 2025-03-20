# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/monkey_patches/schema_object"

module ElasticGraph
  class GraphQL
    module MonkeyPatches
      RSpec.describe SchemaObjectVisibilityDecorator do
        it "does not interfere with the ability to parse and re-dump an SDL string" do
          schema_string = <<~EOS
            type Query {
              foo: Int
            }
          EOS

          dumped = ::GraphQL::Schema.from_definition(schema_string).to_definition

          expect(dumped).to eq(schema_string)
        end
      end
    end
  end
end

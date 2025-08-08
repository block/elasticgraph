# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  module Support
    module JSONSchema
      RSpec.describe ValidatorFactory do
        it "caches Validator instances" do
          type_name = "MyType"
          factory = ValidatorFactory.new(
            schema: {
              "$schema" => JSON_META_SCHEMA,
              "$defs" => {
                type_name => {
                  "type" => "object",
                  "properties" => {
                    "id" => {
                      "type" => "string",
                      "maxLength" => 10
                    }
                  }
                }
              }
            },
            sanitize_pii: false
          )

          # standard:disable RSpec/IdenticalEqualityAssertion
          expect(factory.validator_for(type_name)).to be factory.validator_for(type_name)
          # standard:enable RSpec/IdenticalEqualityAssertion
        end
      end
    end
  end
end

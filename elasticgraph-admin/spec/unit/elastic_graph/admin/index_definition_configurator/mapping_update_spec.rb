# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/index_definition_configurator/mapping_update"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      RSpec.describe MappingUpdate do
        describe ".merge_existing_fields_into" do
          it "preserves removed mapping fields while allowing existing field parameters to be removed" do
            current_mapping = {
              "properties" => {
                "name" => {"type" => "keyword", "meta" => {"foo" => "1"}},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "size" => {"type" => "keyword"}
                  }
                }
              }
            }

            desired_mapping = {
              "properties" => {
                "name" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "weight" => {"type" => "integer"}
                  }
                }
              }
            }

            expect(described_class.merge_existing_fields_into(desired_mapping, current_mapping)).to eq({
              "properties" => {
                "name" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "weight" => {"type" => "integer"},
                    "size" => {"type" => "keyword"}
                  }
                }
              }
            })
          end
        end
      end
    end
  end
end

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
        describe ".build_mapping_update" do
          it "preserves current mapping fields that are missing from the desired mapping, at both root and nested levels" do
            current = {
              "properties" => {
                "name" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "size" => {"type" => "keyword"}
                  }
                }
              }
            }

            desired = {
              "properties" => {
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "weight" => {"type" => "integer"}
                  }
                }
              }
            }

            expect(described_class.build_mapping_update(desired: desired, current: current)).to eq({
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

          it "drops current-only fields that are not protected when `protected_field_paths` is provided, while preserving protected ones" do
            current = {
              "properties" => {
                "name" => {"type" => "keyword"},
                "legacy_field" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "size" => {"type" => "keyword"},
                    "weight" => {"type" => "integer"}
                  }
                }
              }
            }

            desired = {
              "properties" => {
                "name" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"}
                  }
                }
              }
            }

            result = described_class.build_mapping_update(
              desired: desired,
              current: current,
              protected_field_paths: ["options.size"].to_set
            )

            expect(result).to eq({
              "properties" => {
                "name" => {"type" => "keyword"},
                "options" => {
                  "properties" => {
                    "color" => {"type" => "keyword"},
                    "size" => {"type" => "keyword"}
                  }
                }
              }
            })
          end

          it "preserves an entire current-only parent field when a protected path sits underneath it, since dropping the parent would drop the protected field" do
            current = {
              "properties" => {
                "old_parent" => {
                  "properties" => {
                    "keep_me" => {"type" => "keyword"},
                    "sibling" => {"type" => "keyword"}
                  }
                }
              }
            }

            desired = {"properties" => {}}

            result = described_class.build_mapping_update(
              desired: desired,
              current: current,
              protected_field_paths: ["old_parent.keep_me"].to_set
            )

            expect(result).to eq({
              "properties" => {
                "old_parent" => {
                  "properties" => {
                    "keep_me" => {"type" => "keyword"},
                    "sibling" => {"type" => "keyword"}
                  }
                }
              }
            })
          end

          it "favors the desired mapping for fields present in both, allowing existing field parameters to be removed" do
            current = {
              "properties" => {
                "name" => {"type" => "keyword", "meta" => {"foo" => "1"}}
              }
            }

            desired = {
              "properties" => {
                "name" => {"type" => "keyword"}
              }
            }

            expect(described_class.build_mapping_update(desired: desired, current: current)).to eq({
              "properties" => {
                "name" => {"type" => "keyword"}
              }
            })
          end
        end
      end
    end
  end
end

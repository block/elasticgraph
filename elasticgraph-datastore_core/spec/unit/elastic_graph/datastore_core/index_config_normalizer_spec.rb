# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_config_normalizer"
require "json"

module ElasticGraph
  class DatastoreCore
    RSpec.describe IndexConfigNormalizer do
      it "returns an empty hash unchanged" do
        normalized = IndexConfigNormalizer.normalize({})

        expect(normalized).to eq({})
      end

      it "filters out read-only settings" do
        index_config = {
          "settings" => {
            "index.creation_date" => "2020-07-20",
            "index.uuid" => "abcdefg",
            "index.history.uuid" => "98765",
            "index.random.setting" => "random"
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "settings" => {
            "index.random.setting" => "random"
          }
        })
      end

      it "converts non-string setting primitives to strings to mirror Elasticsearch and OpenSearch behavior, which do this when fetching the settings for an index" do
        index_config = {
          "settings" => {
            "index.random.setting" => 123
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "settings" => {
            "index.random.setting" => "123"
          }
        })
      end

      it "leaves nil settings alone" do
        index_config = {
          "settings" => {
            "index.random.setting" => nil
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "settings" => {
            "index.random.setting" => nil
          }
        })
      end

      context "when a setting is a list" do
        it "converts the individual list elements to strings instead of converting the list as a whole to a string" do
          index_config = {
            "settings" => {
              "index.numbers" => [1, 10, 20],
              "index.strings" => ["a", "b", "c"]
            }
          }

          normalized = IndexConfigNormalizer.normalize(index_config)

          expect(normalized).to eq({
            "settings" => {
              "index.numbers" => ["1", "10", "20"],
              "index.strings" => ["a", "b", "c"]
            }
          })
        end
      end

      it "drops `type: object` when it is along side `properties` since the datastore treats that as the default type when `properties` are used and omits it" do
        index_config = {
          "mappings" => {
            "type" => "object",
            "properties" => {}
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "mappings" => {
            "properties" => {}
          }
        })
      end

      it "leaves `type: object` unchanged when there are no `properties`" do
        index_config = {
          "mappings" => {
            "type" => "object"
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "mappings" => {
            "type" => "object"
          }
        })
      end

      it "leaves other types unchanged" do
        index_config = {
          "mappings" => {
            "properties" => {
              "options" => {"type" => "nested", "properties" => {}},
              "name" => {"type" => "keyword"}
            }
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "mappings" => {
            "properties" => {
              "options" => {"type" => "nested", "properties" => {}},
              "name" => {"type" => "keyword"}
            }
          }
        })
      end

      it "applies the removal of `type: object` recursively" do
        index_config = {
          "mappings" => {
            "type" => "object",
            "properties" => {
              "options" => {
                "type" => "object",
                "properties" => {
                  "name" => {"type" => "keyword"},
                  "suboptions" => {"type" => "object", "properties" => {}}
                }
              }
            }
          }
        }

        normalized = IndexConfigNormalizer.normalize(index_config)

        expect(normalized).to eq({
          "mappings" => {
            "properties" => {
              "options" => {
                "properties" => {
                  "name" => {"type" => "keyword"},
                  "suboptions" => {"properties" => {}}
                }
              }
            }
          }
        })
      end

      it "avoids mutating the passed config hash" do
        index_config = {
          "mappings" => {
            "type" => "object",
            "properties" => {
              "options" => {
                "type" => "object",
                "properties" => {
                  "name" => {"type" => "keyword"},
                  "suboptions" => {"type" => "object"}
                }
              }
            }
          },
          "settings" => {
            "index.creation_date" => "2020-07-20",
            "index.uuid" => "abcdefg",
            "index.history.uuid" => "98765",
            "index.random.setting" => 123
          }
        }

        as_json = ::JSON.pretty_generate(index_config)

        expect(IndexConfigNormalizer.normalize(index_config)).not_to eq(index_config)
        expect(::JSON.pretty_generate(index_config)).to eq(as_json)
      end
    end
  end
end

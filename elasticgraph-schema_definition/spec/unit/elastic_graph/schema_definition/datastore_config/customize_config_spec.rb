# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_definition_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config -- customize_config" do
      include_context "IndexDefinitionSpecSupport"

      it "applies customizations to the config of an index" do
        campaigns = index_configs_for "campaigns" do |s|
          s.object_type "Campaign" do |t|
            t.field "id", "ID!"
            t.field "status", "String"

            t.index "campaigns" do |i|
              i.customize_config do |config|
                config["aliases"] = {
                  "campaigns_read" => {},
                  "campaigns_active" => {"filter" => {"term" => {"status" => "ACTIVE"}}}
                }
              end
            end
          end
        end.first

        expect(campaigns).to match(
          "aliases" => {
            "campaigns_read" => {},
            "campaigns_active" => {"filter" => {"term" => {"status" => "ACTIVE"}}}
          },
          "mappings" => an_instance_of(::Hash),
          "settings" => an_instance_of(::Hash)
        )
      end

      it "applies customizations to the template body of a rollover index" do
        campaigns = index_template_configs_for "campaigns" do |s|
          s.object_type "Campaign" do |t|
            t.field "id", "ID!"
            t.field "created_at", "DateTime"

            t.index "campaigns" do |i|
              i.rollover :monthly, "created_at"

              i.customize_config do |config|
                config["aliases"] = {"campaigns_read" => {}}
              end
            end
          end
        end.first

        expect(campaigns).to match(
          "index_patterns" => ["campaigns_rollover__*"],
          "template" => {
            "aliases" => {"campaigns_read" => {}},
            "mappings" => an_instance_of(::Hash),
            "settings" => an_instance_of(::Hash)
          }
        )
      end

      it "applies multiple customization blocks in the order they were registered, ignoring their return values" do
        campaigns = index_configs_for "campaigns" do |s|
          s.object_type "Campaign" do |t|
            t.field "id", "ID!"

            t.index "campaigns" do |i|
              i.customize_config do |config|
                config["aliases"] = {"campaigns_alias1" => {}}
                :ignored_return_value
              end

              i.customize_config do |config|
                config["aliases"] = config["aliases"].merge("campaigns_alias2" => {})
              end
            end
          end
        end.first

        expect(campaigns.fetch("aliases")).to eq({"campaigns_alias1" => {}, "campaigns_alias2" => {}})
      end

      it "supports nested customizations such as field aliases" do
        campaigns = index_configs_for "campaigns" do |s|
          s.object_type "Campaign" do |t|
            t.field "id", "ID!"
            t.field "created_at", "DateTime"

            t.index "campaigns" do |i|
              i.customize_config do |config|
                config["mappings"]["properties"]["created"] = {"type" => "alias", "path" => "created_at"}
              end
            end
          end
        end.first

        expect(campaigns.dig("mappings", "properties", "created")).to eq({"type" => "alias", "path" => "created_at"})
      end

      it "yields a defensive deep copy so that customization mutations cannot corrupt the index's own internal state" do
        index = nil # : Indexing::Index?
        sort_fields = ["created_at"]

        campaigns = index_configs_for "campaigns" do |s|
          s.object_type "Campaign" do |t|
            t.field "id", "ID!"
            t.field "created_at", "DateTime"

            t.index "campaigns", sort: {field: sort_fields, order: ["asc"]} do |i|
              index = i

              i.customize_config do |config|
                # Replacing a value one level down requires the copy to not be a bare `dup` of the config hash...
                config["settings"]["index.number_of_shards"] = 17
                # ...while mutating this array in place requires the copy to be recursive, since the array is the
                # very one the caller passed to `sort:` above.
                config["settings"]["index.sort.field"] << "id"
              end
            end
          end
        end.first

        expect(campaigns.dig("settings", "index.number_of_shards")).to eq(17)
        expect(campaigns.dig("settings", "index.sort.field")).to eq(["created_at", "id"])

        expect(index&.settings).to include(
          "index.number_of_shards" => 1,
          "index.sort.field" => ["created_at"]
        )
        expect(sort_fields).to eq(["created_at"])
      end

      it "raises a clear error when `customize_config` is called without a block" do
        expect {
          index_configs_for "campaigns" do |s|
            s.object_type "Campaign" do |t|
              t.field "id", "ID!"

              t.index "campaigns" do |i|
                i.customize_config
              end
            end
          end
        }.to raise_error(Errors::SchemaError, a_string_including("customize_config", "campaigns", "block"))
      end
    end
  end
end

# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_mappings_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config index mappings -- namespace types" do
      include_context "IndexMappingsSpecSupport"

      it "does not generate an index mapping for a namespace type since it has no backing data to index" do
        index_configs = index_configs_for "widgets" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.index "widgets"
          end

          s.namespace_type "OlapQuery" do |t|
            t.field "name", "String" do |f|
              f.resolve_with :constant_value, value: "olap"
            end
          end
        end

        # Only the `widgets` index is defined; no `olap_queries`-like index for the namespace type.
        widget_mapping = index_configs.first.fetch("mappings")
        expect(widget_mapping.dig("properties")).to include("id" => {"type" => "keyword"})
        expect(widget_mapping.dig("properties")).to exclude("name")
      end
    end
  end
end

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

          s.namespace_type "OlapQuery"
        end

        # Only the `widgets` index mapping is generated (no namespace type mapping).
        widget_mapping = index_configs.first.fetch("mappings")
        expect(widget_mapping.dig("properties")).to include("id" => {"type" => "keyword"})
      end

      it "omits fields that reference a namespace type from the index mapping of an indexed type" do
        # This test would fail if `s.namespace_type` were replaced with `s.object_type` -- the `olap`
        # field would then appear in the Widget mapping as an `object` type. Namespace types have no
        # backing data, so they must be excluded from the parent's mapping.
        widget_mapping = index_mapping_for "widgets" do |s|
          s.namespace_type "OlapQuery"

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "olap", "OlapQuery"
            t.index "widgets"
          end
        end

        expect(widget_mapping.dig("properties")).to include("id" => {"type" => "keyword"})
        expect(widget_mapping.dig("properties")).to exclude("olap")
      end
    end
  end
end

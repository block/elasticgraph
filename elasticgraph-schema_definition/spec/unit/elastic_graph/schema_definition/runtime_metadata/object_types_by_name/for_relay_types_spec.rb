# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #object_types_by_name for generated relay types" do
      include_context "object type metadata support"

      it "tags relay connection types with `elasticgraph_category: :relay_connection`" do
        metadata = object_type_metadata_for "WidgetConnection" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"
          end
        end

        expect(metadata.elasticgraph_category).to eq :relay_connection
      end

      it "tags relay connection types with `elasticgraph_category: :relay_edge`" do
        metadata = object_type_metadata_for "WidgetEdge" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"
          end
        end

        expect(metadata.elasticgraph_category).to eq :relay_edge
      end
    end
  end
end

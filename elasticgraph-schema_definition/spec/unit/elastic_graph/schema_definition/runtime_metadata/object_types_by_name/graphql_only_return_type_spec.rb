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
    RSpec.describe "RuntimeMetadata #object_types_by_name #graphql_only_return_type" do
      include_context "object type metadata support"

      it "is set to `true` on a return type that has `t.graphql_only true`" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID", name_in_index: "id_index"
            t.graphql_only true
          end
        end

        expect(metadata.graphql_only_return_type).to eq true
      end

      it "is set to `false` on a return type that has `t.graphql_only = false`" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID", name_in_index: "id_index"
            t.graphql_only false
          end
        end

        expect(metadata.graphql_only_return_type).to eq false
      end

      it "is set to `false` on a return type that has `graphql_only` unset" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID", name_in_index: "id_index"
          end
        end

        expect(metadata.graphql_only_return_type).to eq false
      end

      it "is set to `false` on an input type regardless of `graphql_only`" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.factory.new_input_type "Widget" do |t|
            t.field "id", "ID", name_in_index: "id_index"
            t.graphql_only true
            s.state.register_input_type(t)
          end
        end

        expect(metadata.graphql_only_return_type).to eq false
      end
    end
  end
end

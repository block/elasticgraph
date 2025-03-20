# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_mappings_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config index mappings -- relation fields" do
      include_context "IndexMappingsSpecSupport"

      context "on a relation with an outbound foreign key" do
        it "includes a foreign key field for a GraphQL relation field" do
          mappings = index_mappings_for "my_type_one", "my_type_many" do |s|
            s.object_type "OtherType" do |t|
              t.field "id", "ID!"
              t.index "other_type"
            end

            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.relates_to_one "other", "OtherType!", via: "other_id", dir: :out
              t.index "my_type_one"
            end

            s.object_type "MyType2" do |t|
              t.field "id", "ID!"
              t.relates_to_many "other", "OtherType", via: "other_id", dir: :out, singular: "other"
              t.index "my_type_many"
            end
          end

          one, many = mappings.map { |h| h.dig("properties") }

          expect([one, many]).to all include({
            "id" => {"type" => "keyword"},
            "other_id" => {"type" => "keyword"}
          })
        end
      end

      context "on a relation with an inbound foreign key" do
        it "includes the foreign key field when the relation is self-referential, regardless of the details of the relation (one or many)" do
          one, many = index_mappings_for "my_type_one", "my_type_many" do |s|
            s.object_type "MyTypeOne" do |t|
              t.field "id", "ID"
              t.relates_to_one "parent", "MyTypeOne", via: "children_ids", dir: :in
              t.index "my_type_one"
            end

            s.object_type "MyTypeMany" do |t|
              t.field "id", "ID"
              t.relates_to_many "children", "MyTypeMany", via: "parent_id", dir: :in, singular: "child"
              t.index "my_type_many"
            end
          end

          expect(one.dig("properties")).to include({
            "id" => {"type" => "keyword"},
            "children_ids" => {"type" => "keyword"}
          })

          expect(many.dig("properties")).to include({
            "id" => {"type" => "keyword"},
            "parent_id" => {"type" => "keyword"}
          })
        end
      end
    end
  end
end

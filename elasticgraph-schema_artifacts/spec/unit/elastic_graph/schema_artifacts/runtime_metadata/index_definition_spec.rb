# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/index_definition"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe IndexDefinition do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          index_def = IndexDefinition.from_hash({})

          expect(index_def).to eq IndexDefinition.new(
            route_with: nil,
            rollover: nil,
            default_sort_fields: [],
            current_sources: Set.new,
            fields_by_path: {},
            field_paths_protected_from_removal: Set.new,
            has_had_multiple_sources: false,
            sourced_from_nested_paths_by_qualified_relationship: {}
          )
        end

        it "includes fields that only have default values when serializing, even though other default runtime metadata elements get dropped, so our GraphQL logic can easily see what all the valid field paths are" do
          index_def = index_definition_with(
            fields_by_path: {
              "foo.bar" => index_field_with(source: SELF_RELATIONSHIP_NAME),
              "foo.bazz" => index_field_with(source: "other")
            },
            has_had_multiple_sources: false
          )

          expect(index_def.to_dumpable_hash["fields_by_path"]).to eq({
            "foo.bar" => index_field_with(source: SELF_RELATIONSHIP_NAME).to_dumpable_hash,
            "foo.bazz" => index_field_with(source: "other").to_dumpable_hash
          })
        end

        it "round-trips `field_paths_protected_from_removal` through a dumped hash as a sorted list" do
          index_def = index_definition_with(field_paths_protected_from_removal: ["options.size", "name"])

          dumped = index_def.to_dumpable_hash
          expect(dumped["field_paths_protected_from_removal"]).to eq ["name", "options.size"]
          expect(IndexDefinition.from_hash(dumped).field_paths_protected_from_removal).to eq ["name", "options.size"].to_set
        end

        it "prunes `has_had_multiple_sources: false` from the dumped hash but includes `has_had_multiple_sources: true`" do
          index_def_without_flag = index_definition_with(has_had_multiple_sources: false)
          expect(index_def_without_flag.to_dumpable_hash["has_had_multiple_sources"]).to be_nil

          index_def_with_flag = index_definition_with(has_had_multiple_sources: true)
          expect(index_def_with_flag.to_dumpable_hash["has_had_multiple_sources"]).to eq true
        end

        describe IndexDefinition::Rollover do
          it "builds from a minimal hash" do
            rollover = IndexDefinition::Rollover.from_hash({"frequency" => "yearly"})

            expect(rollover).to eq IndexDefinition::Rollover.new(
              frequency: :yearly,
              timestamp_field_path: nil
            )
          end
        end
      end
    end
  end
end

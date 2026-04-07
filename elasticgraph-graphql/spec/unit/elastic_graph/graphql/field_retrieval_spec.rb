# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition/index"
require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/graphql/field_retrieval"
require "elastic_graph/schema_artifacts/runtime_metadata/index_field"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  class GraphQL
    RSpec.describe FieldRetrieval::Automatic do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      def plan(fields: ["name"], metadata: {"name" => true}, planner: described_class.new, **options)
        index = instance_double(DatastoreCore::IndexDefinition::Index, fields_by_path: metadata.transform_values { |eligible| index_field_with(doc_values_eligible: eligible) })
        planner.plan(requested_fields: fields, request_all_fields: false, highlighting: false, index_definitions: [index], **options)
      end

      it "automatically requests eligible scalars without source, preserving the id optimization" do
        expect(plan(fields: ["id", "name"]).to_datastore_body).to eq(_source: false, docvalue_fields: ["name"])
        expect(plan(fields: ["id"]).reason).to eq "metadata_only"
        expect(plan.decode({})).to eq("name" => nil)
      end

      it "falls back for old metadata, unknown paths, and any ineligible index" do
        expect(plan(metadata: {"name" => false}).reason).to eq "source_ineligible_fields"
        expect(plan(fields: ["name", "unknown"]).to_datastore_body).to eq(_source: {includes: ["name", "unknown"]})
        expect(plan(index_definitions: []).reason).to eq "source_ineligible_fields"
        eligible = instance_double(DatastoreCore::IndexDefinition::Index, fields_by_path: {"name" => index_field_with(doc_values_eligible: true)})
        old = instance_double(DatastoreCore::IndexDefinition::Index, fields_by_path: {"name" => index_field_with})
        expect(plan(index_definitions: [eligible, old]).reason).to eq "source_ineligible_fields"
      end

      it "retains source for the default mode, highlighting, and all-field requests" do
        expect(plan(planner: FieldRetrieval::Source.new).reason).to eq "source_default"
        expect(plan(highlighting: true).reason).to eq "source_highlighting"
        expect(plan(request_all_fields: true).to_datastore_body).to eq(_source: true)
      end

      it "caps doc-value requests at the datastore default limit" do
        fields = Array.new(101) { |i| "f#{i}" }
        expect(plan(fields: fields).reason).to eq "source_field_limit"
        expect(plan(fields: fields.first(100), metadata: fields.to_h { |name| [name, true] }).reason).to eq "doc_values"
      end

      it "normalizes values once into the document payload and retains the plan through relationship splitting" do
        retrieval = plan(fields: %w[name flag count absent], metadata: %w[name flag count absent].to_h { |f| [f, true] })
        hit = {"_index" => "widgets", "_id" => "1", "fields" => {"name" => ["a"], "flag" => [false], "count" => [0]}}
        raw = {"hits" => {"hits" => [hit, hit.merge("_id" => "2")], "total" => {"value" => 2}}}
        response = DatastoreResponse::SearchResponse.build(raw, field_retrieval_plan: retrieval)
        split = response.filter_results(["name"], Set["a"], 1).filter_results(["id"], Set["1"], 1)
        expect(split.documents.map(&:payload)).to eq([{"id" => "1", "name" => "a", "flag" => false, "count" => 0, "absent" => nil}])
      end

      it "fails loudly if existing data violates scalar cardinality" do
        expect { plan.decode({"fields" => {"name" => ["a", "b"]}}) }.to raise_error(Errors::SearchFailedError, /Expected a scalar/)
      end
    end
  end
end

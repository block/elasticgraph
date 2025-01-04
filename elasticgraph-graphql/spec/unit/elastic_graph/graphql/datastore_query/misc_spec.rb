# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "misc" do
      include_context "DatastoreQueryUnitSupport"
      let(:default_page_size) { 73 }
      let(:graphql) { build_graphql(default_page_size: default_page_size) }

      it "raises an error if instantiated with an empty collection of `search_index_definitions`" do
        expect {
          new_query(search_index_definitions: [])
        }.to raise_error Errors::SearchFailedError, a_string_including("search_index_definitions")
      end

      it "inspects nicely, but redacts filters since they could contain PII" do
        expect(new_query(filter: {"ssn" => {"equal_to_any_of" => ["123-45-6789"]}}, individual_docs_needed: true).inspect).to eq(inspect_output_of(<<~EOS.strip))
          #<ElasticGraph::GraphQL::DatastoreQuery index="widgets_rollover__*" size=#{default_page_size + 1} sort=[{"id" => {"order" => "asc", "missing" => "_first"}}] track_total_hits=false query=<REDACTED> _source=false>
        EOS
      end
    end
  end
end

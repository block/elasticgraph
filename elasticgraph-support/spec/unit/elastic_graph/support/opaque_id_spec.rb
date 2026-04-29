# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/opaque_id"

module ElasticGraph
  module Support
    RSpec.describe OpaqueID do
      describe ".build_header" do
        it "joins parts with semicolons" do
          expect(OpaqueID.build_header(["elasticgraph-graphql", "client=foo", "query=GetColors/abc"])).to eq(
            "elasticgraph-graphql;client=foo;query=GetColors/abc"
          )
        end

        it "drops nil and empty parts" do
          expect(OpaqueID.build_header(["elasticgraph-graphql", nil, "", "client=foo"])).to eq(
            "elasticgraph-graphql;client=foo"
          )
        end

        it "returns nil when no parts remain after normalization" do
          expect(OpaqueID.build_header([nil, "", " "])).to be nil
        end

        it "replaces semicolons and newlines so each part stays a single segment" do
          expect(OpaqueID.build_header(["client=foo;bar", "query=line1\nline2"])).to eq(
            "client=foo,bar;query=line1,line2"
          )
        end
      end
    end
  end
end

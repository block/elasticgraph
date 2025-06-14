# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/configured_graphql_resolver"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe ConfiguredGraphQLResolver do
        it "exposes `name` as a symbol while keeping it as a string in dumped form" do
          resolver = ConfiguredGraphQLResolver.from_hash({"name" => "self"})

          expect(resolver.name).to eq :self
          expect(resolver.to_dumpable_hash).to include("name" => "self")
        end

        it "converts `config` to a stringified hash when dumping it" do
          resolver = ConfiguredGraphQLResolver.new(:foo, {arg1: 17})
          expect(resolver.to_dumpable_hash).to include("config" => {"arg1" => 17})
        end

        it "omits `config` from the dumped form when empty" do
          resolver = ConfiguredGraphQLResolver.new(:foo, {})
          expect(resolver.to_dumpable_hash).to exclude("config")
        end
      end
    end
  end
end

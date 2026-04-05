# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf"

module ElasticGraph
  RSpec.describe Protobuf do
    it "defines the PROTO_SCHEMA_FILE constant" do
      expect(Protobuf::PROTO_SCHEMA_FILE).to eq("schema.proto")
    end

    it "defines the PROTO_FIELD_NUMBERS_FILE constant" do
      expect(Protobuf::PROTO_FIELD_NUMBERS_FILE).to eq("proto_field_numbers.yaml")
    end
  end
end

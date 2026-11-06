# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/proto_conversions"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe ProtoConversions do
      it "removes only the enum prefix, preserving underscores in the enum value" do
        expect(ProtoConversions.enum_value_to_eg_name("ORDER_STATUS_ON_HOLD", "ORDER_STATUS")).to eq("ON_HOLD")
      end
    end
  end
end

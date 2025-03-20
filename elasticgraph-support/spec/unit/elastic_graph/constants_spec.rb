# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "base64"
require "json"
require "elastic_graph/constants"

module ElasticGraph
  RSpec.describe "Constants" do
    specify "SINGLETON_CURSOR is a unique value we never expect to get for a normal cursor while still being encoded like a normal cursor" do
      encoded_data = ::JSON.parse(::Base64.urlsafe_decode64(SINGLETON_CURSOR))

      expect(encoded_data).to eq({"uuid" => "dca02d20-baee-4ee9-a027-feece0a6de3a"})
    end
  end
end

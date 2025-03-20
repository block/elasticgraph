# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/client"

module ElasticGraph
  class GraphQL
    RSpec.describe Client do
      describe "#description" do
        it "combines the name and id in a readable way" do
          client = Client.new(name: "John", source_description: "42")

          expect(client.description).to eq("John (42)")
        end

        it "avoids returning duplicate info when the name and id are the same (such as for `ANONYMOUS`)" do
          expect(Client::ANONYMOUS.description).to eq("(anonymous)")
        end
      end
    end
  end
end

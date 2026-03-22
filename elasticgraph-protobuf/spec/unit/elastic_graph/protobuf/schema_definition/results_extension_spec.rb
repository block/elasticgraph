# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/results_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe ResultsExtension, :proto_schema do
        it "memoizes the schema generator and exposes its field-number mappings" do
          allow(Schema).to receive(:new).and_call_original

          results = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"
            end
          end

          expect(results.proto_schema).to include("message Widget")
          expect(results.proto_schema).to include("message Widget")
          expect(results.proto_field_number_mappings).to eq({
            "messages" => {
              "Widget" => {"fields" => {"id" => 1}}
            }
          })

          expect(Schema).to have_received(:new).once
        end
      end
    end
  end
end

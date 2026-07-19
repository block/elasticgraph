# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/identifier"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe Identifier do
        it "allows keywords in package name segments" do
          expect(Identifier.validate_package_name("proto.package.v1")).to eq("proto.package.v1")
        end

        it "rejects package names with segments that are not valid protobuf identifiers" do
          expect {
            Identifier.validate_package_name("my-app.events")
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`", "my-app.events"))

          expect {
            Identifier.validate_package_name("myapp..events")
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`"))

          expect {
            Identifier.validate_package_name("1myapp.events")
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`"))

          expect {
            Identifier.validate_package_name("")
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`"))

          expect {
            Identifier.validate_package_name("myapp.events.")
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`"))
        end
      end
    end
  end
end

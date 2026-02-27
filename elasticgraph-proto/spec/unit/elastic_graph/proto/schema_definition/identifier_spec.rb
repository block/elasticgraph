# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/identifier"

module ElasticGraph
  module Proto
    module SchemaDefinition
      RSpec.describe Identifier do
        it "escapes reserved keywords" do
          expect(Identifier.escape_keyword("package")).to eq("package_")
          expect(Identifier.escape_keyword("custom")).to eq("custom")
        end

        it "escapes package name segments independently" do
          expect(Identifier.package_name("proto.package.v1")).to eq("proto.package_.v1")
        end

        it "escapes message, enum, field, and enum value names" do
          expect(Identifier.message_name("service")).to eq("service_")
          expect(Identifier.enum_name("message")).to eq("message_")
          expect(Identifier.field_name("string")).to eq("string_")
          expect(Identifier.enum_value_name("stream")).to eq("stream_")
        end
      end
    end
  end
end

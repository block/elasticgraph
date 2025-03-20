# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe DynamicParam do
        include RuntimeMetadataSupport

        it "coerces the cardinality to a symbol in memory vs a string in dumped form" do
          param = dynamic_param_with(cardinality: :one)

          dumped = param.to_dumpable_hash("my_param")
          expect(dumped["cardinality"]).to eq("one")

          loaded = DynamicParam.from_hash(dumped, "my_param")
          expect(loaded).to eq param
          expect(loaded.cardinality).to eq(:one)
        end

        it "sets `source_path` in the dumped hashunset if it is different from the param name" do
          param = dynamic_param_with(source_path: "foo")

          dumped = param.to_dumpable_hash("bar")
          expect(dumped.fetch("source_path")).to eq("foo")

          loaded = DynamicParam.from_hash(dumped, "bar")
          expect(loaded).to eq param
          expect(loaded.source_path).to eq("foo")
        end

        it "leaves `source_path` unset when dumping it if it is the same as the param name to avoid bloating our runtime metadata dumped artifact" do
          param = dynamic_param_with(source_path: "foo")

          dumped = param.to_dumpable_hash("foo")
          expect(dumped.fetch("source_path")).to eq(nil)

          loaded = DynamicParam.from_hash(dumped, "foo")
          expect(loaded).to eq param
          expect(loaded.source_path).to eq("foo")
        end

        describe "#value_for" do
          context "for a param with `:many` cardinality" do
            it "fetches multiple values from the given data hash" do
              param = dynamic_param_with(source_path: "foo.bar", cardinality: :many)

              value = param.value_for({"foo" => [{"bar" => [2, 3]}, {"bar" => 5}]})

              expect(value).to eq([2, 3, 5])
            end

            it "returns `[]` if the `source_path` is not found" do
              param = dynamic_param_with(source_path: "foo.bar", cardinality: :many)

              value = param.value_for({})

              expect(value).to eq([])
            end
          end

          context "for a param with `:one` cardinality" do
            it "fetches a single value from the given data hash" do
              param = dynamic_param_with(source_path: "foo.bar", cardinality: :one)

              value = param.value_for({"foo" => {"bar" => 7}})

              expect(value).to eq(7)
            end

            it "returns `nil` if the `source_path` is not found" do
              param = dynamic_param_with(source_path: "foo.bar", cardinality: :one)

              value = param.value_for({"foo" => {}})

              expect(value).to eq(nil)
            end
          end

          context "on an unrecognized cardinality" do
            it "returns `nil`" do
              param = dynamic_param_with(source_path: "foo.bar", cardinality: :unsure)

              value = param.value_for({"foo" => {"bar" => 7}})

              expect(value).to eq(nil)
            end
          end
        end
      end

      RSpec.describe StaticParam do
        include RuntimeMetadataSupport

        describe "#value_for" do
          it "returns the param's static value regardless of the given data hash" do
            param = static_param_with(17)

            value = param.value_for({"value" => 12})

            expect(value).to eq(17)
          end
        end
      end
    end
  end
end

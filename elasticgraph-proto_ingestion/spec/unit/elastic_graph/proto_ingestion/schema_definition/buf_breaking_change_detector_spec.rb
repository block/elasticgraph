# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/buf_breaking_change_detector"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe BufBreakingChangeDetector do
        it "builds both schemas at one logical path and uses Buf's WIRE rules to detect breaking changes" do
          calls = stub_buf(
            build_results: [["", successful_status], ["", successful_status]],
            breaking_result: ["schema.proto: Field changed type.", failed_status(100)]
          )

          changes = described_class.new.breaking_changes(
            current_schema: %(syntax = "proto3";),
            against_schema: %(syntax = "proto2";)
          )

          expect(changes).to eq("schema.proto: Field changed type.")
          expect(calls.map { |arguments, _| arguments.fetch(1) }).to eq(["build", "build", "breaking"])
          expect(calls.first.first.fetch(2)).to start_with(::Dir.pwd)
          expect(calls.first.first.fetch(2)).to eq(calls.fetch(1).first.fetch(2))
          expect(calls.last.first).to include(
            "--exclude-imports",
            "--config",
            described_class::BREAKING_CONFIG_JSON
          )
        end

        it "returns nil when Buf finds no breaking changes" do
          stub_buf(
            build_results: [["", successful_status], ["", successful_status]],
            breaking_result: ["", successful_status]
          )

          expect(described_class.new.breaking_changes(current_schema: "current", against_schema: "against")).to be_nil
        end

        it "raises a clear error when Buf cannot compile a schema" do
          stub_buf(build_results: [["invalid proto", failed_status(1)]])

          expect {
            described_class.new.breaking_changes(current_schema: "current", against_schema: "against")
          }.to raise_error Errors::SchemaError, a_string_including(
            "compile the current protobuf schema",
            "invalid proto"
          )
        end

        it "identifies which prior schema failed to compile even when Buf provides no diagnostics" do
          stub_buf(build_results: [["", successful_status], ["", failed_status(1)]])

          expect {
            described_class.new.breaking_changes(current_schema: "current", against_schema: "against")
          }.to raise_error Errors::SchemaError, a_string_including(
            "compile the against protobuf schema",
            "Buf did not provide any diagnostics."
          )
        end

        it "raises a clear error when the breaking check itself fails" do
          stub_buf(
            build_results: [["", successful_status], ["", successful_status]],
            breaking_result: ["bad config", failed_status(1)]
          )

          expect {
            described_class.new.breaking_changes(current_schema: "current", against_schema: "against")
          }.to raise_error Errors::SchemaError, a_string_including("compare the protobuf schemas", "bad config")
        end

        it "raises an actionable error when Buf is not installed" do
          allow(::Open3).to receive(:capture3).and_raise(::Errno::ENOENT)

          expect {
            described_class.new.breaking_changes(current_schema: "current", against_schema: "against")
          }.to raise_error Errors::SchemaError, a_string_including(
            "Buf CLI is required",
            "https://buf.build/docs/installation"
          )
        end

        context "with the real Buf CLI", :in_temp_dir, :requires_buf do
          let(:original_schema) do
            widget_schema(<<~EOS)
              optional string id = 1;
              optional string name = 2;
              optional int32 count = 3;
            EOS
          end

          let(:schema_without_count) do
            widget_schema(<<~EOS)
              optional string id = 1;
              optional string name = 2;
              reserved 3; // Previously used by count.
            EOS
          end

          it "allows adding a field" do
            expect(breaking_changes_from(original_schema, to: original_schema.sub("optional int32 count = 3;", "optional int32 count = 3;\n  optional string color = 4;"))).to be_nil
          end

          it "allows removing a field whose number is reserved" do
            expect(breaking_changes_from(original_schema, to: schema_without_count)).to be_nil
          end

          it "allows renaming a field that keeps its number" do
            expect(breaking_changes_from(original_schema, to: original_schema.sub("int32 count = 3;", "int32 total = 3;"))).to be_nil
          end

          it "allows wire-compatible type changes" do
            expect(breaking_changes_from(original_schema, to: original_schema.sub("int32 count", "int64 count"))).to be_nil
          end

          it "rejects wire-incompatible type changes" do
            expect(breaking_changes_from(original_schema, to: original_schema.sub("int32 count", "string count"))).to include(
              "schema.proto",
              'changed type from "int32" to "string"'
            )
          end

          it "rejects changing a single-valued field into a list" do
            expect(breaking_changes_from(original_schema, to: original_schema.sub("optional int32 count", "repeated int32 count"))).to include(
              'changed cardinality from "optional with explicit presence" to "repeated"'
            )
          end

          it "rejects restoring a removed field, which would drop its reservation" do
            expect(breaking_changes_from(schema_without_count, to: original_schema)).to include(
              'Previously present reserved range "[3]" on message "Widget" is missing values: [3] were removed.'
            )
          end

          def breaking_changes_from(against_schema, to:)
            described_class.new.breaking_changes(current_schema: to, against_schema: against_schema)
          end

          def widget_schema(fields)
            <<~EOS
              syntax = "proto3";
              package elasticgraph;

              message Widget {
              #{fields.lines.map { |line| "  #{line}" }.join.chomp}
              }
            EOS
          end
        end

        def stub_buf(build_results:, breaking_result: nil)
          calls = []
          remaining_build_results = build_results.dup

          allow(::Open3).to receive(:capture3) do |*arguments, **options|
            calls << [arguments, options]
            stdout_and_status = if arguments.fetch(1) == "build"
              remaining_build_results.shift
            else
              breaking_result
            end

            output, status = stdout_and_status
            [output, "", status]
          end

          calls
        end

        def successful_status
          instance_double(::Process::Status, success?: true, exitstatus: 0)
        end

        def failed_status(exitstatus)
          instance_double(::Process::Status, success?: false, exitstatus: exitstatus)
        end
      end
    end
  end
end

# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "stringio"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe Schema, "schema evolution" do
        it "persists message, field, and nested-list wrapper names after rename declarations disappear" do
          old = define_account_schema(field_name: "scores", type: "[[Int]]")
          renamed = define_proto_schema_results(old) do |schema|
            schema.object_type "Customer" do |type|
              type.renamed_from "Account"
              type.field "id", "ID"
              type.field "points", "[[Int]]" do |field|
                field.renamed_from "scores"
              end
              type.index "accounts"
            end
          end
          current = define_proto_schema_results(renamed) do |schema|
            schema.object_type "Customer" do |type|
              type.field "id", "ID"
              type.field "points", "[[Int]]"
              type.index "accounts"
            end
          end

          expect(current.proto_schema).to eq(renamed.proto_schema)
          expect(current.proto_schema).to include("message Account", "message ScoresList", "ScoresList scores = 2;", ".elasticgraph.Account account = 5;")
          expect(current.proto_field_number_mappings.dig("messages", "Customer")).to include("proto_name" => "Account", "previous_names" => ["Account"])
          expect(ingestion_config(current)).to include(
            "types" => {"Account" => "Customer"}, "type_aliases" => {"Account" => "Account"},
            "fields" => {"Account" => {"scores" => {"public_name" => "points"}}}
          )
        end

        it "keeps enum type, value, and unspecified names stable after both rename declarations disappear" do
          old = define_status_schema
          renamed = define_status_schema(old, enum_name: "State", value_name: "ENABLED", renamed: true)
          current = define_status_schema(renamed, enum_name: "State", value_name: "ENABLED")

          expect(current.proto_schema).to eq(renamed.proto_schema)
          expect(current.proto_schema).to include("enum Status", "STATUS_UNSPECIFIED = 0;", "STATUS_ACTIVE = 1;", ".elasticgraph.Status status = 2;")
          expect(ingestion_config(current)).to include("types" => {"Status" => "State"}, "enum_values" => {"Status" => {"STATUS_ACTIVE" => "ENABLED"}})
        end

        it "widens integers directionally, reports the source break, and retains the wider contract on narrowing" do
          old = define_account_schema(type: "Int")
          output = StringIO.new
          wider = define_account_schema(old, type: "JsonSafeLong", output: output)
          expect(wider.proto_schema).to include("int64 score = 2;")
          expect(output.string).to include("Source-breaking protobuf widening", "int32 to int64", "Upgrade downstream readers")
          narrower = define_account_schema(wider, type: "Int")
          expect(narrower.proto_schema).to include("int64 score = 2;", "Accepted range: -2147483648 to 2147483647")
          expect(ingestion_config(narrower).dig("fields", "Account", "score")).to eq({"type" => "Int"})
        end

        it "preserves values under integer overrides but rejects signedness, boolean, and bytes/string reinterpretation" do
          %w[sint32 uint32].each do |old_type|
            new_type = old_type.sub("32", "64")
            old = define_account_schema(proto_type: old_type)
            wider = define_account_schema(old, proto_type: new_type)
            expect(wider.proto_schema).to include("#{new_type} score = 2;")
            narrower = define_account_schema(wider, proto_type: old_type)
            expect(narrower.proto_schema).to include("#{new_type} score = 2;")
          end
          [["int32", "uint32"], ["int32", "bool"], ["bytes", "string"], ["float", "double"]].each do |old_type, new_type|
            old = define_account_schema(proto_type: old_type)
            expect { define_account_schema(old, proto_type: new_type) }.to raise_error(Errors::SchemaError, a_string_including("Incompatible protobuf change", "protobuf name:"))
          end
        end

        it "rotates incompatible type or list-shape changes and retains all retired incarnations" do
          old = define_account_schema(type: "Int")
          expect { define_account_schema(old, type: "String") }.to raise_error(Errors::SchemaError, a_string_including("Incompatible protobuf change", "score_new"))
          rotated = define_account_schema(old, type: "String", proto_name: "score_str")
          expect(rotated.proto_schema).to include("string score_str = 3;", "reserved 2; // Previously used by score.")
          expect(ingestion_config(rotated).dig("fields", "Account", "score_str")).to eq({"public_name" => "score"})
          expect(rotated.proto_field_number_mappings.dig("messages", "Account", "retired_fields", "score")).to include("field_number" => 2, "proto_type" => "int32", "list_depth" => 0, "deleted" => true)
          expect { define_account_schema(rotated, type: "[String]", proto_name: "score_str") }.to raise_error(Errors::SchemaError, a_string_including("list depth 1"))
          expect { define_account_schema(rotated, type: "Boolean", proto_name: "score") }
            .to raise_error(Errors::SchemaError, a_string_including("retired with a different wire contract"))
          repeated = define_account_schema(rotated, type: "[String]", proto_name: "scores")
          expect(repeated.proto_schema).to include("repeated string scores = 4;", "reserved 2;", "reserved 3;")
          restored = define_account_schema(repeated, type: "Int", proto_name: "score")
          expect(restored.proto_schema).to include("int32 score = 2;", "reserved 3;", "reserved 4;").and exclude("reserved 2;")
        end

        it "makes a compatible explicit source rename keep its number and warns about generated-code changes" do
          old = define_account_schema
          output = StringIO.new
          current = define_account_schema(old, proto_name: "points", output: output)
          expect(current.proto_schema).to include("int32 points = 2;").and exclude("reserved 2;")
          expect(output.string).to include("Source-breaking protobuf rename", "Account.score", "points")
          expect { define_account_schema(current, field_name: "score", extra: 't.field "old_score", "Int" do |f|; f.protobuf name: "score"; end') }
            .to raise_error(Errors::SchemaError, a_string_including("already retained", "score"))
        end

        it "requires explicit field and type deletions and persists them after the declarations disappear" do
          old = define_account_schema
          expect { define_account_schema(old, omit_score: true) }.to raise_error(Errors::SchemaError, a_string_including("Account.score", "deleted_field"))
          deleted = define_account_schema(old, omit_score: true, extra: 't.deleted_field "score"')
          current = define_account_schema(deleted, omit_score: true)
          expect(current.proto_field_number_mappings).to eq(deleted.proto_field_number_mappings)
          expect(current.proto_schema).to include("reserved 2; // Previously used by score.")
          expect { define_account_schema(deleted, field_name: "unrelated", proto_name: "score") }
            .to raise_error(Errors::SchemaError, a_string_including("already retained", "restore the original"))
          expect {
            define_proto_schema_results(old) { |schema|
              schema.object_type("Other") { |type|
                type.field "id", "ID"
                type.index "others"
              }
            }
          }
            .to raise_error(Errors::SchemaError, a_string_including("Account", "deleted_type"))
        end

        it "keeps an empty envelope and deletion metadata when the last ingestible type is deleted" do
          old = define_account_schema
          deleted = define_proto_schema_results(old) { |schema| schema.deleted_type "Account" }
          current = define_proto_schema_results(deleted) {}
          expect(current.proto_schema).to include("message ElasticGraphEventEnvelope", "message ElasticGraphEventBatch", "reserved 5; // Previously used by account.")
          expect(ingestion_config(current)).to include("deleted_types" => ["Account"], "reserved_envelope_fields" => {"5" => "Account"})
        end

        it "does not treat a still-defined type removed from ingestion as deleted" do
          old = define_account_schema
          current = define_proto_schema_results(old) do |schema|
            schema.object_type("Account") { |type|
              type.field "id", "ID"
              type.field "score", "Int"
            }
          end
          expect(current.proto_schema).to include("reserved 5;")
          expect(ingestion_config(current)).not_to have_key("deleted_types")
          expect(ingestion_config(current)).not_to have_key("reserved_envelope_fields")
        end

        it "reconciles retained type and field renames even while the type is no longer reachable for ingestion" do
          old = define_account_schema
          unreachable = define_proto_schema_results(old) do |schema|
            schema.object_type "Customer" do |type|
              type.renamed_from "Account"
              type.field "id", "ID"
              type.field("points", "Int") { |field| field.renamed_from "score" }
            end
          end
          restored = define_proto_schema_results(unreachable) do |schema|
            schema.object_type "Customer" do |type|
              type.field "id", "ID"
              type.field "points", "Int"
              type.index "accounts"
            end
          end
          expect(unreachable.proto_field_number_mappings.dig("messages", "Customer", "fields", "points")).to include("field_number" => 2, "proto_name" => "score")
          expect(ingestion_config(unreachable)).not_to have_key("deleted_types")
          expect(restored.proto_schema).to include("message Account", "int32 score = 2;", ".elasticgraph.Account account = 5;")
        end

        it "retains active wire name collisions after a field rotation whose public name equals its retired wire name" do
          old = define_account_schema
          rotated = define_account_schema(old, type: "String", proto_name: "score_str")
          expect { define_account_schema(rotated, type: "String", extra: 't.field "unrelated", "String" do |f|; f.protobuf name: "score_str"; end') }
            .to raise_error(Errors::SchemaError, a_string_including("already retained", "score_str"))
        end

        it "restores a compatible retired incarnation after its active public identity has been renamed" do
          old = define_account_schema
          rotated = define_account_schema(old, type: "String", proto_name: "score_str")
          renamed = define_proto_schema_results(rotated) do |schema|
            schema.object_type "Account" do |type|
              type.field "id", "ID"
              type.field("points", "String") { |field| field.renamed_from "score" }
              type.index "accounts"
            end
          end
          [true, false].each do |declaration|
            restored = define_proto_schema_results(renamed) do |schema|
              schema.object_type "Account" do |type|
                type.field "id", "ID"
                type.field("points", "Int") do |field|
                  field.renamed_from "score" if declaration
                  field.protobuf name: "score"
                end
                type.index "accounts"
              end
            end
            current = define_account_schema(restored, field_name: "points", proto_name: "score")
            expect(current.proto_schema).to include("int32 score = 2;", "reserved 3;").and exclude("reserved 2;")
            expect(current.proto_field_number_mappings.dig("messages", "Account", "fields", "points", "previous_names")).to include("score")
          end
        end

        it "rejects reuse of an active field's historical public alias, even with a fresh or retired wire name" do
          old = define_account_schema(field_name: "full_name")
          renamed = define_proto_schema_results(old) do |schema|
            schema.object_type "Account" do |type|
              type.field "id", "ID"
              type.field("name", "Int") { |field| field.renamed_from "full_name" }
              type.index "accounts"
            end
          end
          [false, true].each do |rotated|
            prior = renamed
            if rotated
              prior = define_proto_schema_results(renamed) do |schema|
                schema.object_type "Account" do |type|
                  type.field "id", "ID"
                  type.field("name", "String") { |field| field.protobuf name: "name_str" }
                  type.index "accounts"
                end
              end
            end
            ["full_name", "unrelated_wire"].each do |wire_name|
              expect {
                define_proto_schema_results(prior) do |schema|
                  schema.object_type "Account" do |type|
                    type.field "id", "ID"
                    type.field("name", rotated ? "String" : "Int") { |field| field.protobuf name: "name_str" if rotated }
                    type.field("full_name", "Int") { |field| field.protobuf name: wire_name }
                    type.index "accounts"
                  end
                end
              }.to raise_error(Errors::SchemaError, a_string_including("already retained", "full_name", "name"))
            end
          end
        end

        it "records retired enum numbers and prevents a renamed value's historical source name being reused" do
          old = define_status_schema
          deleted = define_status_schema(old, value_name: "PAUSED")
          expect(ingestion_config(deleted).fetch("retired_enum_values")).to eq({"Status" => [1]})
          renamed = define_status_schema(old, value_name: "ENABLED", renamed_value: true)
          expect { define_status_schema(renamed, value_name: "ENABLED", extra_values: ['t.value "ACTIVE"']) }
            .to raise_error(Errors::SchemaError, a_string_including("already retained"))
        end

        it "retains unknown legacy tombstones without inventing their historical types" do
          old = define_account_schema
          mappings = old.proto_field_number_mappings
          mappings.fetch("messages").fetch("Account").fetch("fields")["legacy"] = 3
          mappings.fetch("messages").fetch("Account")["next_number"] = 4
          current = define_account_schema(proto_field_number_mappings: mappings, extra: 't.deleted_field "legacy"')
          expect(current.proto_field_number_mappings.dig("messages", "Account", "fields", "legacy")).to eq({"field_number" => 3, "deleted" => true})
          expect { define_account_schema(current, extra: 't.field "legacy", "Int"') }
            .to raise_error(Errors::SchemaError, a_string_including("legacy mapping has no historical proto_type", "Record the original wire contract"))
        end

        it "bootstraps active legacy list contracts and reports the unchanged-schema migration requirement once" do
          old = define_account_schema(type: "[[Int]]")
          mappings = old.proto_field_number_mappings
          mappings.fetch("messages").each_value do |message|
            message.fetch("fields").transform_values! { |field| field.fetch("field_number") }
          end
          output = StringIO.new
          current = define_account_schema(type: "[[Int]]", proto_field_number_mappings: mappings, output: output)
          expect(current.proto_schema).to eq(old.proto_schema)
          expect(current.proto_field_number_mappings).to eq(old.proto_field_number_mappings)
          expect(output.string.lines.grep(/Migrating legacy/).size).to eq(1)
          expect(output.string).to include("Dump the unchanged schema before evolving it")
        end

        it "exposes the initial protobuf message name before its historical contract is resolved" do
          names = []
          define_proto_schema_results do |schema|
            schema.object_type "Account" do |type|
              names << type.proto_name
              type.field "id", "ID"
              type.index "accounts"
            end
          end
          expect(names).to eq(["Account"])
        end

        it "rejects invalid explicitly configured protobuf field identifiers before writing artifacts" do
          ["1score", "score-new", "score name", ""].each do |name|
            expect { define_account_schema(proto_name: name) }
              .to raise_error(Errors::SchemaError, a_string_including("Invalid protobuf field name", "expected a protobuf identifier"))
          end
        end

        it "produces the same resolved metadata regardless of artifact accessor order" do
          old = define_account_schema
          build_results = lambda do
            define_schema(extension_modules: [APIExtension], schema_element_name_form: :snake_case) do |schema|
              schema.state.proto_ingestion_state.field_number_mappings = old.proto_field_number_mappings
              schema.object_type "Customer" do |type|
                type.renamed_from "Account"
                type.field "id", "ID"
                type.field "score", "JsonSafeLong"
                type.index "accounts"
              end
            end
          end
          metadata_first = build_results.call
          metadata = ingestion_config(metadata_first)
          proto_first = build_results.call
          proto = proto_first.proto_schema
          expect(metadata).to eq(ingestion_config(proto_first))
          expect(metadata_first.proto_schema).to eq(proto)
          expect(metadata_first.proto_field_number_mappings).to eq(proto_first.proto_field_number_mappings)
        end

        private

        def define_account_schema(prior = nil, field_name: "score", type: "Int", proto_name: nil, proto_type: nil, omit_score: false, extra: "", **options)
          define_proto_schema_results(prior, **options) do |schema|
            if proto_type
              schema.scalar_type "Value" do |scalar|
                scalar.mapping type: "long"
                scalar.protobuf type: proto_type
              end
              type = "Value"
            end
            schema.object_type "Account" do |account|
              account.field "id", "ID"
              account.field(field_name, type) { |field| field.protobuf name: proto_name if proto_name } unless omit_score
              account.instance_eval(extra.delete_prefix("t.").gsub("; t.", "; self.")) unless extra.empty?
              account.index "accounts"
            end
          end
        end

        def define_status_schema(prior = nil, enum_name: "Status", value_name: "ACTIVE", renamed: false, renamed_value: false, extra_values: [])
          define_proto_schema_results(prior) do |schema|
            schema.enum_type enum_name do |enum|
              enum.renamed_from "Status" if renamed
              enum.value(value_name) { |value| value.renamed_from "ACTIVE" if renamed || renamed_value }
              extra_values.each { |source| enum.instance_eval(source.delete_prefix("t.")) }
            end
            schema.object_type "Account" do |type|
              type.field "id", "ID"
              type.field "status", enum_name
              type.index "accounts"
            end
          end
        end

        def ingestion_config(results)
          results.runtime_metadata.indexer_extension_modules.find { |extension| extension.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension" }.extension_ref.fetch("config")
        end
      end
    end
  end
end

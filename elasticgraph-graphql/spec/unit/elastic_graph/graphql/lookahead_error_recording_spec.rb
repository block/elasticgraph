# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_executor"
require "elastic_graph/graphql/schema"

module ElasticGraph
  class GraphQL
    # Exercises `QueryContext#record_lookahead_error` (see `docs/adr/0001-lookahead-error-record-key.md`)
    # purely through GraphQL query execution against custom resolvers backed by static data--no
    # datastore, indexer, or admin component needed--so this covers the same ground as a
    # `LookaheadErrors`-internals unit spec would, but through the same test seam
    # (`register_graphql_resolver` + `graphql_query_executor.execute`) as our other resolver specs,
    # rather than by calling `LookaheadErrors` directly.
    RSpec.describe "lookahead error recording", :capture_logs do
      attr_accessor :schema_artifacts

      # Registered under these constant names (via `::Object.const_set` below) so
      # `register_graphql_resolver`'s `defined_at: __FILE__` has a real, nameable class to point
      # at. Built once, in `before(:context)`, since `generate_schema_artifacts` is expensive and
      # nothing here varies per example.
      before(:context) do
        static_value_resolver_class = Class.new do
          def initialize(elasticgraph_graphql:, config:)
          end

          def resolve(field:, object:, args:, context:)
            # :nocov: -- the whole point of this resolver is that it never runs once flagged.
            "should never be resolved once flagged"
            # :nocov:
          end
        end

        # Flags the `flagged`/`details` subfields of its own `widgets` list (whenever selected) and
        # returns static data, exactly as `Aggregation::QueryAdapter#computation_for` flags an
        # out-of-range `approximatePercentile` selection--except this is a plain resolver, not a
        # datastore query adapter, proving `record_lookahead_error` is usable directly by one.
        # `emptyList:` lets a test simulate the recording field itself resolving to no elements.
        widgets_resolver_class = Class.new do
          def initialize(elasticgraph_graphql:, config:)
          end

          def resolve(field:, object:, args:, context:, lookahead:)
            flagged_node = lookahead.selection("flagged")
            context.record_lookahead_error(flagged_node, "flagged field is invalid") if flagged_node.selected?

            details_node = lookahead.selection("details")
            context.record_lookahead_error(details_node, "details field is invalid") if details_node.selected?

            args["emptyList"] ? [] : [{"id" => "1"}, {"id" => "2"}]
          end
        end

        # A scalar-returning resolver that flags *itself* (rather than a descendant) when invalid,
        # then reuses `matching_lookahead_error` to report it--the same mechanism a descendant flag
        # would use--instead of raising directly.
        risky_value_resolver_class = Class.new do
          def initialize(elasticgraph_graphql:, config:)
          end

          def resolve(field:, object:, args:, context:, lookahead:)
            context.record_lookahead_error(lookahead, "threshold too high") if args.fetch("threshold") > 100

            context.matching_lookahead_error || args.fetch("threshold")
          end
        end

        # Simulates a caller bug: flags a node that isn't at or beneath the field being resolved
        # (here, an unrelated sibling top-level field).
        misrooted_recording_resolver_class = Class.new do
          def initialize(elasticgraph_graphql:, config:)
          end

          # No return value: the `record_lookahead_error` call raises.
          def resolve(field:, object:, args:, context:, lookahead:)
            context.record_lookahead_error(context.query.lookahead.selection("riskyValue"), "misrooted")
          end
        end

        # Simulates a caller bug: flags a descendant field the client did not select (which is what a
        # typo'd `selection` name looks like, since `Lookahead#selection` returns a null object).
        unselected_flagging_resolver_class = Class.new do
          def initialize(elasticgraph_graphql:, config:)
          end

          # No return value: the `record_lookahead_error` call raises.
          def resolve(field:, object:, args:, context:, lookahead:)
            context.record_lookahead_error(lookahead.selection("flagged"), "unselected")
          end
        end

        ::Object.const_set(:StaticValueResolver, static_value_resolver_class)
        ::Object.const_set(:WidgetsResolver, widgets_resolver_class)
        ::Object.const_set(:RiskyValueResolver, risky_value_resolver_class)
        ::Object.const_set(:MisrootedRecordingResolver, misrooted_recording_resolver_class)
        ::Object.const_set(:UnselectedFlaggingResolver, unselected_flagging_resolver_class)

        self.schema_artifacts = generate_schema_artifacts do |schema|
          schema.register_graphql_resolver :static_value, StaticValueResolver, defined_at: __FILE__
          schema.register_graphql_resolver :widgets, WidgetsResolver, defined_at: __FILE__
          schema.register_graphql_resolver :risky_value, RiskyValueResolver, defined_at: __FILE__
          schema.register_graphql_resolver :misrooted_recording, MisrootedRecordingResolver, defined_at: __FILE__
          schema.register_graphql_resolver :unselected_flagging, UnselectedFlaggingResolver, defined_at: __FILE__

          schema.object_type "WidgetDetails" do |t|
            t.field "value", "String"
          end

          schema.object_type "Widget" do |t|
            t.field "id", "ID"
            t.field "flagged", "String", graphql_only: true do |f|
              f.resolve_with :static_value
            end
            t.field "details", "WidgetDetails", graphql_only: true do |f|
              f.resolve_with :static_value
            end
          end

          schema.on_root_query_type do |t|
            t.field "widgets", "[Widget]" do |f|
              f.argument "emptyList", "Boolean" do |a|
                a.default false
              end
              f.resolve_with :widgets
            end

            t.field "riskyValue", "Int" do |f|
              f.argument "threshold", "Int"
              f.resolve_with :risky_value
            end

            t.field "misrootedRecording", "[Widget]" do |f|
              f.resolve_with :misrooted_recording
            end

            t.field "unselectedFlagging", "[Widget]" do |f|
              f.resolve_with :unselected_flagging
            end
          end
        end
      end

      after(:context) do
        # standard:disable RSpec/RemoveConst
        ::Object.send(:remove_const, :StaticValueResolver)
        ::Object.send(:remove_const, :WidgetsResolver)
        ::Object.send(:remove_const, :RiskyValueResolver)
        ::Object.send(:remove_const, :MisrootedRecordingResolver)
        ::Object.send(:remove_const, :UnselectedFlaggingResolver)
        # standard:enable RSpec/RemoveConst
      end

      before do
        # Stub the `require` call `register_graphql_resolver` triggers for `defined_at:`. If we allow
        # it to load this spec file it'll mess with our reported code coverage (as done elsewhere in
        # the codebase for the same reason, e.g. `query_executor_spec.rb`).
        allow(SchemaArtifacts::RuntimeMetadata::GraphQLResolver.without_lookahead_loader).to receive(:require)
        allow(SchemaArtifacts::RuntimeMetadata::GraphQLResolver.with_lookahead_loader).to receive(:require)
      end

      let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }

      it "halts just the flagged field's subtree, resolving it to `null` with a precisely-pathed error, while sibling fields, other list items, and an unrelated top-level field resolve normally--including when the flagged field is selected under multiple aliases" do
        response = nil
        expect {
          response = graphql.graphql_query_executor.execute(<<~QUERY).to_h
            query {
              widgets {
                id
                a: flagged
                b: flagged
              }
              riskyValue(threshold: 10)
            }
          QUERY
        }.to log_warning(a_string_including("flagged field is invalid"))

        expect(response.dig("data", "widgets")).to contain_exactly(
          {"id" => "1", "a" => nil, "b" => nil},
          {"id" => "2", "a" => nil, "b" => nil}
        )
        # `riskyValue` has nothing to do with `widgets`' recorded errors--proves a resolved path
        # with an entirely different prefix than any recorded path just doesn't match.
        expect(response.dig("data", "riskyValue")).to eq 10

        expect(response.fetch("errors")).to contain_exactly(
          hash_including("message" => "flagged field is invalid", "path" => ["widgets", 0, "a"]),
          hash_including("message" => "flagged field is invalid", "path" => ["widgets", 0, "b"]),
          hash_including("message" => "flagged field is invalid", "path" => ["widgets", 1, "a"]),
          hash_including("message" => "flagged field is invalid", "path" => ["widgets", 1, "b"])
        )
      end

      it "halts an entire object subtree, not just a leaf, when the flagged node is a non-leaf (object) field" do
        response = nil
        expect {
          response = graphql.graphql_query_executor.execute(<<~QUERY).to_h
            query {
              widgets {
                id
                details {
                  value
                }
              }
            }
          QUERY
        }.to log_warning(a_string_including("details field is invalid"))

        expect(response.dig("data", "widgets")).to eq [
          {"id" => "1", "details" => nil},
          {"id" => "2", "details" => nil}
        ]
        expect(response.fetch("errors")).to contain_exactly(
          hash_including("message" => "details field is invalid", "path" => ["widgets", 0, "details"]),
          hash_including("message" => "details field is invalid", "path" => ["widgets", 1, "details"])
        )
      end

      it "does not flag (or halt) the field when it is not even selected" do
        response = graphql.graphql_query_executor.execute(<<~QUERY).to_h
          query {
            widgets {
              id
            }
          }
        QUERY

        expect(response.dig("data", "widgets")).to eq [{"id" => "1"}, {"id" => "2"}]
        expect(response).not_to have_key("errors")
      end

      it "silently ignores a recorded error GraphQL execution never reaches, such as when the recording field itself resolves to an empty list" do
        response = graphql.graphql_query_executor.execute(<<~QUERY).to_h
          query {
            widgets(emptyList: true) {
              id
              flagged
            }
          }
        QUERY

        expect(response.dig("data", "widgets")).to eq []
        expect(response).not_to have_key("errors")
      end

      it "lets a resolver flag itself (rather than a descendant) and report the error via `matching_lookahead_error`" do
        invalid = nil
        expect {
          invalid = graphql.graphql_query_executor.execute("query { riskyValue(threshold: 150) }").to_h
        }.to log_warning(a_string_including("threshold too high"))

        expect(invalid.dig("data", "riskyValue")).to eq nil
        expect(invalid.fetch("errors")).to contain_exactly(
          hash_including("message" => "threshold too high", "path" => ["riskyValue"])
        )

        valid = graphql.graphql_query_executor.execute("query { riskyValue(threshold: 50) }").to_h
        expect(valid.to_h).to eq({"data" => {"riskyValue" => 50}})
      end

      it "raises when the flagged node is not at or beneath the field being resolved", :expect_warning_logging do
        expect {
          graphql.graphql_query_executor.execute("query { misrootedRecording { id } riskyValue(threshold: 10) }")
        }.to raise_error(Errors::ConfigError, a_string_including("misrootedRecording", "not selected at or beneath"))
      end

      it "raises when the flagged node is not selected at all", :expect_warning_logging do
        expect {
          graphql.graphql_query_executor.execute("query { unselectedFlagging { id } }")
        }.to raise_error(Errors::ConfigError, a_string_including("unselectedFlagging", "not selected at or beneath"))
      end
    end
  end
end

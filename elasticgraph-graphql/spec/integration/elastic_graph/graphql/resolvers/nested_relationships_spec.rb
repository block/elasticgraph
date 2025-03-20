# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/nested_relationships"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe NestedRelationships, :factories, :uses_datastore, :capture_logs, :resolver do
        # :expect_search_routing because the relation we use here uses an outbaund foreign key, which
        # is implemented via a filter on `id` (the search routing field)
        context "when the field being resolved is a relay connection field", :expect_search_routing do
          let(:graphql) do
            build_graphql(schema_definition: lambda do |schema|
              schema.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_one "widget", "Widget!", via: "component_ids", dir: :in
                t.index "components" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "workspace_id", "ID", name_in_index: "workspace_id2"
                t.field "created_at", "DateTime!"
                t.relates_to_many "components", "Component", via: "component_ids", dir: :out, singular: "component"
                t.index "widgets" do |i|
                  i.rollover :yearly, "created_at"
                  i.route_with "workspace_id"
                  i.default_sort "created_at", :desc
                end
              end
            end)
          end

          let(:component1) { build(:component) }

          it "wraps the datastore response in a relay connection adapter when the field is a relay connection field" do
            result = resolve("Widget", "components", {"component_ids" => [component1.fetch(:id)]})

            expect(result).to be_a RelayConnection::GenericAdapter
          end

          it "wraps the datastore response in a relay connection adapter when the foreign key field is missing" do
            expect {
              result = resolve("Widget", "components", {"name" => "a"})

              expect(result).to be_a(RelayConnection::GenericAdapter)
              expect(result.edges).to be_empty
            }.to log a_string_including("Widget(id: <no id>).components", "component_ids is missing from the document")
          end
        end

        describe "a relates_to_many/relates_to_one bidirectional relationship with an array foreign key from the one to the many" do
          let(:graphql) do
            build_graphql(schema_definition: lambda do |schema|
              schema.object_type "Money" do |t|
                t.field "currency", "String!"
                t.field "amount_cents", "Int"
              end

              schema.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_one "widget", "Widget!", via: "component_ids", dir: :in
                t.relates_to_one "dollar_widget", "Widget", via: "component_ids", dir: :in do |rel|
                  rel.additional_filter cost: {amount_cents: {equal_to_any_of: [100]}}
                end
                t.relates_to_many "dollar_widgets", "Widget", via: "component_ids", dir: :in, singular: "dollar_widget" do |rel|
                  rel.additional_filter cost: {amount_cents: {equal_to_any_of: [100]}}
                end
                t.index "components" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "workspace_id", "ID", name_in_index: "workspace_id2"
                t.field "created_at", "DateTime!"
                t.field "cost", "Money"
                t.relates_to_many "components", "Component", via: "component_ids", dir: :out, singular: "component"
                t.index "widgets" do |i|
                  i.rollover :yearly, "created_at"
                  i.route_with "workspace_id"
                  i.default_sort "created_at", :desc
                end
              end
            end)
          end

          let(:component1) { build(:component, created_at: "2019-06-01T00:00:00Z") }
          let(:component2) { build(:component, created_at: "2019-06-02T00:00:00Z") }
          let(:component3) { build(:component) }
          let(:widget1) { build(:widget, amount_cents: 100, components: [component1, component2], created_at: "2019-06-01T00:00:00Z") }
          let(:widget2) { build(:widget, components: [component2], created_at: "2019-06-02T00:00:00Z") }
          let(:widget3) { build(:widget, amount_cents: 200, components: [component3], created_at: "2019-06-03T00:00:00Z") }

          # :expect_search_routing because the relation we use here uses an outbaund foreign key, which
          # is implemented via a filter on `id` (the search routing field)
          context "loading the relates_to_many", :expect_search_routing do
            before do
              index_into(graphql, component1, component2, component3, widget1, widget2, widget3)
            end

            it "loads the relationship and respects defaultSort" do
              result = resolve_nodes("Widget", "components", {"component_ids" => [component1.fetch(:id), component2.fetch(:id)]})

              expect(result.map { |c| c.fetch("id") }).to eq([component2.fetch(:id), component1.fetch(:id)])
            end

            it "respects a list of `order_by` options, supporting ascending and descending sorts" do
              result = resolve_nodes("Widget", "components",
                {"component_ids" => [component2.fetch(:id), component3.fetch(:id), component1.fetch(:id)]},
                order_by: ["created_at_ASC"])
              expect(result.map { |c| c.fetch("id") }).to eq([component1.fetch(:id), component2.fetch(:id), component3.fetch(:id)])

              result = resolve_nodes("Widget", "components",
                {"component_ids" => [component2.fetch(:id), component3.fetch(:id), component1.fetch(:id)]},
                order_by: ["created_at_DESC"])
              expect(result.map { |c| c.fetch("id") }).to eq([component3.fetch(:id), component2.fetch(:id), component1.fetch(:id)])
            end

            it "tolerates not finding some ids" do
              result = resolve_nodes("Widget", "components", {"component_ids" => [component1.fetch(:id), build(:component).fetch(:id)]})

              expect(result.map { |c| c.fetch("id") }).to contain_exactly(component1.fetch(:id))
            end

            it "returns an empty list when given a blank list of ids" do
              result = resolve_nodes("Widget", "components", {"component_ids" => []})

              expect(result).to be_empty
            end

            it "returns a list of a single record (and logs a warning) when the foreign key field is a scalar instead of a list" do
              expect {
                result = resolve_nodes("Widget", "components", {"component_ids" => component1.fetch(:id), "id" => "123"})

                expect(result.map { |c| c.fetch("id") }).to contain_exactly(component1.fetch(:id))
              }.to log a_string_including("Widget(id: 123).components", "component_ids: scalar instead of a list")
            end

            it "returns an empty list (and logs a warning) when the foreign key field is missing" do
              expect {
                result = resolve_nodes("Widget", "components", {"name" => "a"})

                expect(result).to be_empty
              }.to log a_string_including("Widget(id: <no id>).components", "component_ids is missing from the document")
            end

            it "returns a list of records matching additional filter conditions" do
              result = resolve_nodes("Component", "dollar_widgets", {"id" => component1.fetch(:id)}, requested_fields: ["id", "cost.amount_cents"])

              expect(result.map { |c| c.fetch("id") }).to contain_exactly(widget1.fetch(:id))
              expect(result.map { |c| c.fetch("cost").fetch("amount_cents") }).to contain_exactly(100)
            end

            it "returns an empty list when records with matching conditions are not found" do
              result = resolve_nodes("Component", "dollar_widgets", {"id" => component3.fetch(:id)}, requested_fields: ["id", "cost.amount_cents"])

              expect(result).to be_empty
            end
          end

          context "loading the relates_to_one" do
            before do
              index_into(graphql, widget1, widget2, widget3)
            end

            it "loads the relationship" do
              result = resolve("Component", "widget", {"id" => component1.fetch(:id)})

              expect(result.fetch("id")).to eq widget1.fetch(:id)
            end

            it "tolerates not finding the id" do
              result = resolve("Component", "widget", {"id" => build(:component).fetch(:id)})

              expect(result).to eq nil
            end

            it "returns nil when given a nil id" do
              result = resolve("Component", "widget", {"id" => nil})

              expect(result).to eq nil
            end

            it "returns one record (and logs a warning) when querying the datastore produces a list of records instead of a single one" do
              expect {
                # Note: inclusion of nested field `cost.amount_cents` is necessary to exercise an edge case that originally resulted in an exception.
                result = resolve("Component", "widget", {"id" => component2.fetch(:id)}, requested_fields: ["id", "cost.amount_cents"])

                expect(result.fetch("id")).to eq(widget1.fetch(:id)).or eq(widget2.fetch(:id))
                expect(result.fetch("cost").fetch("amount_cents")).to eq(widget1.fetch(:cost).fetch(:amount_cents)).or eq(widget2.fetch(:cost).fetch(:amount_cents))
              }.to log a_string_including("Component(id: #{component2.fetch(:id)}).widget", "got list of more than one item instead of a scalar from the datastore search query")
            end

            it "returns one record (and logs a warning) when the id field is a list instead of a scalar" do
              ids = [component1.fetch(:id), component3.fetch(:id)]
              expect {
                result = resolve("Component", "widget", {"id" => ids})

                expect(result.fetch("id")).to eq(widget1.fetch(:id)).or eq(widget3.fetch(:id))
              }.to log a_string_including("Component(id: #{ids}).widget", "id: list of more than one item instead of a scalar")
            end

            it "returns nil (and logs a warning) when the id field is missing" do
              expect {
                result = resolve("Component", "widget", {"name" => "foo"})

                expect(result).to eq nil
              }.to log a_string_including("Component(id: <no id>).widget", "id is missing from the document")
            end

            it "returns one record matching additional filter conditions" do
              result = resolve("Component", "dollar_widget", {"id" => component1.fetch(:id)}, requested_fields: ["id", "cost.amount_cents"])

              expect(result.fetch("id")).to eq(widget1.fetch(:id))
              expect(result.fetch("cost").fetch("amount_cents")).to eq(widget1.fetch(:cost).fetch(:amount_cents))
            end

            it "returns nil when a record with matching conditions is not found" do
              result = resolve("Component", "dollar_widget", {"id" => component3.fetch(:id)}, requested_fields: ["id", "cost.amount_cents"])

              expect(result).to eq nil
            end
          end
        end

        describe "a relates_to_many/relates_to_one bidirectional relationship with a scalar foreign key from the many to the one" do
          let(:graphql) do
            build_graphql(schema_definition: lambda do |schema|
              schema.object_type "ElectricalPart" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out
                t.index "electrical_parts" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.object_type "MechanicalPart" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out
                t.index "mechanical_parts" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.union_type "Part" do |t|
                t.subtypes "ElectricalPart", "MechanicalPart"
              end

              schema.object_type "Manufacturer" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "created_at", "DateTime!"
                t.relates_to_many "manufactured_parts", "Part", via: "manufacturer_id", dir: :in, singular: "manufactured_part"
                t.index "manufacturers"
              end
            end)
          end

          let(:manufacturer1) { build(:manufacturer, created_at: "2019-06-01T00:00:00Z") }
          let(:manufacturer2) { build(:manufacturer, created_at: "2019-06-02T00:00:00Z") }
          let(:part1) { build(:part, manufacturer: manufacturer1, created_at: "2019-06-01T00:00:00Z") }
          let(:part2) { build(:part, manufacturer: manufacturer1, created_at: "2019-06-02T00:00:00Z") }
          let(:part3) { build(:part, manufacturer: manufacturer2, created_at: "2019-06-03T00:00:00Z") }

          context "loading the relates_to_many" do
            before do
              index_into(graphql, part1, part2, part3)
            end

            it "loads the relationship and respects defaultSort" do
              result = resolve_nodes("Manufacturer", "manufactured_parts", {"id" => manufacturer1.fetch(:id)})

              expect(result.map { |c| c.fetch("id") }).to eq([part2.fetch(:id), part1.fetch(:id)])
            end

            it "respects a list of `order_by` options, supporting ascending and descending sorts" do
              result = resolve_nodes("Manufacturer", "manufactured_parts",
                {"id" => manufacturer1.fetch(:id)},
                order_by: ["created_at_ASC"])
              expect(result.map { |c| c.fetch("id") }).to eq([part1.fetch(:id), part2.fetch(:id)])

              result = resolve_nodes("Manufacturer", "manufactured_parts",
                {"id" => manufacturer1.fetch(:id)},
                order_by: ["created_at_DESC"])
              expect(result.map { |c| c.fetch("id") }).to eq([part2.fetch(:id), part1.fetch(:id)])
            end

            it "tolerates not finding records for the given id" do
              result = resolve_nodes("Manufacturer", "manufactured_parts", {"id" => build(:manufacturer).fetch(:id)})

              expect(result).to be_empty
            end

            it "returns an empty list when given a nil id" do
              result = resolve_nodes("Manufacturer", "manufactured_parts", {"id" => nil})

              expect(result).to be_empty
            end

            it "returns one of the two lists of matches (and logs a warning) when the id field is a list instead of a scalar" do
              ids = [manufacturer1.fetch(:id), manufacturer2.fetch(:id)]
              expect {
                result = resolve_nodes("Manufacturer", "manufactured_parts", {"id" => ids})

                expect(result.map { |c| c.fetch("id") }).to contain_exactly(part1.fetch(:id), part2.fetch(:id)).or eq([part3.fetch(:id)])
              }.to log a_string_including("Manufacturer(id: #{ids}).manufactured_parts", "id: list of more than one item instead of a scalar")
            end

            it "returns an empty list (and logs a warning) when the id field is missing" do
              expect {
                result = resolve_nodes("Manufacturer", "manufactured_parts", {"name" => "foo"})

                expect(result).to be_empty
              }.to log a_string_including("Manufacturer(id: <no id>).manufactured_parts", "id is missing from the document")
            end
          end

          # :expect_search_routing because the relation we use here uses an outbaund foreign key, which
          # is implemented via a filter on `id` (the search routing field)
          context "loading the relates_to_one", :expect_search_routing do
            before do
              index_into(graphql, manufacturer1, manufacturer2)
            end

            it "loads the relationship" do
              result = resolve("ElectricalPart", "manufacturer", {"manufacturer_id" => manufacturer1.fetch(:id)})

              expect(result.fetch("id")).to eq manufacturer1.fetch(:id)
            end

            it "tolerates not finding a record the given id" do
              result = resolve("ElectricalPart", "manufacturer", {"manufacturer_id" => build(:manufacturer).fetch(:id)})

              expect(result).to eq nil
            end

            it "returns nil when given a nil id" do
              result = resolve("ElectricalPart", "manufacturer", {"manufacturer_id" => nil})

              expect(result).to eq nil
            end

            it "returns one of the referenced documents (and logs a warning) when the foreign key field is a list instead of a scalar" do
              expect {
                manufacturer_ids = [manufacturer1.fetch(:id), manufacturer2.fetch(:id)]
                result = resolve("ElectricalPart", "manufacturer", {"id" => "123", "manufacturer_id" => manufacturer_ids})

                expect(result.fetch("id")).to eq(manufacturer1.fetch(:id)).or eq(manufacturer2.fetch(:id))
              }.to log a_string_including("Part(id: 123).manufacturer", "manufacturer_id: list of more than one item instead of a scalar")
            end

            it "returns nil (and logs a warning) when the foreign key field is missing" do
              expect {
                result = resolve("ElectricalPart", "manufacturer", {"id" => "123"})

                expect(result).to eq nil
              }.to log a_string_including("Part(id: 123).manufacturer", "manufacturer_id is missing from the document")
            end
          end
        end

        describe "a relates_to_many/relates_to_many bidirectional relationship with an array foreign key from a many to a many" do
          let(:graphql) do
            build_graphql(schema_definition: lambda do |schema|
              schema.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_many "parts", "Part", via: "part_ids", dir: :out, singular: "part"
                t.index "components" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.object_type "ElectricalPart" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_many "components", "Component", via: "part_ids", dir: :in, singular: "component"
                t.index "electrical_parts" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.object_type "MechanicalPart" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "created_at", "DateTime!"
                t.relates_to_many "components", "Component", via: "part_ids", dir: :in, singular: "component"
                t.index "mechanical_parts" do |i|
                  i.default_sort "created_at", :desc
                end
              end

              schema.union_type "Part" do |t|
                t.subtypes "ElectricalPart", "MechanicalPart"
              end
            end)
          end

          # Here we explicitly create parts of both unioned types. That ensures that both indices are created
          # in the datastore. Otherwise, some of the tests below may run with one or the other index missing,
          # if all 4 parts are randomly created of the same type. While we can easily work around that with
          # The datastore's `search` using `ignore_unavailable: true`, the same thing is not supported for `msearch`,
          # which we are migrating to. We do not expect this to ever be a problem outside tests, and we plan
          # to solve this in a more robust way by explicitly putting mappings into the datastore, but for now
          # this is simple work around.
          let(:part1) { build(:mechanical_part, name: "p1", created_at: "2019-06-01T00:00:00Z") }
          let(:part2) { build(:mechanical_part, name: "p2", created_at: "2019-06-02T00:00:00Z") }
          let(:part3) { build(:electrical_part, name: "p3", created_at: "2019-06-03T00:00:00Z") }
          let(:part4) { build(:electrical_part, name: "p4", created_at: "2019-06-04T00:00:00Z") }
          let(:component1) { build(:component, parts: [part1, part2], name: "c1", created_at: "2019-06-01T00:00:00Z") }
          let(:component2) { build(:component, parts: [part1, part3], name: "c2", created_at: "2019-06-02T00:00:00Z") }
          let(:component3) { build(:component, parts: [part2, part3], name: "c3", created_at: "2019-06-03T00:00:00Z") }
          let(:component4) { build(:component, name: "c4") }

          # :expect_search_routing because the relation we use here uses an outbaund foreign key, which
          # is implemented via a filter on `id` (the search routing field)
          context "loading the relates_to_many with an outbound foreign key", :expect_search_routing do
            before do
              index_into(graphql, part1, part2, part3, part4)
            end

            it "loads the relationship and respects defaultSort" do
              result = resolve_nodes("Component", "parts", {"part_ids" => [part1.fetch(:id), part2.fetch(:id)]})

              expect(result.map { |c| c.fetch("id") }).to eq([part2.fetch(:id), part1.fetch(:id)])
            end

            it "respects a list of `order_by` options, supporting ascending and descending sorts" do
              result = resolve_nodes("Component", "parts",
                {"part_ids" => [part1.fetch(:id), part2.fetch(:id)]},
                order_by: ["created_at_ASC"])
              expect(result.map { |c| c.fetch("id") }).to eq([part1.fetch(:id), part2.fetch(:id)])

              result = resolve_nodes("Component", "parts",
                {"part_ids" => [part1.fetch(:id), part2.fetch(:id)]},
                order_by: ["created_at_DESC"])
              expect(result.map { |c| c.fetch("id") }).to eq([part2.fetch(:id), part1.fetch(:id)])
            end

            it "tolerates not finding some ids" do
              result = resolve_nodes("Component", "parts", {"part_ids" => [part1.fetch(:id), build(:part).fetch(:id)]})

              expect(result.map { |c| c.fetch("id") }).to contain_exactly(part1.fetch(:id))
            end

            it "returns an empty list when given a blank list of ids" do
              result = resolve_nodes("Component", "parts", {"part_ids" => []})

              expect(result).to be_empty
            end

            it "returns a list of the matching document (and logs a warning) when the foreign key field is a scalar instead of a list" do
              expect {
                result = resolve_nodes("Component", "parts", {"id" => "123", "part_ids" => part1.fetch(:id)})

                expect(result.map { |p| p.fetch("id") }).to eq [part1.fetch(:id)]
              }.to log a_string_including("Component(id: 123).parts", "part_ids: scalar instead of a list")
            end

            it "returns an empty list" do
              expect {
                result = resolve_nodes("Component", "parts", {"id" => "123"})

                expect(result).to be_empty
              }.to log a_string_including("Component(id: 123).parts", "part_ids is missing from the document")
            end

            it "supports filtering on a non-id field" do
              results = resolve_nodes("Component", "parts", {"part_ids" => [part1.fetch(:id), part2.fetch(:id)]},
                filter: {name: {equal_to_any_of: ["p1", "p4"]}})

              expect(results.map { |c| c.fetch("id") }).to contain_exactly(part1.fetch(:id))
            end

            it "supports filtering on id" do
              results = resolve_nodes("Component", "parts", {"part_ids" => [part1.fetch(:id), part2.fetch(:id)]},
                filter: {id: {equal_to_any_of: [part1.fetch(:id), part4.fetch(:id)]}})

              expect(results.map { |c| c.fetch("id") }).to contain_exactly(part1.fetch(:id))
            end
          end

          context "loading the relates_to_many with an inbound foreign key" do
            before do
              index_into(graphql, component1, component2, component3, component4)
            end

            it "loads the relationship and supports defaultSort" do
              result = resolve_nodes("ElectricalPart", "components", {"id" => part1.fetch(:id)})

              expect(result.map { |c| c.fetch("id") }).to eq([component2.fetch(:id), component1.fetch(:id)])
            end

            it "respects a list of `order_by` options, supporting ascending and descending sorts" do
              result = resolve_nodes("ElectricalPart", "components", {"id" => part1.fetch(:id)}, order_by: ["created_at_ASC"])
              expect(result.map { |c| c.fetch("id") }).to eq([component1.fetch(:id), component2.fetch(:id)])

              result = resolve_nodes("ElectricalPart", "components", {"id" => part1.fetch(:id)}, order_by: ["created_at_DESC"])
              expect(result.map { |c| c.fetch("id") }).to eq([component2.fetch(:id), component1.fetch(:id)])
            end

            it "tolerates not finding records for the given id" do
              result = resolve_nodes("ElectricalPart", "components", {"id" => build(:part).fetch(:id)})

              expect(result).to be_empty
            end

            it "returns an empty list when given a nil id" do
              result = resolve_nodes("ElectricalPart", "components", {"id" => nil})

              expect(result).to be_empty
            end

            it "returns one of the two lists of matches (and logs a warning) when the id field is a list instead of a scalar" do
              ids = [part1.fetch(:id), part2.fetch(:id)]
              expect {
                result = resolve_nodes("ElectricalPart", "components", {"id" => ids})

                expect(result.map { |c| c.fetch("id") }).to \
                  contain_exactly(component1.fetch(:id), component2.fetch(:id)).or \
                    contain_exactly(component1.fetch(:id), component3.fetch(:id))
              }.to log a_string_including("ElectricalPart(id: #{ids}).components", "id: list of more than one item instead of a scalar")
            end

            it "returns an empty list (and logs a warning) when the id field is missing" do
              expect {
                result = resolve_nodes("ElectricalPart", "components", {"name" => "foo"})

                expect(result).to be_empty
              }.to log a_string_including("ElectricalPart(id: <no id>).components", "id is missing from the document")
            end

            it "supports filtering on a non-id field" do
              results = resolve_nodes("ElectricalPart", "components", {"id" => part1.fetch(:id)},
                filter: {name: {equal_to_any_of: ["c1", "c4"]}})

              expect(results.map { |c| c.fetch("id") }).to contain_exactly(component1.fetch(:id))
            end

            it "supports filtering on id", :expect_search_routing do
              component_ids = [component1.fetch(:id), component4.fetch(:id)]

              results = resolve_nodes("ElectricalPart", "components", {"id" => part1.fetch(:id)},
                filter: {id: {equal_to_any_of: component_ids}})

              expect(results.map { |c| c.fetch("id") }).to contain_exactly(component1.fetch(:id))
              expect_to_have_routed_to_shards_with("main", ["components", component_ids.sort.join(",")])
            end
          end
        end

        describe "a relates_to_one/relates_to_one bidirectional relationship with a scalar foreign key from a one to a one" do
          let(:graphql) do
            build_graphql(schema_definition: lambda do |schema|
              schema.object_type "Manufacturer" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.relates_to_one "address", "Address!", via: "manufacturer_id", dir: :in
                t.index "manufacturers"
              end

              schema.object_type "Address" do |t|
                t.field "id", "ID!"
                t.field "full_address", "String"
                t.relates_to_one "manufacturer", "Manufacturer!", via: "manufacturer_id", dir: :out
                t.index "addresses"
              end
            end)
          end

          let(:manufacturer1) { build(:manufacturer) }
          let(:manufacturer2) { build(:manufacturer) }
          let(:manufacturer3) { build(:manufacturer) }

          let(:address1) { build(:address, manufacturer: manufacturer1) }
          let(:address2) { build(:address, manufacturer: manufacturer2) }
          let(:address3) { build(:address, manufacturer: manufacturer2) }
          let(:address4) { build(:address, manufacturer: manufacturer3) }

          # :expect_search_routing because the relation we use here uses an outbaund foreign key, which
          # is implemented via a filter on `id` (the search routing field)
          context "loading the relates_to_one with the outbound foreign key", :expect_search_routing do
            before do
              index_into(graphql, manufacturer1, manufacturer2)
            end

            it "loads the relationship" do
              result = resolve("Address", "manufacturer", {"manufacturer_id" => manufacturer1.fetch(:id)})

              expect(result.fetch("id")).to eq manufacturer1.fetch(:id)
            end

            it "tolerates not finding a record for the given id" do
              result = resolve("Address", "manufacturer", {"manufacturer_id" => build(:manufacturer).fetch(:id)})

              expect(result).to eq nil
            end

            it "returns nil when given a nil id" do
              result = resolve("Address", "manufacturer", {"manufacturer_id" => nil})

              expect(result).to eq nil
            end

            it "returns one of the referenced documents (and logs a warning) when the foreign key field is a list instead of a scalar" do
              expect {
                manufacturer_ids = [manufacturer1.fetch(:id), manufacturer2.fetch(:id)]
                result = resolve("Address", "manufacturer", {"id" => "123", "manufacturer_id" => manufacturer_ids})

                expect(result.fetch("id")).to eq(manufacturer1.fetch(:id)).or eq(manufacturer2.fetch(:id))
              }.to log a_string_including("Address(id: 123).manufacturer", "manufacturer_id: list of more than one item instead of a scalar")
            end

            it "returns nil (and logs a warning) when the foreign key field is missing" do
              expect {
                result = resolve("Address", "manufacturer", {"id" => "123"})

                expect(result).to eq nil
              }.to log a_string_including("Address(id: 123).manufacturer", "manufacturer_id is missing from the document")
            end
          end

          context "loading the relates_to_one with the inbound foreign key" do
            before do
              index_into(graphql, address1, address2, address3, address4)
            end

            it "loads the relationship" do
              result = resolve("Manufacturer", "address", {"id" => manufacturer1.fetch(:id)})

              expect(result.fetch("id")).to eq address1.fetch(:id)
            end

            it "tolerates not finding a record for the given id" do
              result = resolve("Manufacturer", "address", {"id" => build(:manufacturer).fetch(:id)})

              expect(result).to eq nil
            end

            it "returns nil when given a nil id" do
              result = resolve("Manufacturer", "address", {"id" => nil})

              expect(result).to eq nil
            end

            it "returns one of the matching records (and logs a warning) when querying the datastore produces a list of records instead of a single one" do
              expect {
                result = resolve("Manufacturer", "address", {"id" => manufacturer2.fetch(:id)})

                expect(result.fetch("id")).to eq(address2.fetch(:id)).or eq(address3.fetch(:id))
              }.to log a_string_including("Manufacturer(id: #{manufacturer2.fetch(:id)}).address", "got list of more than one item instead of a scalar from the datastore search query")
            end

            it "returns one of the matching records (and logs a warning) when the id field is a list instead of a scalar" do
              ids = [manufacturer1.fetch(:id), manufacturer3.fetch(:id)]
              expect {
                result = resolve("Manufacturer", "address", {"id" => ids})

                expect(result.fetch("id")).to eq(address1.fetch(:id)).or eq(address4.fetch(:id))
              }.to log a_string_including("Manufacturer(id: #{ids}).address", "id: list of more than one item instead of a scalar")
            end

            it "returns nil (and logs a warning) when the id field is missing" do
              expect {
                result = resolve("Manufacturer", "address", {"name" => "foo"})

                expect(result).to eq nil
              }.to log a_string_including("Manufacturer(id: <no id>).address", "id is missing from the document")
            end
          end
        end

        describe "a relates_to_many unidirectional relationship with a nested array foreign key from the one to the many" do
          let(:graphql) { build_graphql }
          let(:sponsor1) { build(:sponsor) }
          let(:sponsor2) { build(:sponsor) }

          let(:team1) { build(:team, sponsors: [sponsor1, sponsor2]) }
          let(:team2) { build(:team, sponsors: [sponsor1]) }
          let(:team3) { build(:team, sponsors: [sponsor2]) }

          context "loading the relates_to_many in relationship with fields in nested list objects" do
            before do
              index_into(graphql, sponsor1, sponsor2, team1, team2, team3)
            end

            it "loads the relationship from a nested field in an object list" do
              result = resolve_nodes("Sponsor", "affiliated_teams_from_object", {"id" => sponsor1.fetch(:id)}, requested_fields: ["id"])

              expect(result.map { |t| t.fetch("id") }).to contain_exactly(team1.fetch(:id), team2.fetch(:id))
            end

            it "loads the relationship from a nested field in a nested list" do
              result = resolve_nodes("Sponsor", "affiliated_teams_from_nested", {"id" => sponsor1.fetch(:id)}, requested_fields: ["id"])

              expect(result.map { |t| t.fetch("id") }).to contain_exactly(team1.fetch(:id), team2.fetch(:id))
            end
          end
        end

        # we override `resolve` (defined in the `resolver support` shared context) in order
        # to enforce that no `resolve` call ever queries the datastore more than once, as part
        # of preventing N+1 queries.
        #
        # Also, we force `id` and `created_at` as requested fields here since:
        #
        # * The specs rely on `id` always being requested.
        # * We need to request more than just `id` to avoid the synthesizing of a datastore response based just on the ids.
        def resolve(*args, requested_fields: ["id", "created_at"], **options)
          result = nil

          # Perform any cached calls to the datastore to happen before our `query_datastore`
          # matcher below which tries to assert which specific requests get made, since index definitions
          # have caching behavior that can make the presence or absence of that request slightly non-deterministic.
          pre_cache_index_state(graphql)

          expect {
            result = super(*args, query_overrides: {requested_fields: requested_fields}, **options)
          }.to query_datastore("main", 0).times.or query_datastore("main", 1).time

          result
        end

        def resolve_nodes(...)
          resolve(...).edges.map(&:node)
        end
      end
    end
  end
end

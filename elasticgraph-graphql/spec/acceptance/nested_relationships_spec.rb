# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--nested relationships" do
    include_context "ElasticGraph GraphQL acceptance support"

    context "with widget data indexed" do
      with_both_casing_forms do
        let(:manufacturer1) { build(:manufacturer) }
        let(:manufacturer2) { build(:manufacturer) }

        let(:address1) { build(:address, full_address: "a1", manufacturer: manufacturer1, created_at: "2019-09-12T12:00:00Z") }
        let(:address2) { build(:address, full_address: "a2", manufacturer: manufacturer2, created_at: "2019-09-11T12:00:00Z") }

        let(:part1) { build(:electrical_part, id: "p1", manufacturer: manufacturer1, created_at: "2019-06-01T00:00:00Z") }
        let(:part2) { build(:electrical_part, id: "p2", manufacturer: manufacturer1, created_at: "2019-06-02T00:00:00Z") }
        let(:part3) { build(:mechanical_part, id: "p3", manufacturer: manufacturer2, created_at: "2019-06-03T00:00:00Z") }

        let(:component1) { build(:component, parts: [part1, part2], name: "comp1", created_at: "2019-06-04T00:00:00Z") }
        let(:component2) { build(:component, parts: [part1, part3], name: "comp2", created_at: "2019-06-03T00:00:00Z") }
        let(:component3) { build(:component, parts: [part2, part3], name: "comp3", created_at: "2019-06-02T00:00:00Z") }
        let(:component4) { build(:component, parts: [part2], name: "comp4", created_at: "2019-06-01T00:00:00Z") }

        let(:widget1) { build(:widget, name: "widget1", amount_cents: 100, components: [component1, component2, component4], created_at: "2019-06-02T00:00:00Z") }
        let(:widget2) { build(:widget, name: "widget2", amount_cents: 200, components: [component3], created_at: "2019-06-01T00:00:00Z") }

        before do
          index_records(manufacturer1, manufacturer2, address1, address2, part1, part2, part3, component1, component2, component3, component4, widget1, widget2)
        end

        it "supports filtering relationships with additional filter conditions" do
          component_args = {filter: {name: {equal_to_any_of: %w[comp1]}}}
          results = query_components_and_dollar_widgets(component_args: component_args)
          expect(results).to match(
            case_correctly("nodes") => [{
              case_correctly("name") => "comp1",
              case_correctly("dollar_widget") => {
                case_correctly("name") => "widget1",
                case_correctly("cost") => {
                  case_correctly("amount_cents") => 100
                }
              }
            }],
            case_correctly("total_edge_count") => 1
          )

          # verify that non-dollar widgets are filtered out
          component_args2 = {filter: {name: {equal_to_any_of: %w[comp3]}}}
          results2 = query_components_and_dollar_widgets(component_args: component_args2)
          expect(results2).to match(
            case_correctly("nodes") => [{
              case_correctly("name") => "comp3",
              case_correctly("dollar_widget") => nil # dollar_widget is nil since widget 2 costs $2
            }],
            case_correctly("total_edge_count") => 1
          )
        end

        it "avoids unneeded datastore queries when the client just requests the `id` from a relationship with an outbound foreign key", :expect_search_routing do
          widget1_component_ids = [
            component1.fetch(:id),
            component2.fetch(:id),
            component4.fetch(:id)
          ]

          # Test a relates_to_many case (Widget.components) with `id_ASC` sorting.
          expect {
            results = query_widgets_and_component_ids(component_args: {order_by: [:id_ASC]})

            expect(results).to eq [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => widget1_component_ids.sort.map { |id| {"id" => id} }
                }
              },
              {
                "id" => widget2.fetch(:id),
                "components" => {
                  "nodes" => [
                    string_hash_of(component3, :id)
                  ]
                }
              }
            ]
          }.to query_datastore("main", 1).time

          # Test a relates_to_many case (Widget.components) with `id_DESC` sorting.
          expect {
            results = query_widgets_and_component_ids(component_args: {order_by: [:id_DESC]})

            expect(results).to eq [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => widget1_component_ids.sort.reverse.map { |id| {"id" => id} }
                }
              },
              {
                "id" => widget2.fetch(:id),
                "components" => {
                  "nodes" => [
                    string_hash_of(component3, :id)
                  ]
                }
              }
            ]
          }.to query_datastore("main", 1).time

          # Test a relates_to_many case (Widget.components) with default (non-id) sorting--it has to make 2 queries.
          expect {
            results = query_widgets_and_component_ids

            expect(results).to eq [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => widget1_component_ids.map { |id| {"id" => id} }
                }
              },
              {
                "id" => widget2.fetch(:id),
                "components" => {
                  "nodes" => [
                    string_hash_of(component3, :id)
                  ]
                }
              }
            ]
          }.to query_datastore("main", 2).times

          # Test a relates_to_many case (Widget.components) with additional requested fields--it has to make 2 queries.
          expect {
            results = query_widgets_and_component_ids(other_component_fields: ["name"], component_args: {order_by: [:id_ASC]})

            expect(results).to eq [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => [
                    string_hash_of(component1, :id, :name),
                    string_hash_of(component2, :id, :name),
                    string_hash_of(component4, :id, :name)
                  ].sort_by { |hash| hash.fetch("id") }
                }
              },
              {
                "id" => widget2.fetch(:id),
                "components" => {
                  "nodes" => [
                    string_hash_of(component3, :id, :name)
                  ]
                }
              }
            ]
          }.to query_datastore("main", 2).time

          # Test a relates_to_many case (Widget.components) with ascending forwards pagination
          paginate_widgets_and_component_ids(backwards: false, first_page: :min, last_page: :max) do |cursor|
            {order_by: [:id_ASC], first: 1, after: cursor}
          end

          # Test a relates_to_many case (Widget.components) with descending forwards pagination
          paginate_widgets_and_component_ids(backwards: false, first_page: :max, last_page: :min) do |cursor|
            {order_by: [:id_DESC], first: 1, after: cursor}
          end

          # Test a relates_to_many case (Widget.components) with ascending backwards pagination
          paginate_widgets_and_component_ids(backwards: true, first_page: :max, last_page: :min) do |cursor|
            {order_by: [:id_ASC], last: 1, before: cursor}
          end

          # Test a relates_to_many case (Widget.components) with descending backwards pagination
          paginate_widgets_and_component_ids(backwards: true, first_page: :min, last_page: :max) do |cursor|
            {order_by: [:id_DESC], last: 1, before: cursor}
          end

          # Test a relates_to_one case (ElectricalPart.manufacturer)
          expect {
            results = query_electrical_parts_and_manufacturer_ids

            expect(results).to eq [
              {
                "id" => part2.fetch(:id),
                "manufacturer" => string_hash_of(manufacturer1, :id)
              },
              {
                "id" => part1.fetch(:id),
                "manufacturer" => string_hash_of(manufacturer1, :id)
              }
            ]
          }.to query_datastore("main", 1).time
        end

        it "supports loading bi-directional relationships, starting from either end", :expect_search_routing do
          component_args_without_not = {filter: {name: {equal_to_any_of: %w[comp1 comp2 comp3]}}}
          component_args_with_not = {filter: {name: {not: {equal_to_any_of: %w[comp4]}}}}
          part_args = {order_by: [:id_DESC]} # ensure deterministic ordering of parts
          address_args = {order_by: [:full_address_ASC]} # ensure deterministic ordering of addresses

          [component_args_without_not, component_args_with_not].each do |component_args|
            expect {
              expect(query_all_relationship_levels_from_widgets(component_args: component_args, part_args: part_args)).to match edges_of(
                node_of(widget1, :name, components: edges_of(
                  node_of(component1, :name, parts: edges_of(
                    node_of(part2, :name, manufacturer: string_hash_of(manufacturer1, :name, address: string_hash_of(address1, :full_address))),
                    node_of(part1, :name, manufacturer: string_hash_of(manufacturer1, :name, address: string_hash_of(address1, :full_address)))
                  )),
                  node_of(component2, :name, parts: edges_of(
                    node_of(part3, :name, manufacturer: string_hash_of(manufacturer2, :name, address: string_hash_of(address2, :full_address))),
                    node_of(part1, :name, manufacturer: string_hash_of(manufacturer1, :name, address: string_hash_of(address1, :full_address)))
                  ))
                )),
                node_of(widget2, :name, components: edges_of(
                  node_of(component3, :name, parts: edges_of(
                    node_of(part3, :name, manufacturer: string_hash_of(manufacturer2, :name, address: string_hash_of(address2, :full_address))),
                    node_of(part2, :name, manufacturer: string_hash_of(manufacturer1, :name, address: string_hash_of(address1, :full_address)))
                  ))
                ))
              )
            }.to query_datastore("main", 5).times

            expect_to_have_routed_to_shards_with("main",
              # Root `widgets` query isn't filtering on anything and uses no routing.
              ["widgets_rollover__*", nil],
              # `Widget.components` uses an `out` foreign key and routes on `id`
              ["components", widget1.fetch(case_correctly(:component_ids)).sort.join(",")],
              ["components", widget2.fetch(case_correctly(:component_ids)).sort.join(",")],
              # `Component.parts` is an `out` foreign key, and routes on `id`
              ["electrical_parts,mechanical_parts", component1.fetch(case_correctly(:part_ids)).sort.join(",")],
              ["electrical_parts,mechanical_parts", component2.fetch(case_correctly(:part_ids)).sort.join(",")],
              ["electrical_parts,mechanical_parts", component3.fetch(case_correctly(:part_ids)).sort.join(",")],
              # `ElectricalPart.manufacturer`/`MechanicalPart.manufacturer` use an `out` foreign key and route on `id`.
              ["manufacturers", part1.fetch(case_correctly(:manufacturer_id))],
              ["manufacturers", part3.fetch(case_correctly(:manufacturer_id))],
              # `Manufacturer.addresses` uses an `in` foreign key and therefore cannot route on `id`.
              ["addresses", nil], ["addresses", nil])

            datastore_requests_by_cluster_name["main"].clear

            expect {
              expect(query_all_relationship_levels_from_addresses(component_args: component_args, part_args: part_args, address_args: address_args)).to match edges_of(
                node_of(address1, :full_address, manufacturer:
                  string_hash_of(manufacturer1, :name, manufactured_parts: edges_of(
                    node_of(part2, :name, components: edges_of(
                      node_of(component1, :name, widget: string_hash_of(widget1, :name)),
                      node_of(component3, :name, widget: string_hash_of(widget2, :name))
                    )),
                    node_of(part1, :name, components: edges_of(
                      node_of(component1, :name, widget: string_hash_of(widget1, :name)),
                      node_of(component2, :name, widget: string_hash_of(widget1, :name))
                    ))
                  ))),
                node_of(address2, :full_address, manufacturer:
                  string_hash_of(manufacturer2, :name, manufactured_parts: edges_of(
                    node_of(part3, :name, components: edges_of(
                      node_of(component2, :name, widget: string_hash_of(widget1, :name)),
                      node_of(component3, :name, widget: string_hash_of(widget2, :name))
                    ))
                  )))
              )
            }.to query_datastore("main", 5).times

            expect_to_have_routed_to_shards_with("main",
              # Root `addresses` query isn't filtering on anything and uses no routing.
              ["addresses", nil],
              # The `Address.manufacturer` relation uses an `out` foreign key and therefore uses routing on `id`.
              ["manufacturers", address1.fetch(case_correctly(:manufacturer_id))],
              ["manufacturers", address2.fetch(case_correctly(:manufacturer_id))],
              # The `Manufacturer.manufactured_parts` relation uses an `in` foreign key and therefore cannot route on `id`.
              ["electrical_parts,mechanical_parts", nil], ["electrical_parts,mechanical_parts", nil],
              # The `ElectricalPart.components` and `MechanicalPart.components` relations use an `in` foreign key and therefore cannot route on `id`
              ["components", nil], ["components", nil], ["components", nil],
              # The `Component.widgets` relation uses an `in` foreign key and therefore cannot route on `id`.
              ["widgets_rollover__*", nil], ["widgets_rollover__*", nil], ["widgets_rollover__*", nil])
          end
        end

        it "supports pagination at any level using relay connections", :expect_search_routing do
          results = query_widgets_and_components_including_page_info(
            widget_args: {first: 1, order_by: [:amount_cents_ASC]},
            component_args: {first: 1, order_by: [:name_ASC]}
          )

          expect_to_have_routed_to_shards_with("main",
            ["widgets_rollover__*", nil],
            # `Widget.components` uses an `out` foreign key and routes on `id`
            ["components", widget1.fetch(case_correctly(:component_ids)).sort.join(",")])

          expect(results).to match_single_widget_and_component_result(
            widget1, component1,
            widgets_have_next_page: true, widgets_have_previous_page: false, widget_count: 2,
            components_have_next_page: true, components_have_previous_page: false, component_count: 3
          )

          # Demonstrate how negative `first` values behave.
          expect {
            response = query_widgets_and_components_including_page_info(
              widget_args: {first: -2, order_by: [:amount_cents_ASC]},
              expect_errors: true
            )
            expect(response["errors"]).to contain_exactly(a_hash_including("message" => "`first` cannot be negative, but is -2."))
          }.to log_warning a_string_including("`first` cannot be negative, but is -2.")

          # Demonstrate how broken cursors behave.
          expect {
            response = query_widgets_and_components_including_page_info(
              widget_args: {first: 1, order_by: [:amount_cents_ASC]},
              component_args: {first: 1, after: [1, 2, 3], order_by: [:name_ASC]},
              expect_errors: true
            )
            expect(response["errors"]).to contain_exactly(a_hash_including("message" => "Argument 'after' on Field 'components' has an invalid value ([1, 2, 3]). Expected type 'Cursor'."))
          }.to log_warning a_string_including("Argument 'after' on Field 'components' has an invalid value", "[1, 2, 3]")

          broken_cursor = results["edges"][0]["node"]["components"][case_correctly "page_info"][case_correctly "end_cursor"] + "-broken"
          expect {
            response = query_widgets_and_components_including_page_info(
              widget_args: {first: 1, order_by: [:amount_cents_ASC]},
              component_args: {first: 1, after: broken_cursor, order_by: [:name_ASC]},
              expect_errors: true
            )
            expect(response["errors"]).to contain_exactly(a_hash_including("message" => "Argument 'after' on Field 'components' has an invalid value (#{broken_cursor.inspect}). Expected type 'Cursor'."))
          }.to log_warning a_string_including("Argument 'after' on Field 'components' has an invalid value", broken_cursor)

          # get next page of components (but still on the first page of widgets)
          results = query_widgets_and_components_including_page_info(
            widget_args: {first: 1, order_by: [:amount_cents_ASC]},
            component_args: {first: 1, after: results["edges"][0]["node"]["components"][case_correctly "page_info"][case_correctly "end_cursor"], order_by: [:name_ASC]}
          )

          expect_to_have_routed_to_shards_with("main",
            ["widgets_rollover__*", nil],
            # `Widget.components` uses an `out` foreign key and routes on `id`
            ["components", widget1.fetch(case_correctly(:component_ids)).sort.join(",")])

          expect(results).to match_single_widget_and_component_result(
            widget1, component2,
            widgets_have_next_page: true, widgets_have_previous_page: false, widget_count: 2,
            components_have_next_page: true, components_have_previous_page: true, component_count: 3
          )

          # get next page of widgets
          results = query_widgets_and_components_including_page_info(
            widget_args: {first: 1, after: results[case_correctly "page_info"][case_correctly "end_cursor"], order_by: [:amount_cents_ASC]},
            component_args: {first: 1, order_by: [:name_ASC]}
          )

          expect_to_have_routed_to_shards_with("main",
            ["widgets_rollover__*", nil],
            # `Widget.components` uses an `out` foreign key and routes on `id`
            ["components", widget2.fetch(case_correctly(:component_ids)).sort.join(",")])

          expect(results).to match_single_widget_and_component_result(
            widget2, component3,
            widgets_have_next_page: false, widgets_have_previous_page: true, widget_count: 2,
            components_have_next_page: false, components_have_previous_page: false, component_count: 1
          )

          results = query_widget_pagination_info(widget_args: {first: 1})
          expect_to_have_routed_to_shards_with("main", ["widgets_rollover__*", nil])

          expect(results).to match(
            case_correctly("total_edge_count") => 2,
            case_correctly("page_info") => {
              case_correctly("has_next_page") => true,
              case_correctly("has_previous_page") => false,
              case_correctly("start_cursor") => /\w+/,
              case_correctly("end_cursor") => /\w+/
            }
          )
        end

        def case_correctly(string_or_sym)
          return super(string_or_sym.to_s).to_sym if string_or_sym.is_a?(Symbol)
          super
        end

        def paginate_widgets_and_component_ids(backwards:, first_page:, last_page:)
          cursor_field = backwards ? "start_cursor" : "end_cursor"
          widget1_component_ids = [
            component1.fetch(:id),
            component2.fetch(:id),
            component4.fetch(:id)
          ]

          expect {
            results = query_widgets_and_component_ids(
              request_page_info: true,
              widget_args: {filter: {id: {equal_to_any_of: [widget1.fetch(:id)]}}},
              component_args: yield(nil)
            )

            expect(results).to match [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => [{"id" => widget1_component_ids.public_send(first_page)}],
                  case_correctly("page_info") => {
                    case_correctly("has_next_page") => !backwards,
                    case_correctly("has_previous_page") => backwards,
                    case_correctly("end_cursor") => /\w+/,
                    case_correctly("start_cursor") => /\w+/
                  }
                }
              }
            ]

            # Fetch page 2...
            cursor = results.dig(0, "components", case_correctly("page_info"), case_correctly(cursor_field))
            expect(cursor).to match(/\w+/)
            results = query_widgets_and_component_ids(
              request_page_info: true,
              widget_args: {filter: {id: {equal_to_any_of: [widget1.fetch(:id)]}}},
              component_args: yield(cursor)
            )

            expect(results).to match [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => [{"id" => widget1_component_ids.sort[1]}],
                  case_correctly("page_info") => {
                    case_correctly("has_next_page") => true,
                    case_correctly("has_previous_page") => true,
                    case_correctly("end_cursor") => /\w+/,
                    case_correctly("start_cursor") => /\w+/
                  }
                }
              }
            ]

            # Fetch page 3...
            cursor = results.dig(0, "components", case_correctly("page_info"), case_correctly(cursor_field))
            expect(cursor).to match(/\w+/)
            results = query_widgets_and_component_ids(
              request_page_info: true,
              widget_args: {filter: {id: {equal_to_any_of: [widget1.fetch(:id)]}}},
              component_args: yield(cursor)
            )

            expect(results).to match [
              {
                "id" => widget1.fetch(:id),
                "components" => {
                  "nodes" => [{"id" => widget1_component_ids.public_send(last_page)}],
                  case_correctly("page_info") => {
                    case_correctly("has_next_page") => backwards,
                    case_correctly("has_previous_page") => !backwards,
                    case_correctly("end_cursor") => /\w+/,
                    case_correctly("start_cursor") => /\w+/
                  }
                }
              }
            ]
          }.to query_datastore("main", 3).times
        end

        def query_all_relationship_levels_from_widgets(component_args: {}, part_args: {})
          call_graphql_query(<<~QUERY).dig("data", "widgets")
            query {
              widgets {
                edges {
                  node {
                    name
                    components#{graphql_args(component_args)} {
                      edges {
                        node {
                          name
                          parts#{graphql_args(part_args)} {
                            edges {
                              node {
                                ... on MechanicalPart {
                                  name
                                  manufacturer {
                                    name
                                    address {
                                      full_address
                                    }
                                  }
                                }
                                ... on ElectricalPart {
                                  name
                                  manufacturer {
                                    name
                                    address {
                                      full_address
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY
        end

        def query_widgets_and_component_ids(widget_args: {}, component_args: {}, other_component_fields: [], request_page_info: false)
          page_info_fields = <<~EOS
            page_info {
              has_next_page
              has_previous_page
              end_cursor
              start_cursor
            }
          EOS

          call_graphql_query(<<~QUERY).dig("data", "widgets", "nodes")
            query {
              widgets#{graphql_args(widget_args)} {
                nodes {
                  id
                  components#{graphql_args(component_args)} {
                    nodes {
                      id
                      #{other_component_fields.join("\n")}
                    }

                    #{page_info_fields if request_page_info}
                  }
                }
              }
            }
          QUERY
        end

        def query_electrical_parts_and_manufacturer_ids
          call_graphql_query(<<~QUERY).dig("data", case_correctly("electrical_parts"), "nodes")
            query {
              electrical_parts {
                nodes {
                  id
                  manufacturer {
                    id
                  }
                }
              }
            }
          QUERY
        end

        def query_components_and_dollar_widgets(component_args: {})
          call_graphql_query(<<~QUERY).dig("data", "components")
            query {
              components#{graphql_args(component_args)} {
                total_edge_count
                nodes {
                  name
                  dollar_widget {
                    name
                    cost {
                      amount_cents
                    }
                  }
                }
              }
            }
          QUERY
        end

        def query_widgets_and_components_including_page_info(component_args: {}, widget_args: {}, expect_errors: false)
          response = call_graphql_query(<<~QUERY, allow_errors: expect_errors)
            query {
              widgets#{graphql_args(widget_args)} {
                page_info {
                  has_next_page
                  has_previous_page
                  start_cursor
                  end_cursor
                }
                total_edge_count
                edges {
                  cursor
                  node {
                    name
                    components#{graphql_args(component_args)} {
                      page_info {
                        has_next_page
                        has_previous_page
                        start_cursor
                        end_cursor
                      }
                      total_edge_count
                      edges {
                        cursor
                        node {
                          name
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY

          return response if expect_errors
          response.dig("data", "widgets")
        end

        def query_all_relationship_levels_from_addresses(component_args: {}, part_args: {}, address_args: {})
          call_graphql_query(<<~QUERY).dig("data", "addresses")
            query {
              addresses#{graphql_args(address_args)} {
                edges {
                  node {
                    full_address
                    manufacturer {
                      name
                      manufactured_parts#{graphql_args(part_args)} {
                        edges {
                          node {
                            ... on MechanicalPart {
                              name
                              components#{graphql_args(component_args)} {
                                edges {
                                  node {
                                    name
                                    widget {
                                      name
                                    }
                                  }
                                }
                              }
                            }
                            ... on ElectricalPart {
                              name
                              components#{graphql_args(component_args)} {
                                edges {
                                  node {
                                    name
                                    widget {
                                      name
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          QUERY
        end
      end
    end

    context "with team data indexed" do
      with_both_casing_forms do
        let(:sponsor1) { build(:sponsor, name: "business1") }
        let(:sponsor2) { build(:sponsor, name: "business2") }

        let(:team1) { build(:team, current_name: "team1", sponsors: [sponsor1, sponsor2]) }
        let(:team2) { build(:team, current_name: "team2", sponsors: [sponsor2]) }
        before do
          index_records(sponsor1, sponsor2, team1, team2)
        end

        it "supports in relationships from fields nested in lists" do
          sponsors_args = {filter: {name: {equal_to_any_of: %w[business1]}}}
          results = query_sponsors(sponsor_args: sponsors_args)

          expect(results).to match(
            case_correctly("nodes") => [
              {
                case_correctly("name") => "business1",
                case_correctly("affiliated_teams_from_object") => {
                  case_correctly("nodes") => [
                    {
                      case_correctly("current_name") => "team1"
                    }
                  ]
                },
                case_correctly("affiliated_teams_from_nested") => {
                  case_correctly("nodes") => [
                    {
                      case_correctly("current_name") => "team1"
                    }
                  ]
                }
              }
            ]
          )
        end
      end
    end

    def query_widget_pagination_info(widget_args: {})
      call_graphql_query(<<~QUERY).dig("data", "widgets")
        query {
          widgets#{graphql_args(widget_args)} {
            total_edge_count
            page_info {
              has_next_page
              has_previous_page
              start_cursor
              end_cursor
            }
          }
        }
      QUERY
    end

    def query_sponsors(sponsor_args: {})
      call_graphql_query(<<~QUERY).dig("data", "sponsors")
        query {
          sponsors#{graphql_args(sponsor_args)} {
            nodes {
              name
              affiliated_teams_from_object {
                nodes {
                  current_name
                }
              }
              affiliated_teams_from_nested {
                nodes {
                  current_name
                }
              }
            }
          }
        }
      QUERY
    end

    def match_single_widget_and_component_result(widget, component,
      widgets_have_next_page:, widgets_have_previous_page:, widget_count:,
      components_have_next_page:, components_have_previous_page:, component_count:)
      match(
        case_correctly("total_edge_count") => widget_count,
        case_correctly("page_info") => {
          case_correctly("has_next_page") => widgets_have_next_page,
          case_correctly("has_previous_page") => widgets_have_previous_page,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("end_cursor") => /\w+/
        },
        "edges" => [{
          "cursor" => /\w+/,
          "node" => string_hash_of(widget, :name, components: {
            case_correctly("total_edge_count") => component_count,
            case_correctly("page_info") => {
              case_correctly("has_next_page") => components_have_next_page,
              case_correctly("has_previous_page") => components_have_previous_page,
              case_correctly("start_cursor") => /\w+/,
              case_correctly("end_cursor") => /\w+/
            },
            "edges" => [{
              "cursor" => /\w+/,
              "node" => string_hash_of(component, :name)
            }]
          })
        }]
      )
    end
  end
end

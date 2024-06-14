# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--hidden types" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      context "when some indices are configured to query clusters that are not configured, or are configured with `query_cluster: nil`" do
        let(:graphql_hiding_addresses_and_mechanical_parts) do
          build_graphql do |config|
            config.with(index_definitions: config.index_definitions.merge(
              index_definition_name_for("addresses") => config_index_def_of(query_cluster: "unknown1"),
              index_definition_name_for("mechanical_parts") => config_index_def_of(query_cluster: nil)
            ))
          end
        end

        it "hides the GraphQL schema elements that require access to those indices" do
          all_fields_by_type_name = fields_by_type_name_from(graphql)
          restricted_fields_by_type_name = nil

          expect {
            restricted_fields_by_type_name = fields_by_type_name_from(graphql_hiding_addresses_and_mechanical_parts)
          }.to log_warning(a_string_including(
            "4 GraphQL types were hidden",
            "Address",
            "MechanicalPart",
            apply_derived_type_customizations("AddressAggregation"),
            apply_derived_type_customizations("MechanicalPartAggregation")
          ))

          hidden_types = (all_fields_by_type_name.keys - restricted_fields_by_type_name.keys)

          hidden_fields = restricted_fields_by_type_name.each_with_object({}) do |(type, fields), hash|
            missing_fields = all_fields_by_type_name.fetch(type) - fields
            hash[type] = missing_fields if missing_fields.any?
          end

          expect(hidden_types).to match_array(adjust_derived_type_names_as_needed(
            all_types_related_to("Address") +
            all_types_related_to("MechanicalPart") +
            # `AddressTimestamps` and `GeoShape` are only used on `Address` so when `Address` is hidden, they are, too.
            ["AddressTimestamps", "GeoShape"]
          ))

          expect(hidden_fields).to eq(
            "Query" => [case_correctly("address_aggregations"), "addresses", case_correctly("mechanical_part_aggregations"), case_correctly("mechanical_parts")],
            "Manufacturer" => ["address"]
          )

          # Our mechanism for determining which types to hide on the basis of inaccessible indexes uses the type name.
          # If/when our schema definition API started generating some new types for indexed types, the current logic
          # may not correctly hide those types when the index is inaccessible. To guard against that, we are enumerating
          # all of the types we expect to be present on both schemas here--that way, when the set of types on our test
          # schema grows, we are forced to consider if the new type should be subject to the hidden type logic we test
          # here.
          #
          # When the expectation below fails, please add the new types to this list here so long as the new types are
          # not backed by the `addresses` or `mechanical_parts` indices. If they are backed by one of those indices,
          # you'll need to account for the types in the expectations above (and fix the hidden type logic as well).
          expected_types_present_on_both_schemas = GraphQL::Schema::BUILT_IN_TYPE_NAMES +
            all_types_related_to("Widget") +
            all_types_related_to("WidgetWorkspace") +
            all_types_related_to("WidgetOrAddress") +
            all_types_related_to("Component") +
            all_types_related_to("Manufacturer") +
            all_types_related_to("ElectricalPart") +
            all_types_related_to("Part") +
            all_types_related_to("NamedEntity") +
            all_types_related_to("WidgetCurrency") +
            all_types_related_to("Team") +
            all_types_related_to("Sponsor") +
            relay_types_related_to("String", include_list_filter: true) - ["StringSortOrderInput"] +
            type_and_filters_for("Boolean", include_list: true) +
            type_and_filters_for("Color", include_list: true, as_input_enum: true) +
            type_and_filters_for("Date", include_list: true) +
            type_and_filters_for("DateTime", include_list: true) +
            type_and_filters_for("LocalTime") +
            type_and_filters_for("JsonSafeLong", include_list: true) +
            type_and_filters_for("Untyped") +
            type_and_filters_for("LongString") +
            type_and_filters_for("Material", as_input_enum: true) +
            type_and_filters_for("Size", include_list: true, as_input_enum: true) +
            type_and_filters_for("TeamNestedFields") +
            type_and_filters_for("Affiliations") +
            type_and_filters_for("ID", include_list: true) +
            type_filter_and_non_indexed_aggregation_types_for("TeamDetails") +
            type_filter_and_non_indexed_aggregation_types_for("AddressTimestamps") - ["AddressTimestamps"] +
            type_filter_and_non_indexed_aggregation_types_for("Affiliations", include_fields_list_filter: true) +
            type_filter_and_non_indexed_aggregation_types_for("CurrencyDetails") +
            type_filter_and_non_indexed_aggregation_types_for("Inventor") +
            type_filter_and_non_indexed_aggregation_types_for("NamedInventor") +
            type_filter_and_non_indexed_aggregation_types_for("Money", include_list_filter: true, include_fields_list_filter: true) - ["MoneyListElementFilterInput"] +
            type_filter_and_non_indexed_aggregation_types_for("Position") +
            type_filter_and_non_indexed_aggregation_types_for("Player", include_list_filter: true, include_fields_list_filter: true) - ["PlayerListElementFilterInput"] +
            type_filter_and_non_indexed_aggregation_types_for("PlayerSeason", include_list_filter: true, include_fields_list_filter: true) - ["PlayerSeasonListElementFilterInput"] +
            type_filter_and_non_indexed_aggregation_types_for("TeamRecord", include_fields_list_filter: true) +
            type_filter_and_non_indexed_aggregation_types_for("TeamSeason", include_list_filter: true, include_fields_list_filter: true) - ["TeamSeasonListElementFilterInput"] +
            type_filter_and_non_indexed_aggregation_types_for("WidgetOptions") +
            type_filter_and_non_indexed_aggregation_types_for("WidgetOptionSets") - ["WidgetOptionSetsGroupedBy"] +
            type_filter_and_non_indexed_aggregation_types_for("WidgetCurrencyNestedFields") +
            type_filter_and_non_indexed_aggregation_types_for("WorkspaceWidget") +
            type_filter_and_non_indexed_aggregation_types_for("Sponsorship", include_list_filter: true, include_fields_list_filter: true) - ["SponsorshipListElementFilterInput"] +
            ::GraphQL::Schema::BUILT_IN_TYPES.keys.flat_map { |k| type_and_filters_for(k) } +
            %w[
              FloatAggregatedValues IntAggregatedValues JsonSafeLongAggregatedValues LongStringAggregatedValues NonNumericAggregatedValues
              DateAggregatedValues DateTimeAggregatedValues LocalTimeAggregatedValues
              Company Cursor PageInfo Person Query TextFilterInput GeoLocation
              DateTimeGroupingOffsetInput DateTimeUnitInput DateTimeTimeOfDayFilterInput
              DateGroupedBy DateGroupingOffsetInput DateGroupingTruncationUnitInput DateUnitInput
              DateTimeGroupedBy DateTimeGroupingTruncationUnitInput TimeZone
              DayOfWeek DayOfWeekGroupingOffsetInput DistanceUnitInput GeoLocationFilterInput GeoLocationDistanceFilterInput
              IntListFilterInput IntListElementFilterInput AggregationCountDetail
              LocalTimeGroupingOffsetInput LocalTimeGroupingTruncationUnitInput LocalTimeUnitInput MatchesQueryFilterInput
              MatchesPhraseFilterInput MatchesQueryAllowedEditsPerTermInput
            ]

          # The sub-aggregation types are quite complicated and we just add them all here.
          expected_types_present_on_both_schemas += %w[
            TeamAggregationSubAggregations
            TeamMoneySubAggregation TeamMoneySubAggregationConnection
            TeamPlayerSubAggregation TeamPlayerSubAggregationConnection
            TeamTeamSeasonSubAggregation TeamTeamSeasonSubAggregationConnection
            TeamAggregationCurrentPlayersObjectSubAggregations
            TeamAggregationNestedFieldsSubAggregations
            TeamAggregationNestedFields2SubAggregations
            TeamAggregationSeasonsObjectPlayersObjectSubAggregations
            TeamAggregationSeasonsObjectSubAggregations
            TeamPlayerPlayerSeasonSubAggregation
            TeamPlayerPlayerSeasonSubAggregationConnection
            TeamPlayerSeasonSubAggregation
            TeamPlayerSeasonSubAggregationConnection
            TeamPlayerSubAggregationSubAggregations
            TeamTeamSeasonPlayerPlayerSeasonSubAggregation
            TeamTeamSeasonPlayerPlayerSeasonSubAggregationConnection
            TeamTeamSeasonPlayerSeasonSubAggregation
            TeamTeamSeasonPlayerSeasonSubAggregationConnection
            TeamTeamSeasonPlayerSubAggregation
            TeamTeamSeasonPlayerSubAggregationConnection
            TeamTeamSeasonPlayerSubAggregationSubAggregations
            TeamTeamSeasonSubAggregationPlayersObjectSubAggregations
            TeamTeamSeasonSubAggregationSubAggregations
            TeamSponsorshipSubAggregation
            TeamSponsorshipSubAggregationConnection
            TeamAggregationCurrentPlayersObjectAffiliationsSubAggregations
            TeamAggregationSeasonsObjectPlayersObjectAffiliationsSubAggregations
            TeamPlayerSponsorshipSubAggregation
            TeamPlayerSponsorshipSubAggregationConnection
            TeamPlayerSubAggregationAffiliationsSubAggregations
            TeamTeamSeasonPlayerSponsorshipSubAggregation
            TeamTeamSeasonPlayerSponsorshipSubAggregationConnection
            TeamTeamSeasonPlayerSubAggregationAffiliationsSubAggregations
            TeamTeamSeasonSponsorshipSubAggregation
            TeamTeamSeasonSponsorshipSubAggregationConnection
            TeamTeamSeasonSubAggregationPlayersObjectAffiliationsSubAggregations
          ]

          expected_types_present_on_both_schemas = adjust_derived_type_names_as_needed(expected_types_present_on_both_schemas)

          actual_types_present_on_both_schemas = (all_fields_by_type_name.keys & restricted_fields_by_type_name.keys)
          # We compare as multi-line strings here to get nice diffing from RSpec :).
          expect(actual_types_present_on_both_schemas.sort.join("\n")).to eq(expected_types_present_on_both_schemas.uniq.sort.join("\n"))
        end

        def adjust_derived_type_names_as_needed(type_names)
          type_names.map { |type| apply_derived_type_customizations(type) }
        end

        def fields_by_type_name_from(graphql)
          types = call_graphql_query(<<~EOS, gql: graphql).fetch("data").fetch("__schema").fetch("types")
            query {
              __schema {
                types {
                  name
                  fields {
                    name
                  }
                }
              }
            }
          EOS

          types.each_with_object({}) do |type, hash|
            hash[type.fetch("name")] = (type.fetch("fields") || []).map { |f| f.fetch("name") }
          end
        end

        def all_types_related_to(type_name, include_list_filter: false)
          relay_types_related_to(type_name, include_list_filter: include_list_filter) +
            aggregation_types_related_to(type_name)
        end

        def relay_types_related_to(type_name, include_list_filter: false)
          ["Edge", "Connection", "SortOrderInput"].map do |suffix|
            type_name + suffix
          end + type_and_filters_for(type_name, include_list: include_list_filter)
        end

        def type_and_filters_for(type_name, include_list: false, as_input_enum: false)
          suffixes = ["", "FilterInput"]
          suffixes += ["Input"] if as_input_enum
          suffixes += ["ListFilterInput", "ListElementFilterInput"] if include_list
          suffixes.map { |suffix| type_name + suffix }
        end

        def type_filter_and_non_indexed_aggregation_types_for(type_name, include_list_filter: false, include_fields_list_filter: false)
          suffixes = ["", "FilterInput", "GroupedBy", "AggregatedValues"]
          suffixes += ["ListFilterInput", "ListElementFilterInput"] if include_list_filter
          suffixes += ["FieldsListFilterInput"] if include_fields_list_filter
          suffixes.map { |suffix| type_name + suffix }
        end

        def aggregation_types_related_to(type_name)
          suffixes = %w[
            Aggregation AggregationConnection AggregationEdge GroupedBy AggregatedValues
          ]

          suffixes.map { |suffix| type_name + suffix }
        end
      end
    end
  end
end

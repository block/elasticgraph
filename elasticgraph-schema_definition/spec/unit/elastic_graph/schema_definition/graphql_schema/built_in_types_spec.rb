# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"
require "elastic_graph/schema_definition/schema_elements/type_namer"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "built-in types" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do |form|
        if form == :camelCase # Our docs are written assuming `camelCase` since that's the common GraphQL convention.
          it "fully documents all primary built in types" do
            derived_type_regexes = SchemaElements::TypeNamer.new.regexes.values

            primary_built_in_types_and_docs = ::GraphQL::Schema.from_definition(@result).types.filter_map do |name, type|
              if %w[Query].include?(name) || name.start_with?("__") || derived_type_regexes.any? { |r| r.match(name) }
                # skip it as it's not a primary type.
              else
                [name, type.description.gsub(/\s+/, " ")]
              end
            end.to_h

            built_in_types_code = ::File.read($LOADED_FEATURES.grep(/schema_elements\/built_in_types/).first)
            class_comment = built_in_types_code[/\n\s+module SchemaElements\n(.*)\n\s+class BuiltInTypes/m, 1]

            # https://rubular.com/r/uyl4hdk96uMXDC
            documented_types_and_docs = class_comment.scan(/\n\s+# (\w+)\n\s+# : (.*?)(?=\n\s+# (?:\w+\n\s+# :|##|@!))/m).to_h do |type, doc|
              normalized_doc = doc.gsub(/\n\s*#/m, "").gsub(/\s+/, " ")
              [type, normalized_doc]
            end

            # Surface any missing types
            expect(documented_types_and_docs.keys).to match_array(primary_built_in_types_and_docs.keys)

            # For types that are in both, verify the documentation matches.
            (documented_types_and_docs.keys & primary_built_in_types_and_docs.keys).each do |type|
              expected_doc = primary_built_in_types_and_docs.fetch(type)
              actual_doc = documented_types_and_docs.fetch(type)

              expect("- `#{type}`: #{actual_doc}").to eq("- `#{type}`: #{expected_doc}")
            end
          end
        end

        it "defines an `@eg_latency_slo` directive" do
          expect(type_named("@#{schema_elements.eg_latency_slo}", include_docs: true)).to eq(<<~EOS.strip)
            """
            Indicates an upper bound on how quickly a query must respond to meet the service-level objective.
            ElasticGraph will log a "good event" message if the query latency is less than or equal to this value,
            and a "bad event" message if the query latency is greater than this value. These messages can be used
            to drive an SLO dashboard.

            Note that the latency compared against this only contains processing time within ElasticGraph itself.
            Any time spent on sending the request or response over the network is not included in the comparison.
            """
            directive @#{schema_elements.eg_latency_slo}(#{schema_elements.ms}: Int!) on QUERY
          EOS
        end

        it "defines a `Cursor` scalar" do
          expect(type_named("Cursor", include_docs: true)).to eq(<<~EOS.strip)
            """
            An opaque string value representing a specific location in a paginated connection type.
            Returned cursors can be passed back in the next query via the `before` or `after`
            arguments to continue paginating from that point.
            """
            scalar Cursor
          EOS
        end

        it "defines a `GeoLocation` object type and related filter types" do
          expect(type_named("GeoLocation", include_docs: true)).to eq(<<~EOS.strip)
            """
            Geographic coordinates representing a location on the Earth's surface.
            """
            type GeoLocation {
              """
              Angular distance north or south of the Earth's equator, measured in degrees from -90 to +90.
              """
              latitude: Float
              """
              Angular distance east or west of the Prime Meridian at Greenwich, UK, measured in degrees from -180 to +180.
              """
              longitude: Float
            }
          EOS

          expect(type_named("GeoLocationFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `GeoLocation` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input GeoLocationFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [GeoLocationFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `GeoLocationFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [GeoLocationFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              not: GeoLocationFilterInput
              """
              Matches records where the field's geographic location is within a specified distance from the
              location identified by `latitude` and `longitude`.

              When `null` or an empty object is passed, matches all documents.
              """
              near: GeoLocationDistanceFilterInput
            }
          EOS

          expect(type_named("GeoLocationListElementFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on elements of a `[GeoLocation]` field.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input GeoLocationListElementFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [GeoLocationListElementFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `GeoLocationListElementFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [GeoLocationListElementFilterInput!]
              """
              Matches records where the field's geographic location is within a specified distance from the
              location identified by `latitude` and `longitude`.

              When `null` or an empty object is passed, matches all documents.
              """
              near: GeoLocationDistanceFilterInput
            }
          EOS

          expect(type_named("GeoLocationDistanceFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify distance filtering parameters on `GeoLocation` fields.
            """
            input GeoLocationDistanceFilterInput {
              """
              Angular distance north or south of the Earth's equator, measured in degrees from -90 to +90.
              """
              latitude: Float!
              """
              Angular distance east or west of the Prime Meridian at Greenwich, UK, measured in degrees from -180 to +180.
              """
              longitude: Float!
              """
              Maximum distance (of the provided `unit`) to consider "near" the location identified
              by `latitude` and `longitude`.
              """
              #{schema_elements.max_distance}: Float!
              """
              Determines the unit of the specified `#{schema_elements.max_distance}`.
              """
              unit: DistanceUnitInput!
            }
          EOS
        end

        it "defines a `Date` scalar and filter types" do
          expect(type_named("Date", include_docs: true)).to eq(<<~EOS.strip)
            """
            A date, represented as an [ISO 8601 date string](https://en.wikipedia.org/wiki/ISO_8601).
            """
            scalar Date
          EOS

          expect(type_named("DateFilterInput")).to eq(<<~EOS.strip)
            input DateFilterInput {
              #{schema_elements.any_of}: [DateFilterInput!]
              #{schema_elements.all_of}: [DateFilterInput!]
              #{schema_elements.not}: DateFilterInput
              #{schema_elements.equal_to_any_of}: [Date]
              #{schema_elements.gt}: Date
              #{schema_elements.gte}: Date
              #{schema_elements.lt}: Date
              #{schema_elements.lte}: Date
            }
          EOS

          expect(type_named("DateListElementFilterInput")).to eq(<<~EOS.strip)
            input DateListElementFilterInput {
              #{schema_elements.any_of}: [DateListElementFilterInput!]
              #{schema_elements.all_of}: [DateListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [Date!]
              #{schema_elements.gt}: Date
              #{schema_elements.gte}: Date
              #{schema_elements.lt}: Date
              #{schema_elements.lte}: Date
            }
          EOS
        end

        it "defines a `DateTime` scalar and filter types and a `DateTimeTimeOfDayFilterInput` to filter on a DateTime's time of day" do
          expect(type_named("DateTime", include_docs: true)).to eq(<<~EOS.strip)
            """
            A timestamp, represented as an [ISO 8601 time string](https://en.wikipedia.org/wiki/ISO_8601).
            """
            scalar DateTime
          EOS

          expect(type_named("DateTimeFilterInput")).to eq(<<~EOS.strip)
            input DateTimeFilterInput {
              #{schema_elements.any_of}: [DateTimeFilterInput!]
              #{schema_elements.all_of}: [DateTimeFilterInput!]
              #{schema_elements.not}: DateTimeFilterInput
              #{schema_elements.equal_to_any_of}: [DateTime]
              #{schema_elements.gt}: DateTime
              #{schema_elements.gte}: DateTime
              #{schema_elements.lt}: DateTime
              #{schema_elements.lte}: DateTime
              #{schema_elements.time_of_day}: DateTimeTimeOfDayFilterInput
            }
          EOS

          expect(type_named("DateTimeListElementFilterInput")).to eq(<<~EOS.strip)
            input DateTimeListElementFilterInput {
              #{schema_elements.any_of}: [DateTimeListElementFilterInput!]
              #{schema_elements.all_of}: [DateTimeListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [DateTime!]
              #{schema_elements.gt}: DateTime
              #{schema_elements.gte}: DateTime
              #{schema_elements.lt}: DateTime
              #{schema_elements.lte}: DateTime
              #{schema_elements.time_of_day}: DateTimeTimeOfDayFilterInput
            }
          EOS

          expect(type_named("DateTimeTimeOfDayFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on the time-of-day of `DateTime` fields.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input DateTimeTimeOfDayFilterInput {
              """
              Matches records where the time of day of the `DateTime` field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [LocalTime!]
              """
              Matches records where the time of day of the `DateTime` field value is greater than (>) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.gt}: LocalTime
              """
              Matches records where the time of day of the `DateTime` field value is greater than or equal to (>=) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.gte}: LocalTime
              """
              Matches records where the time of day of the `DateTime` field value is less than (<) the provided value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.lt}: LocalTime
              """
              Matches records where the time of day of the `DateTime` field value is less than or equal to (<=) the provided value.

              When `null` is passed, matches all documents.
              """
              lte: LocalTime
              """
              TimeZone to use when comparing the `DateTime` values against the provided `LocalTime` values.
              """
              #{schema_elements.time_zone}: TimeZone! = "UTC"
            }
          EOS
        end

        it "respects a type name override for the `DateTime` type" do
          result = define_schema(type_name_overrides: {DateTime: "Timestamp"})

          expect(type_def_from(result, "Timestamp")).to eq("scalar Timestamp")

          expect(type_def_from(result, "TimestampFilterInput")).to eq(<<~EOS.strip)
            input TimestampFilterInput {
              #{schema_elements.any_of}: [TimestampFilterInput!]
              #{schema_elements.all_of}: [TimestampFilterInput!]
              #{schema_elements.not}: TimestampFilterInput
              #{schema_elements.equal_to_any_of}: [Timestamp]
              #{schema_elements.gt}: Timestamp
              #{schema_elements.gte}: Timestamp
              #{schema_elements.lt}: Timestamp
              #{schema_elements.lte}: Timestamp
              #{schema_elements.time_of_day}: TimestampTimeOfDayFilterInput
            }
          EOS

          expect(type_def_from(result, "TimestampListElementFilterInput")).to eq(<<~EOS.strip)
            input TimestampListElementFilterInput {
              #{schema_elements.any_of}: [TimestampListElementFilterInput!]
              #{schema_elements.all_of}: [TimestampListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [Timestamp!]
              #{schema_elements.gt}: Timestamp
              #{schema_elements.gte}: Timestamp
              #{schema_elements.lt}: Timestamp
              #{schema_elements.lte}: Timestamp
              #{schema_elements.time_of_day}: TimestampTimeOfDayFilterInput
            }
          EOS

          expect(type_def_from(result, "TimestampTimeOfDayFilterInput")).to eq(<<~EOS.strip)
            input TimestampTimeOfDayFilterInput {
              #{schema_elements.equal_to_any_of}: [LocalTime!]
              #{schema_elements.gt}: LocalTime
              #{schema_elements.gte}: LocalTime
              #{schema_elements.lt}: LocalTime
              #{schema_elements.lte}: LocalTime
              #{schema_elements.time_zone}: TimeZone! = "UTC"
            }
          EOS
        end

        it "respects type name overrides for all of the `DateTime` filter types" do
          result = define_schema(type_name_overrides: {
            DateTimeFilterInput: "TimestampFilterInput",
            DateTimeListElementFilterInput: "TimestampListElementFilterInput"
          })

          expect(type_def_from(result, "TimestampFilterInput")).to eq(<<~EOS.strip)
            input TimestampFilterInput {
              #{schema_elements.any_of}: [TimestampFilterInput!]
              #{schema_elements.all_of}: [TimestampFilterInput!]
              #{schema_elements.not}: TimestampFilterInput
              #{schema_elements.equal_to_any_of}: [DateTime]
              #{schema_elements.gt}: DateTime
              #{schema_elements.gte}: DateTime
              #{schema_elements.lt}: DateTime
              #{schema_elements.lte}: DateTime
              #{schema_elements.time_of_day}: DateTimeTimeOfDayFilterInput
            }
          EOS

          expect(type_def_from(result, "TimestampListElementFilterInput")).to eq(<<~EOS.strip)
            input TimestampListElementFilterInput {
              #{schema_elements.any_of}: [TimestampListElementFilterInput!]
              #{schema_elements.all_of}: [TimestampListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [DateTime!]
              #{schema_elements.gt}: DateTime
              #{schema_elements.gte}: DateTime
              #{schema_elements.lt}: DateTime
              #{schema_elements.lte}: DateTime
              #{schema_elements.time_of_day}: DateTimeTimeOfDayFilterInput
            }
          EOS
        end

        it "defines a `LocalTime` scalar and filter types" do
          expect(type_named("LocalTime", include_docs: true)).to eq(<<~EOS.strip)
            """
            A local time such as `"23:59:33"` or `"07:20:47.454"` without a time zone or offset, formatted based on the
            [partial-time portion of RFC3339](https://datatracker.ietf.org/doc/html/rfc3339#section-5.6).
            """
            scalar LocalTime
          EOS

          expect(type_named("LocalTimeFilterInput")).to eq(<<~EOS.strip)
            input LocalTimeFilterInput {
              #{schema_elements.any_of}: [LocalTimeFilterInput!]
              #{schema_elements.all_of}: [LocalTimeFilterInput!]
              #{schema_elements.not}: LocalTimeFilterInput
              #{schema_elements.equal_to_any_of}: [LocalTime]
              #{schema_elements.gt}: LocalTime
              #{schema_elements.gte}: LocalTime
              #{schema_elements.lt}: LocalTime
              #{schema_elements.lte}: LocalTime
            }
          EOS

          expect(type_named("LocalTimeListElementFilterInput")).to eq(<<~EOS.strip)
            input LocalTimeListElementFilterInput {
              #{schema_elements.any_of}: [LocalTimeListElementFilterInput!]
              #{schema_elements.all_of}: [LocalTimeListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [LocalTime!]
              #{schema_elements.gt}: LocalTime
              #{schema_elements.gte}: LocalTime
              #{schema_elements.lt}: LocalTime
              #{schema_elements.lte}: LocalTime
            }
          EOS
        end

        it "defines a `TimeZone` scalar and filter types" do
          expect(type_named("TimeZone", include_docs: true)).to eq(<<~EOS.strip)
            """
            An [IANA time zone identifier](https://www.iana.org/time-zones), such as `America/Los_Angeles` or `UTC`.

            For a full list of valid identifiers, see the [wikipedia article](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).
            """
            scalar TimeZone
          EOS

          expect(type_named("TimeZoneFilterInput")).to eq(<<~EOS.strip)
            input TimeZoneFilterInput {
              #{schema_elements.any_of}: [TimeZoneFilterInput!]
              #{schema_elements.all_of}: [TimeZoneFilterInput!]
              #{schema_elements.not}: TimeZoneFilterInput
              #{schema_elements.equal_to_any_of}: [TimeZone]
            }
          EOS

          expect(type_named("TimeZoneListElementFilterInput")).to eq(<<~EOS.strip)
            input TimeZoneListElementFilterInput {
              #{schema_elements.any_of}: [TimeZoneListElementFilterInput!]
              #{schema_elements.all_of}: [TimeZoneListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [TimeZone!]
            }
          EOS
        end

        it "defines a `DateTimeUnit` enum and filter types" do
          expect(type_named("DateTimeUnit", include_docs: true)).to eq(<<~EOS.strip)
            """
            Enumeration of `DateTime` units.
            """
            enum DateTimeUnit {
              """
              The time period of a full rotation of the Earth with respect to the Sun.
              """
              DAY
              """
              1/24th of a day.
              """
              HOUR
              """
              1/60th of an hour.
              """
              MINUTE
              """
              1/60th of a minute.
              """
              SECOND
              """
              1/1000th of a second.
              """
              MILLISECOND
            }
          EOS

          expect(type_named("DateTimeUnitFilterInput")).to eq(<<~EOS.strip)
            input DateTimeUnitFilterInput {
              #{schema_elements.any_of}: [DateTimeUnitFilterInput!]
              #{schema_elements.all_of}: [DateTimeUnitFilterInput!]
              #{schema_elements.not}: DateTimeUnitFilterInput
              #{schema_elements.equal_to_any_of}: [DateTimeUnitInput]
            }
          EOS

          expect(type_named("DateTimeUnitListElementFilterInput")).to eq(<<~EOS.strip)
            input DateTimeUnitListElementFilterInput {
              #{schema_elements.any_of}: [DateTimeUnitListElementFilterInput!]
              #{schema_elements.all_of}: [DateTimeUnitListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [DateTimeUnitInput!]
            }
          EOS
        end

        it "defines a `DateTimeGroupingOffsetInput` input type" do
          expect(type_named("DateTimeGroupingOffsetInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type offered when grouping on `DateTime` fields, representing the amount of offset
            (positive or negative) to shift the `DateTime` boundaries of each grouping bucket.

            For example, when grouping by `WEEK`, you can shift by 1 day to change
            what day-of-week weeks are considered to start on.
            """
            input DateTimeGroupingOffsetInput {
              """
              Number (positive or negative) of the given `unit` to offset the boundaries of the `DateTime` groupings.
              """
              amount: Int!
              """
              Unit of offsetting to apply to the boundaries of the `DateTime` groupings.
              """
              unit: DateTimeUnitInput!
            }
          EOS
        end

        it "defines a `JsonSafeLong` scalar and filter types" do
          expect(type_named("JsonSafeLong", include_docs: true)).to eq(<<~EOS.strip)
            """
            A numeric type for large integer values that can serialize safely as JSON.

            While JSON itself has no hard limit on the size of integers, the RFC-7159 spec
            mentions that values outside of the range -9,007,199,254,740,991 (-(2^53) + 1)
            to 9,007,199,254,740,991 (2^53 - 1) may not be interopable with all JSON
            implementations. As it turns out, the number implementation used by JavaScript
            has this issue. When you parse a JSON string that contains a numeric value like
            `4693522397653681111`, the parsed result will contain a rounded value like
            `4693522397653681000`.

            While this is entirely a client-side problem, we want to preserve maximum compatibility
            with common client languages. Given the ubiquity of GraphiQL as a GraphQL client,
            we want to avoid this problem.

            Our solution is to support two separate types:

            - This type (`JsonSafeLong`) is serialized as a number, but limits values to the safely
              serializable range.
            - The `LongString` type supports long values that use all 64 bits, but serializes as a
              string rather than a number, avoiding the JavaScript compatibility problems.

            For more background, see the [JavaScript `Number.MAX_SAFE_INTEGER`
            docs](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER).
            """
            scalar JsonSafeLong
          EOS

          expect(type_named("JsonSafeLongFilterInput")).to eq(<<~EOS.strip)
            input JsonSafeLongFilterInput {
              #{schema_elements.any_of}: [JsonSafeLongFilterInput!]
              #{schema_elements.all_of}: [JsonSafeLongFilterInput!]
              #{schema_elements.not}: JsonSafeLongFilterInput
              #{schema_elements.equal_to_any_of}: [JsonSafeLong]
              #{schema_elements.gt}: JsonSafeLong
              #{schema_elements.gte}: JsonSafeLong
              #{schema_elements.lt}: JsonSafeLong
              #{schema_elements.lte}: JsonSafeLong
            }
          EOS

          expect(type_named("JsonSafeLongListElementFilterInput")).to eq(<<~EOS.strip)
            input JsonSafeLongListElementFilterInput {
              #{schema_elements.any_of}: [JsonSafeLongListElementFilterInput!]
              #{schema_elements.all_of}: [JsonSafeLongListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [JsonSafeLong!]
              #{schema_elements.gt}: JsonSafeLong
              #{schema_elements.gte}: JsonSafeLong
              #{schema_elements.lt}: JsonSafeLong
              #{schema_elements.lte}: JsonSafeLong
            }
          EOS
        end

        it "defines a `LongString` scalar and filter types" do
          expect(type_named("LongString", include_docs: true)).to eq(<<~EOS.strip)
            """
            A numeric type for large integer values in the inclusive range -2^63
            (-9,223,372,036,854,775,808) to (2^63 - 1) (9,223,372,036,854,775,807).

            Note that `LongString` values are serialized as strings within JSON, to avoid
            interopability problems with JavaScript. If you want a large integer type that
            serializes within JSON as a number, use `JsonSafeLong`.
            """
            scalar LongString
          EOS

          expect(type_named("LongStringListElementFilterInput")).to eq(<<~EOS.strip)
            input LongStringListElementFilterInput {
              #{schema_elements.any_of}: [LongStringListElementFilterInput!]
              #{schema_elements.all_of}: [LongStringListElementFilterInput!]
              #{schema_elements.equal_to_any_of}: [LongString!]
              #{schema_elements.gt}: LongString
              #{schema_elements.gte}: LongString
              #{schema_elements.lt}: LongString
              #{schema_elements.lte}: LongString
            }
          EOS
        end

        %w[Int Float].each do |type|
          it "defines `#{type}FilterInput` and `#{type}ListElementFilterInput` inputs (but not a `#{type}` scalar, since it's built in)" do
            expect(type_named(type)).to eq nil

            expect(type_named("#{type}FilterInput")).to eq(<<~EOS.strip)
              input #{type}FilterInput {
                #{schema_elements.any_of}: [#{type}FilterInput!]
                #{schema_elements.all_of}: [#{type}FilterInput!]
                #{schema_elements.not}: #{type}FilterInput
                #{schema_elements.equal_to_any_of}: [#{type}]
                #{schema_elements.gt}: #{type}
                #{schema_elements.gte}: #{type}
                #{schema_elements.lt}: #{type}
                #{schema_elements.lte}: #{type}
              }
            EOS

            expect(type_named("#{type}ListElementFilterInput")).to eq(<<~EOS.strip)
              input #{type}ListElementFilterInput {
                #{schema_elements.any_of}: [#{type}ListElementFilterInput!]
                #{schema_elements.all_of}: [#{type}ListElementFilterInput!]
                #{schema_elements.equal_to_any_of}: [#{type}!]
                #{schema_elements.gt}: #{type}
                #{schema_elements.gte}: #{type}
                #{schema_elements.lt}: #{type}
                #{schema_elements.lte}: #{type}
              }
            EOS
          end
        end

        %w[String ID Boolean].each do |type|
          it "defines `#{type}FilterInput` and `#{type}ListElementFilterInput` inputs (but not a `#{type}` scalar, since it's built in)" do
            expect(type_named(type)).to eq nil

            expect(type_named("#{type}FilterInput")).to eq(<<~EOS.strip)
              input #{type}FilterInput {
                #{schema_elements.any_of}: [#{type}FilterInput!]
                #{schema_elements.all_of}: [#{type}FilterInput!]
                #{schema_elements.not}: #{type}FilterInput
                #{schema_elements.equal_to_any_of}: [#{type}]
              }
            EOS

            expect(type_named("#{type}ListElementFilterInput")).to eq(<<~EOS.strip)
              input #{type}ListElementFilterInput {
                #{schema_elements.any_of}: [#{type}ListElementFilterInput!]
                #{schema_elements.all_of}: [#{type}ListElementFilterInput!]
                #{schema_elements.equal_to_any_of}: [#{type}!]
              }
            EOS
          end
        end

        it "defines `TextFilterInput` and `TextListElementFilterInput` input (but not a `Text` scalar, since it's a specialized string filter)" do
          expect(type_named("Text")).to eq nil

          # The `TextFilterInput` has customizations compared to other scalar filters, so it is worth verifying the generated docs.
          expect(type_named("TextFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `String` fields that have been indexed for full text search.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input TextFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [TextFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `TextFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [TextFilterInput!]
              """
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
              """
              #{schema_elements.not}: TextFilterInput
              """
              Matches records where the field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [String]
              """
              Matches records where the field value matches the provided value using full text search.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches}: String @deprecated(reason: "Use `#{schema_elements.matches_query}` instead.")
              """
              Matches records where the field value matches the provided query using full text search.
              This is more lenient than `#{schema_elements.matches_phrase}`: the order of terms is ignored, and,
              by default, only one search term is required to be in the field value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches_query}: MatchesQueryFilterInput
              """
              Matches records where the field value has a phrase matching the provided phrase using
              full text search. This is stricter than `#{schema_elements.matches_query}`: all terms must match
              and be in the same order as the provided phrase.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches_phrase}: MatchesPhraseFilterInput
            }
          EOS

          expect(type_named("TextListElementFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify filters on `String` fields that have been indexed for full text search.

            Will match all documents if passed as an empty object (or as `null`).
            """
            input TextListElementFilterInput {
              """
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
              """
              #{schema_elements.any_of}: [TextListElementFilterInput!]
              """
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `TextListElementFilterInput` input because of collisions between key names. For example, if you want to AND multiple
              OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

              When `null` or an empty list is passed, matches all documents.
              """
              #{schema_elements.all_of}: [TextListElementFilterInput!]
              """
              Matches records where the field value is equal to any of the provided values.
              This works just like an IN operator in SQL.

              When `null` is passed, matches all documents. When an empty list is passed,
              this part of the filter matches no documents. When `null` is passed in the
              list, this part of the filter matches records where the field value is `null`.
              """
              #{schema_elements.equal_to_any_of}: [String!]
              """
              Matches records where the field value matches the provided value using full text search.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches}: String @deprecated(reason: "Use `#{schema_elements.matches_query}` instead.")
              """
              Matches records where the field value matches the provided query using full text search.
              This is more lenient than `#{schema_elements.matches_phrase}`: the order of terms is ignored, and,
              by default, only one search term is required to be in the field value.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches_query}: MatchesQueryFilterInput
              """
              Matches records where the field value has a phrase matching the provided phrase using
              full text search. This is stricter than `#{schema_elements.matches_query}`: all terms must match
              and be in the same order as the provided phrase.

              When `null` is passed, matches all documents.
              """
              #{schema_elements.matches_phrase}: MatchesPhraseFilterInput
            }
          EOS
        end

        describe "`*ListFilterInput` types" do
          %w[Boolean ID String Untyped].each do |scalar|
            it "defines a `#{scalar}ListFilterInput` to support filtering on lists of `#{scalar}` values" do
              expect_list_filter(scalar)
            end
          end

          %w[DistanceUnit].each do |enum|
            it "defines a `#{enum}ListFilterInput` to support filtering on lists of `#{enum}` values" do
              expect_list_filter(enum)
            end
          end

          %w[Date DateTime Float Int JsonSafeLong LocalTime LongString].each do |scalar|
            it "defines a `#{scalar}ListFilterInput` to support filtering on lists of `#{scalar}` values" do
              expect_list_filter(scalar)
            end
          end

          %w[GeoLocation].each do |scalar|
            it "defines a `#{scalar}ListFilterInput` to support filtering on lists of `#{scalar}` values" do
              expect_list_filter(scalar)
            end
          end

          %w[Text].each do |scalar|
            it "defines a `#{scalar}ListFilterInput` to support filtering on lists of `#{scalar}` values" do
              expect_list_filter(scalar, fields_description: "`[String]` fields that have been indexed for full text search")
            end
          end

          def expect_list_filter(scalar, fields_description: "`[#{scalar}]` fields")
            expect(type_named("#{scalar}ListFilterInput", include_docs: true)).to eq(<<~EOS.strip)
              """
              Input type used to specify filters on #{fields_description}.

              Will match all documents if passed as an empty object (or as `null`).
              """
              input #{scalar}ListFilterInput {
                """
                Matches records where any of the provided sub-filters evaluate to true.
                This works just like an OR operator in SQL.

                When `null` is passed, matches all documents.
                When an empty list is passed, this part of the filter matches no documents.
                """
                #{schema_elements.any_of}: [#{scalar}ListFilterInput!]
                """
                Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

                Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
                be provided on a single `#{scalar}ListFilterInput` input because of collisions between key names. For example, if you want to AND multiple
                OR'd sub-filters (the equivalent of (A OR B) AND (C OR D)), you could do #{schema_elements.all_of}: [{#{schema_elements.any_of}: [...]}, {#{schema_elements.any_of}: [...]}].

                When `null` or an empty list is passed, matches all documents.
                """
                #{schema_elements.all_of}: [#{scalar}ListFilterInput!]
                """
                Matches records where the provided sub-filter evaluates to false.
                This works just like a NOT operator in SQL.

                When `null` or an empty object is passed, matches no documents.
                """
                #{schema_elements.not}: #{scalar}ListFilterInput
                """
                Matches records where any of the list elements match the provided sub-filter.

                When `null` or an empty object is passed, matches all documents.
                """
                #{schema_elements.any_satisfy}: #{scalar}ListElementFilterInput
                """
                Used to filter on the number of non-null elements in this list field.

                When `null` or an empty object is passed, matches all documents.
                """
                #{schema_elements.count}: IntFilterInput
              }
            EOS
          end
        end

        it "defines a `MatchesQueryFilterInput` type" do
          expect(type_named("MatchesQueryFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify parameters for the `#{schema_elements.matches_query}` filtering operator.

            When `null` is passed, matches all documents.
            """
            input MatchesQueryFilterInput {
              """
              The input query to search for.
              """
              #{schema_elements.query}: String!
              """
              Number of allowed modifications per term to arrive at a match. For example, if set to 'ONE', the input
              term 'glue' would match 'blue' but not 'clued', since the latter requires two modifications.
              """
              #{schema_elements.allowed_edits_per_term}: MatchesQueryAllowedEditsPerTermInput! = "DYNAMIC"
              """
              Set to `true` to match only if all terms in `#{schema_elements.query}` are found, or
              `false` to only require one term to be found.
              """
              #{schema_elements.require_all_terms}: Boolean! = false
            }
          EOS
        end

        it "defines a `MatchesPhraseFilterInput` type" do
          expect(type_named("MatchesPhraseFilterInput", include_docs: true)).to eq(<<~EOS.strip)
            """
            Input type used to specify parameters for the `#{schema_elements.matches_phrase}` filtering operator.

            When `null` is passed, matches all documents.
            """
            input MatchesPhraseFilterInput {
              """
              The input phrase to search for.
              """
              #{schema_elements.phrase}: String!
            }
          EOS
        end

        it "defines a `PageInfo` type" do
          expect(type_named("PageInfo", include_docs: true)).to eq(<<~EOS.strip)
            """
            Provides information about the specific fetched page. This implements the `PageInfo`
            specification from the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo).
            """
            type PageInfo {
              """
              Indicates if there is another page of results available after the current one.
              """
              #{schema_elements.has_next_page}: Boolean!
              """
              Indicates if there is another page of results available before the current one.
              """
              #{schema_elements.has_previous_page}: Boolean!
              """
              The `Cursor` of the first edge of the current page. This can be passed in the next query as
              a `before` argument to paginate backwards.
              """
              #{schema_elements.start_cursor}: Cursor
              """
              The `Cursor` of the last edge of the current page. This can be passed in the next query as
              a `after` argument to paginate forwards.
              """
              #{schema_elements.end_cursor}: Cursor
            }
          EOS
        end

        ["FloatAggregatedValues"].each do |expected_type|
          it "defines an `#{expected_type}` type" do
            expect(type_named(expected_type, include_docs: true)).to eq(<<~EOS.strip)
              """
              A return type used from aggregations to provided aggregated values over `Float` fields.
              """
              type #{expected_type} {
                """
                An approximation of the number of unique values for this field within this grouping.

                The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
                paper. The accuracy of the returned value varies based on the specific dataset, but
                it usually differs from the true distinct value count by less than 7%.
                """
                #{schema_elements.approximate_distinct_value_count}: JsonSafeLong
                """
                The sum of the field values within this grouping.

                As with all double-precision `Float` values, operations are subject to floating-point loss
                of precision, so the value may be approximate.
                """
                #{schema_elements.approximate_sum}: Float!
                """
                The minimum of the field values within this grouping.

                The value will be "exact" in that the aggregation computation will return
                the exact value of the smallest float that has been indexed, without
                introducing any new imprecision. However, floats by their nature are
                naturally imprecise since they cannot precisely represent all real numbers.
                """
                #{schema_elements.exact_min}: Float
                """
                The maximum of the field values within this grouping.

                The value will be "exact" in that the aggregation computation will return
                the exact value of the largest float that has been indexed, without
                introducing any new imprecision. However, floats by their nature are
                naturally imprecise since they cannot precisely represent all real numbers.
                """
                #{schema_elements.exact_max}: Float
                """
                The average (mean) of the field values within this grouping.

                The computation of this value may introduce additional imprecision (on top of the
                natural imprecision of floats) when it deals with intermediary values that are
                outside the `JsonSafeLong` range (-9,007,199,254,740,991 to 9,007,199,254,740,991).
                """
                #{schema_elements.approximate_avg}: Float
              }
            EOS
          end
        end

        %w[Date DateTime LocalTime].each do |scalar_type|
          it "defines a `#{scalar_type}AggregatedValues` type" do
            expect(type_named("#{scalar_type}AggregatedValues", include_docs: true)).to eq(<<~EOS.strip)
              """
              A return type used from aggregations to provided aggregated values over `#{scalar_type}` fields.
              """
              type #{scalar_type}AggregatedValues {
                """
                An approximation of the number of unique values for this field within this grouping.

                The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
                paper. The accuracy of the returned value varies based on the specific dataset, but
                it usually differs from the true distinct value count by less than 7%.
                """
                #{schema_elements.approximate_distinct_value_count}: JsonSafeLong
                """
                The minimum of the field values within this grouping.

                So long as the grouping contains at least one non-null value for the
                underlying indexed field, this will return an exact non-null value.
                """
                #{schema_elements.exact_min}: #{scalar_type}
                """
                The maximum of the field values within this grouping.

                So long as the grouping contains at least one non-null value for the
                underlying indexed field, this will return an exact non-null value.
                """
                #{schema_elements.exact_max}: #{scalar_type}
                """
                The average (mean) of the field values within this grouping.
                The returned value will be rounded to the nearest `#{scalar_type}` value.
                """
                #{schema_elements.approximate_avg}: #{scalar_type}
              }
            EOS
          end
        end

        it "defines a `NonNumericAggregatedValues` type" do
          expect(type_named("NonNumericAggregatedValues", include_docs: true)).to eq(<<~EOS.strip)
            """
            A return type used from aggregations to provided aggregated values over non-numeric fields.
            """
            type NonNumericAggregatedValues {
              """
              An approximation of the number of unique values for this field within this grouping.

              The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
              paper. The accuracy of the returned value varies based on the specific dataset, but
              it usually differs from the true distinct value count by less than 7%.
              """
              #{schema_elements.approximate_distinct_value_count}: JsonSafeLong
            }
          EOS
        end

        it "defines an `AggregationCountDetail` type" do
          expect(type_named("AggregationCountDetail", include_docs: true)).to eq(<<~EOS.strip)
            """
            Provides detail about an aggregation `count`.
            """
            type AggregationCountDetail {
              """
              The (approximate) count of documents in this aggregation bucket.

              When documents in an aggregation bucket are sourced from multiple shards, the count may be only
              approximate. The `#{schema_elements.upper_bound}` indicates the maximum value of the true count, but usually
              the true count is much closer to this approximate value (which also provides a lower bound on the
              true count).

              When this approximation is known to be exact, the same value will be available from `#{schema_elements.exact_value}`
              and `#{schema_elements.upper_bound}`.
              """
              #{schema_elements.approximate_value}: JsonSafeLong!
              """
              The exact count of documents in this aggregation bucket, if an exact value can be determined.

              When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
              efficiently determine an exact value. When no exact value can be determined, this field will be `null`.
              The `#{schema_elements.approximate_value}` field--which will never be `null`--can be used to get an approximation
              for the count.
              """
              #{schema_elements.exact_value}: JsonSafeLong
              """
              An upper bound on how large the true count of documents in this aggregation bucket could be.

              When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
              efficiently determine an exact value. The `#{schema_elements.approximate_value}` field provides an approximation,
              and this field puts an upper bound on the true count.
              """
              #{schema_elements.upper_bound}: JsonSafeLong!
            }
          EOS
        end

        %w[Int JsonSafeLong].each do |scalar_type|
          long_type = "JsonSafeLong"
          ["#{scalar_type}AggregatedValues"].each do |expected_type|
            it "defines an `#{expected_type}` type" do
              expect(type_named(expected_type, include_docs: true)).to eq(<<~EOS.strip)
                """
                A return type used from aggregations to provided aggregated values over `#{scalar_type}` fields.
                """
                type #{expected_type} {
                  """
                  An approximation of the number of unique values for this field within this grouping.

                  The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
                  paper. The accuracy of the returned value varies based on the specific dataset, but
                  it usually differs from the true distinct value count by less than 7%.
                  """
                  #{schema_elements.approximate_distinct_value_count}: JsonSafeLong
                  """
                  The (approximate) sum of the field values within this grouping.

                  Sums of large `#{scalar_type}` values can result in overflow, where the exact sum cannot
                  fit in a `#{long_type}` return value. This field, as a double-precision `Float`, can
                  represent larger sums, but the value may only be approximate.
                  """
                  #{schema_elements.approximate_sum}: Float!
                  """
                  The exact sum of the field values within this grouping, if it fits in a `#{long_type}`.

                  Sums of large `#{scalar_type}` values can result in overflow, where the exact sum cannot
                  fit in a `#{long_type}`. In that case, `null` will be returned, and `#{schema_elements.approximate_sum}`
                  can be used to get an approximate value.
                  """
                  #{schema_elements.exact_sum}: #{long_type}
                  """
                  The minimum of the field values within this grouping.

                  So long as the grouping contains at least one non-null value for the
                  underlying indexed field, this will return an exact non-null value.
                  """
                  #{schema_elements.exact_min}: #{scalar_type}
                  """
                  The maximum of the field values within this grouping.

                  So long as the grouping contains at least one non-null value for the
                  underlying indexed field, this will return an exact non-null value.
                  """
                  #{schema_elements.exact_max}: #{scalar_type}
                  """
                  The average (mean) of the field values within this grouping.

                  Note that the returned value is approximate. Imprecision can be introduced by the computation if
                  any intermediary values fall outside the `JsonSafeLong` range (-9,007,199,254,740,991
                  to 9,007,199,254,740,991).
                  """
                  #{schema_elements.approximate_avg}: Float
                }
              EOS
            end
          end
        end

        ["LongStringAggregatedValues"].each do |expected_type|
          it "defines an `#{expected_type}` type" do
            expect(type_named(expected_type, include_docs: true)).to eq(<<~EOS.strip)
              """
              A return type used from aggregations to provided aggregated values over `LongString` fields.
              """
              type #{expected_type} {
                """
                An approximation of the number of unique values for this field within this grouping.

                The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
                paper. The accuracy of the returned value varies based on the specific dataset, but
                it usually differs from the true distinct value count by less than 7%.
                """
                #{schema_elements.approximate_distinct_value_count}: JsonSafeLong
                """
                The (approximate) sum of the field values within this grouping.

                Sums of large `LongString` values can result in overflow, where the exact sum cannot
                fit in a `LongString` return value. This field, as a double-precision `Float`, can
                represent larger sums, but the value may only be approximate.
                """
                #{schema_elements.approximate_sum}: Float!
                """
                The exact sum of the field values within this grouping, if it fits in a `JsonSafeLong`.

                Sums of large `LongString` values can result in overflow, where the exact sum cannot
                fit in a `JsonSafeLong`. In that case, `null` will be returned, and `#{schema_elements.approximate_sum}`
                can be used to get an approximate value.
                """
                #{schema_elements.exact_sum}: JsonSafeLong
                """
                The minimum of the field values within this grouping.

                So long as the grouping contains at least one non-null value, and no values exceed the
                `JsonSafeLong` range in the underlying indexed field, this will return an exact non-null value.

                If no non-null values are available, or if the minimum value is outside the `JsonSafeLong`
                range, `null` will be returned. `#{schema_elements.approximate_min}` can be used to differentiate between these
                cases and to get an approximate value.
                """
                #{schema_elements.exact_min}: JsonSafeLong
                """
                The maximum of the field values within this grouping.

                So long as the grouping contains at least one non-null value, and no values exceed the
                `JsonSafeLong` range in the underlying indexed field, this will return an exact non-null value.

                If no non-null values are available, or if the maximum value is outside the `JsonSafeLong`
                range, `null` will be returned. `#{schema_elements.approximate_max}` can be used to differentiate between these
                cases and to get an approximate value.
                """
                #{schema_elements.exact_max}: JsonSafeLong
                """
                The minimum of the field values within this grouping.

                The aggregation computation performed to identify the smallest value is not able
                to maintain exact precision when dealing with values that are outside the `JsonSafeLong`
                range (-9,007,199,254,740,991 to 9,007,199,254,740,991).
                In that case, the `#{schema_elements.exact_min}` field will return `null`, but this field will provide
                a value which may be approximate.
                """
                #{schema_elements.approximate_min}: LongString
                """
                The maximum of the field values within this grouping.

                The aggregation computation performed to identify the largest value is not able
                to maintain exact precision when dealing with values that are outside the `JsonSafeLong`
                range (-9,007,199,254,740,991 to 9,007,199,254,740,991).
                In that case, the `#{schema_elements.exact_max}` field will return `null`, but this field will provide
                a value which may be approximate.
                """
                #{schema_elements.approximate_max}: LongString
                """
                The average (mean) of the field values within this grouping.

                Note that the returned value is approximate. Imprecision can be introduced by the computation if
                any intermediary values fall outside the `JsonSafeLong` range (-9,007,199,254,740,991
                to 9,007,199,254,740,991).
                """
                #{schema_elements.approximate_avg}: Float
              }
            EOS
          end
        end

        it "correctly defines `Cursor` when our schema does not reference it, but references `PageInfo`, which does" do
          result = define_schema do |api|
            api.raw_sdl <<~EOS
              type MyType {
                page_info: PageInfo
              }
            EOS
          end

          expect(result).to include("scalar Cursor")
        end

        it "creates the built in types after extension modules are applied to allow factory extensions to apply to them" do
          deprecatable = Module.new do
            def deprecated!
              directive "deprecated"
            end
          end

          factory_extension = Module.new do
            define_method :new_scalar_type do |name, &block|
              super(name) do |t|
                t.extend deprecatable
                block.call(t)
              end
            end
          end

          api_extension = Module.new do
            define_singleton_method :extended do |api|
              api.factory.extend factory_extension
            end
          end

          result = define_schema(extension_modules: [api_extension]) do |api|
            api.on_built_in_types do |t|
              t.deprecated! if t.name == "DateTime"
            end
          end

          expect(type_def_from(result, "DateTime")).to eq "scalar DateTime @deprecated"
        end

        describe "#on_built_in_types" do
          it "can tag built in types" do
            result = define_schema do |api|
              api.raw_sdl <<~SDL
                directive @tag(name: String!) repeatable on ARGUMENT_DEFINITION | ENUM | ENUM_VALUE | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | INPUT_OBJECT | INTERFACE | OBJECT | SCALAR | UNION
              SDL

              api.object_type "NotABuiltInType" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "widgets"
              end

              api.on_built_in_types do |t|
                t.directive("tag", name: "tag1")
              end

              api.on_built_in_types do |t|
                t.directive("tag", name: "tag2")
              end
            end

            all_type_names = types_defined_in(result)
            categorized_type_names = all_type_names.group_by do |type_name|
              if type_name.start_with?("__") || STOCK_GRAPHQL_SCALARS.include?(type_name)
                :not_explicitly_defined
              elsif type_name.include?("NotABuiltInType")
                :expect_no_tags
              else
                :expect_tags
              end
            end

            # Verify that we have types in all 3 categories as expected.
            expect(categorized_type_names).to include(:expect_no_tags, :expect_tags, :not_explicitly_defined)
            expect(categorized_type_names[:expect_no_tags]).not_to be_empty
            expect(categorized_type_names[:expect_tags]).not_to be_empty
            expect(categorized_type_names[:not_explicitly_defined]).not_to be_empty

            type_defs_by_name = all_type_names.to_h { |type| [type, type_def_from(result, type)] }
            expect(type_defs_by_name.select { |k, type_def| type_def.nil? }.keys).to match_array(categorized_type_names[:not_explicitly_defined])

            categorized_type_names[:expect_tags].each do |type|
              expect(type_defs_by_name[type]).to include("@tag(name: \"tag1\")", "@tag(name: \"tag2\")")
            end

            categorized_type_names[:expect_no_tags].each do |type|
              expect(type_defs_by_name[type]).not_to include("@tag")
            end
          end
        end

        describe "standard enum types" do
          it "generates a `DateGroupingGranularity` enum" do
            expect(type_named("DateGroupingGranularity", include_docs: true)).to eq(<<~EOS.strip)
              """
              Enumerates the supported granularities of a `Date`.
              """
              enum DateGroupingGranularity {
                """
                The year a `Date` falls in.
                """
                YEAR
                """
                The quarter a `Date` falls in.
                """
                QUARTER
                """
                The month a `Date` falls in.
                """
                MONTH
                """
                The week, beginning on Monday, a `Date` falls in.
                """
                WEEK
                """
                The exact day of a `Date`.
                """
                DAY
              }
            EOS
          end

          it "generates a `DateGroupingTruncationUnit` enum" do
            expect(type_named("DateGroupingTruncationUnit", include_docs: true)).to eq(<<~EOS.strip)
              """
              Enumerates the supported truncation units of a `Date`.
              """
              enum DateGroupingTruncationUnit {
                """
                The year a `Date` falls in.
                """
                YEAR
                """
                The quarter a `Date` falls in.
                """
                QUARTER
                """
                The month a `Date` falls in.
                """
                MONTH
                """
                The week, beginning on Monday, a `Date` falls in.
                """
                WEEK
                """
                The exact day of a `Date`.
                """
                DAY
              }
            EOS
          end

          it "generates a `DateTimeGroupingGranularity` enum" do
            expect(type_named("DateTimeGroupingGranularity", include_docs: true)).to eq(<<~EOS.strip)
              """
              Enumerates the supported granularities of a `DateTime`.
              """
              enum DateTimeGroupingGranularity {
                """
                The year a `DateTime` falls in.
                """
                YEAR
                """
                The quarter a `DateTime` falls in.
                """
                QUARTER
                """
                The month a `DateTime` falls in.
                """
                MONTH
                """
                The week, beginning on Monday, a `DateTime` falls in.
                """
                WEEK
                """
                The day a `DateTime` falls in.
                """
                DAY
                """
                The hour a `DateTime` falls in.
                """
                HOUR
                """
                The minute a `DateTime` falls in.
                """
                MINUTE
                """
                The second a `DateTime` falls in.
                """
                SECOND
              }
            EOS
          end

          it "generates a `DateTimeGroupingTruncationUnit` enum" do
            expect(type_named("DateTimeGroupingTruncationUnit", include_docs: true)).to eq(<<~EOS.strip)
              """
              Enumerates the supported truncation units of a `DateTime`.
              """
              enum DateTimeGroupingTruncationUnit {
                """
                The year a `DateTime` falls in.
                """
                YEAR
                """
                The quarter a `DateTime` falls in.
                """
                QUARTER
                """
                The month a `DateTime` falls in.
                """
                MONTH
                """
                The week, beginning on Monday, a `DateTime` falls in.
                """
                WEEK
                """
                The day a `DateTime` falls in.
                """
                DAY
                """
                The hour a `DateTime` falls in.
                """
                HOUR
                """
                The minute a `DateTime` falls in.
                """
                MINUTE
                """
                The second a `DateTime` falls in.
                """
                SECOND
              }
            EOS
          end

          it "generates a `DistanceUnit` enum for use in geo location filtering" do
            expect(type_named("DistanceUnit", include_docs: true)).to eq(<<~EOS.strip)
              """
              Enumerates the supported distance units.
              """
              enum DistanceUnit {
                """
                A United States customary unit of 5,280 feet.
                """
                MILE
                """
                A United States customary unit of 3 feet.
                """
                YARD
                """
                A United States customary unit of 12 inches.
                """
                FOOT
                """
                A United States customary unit equal to 1/12th of a foot.
                """
                INCH
                """
                A metric system unit equal to 1,000 meters.
                """
                KILOMETER
                """
                The base unit of length in the metric system.
                """
                METER
                """
                A metric system unit equal to 1/100th of a meter.
                """
                CENTIMETER
                """
                A metric system unit equal to 1/1,000th of a meter.
                """
                MILLIMETER
                """
                An international unit of length used for air, marine, and space navigation. Equivalent to 1,852 meters.
                """
                NAUTICAL_MILE
              }
            EOS
          end
        end

        describe "date and time grouped by types" do
          it "generates a `DateTimeGroupedBy` type" do
            expect(type_named("DateTimeGroupedBy", include_docs: true)).to eq(<<~EOS.strip)
              """
              Allows for grouping `DateTime` values based on the desired return type.
              """
              type DateTimeGroupedBy {
                """
                Used when grouping on the full `DateTime` value.
                """
                #{schema_elements.as_date_time}(
                  """
                  Amount of offset (positive or negative) to shift the `DateTime` boundaries of each grouping bucket.

                  For example, when grouping by `WEEK`, you can shift by 1 day to change what day-of-week weeks are considered to start on.
                  """
                  #{schema_elements.offset}: DateTimeGroupingOffsetInput
                  """
                  The time zone to use when determining which grouping a `DateTime` value falls in.
                  """
                  #{schema_elements.time_zone}: TimeZone! = "UTC"
                  """
                  Determines the grouping truncation unit for this field.
                  """
                  #{schema_elements.truncation_unit}: DateTimeGroupingTruncationUnitInput!): DateTime
                """
                An alternative to `#{schema_elements.as_date_time}` for when grouping on just the date is desired.
                """
                #{schema_elements.as_date}(
                  """
                  Amount of offset (positive or negative) to shift the `Date` boundaries of each grouping bucket.

                  For example, when grouping by `WEEK`, you can shift by 1 day to change what day-of-week weeks are considered to start on.
                  """
                  #{schema_elements.offset}: DateGroupingOffsetInput
                  """
                  The time zone to use when determining which grouping a `Date` value falls in.
                  """
                  #{schema_elements.time_zone}: TimeZone! = "UTC"
                  """
                  Determines the grouping truncation unit for this field.
                  """
                  #{schema_elements.truncation_unit}: DateGroupingTruncationUnitInput!): Date
                """
                An alternative to `#{schema_elements.as_date_time}` for when grouping on just the time-of-day is desired.
                """
                #{schema_elements.as_time_of_day}(
                  """
                  Amount of offset (positive or negative) to shift the `LocalTime` boundaries of each grouping bucket.

                  For example, when grouping by `HOUR`, you can apply an offset of -5 minutes to shift `LocalTime`
                  values to the prior hour when they fall between the the top of an hour and 5 after.
                  """
                  #{schema_elements.offset}: LocalTimeGroupingOffsetInput
                  """
                  The time zone to use when determining which grouping a `LocalTime` value falls in.
                  """
                  #{schema_elements.time_zone}: TimeZone! = "UTC"
                  """
                  Determines the grouping truncation unit for this field.
                  """
                  #{schema_elements.truncation_unit}: LocalTimeGroupingTruncationUnitInput!): LocalTime
                """
                An alternative to `#{schema_elements.as_date_time}` for when grouping on the day-of-week is desired.
                """
                #{schema_elements.as_day_of_week}(
                  """
                  Amount of offset (positive or negative) to shift the `DayOfWeek` boundaries of each grouping bucket.

                  For example, you can apply an offset of -2 hours to shift `DateTime` values to the prior `DayOfWeek`
                  when they fall between midnight and 2 AM.
                  """
                  #{schema_elements.offset}: DayOfWeekGroupingOffsetInput
                  """
                  The time zone to use when determining which grouping a `DayOfWeek` value falls in.
                  """
                  #{schema_elements.time_zone}: TimeZone! = "UTC"): DayOfWeek
              }
            EOS
          end

          it "generates a `DateGroupedBy` type" do
            expect(type_named("DateGroupedBy", include_docs: true)).to eq(<<~EOS.strip)
              """
              Allows for grouping `Date` values based on the desired return type.
              """
              type DateGroupedBy {
                """
                Used when grouping on the full `Date` value.
                """
                #{schema_elements.as_date}(
                  """
                  Amount of offset (positive or negative) to shift the `Date` boundaries of each grouping bucket.

                  For example, when grouping by `WEEK`, you can shift by 1 day to change what day-of-week weeks are considered to start on.
                  """
                  #{schema_elements.offset}: DateGroupingOffsetInput
                  """
                  Determines the grouping truncation unit for this field.
                  """
                  #{schema_elements.truncation_unit}: DateGroupingTruncationUnitInput!): Date
                """
                An alternative to `#{schema_elements.as_date}` for when grouping on the day-of-week is desired.
                """
                #{schema_elements.as_day_of_week}(
                  """
                  Amount of offset (positive or negative) to shift the `DayOfWeek` boundaries of each grouping bucket.

                  For example, you can apply an offset of -2 hours to shift `DateTime` values to the prior `DayOfWeek`
                  when they fall between midnight and 2 AM.
                  """
                  #{schema_elements.offset}: DayOfWeekGroupingOffsetInput): DayOfWeek
              }
            EOS
          end

          it "generates a `DayOfWeek` enum" do
            expect(type_named("DayOfWeek", include_docs: true)).to eq(<<~EOS.strip)
              """
              Indicates the specific day of the week.
              """
              enum DayOfWeek {
                """
                Monday.
                """
                MONDAY
                """
                Tuesday.
                """
                TUESDAY
                """
                Wednesday.
                """
                WEDNESDAY
                """
                Thursday.
                """
                THURSDAY
                """
                Friday.
                """
                FRIDAY
                """
                Saturday.
                """
                SATURDAY
                """
                Sunday.
                """
                SUNDAY
              }
            EOS
          end
        end

        before(:context) { @result = define_schema }

        def type_named(name, include_docs: false)
          type_def_from(@result, name, include_docs: include_docs)
        end
      end
    end
  end
end

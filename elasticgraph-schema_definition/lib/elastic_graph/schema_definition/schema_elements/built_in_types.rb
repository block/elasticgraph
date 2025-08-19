# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/schema_artifacts/runtime_metadata/enum"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Defines all built-in GraphQL types provided by ElasticGraph.
      #
      # ## Scalar Types
      #
      # ### Standard GraphQL Scalars
      #
      # These are defined by the [GraphQL spec](https://spec.graphql.org/October2021/#sec-Scalars.Built-in-Scalars).
      #
      # Boolean
      # : Represents `true` or `false` values.
      #
      # Float
      # : Represents signed double-precision fractional values as specified by
      #   [IEEE 754](https://en.wikipedia.org/wiki/IEEE_floating_point).
      #
      # ID
      # : Represents a unique identifier that is Base64 obfuscated. It is often used to
      #   refetch an object or as key for a cache. The ID type appears in a JSON response as a
      #   String; however, it is not intended to be human-readable. When expected as an input
      #   type, any string (such as `"VXNlci0xMA=="`) or integer (such as `4`) input value will
      #   be accepted as an ID.
      #
      # Int
      # : Represents non-fractional signed whole numeric values. Int can represent values between
      #   -(2^31) and 2^31 - 1.
      #
      # String
      # : Represents textual data as UTF-8 character sequences. This type is most often used by
      #   GraphQL to represent free-form human-readable text.
      #
      # ### Additional ElasticGraph Scalars
      #
      # ElasticGraph defines these additional scalar types.
      #
      # Cursor
      # : An opaque string value representing a specific location in a paginated connection type.
      #   Returned cursors can be passed back in the next query via the `before` or `after`
      #   arguments to continue paginating from that point.
      #
      # Date
      # : A date, represented as an [ISO 8601 date string](https://en.wikipedia.org/wiki/ISO_8601).
      #
      # DateTime
      # : A timestamp, represented as an [ISO 8601 time string](https://en.wikipedia.org/wiki/ISO_8601).
      #
      # JsonSafeLong
      # : A numeric type for large integer values that can serialize safely as JSON. While JSON
      #   itself has no hard limit on the size of integers, the RFC-7159 spec mentions that
      #   values outside of the range -9,007,199,254,740,991 (-(2^53) + 1) to 9,007,199,254,740,991
      #   (2^53 - 1) may not be interopable with all JSON implementations. As it turns out, the
      #   number implementation used by JavaScript has this issue. When you parse a JSON string that
      #   contains a numeric value like `4693522397653681111`, the parsed result will contain a
      #   rounded value like `4693522397653681000`. While this is entirely a client-side problem,
      #   we want to preserve maximum compatibility with common client languages. Given the ubiquity
      #   of GraphiQL as a GraphQL client, we want to avoid this problem. Our solution is to support
      #   two separate types:
      #
      #   - This type (`JsonSafeLong`) is serialized as a number, but limits values to the safely
      #     serializable range.
      #   - The `LongString` type supports long values that use all 64 bits, but serializes as a
      #     string rather than a number, avoiding the JavaScript compatibility problems. For more
      #     background, see the [JavaScript `Number.MAX_SAFE_INTEGER`
      #     docs](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER).
      #
      # LocalTime
      # : A local time such as `"23:59:33"` or `"07:20:47.454"` without a time zone or offset,
      #   formatted based on the [partial-time portion of
      #   RFC3339](https://datatracker.ietf.org/doc/html/rfc3339#section-5.6).
      #
      # LongString
      # : A numeric type for large integer values in the inclusive range -2^63 (-9,223,372,036,854,775,808)
      #   to (2^63 - 1) (9,223,372,036,854,775,807). Note that `LongString` values are serialized as strings
      #   within JSON, to avoid interopability problems with JavaScript. If you want a large integer type
      #   that serializes within JSON as a number, use `JsonSafeLong`.
      #
      # TimeZone
      # : An [IANA time zone identifier](https://www.iana.org/time-zones), such as `America/Los_Angeles`
      #   or `UTC`. For a full list of valid identifiers, see the
      #   [wikipedia article](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).
      #
      # Untyped
      # : A custom scalar type that allows any type of data, including:
      #
      #   - strings
      #   - numbers
      #   - objects and arrays (nested as deeply as you like)
      #   - booleans
      #
      #   Note: fields of this type are effectively untyped. We recommend it only be used for parts
      #   of your schema that can't be statically typed.
      #
      # ## Enum Types
      #
      # ElasticGraph defines these enum types. Most of these are intended for usage as an _input_
      # argument, but they could be used as a return type in your schema if they meet your needs.
      #
      # DateGroupingTruncationUnit
      # : Enumerates the supported truncation units of a `Date`.
      #
      # DateTimeGroupingTruncationUnit
      # : Enumerates the supported truncation units of a `DateTime`.
      #
      # DateTimeUnit
      # : Enumeration of `DateTime` units.
      #
      # DateUnit
      # : Enumeration of `Date` units.
      #
      # DayOfWeek
      # : Indicates the specific day of the week.
      #
      # DistanceUnit
      # : Enumerates the supported distance units.
      #
      # LocalTimeGroupingTruncationUnit
      # : Enumerates the supported truncation units of a `LocalTime`.
      #
      # LocalTimeUnit
      # : Enumeration of `LocalTime` units.
      #
      # MatchesQueryAllowedEditsPerTerm
      # : Enumeration of allowed values for the `matchesQuery: {allowedEditsPerTerm: ...}` filter option.
      #
      # ## Object Types
      #
      # ElasticGraph defines these object types.
      #
      # AggregationCountDetail
      # : Provides detail about an aggregation `count`.
      #
      # GeoLocation
      # : Geographic coordinates representing a location on the Earth's surface.
      #
      # PageInfo
      # : Provides information about the specific fetched page. This implements the
      #   `PageInfo` specification from the [Relay GraphQL Cursor Connections
      #   Specification](https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo).
      #
      # SearchHighlight
      # : Provides information about why a document matched a search via highlighted snippets.
      #
      # @!attribute [rw] schema_def_api
      #   @private
      # @!attribute [rw] schema_def_state
      #   @private
      # @!attribute [rw] names
      #   @private
      class BuiltInTypes
        attr_reader :schema_def_api, :schema_def_state, :names

        # @private
        def initialize(schema_def_api, schema_def_state)
          @schema_def_api = schema_def_api
          @schema_def_state = schema_def_state
          @names = schema_def_state.schema_elements
        end

        # @private
        def register_built_in_types
          register_directives
          register_standard_graphql_scalars
          register_custom_elastic_graph_scalars
          register_enum_types
          register_date_and_time_grouped_by_types
          register_standard_elastic_graph_types
          register_standard_graphql_resolvers
        end

        private

        def register_directives
          # Note: The `eg` prefix is being used based on a GraphQL Spec recommendation:
          # http://spec.graphql.org/October2021/#sec-Type-System.Directives.Custom-Directives
          schema_def_api.raw_sdl <<~EOS
            """
            Indicates an upper bound on how quickly a query must respond to meet the service-level objective.
            ElasticGraph will log a "good event" message if the query latency is less than or equal to this value,
            and a "bad event" message if the query latency is greater than this value. These messages can be used
            to drive an SLO dashboard.

            Note that the latency compared against this only contains processing time within ElasticGraph itself.
            Any time spent on sending the request or response over the network is not included in the comparison.
            """
            directive @#{names.eg_latency_slo}(#{names.ms}: Int!) on QUERY
          EOS
        end

        def register_standard_elastic_graph_types
          # This is a special filter on a `String` type, so we don't have a `Text` scalar to generate it from.
          schema_def_state.factory.build_standard_filter_input_types_for_index_leaf_type("String", name_prefix: "Text") do |t|
            t.field names.matches_query, schema_def_state.type_ref("MatchesQuery").as_filter_input.name do |f|
              f.documentation <<~EOS
                Matches records where the field value matches the provided query using full text search.
                This is more lenient than `#{names.matches_phrase}`: the order of terms is ignored, and,
                by default, only one search term is required to be in the field value.

                When `null` is passed, matches all documents.
              EOS
            end

            t.field names.matches_phrase, schema_def_state.type_ref("MatchesPhrase").as_filter_input.name do |f|
              f.documentation <<~EOS
                Matches records where the field value has a phrase matching the provided phrase using
                full text search. This is stricter than `#{names.matches_query}`: all terms must match
                and be in the same order as the provided phrase.

                When `null` is passed, matches all documents.
              EOS
            end

            t.field names.matches_query_with_prefix, schema_def_state.type_ref("MatchesQueryWithPrefix").as_filter_input.name do |f|
              f.documentation <<~EOS
                Matches records where the field value matches the provided query with the last term treated as a prefix.
                Similar to `#{names.matches_query}`, but allows prefix matching on the last term.

                When `null` is passed, matches all documents.
              EOS
            end
          end.each do |input_type|
            field_type = input_type.type_ref.list_filter_input? ? "[String]" : "String"
            input_type.documentation <<~EOS
              Input type used to specify filters on `#{field_type}` fields that have been indexed for full text search.

              Will match all documents if passed as an empty object (or as `null`).
            EOS

            register_input_type(input_type)
          end

          register_filter "MatchesQuery" do |t|
            t.documentation <<~EOS
              Input type used to specify parameters for the `#{names.matches_query}` filtering operator.

              When `null` is passed, matches all documents.
            EOS

            t.field names.query, "String!" do |f|
              f.documentation "The input query to search for."
            end

            t.field names.allowed_edits_per_term, "MatchesQueryAllowedEditsPerTerm!" do |f|
              f.documentation <<~EOS
                Number of allowed modifications per term to arrive at a match. For example, if set to 'ONE', the input
                term 'glue' would match 'blue' but not 'clued', since the latter requires two modifications.
              EOS

              f.default "DYNAMIC"
            end

            t.field names.require_all_terms, "Boolean!" do |f|
              f.documentation <<~EOS
                Set to `true` to match only if all terms in `#{names.query}` are found, or
                `false` to only require one term to be found.
              EOS

              f.default false
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          register_filter "MatchesPhrase" do |t|
            t.documentation <<~EOS
              Input type used to specify parameters for the `#{names.matches_phrase}` filtering operator.

              When `null` is passed, matches all documents.
            EOS

            t.field names.phrase, "String!" do |f|
              f.documentation "The input phrase to search for."
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          register_filter "MatchesQueryWithPrefix" do |t|
            t.documentation <<~EOS
              Input type used to specify parameters for the `#{names.matches_query_with_prefix}` filtering operator.

              When `null` is passed, matches all documents.
            EOS

            t.field names.query_with_prefix, "String!" do |f|
              f.documentation "The input query to search for, with the last term treated as a prefix."
            end

            t.field names.allowed_edits_per_term, "MatchesQueryAllowedEditsPerTerm!" do |f|
              f.documentation <<~EOS
                Number of allowed modifications per term to arrive at a match. For example, if set to 'ONE', the input
                term 'glue' would match 'blue' but not 'clued', since the latter requires two modifications.
              EOS

              f.default "DYNAMIC"
            end

            t.field names.require_all_terms, "Boolean!" do |f|
              f.documentation <<~EOS
                Set to `true` to match only if all terms in `#{names.query_with_prefix}` are found, or
                `false` to only require one term to be found.
              EOS

              f.default false
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          register_filter "StringContains" do |t|
            t.documentation <<~EOS
              Input type used to specify parameters for the `#{names.contains}` string filtering operator.

              When `null` is passed, matches all documents.
            EOS

            t.field names.any_substring_of, "[String!]" do |f|
              f.documentation <<~EOS
                Matches records where the field value contains one or more of the provided substrings.

                When `null` is passed, matches all documents. When an empty list is passed,
                this part of the filter matches no documents.
              EOS
            end

            t.field names.all_substrings_of, "[String!]" do |f|
              f.documentation <<~EOS
                Matches records where the field value contains all of the provided substrings.

                When `null` is passed or an empty list is passed, matches all documents.
              EOS
            end

            t.field names.ignore_case, "Boolean!" do |f|
              f.default false
              f.documentation "Determines if the substring matching is case-sensitive (the default) or case-insensitive."
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          register_filter "StringStartsWith" do |t|
            t.documentation <<~EOS
              Input type used to specify parameters for the `#{names.starts_with}` string filtering operator.

              When `null` is passed, matches all documents.
            EOS

            t.field names.any_prefix_of, "[String!]" do |f|
              f.documentation <<~EOS
                Matches records where the field value starts with one or more of the provided prefixes.

                When `null` is passed, matches all documents. When an empty list is passed,
                this part of the filter matches no documents.
              EOS
            end

            t.field names.ignore_case, "Boolean!" do |f|
              f.default false
              f.documentation "Determines if the prefix matching is case-sensitive (the default) or case-insensitive."
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          # This is defined as a built-in ElasticGraph type so that we can leverage Elasticsearch/OpenSearch GeoLocation features
          # based on the geo-point type:
          # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/geo-point.html
          schema_def_api.object_type "GeoLocation" do |t|
            t.documentation "Geographic coordinates representing a location on the Earth's surface."

            # As per the Elasticsearch docs, the field MUST come in named `lat` in Elastisearch (but we want the full name in GraphQL).
            t.field names.latitude, "Float", name_in_index: "lat" do |f|
              f.documentation "Angular distance north or south of the Earth's equator, measured in degrees from -90 to +90."

              # Note: we use `nullable: false` because we index it as a single `geo_point` field, and therefore can't
              # support a `latitude` without a `longitude` or vice-versa.
              f.json_schema minimum: -90, maximum: 90, nullable: false
            end

            # As per the Elasticsearch docs, the field MUST come in named `lon` in Elastisearch (but we want the full name in GraphQL).
            t.field names.longitude, "Float", name_in_index: "lon" do |f|
              f.documentation "Angular distance east or west of the Prime Meridian at Greenwich, UK, measured in degrees from -180 to +180."

              # Note: we use `nullable: false` because we index it as a single `geo_point` field, and therefore can't
              # support a `latitude` without a `longitude` or vice-versa.
              f.json_schema minimum: -180, maximum: 180, nullable: false
            end

            t.mapping type: "geo_point"
          end

          # Note: `GeoLocation` is an index leaf type even though it is a GraphQL object type. In the datastore,
          # it is indexed as an indivisible `geo_point` field.
          schema_def_state.factory.build_standard_filter_input_types_for_index_leaf_type("GeoLocation") do |t|
            t.field names.near, schema_def_state.type_ref("GeoLocationDistance").as_filter_input.name do |f|
              f.documentation <<~EOS
                Matches records where the field's geographic location is within a specified distance from the
                location identified by `#{names.latitude}` and `#{names.longitude}`.

                When `null` or an empty object is passed, matches all documents.
              EOS
            end
          end.each { |input_filter| register_input_type(input_filter) }

          register_filter "GeoLocationDistance" do |t|
            t.documentation "Input type used to specify distance filtering parameters on `GeoLocation` fields."

            # Note: all 4 of these fields (latitude, longitude, max_distance, unit) are required for this
            # filter to operator properly, so they are all non-null fields.

            t.field names.latitude, "Float!" do |f|
              f.documentation "Angular distance north or south of the Earth's equator, measured in degrees from -90 to +90."
            end

            t.field names.longitude, "Float!" do |f|
              f.documentation "Angular distance east or west of the Prime Meridian at Greenwich, UK, measured in degrees from -180 to +180."
            end

            t.field names.max_distance, "Float!" do |f|
              f.documentation <<~EOS
                Maximum distance (of the provided `#{names.unit}`) to consider "near" the location identified
                by `#{names.latitude}` and `#{names.longitude}`.
              EOS
            end

            t.field names.unit, "DistanceUnit!" do |f|
              f.documentation "Determines the unit of the specified `#{names.max_distance}`."
            end

            # any_of/all_of/not don't really make sense on this filter because it doesn't make sense
            # to apply an OR operator or negation to the fields of this type since they are all an
            # indivisible part of a single filter operation on a specific field. So we remove them
            # here.
            remove_any_of_and_all_of_and_not_filter_operators_on(t)
          end

          # Note: `has_next_page`/`has_previous_page` are required to be non-null by the relay
          # spec: https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo.
          # The cursors are required to be non-null by the relay spec, but it is nonsensical
          # when dealing with an empty collection, and relay itself implements it to be null:
          #
          # https://github.com/facebook/relay/commit/a17b462b3ff7355df4858a42ddda75f58c161302
          #
          # For more context, see:
          # https://github.com/rmosolgo/graphql-ruby/pull/2886#issuecomment-618414736
          # https://github.com/facebook/relay/pull/2655
          #
          # For now we will make the cursor fields nullable. It would be a breaking change
          # to go from non-null to null, but is not a breaking change to make it non-null
          # in the future.
          register_framework_object_type "PageInfo" do |t|
            t.resolve_fields_with :object_without_lookahead

            t.documentation <<~EOS
              Provides information about the specific fetched page. This implements the `PageInfo`
              specification from the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-undefined.PageInfo).
            EOS

            t.field names.has_next_page, "Boolean!", graphql_only: true do |f|
              f.documentation "Indicates if there is another page of results available after the current one."
            end

            t.field names.has_previous_page, "Boolean!", graphql_only: true do |f|
              f.documentation "Indicates if there is another page of results available before the current one."
            end

            t.field names.start_cursor, "Cursor", graphql_only: true do |f|
              f.documentation <<~EOS
                The `Cursor` of the first edge of the current page. This can be passed in the next query as
                a `before` argument to paginate backwards.
              EOS
            end

            t.field names.end_cursor, "Cursor", graphql_only: true do |f|
              f.documentation <<~EOS
                The `Cursor` of the last edge of the current page. This can be passed in the next query as
                a `after` argument to paginate forwards.
              EOS
            end
          end

          register_framework_object_type "SearchHighlight" do |t|
            t.resolve_fields_with :object_without_lookahead

            t.documentation "Provides information about why a document matched a search via highlighted snippets."

            t.field names.path, "[String!]!" do |f|
              f.documentation <<~EOS
                Path to a leaf field containing one or more search highlight snippets. The returned list will contain a path segment for
                each object layer of the schema, from the document root.
              EOS
            end

            t.field names.snippets, "[String!]!" do |f|
              f.documentation "List of snippets containing search highlights from field values at this `path`."
            end
          end

          schema_def_api.factory.new_input_type("DateTimeGroupingOffsetInput") do |t|
            t.documentation <<~EOS
              Input type offered when grouping on `DateTime` fields, representing the amount of offset
              (positive or negative) to shift the `DateTime` boundaries of each grouping bucket.

              For example, when grouping by `WEEK`, you can shift by 1 day to change
              what day-of-week weeks are considered to start on.
            EOS

            t.field names.amount, "Int!" do |f|
              f.documentation "Number (positive or negative) of the given `#{names.unit}` to offset the boundaries of the `DateTime` groupings."
            end

            t.field names.unit, "DateTimeUnit!" do |f|
              f.documentation "Unit of offsetting to apply to the boundaries of the `DateTime` groupings."
            end

            register_input_type(t)
          end

          schema_def_api.factory.new_input_type("DateGroupingOffsetInput") do |t|
            t.documentation <<~EOS
              Input type offered when grouping on `Date` fields, representing the amount of offset
              (positive or negative) to shift the `Date` boundaries of each grouping bucket.

              For example, when grouping by `WEEK`, you can shift by 1 day to change
              what day-of-week weeks are considered to start on.
            EOS

            t.field names.amount, "Int!" do |f|
              f.documentation "Number (positive or negative) of the given `#{names.unit}` to offset the boundaries of the `Date` groupings."
            end

            t.field names.unit, "DateUnit!" do |f|
              f.documentation "Unit of offsetting to apply to the boundaries of the `Date` groupings."
            end

            register_input_type(t)
          end

          schema_def_api.factory.new_input_type("DayOfWeekGroupingOffsetInput") do |t|
            t.documentation <<~EOS
              Input type offered when grouping on `DayOfWeek` fields, representing the amount of offset
              (positive or negative) to shift the `DayOfWeek` boundaries of each grouping bucket.

              For example, you can apply an offset of -2 hours to shift `DateTime` values to the prior `DayOfWeek`
              when they fall between midnight and 2 AM.
            EOS

            t.field names.amount, "Int!" do |f|
              f.documentation "Number (positive or negative) of the given `#{names.unit}` to offset the boundaries of the `DayOfWeek` groupings."
            end

            t.field names.unit, "DateTimeUnit!" do |f|
              f.documentation "Unit of offsetting to apply to the boundaries of the `DayOfWeek` groupings."
            end

            register_input_type(t)
          end

          schema_def_api.factory.new_input_type("LocalTimeGroupingOffsetInput") do |t|
            t.documentation <<~EOS
              Input type offered when grouping on `LocalTime` fields, representing the amount of offset
              (positive or negative) to shift the `LocalTime` boundaries of each grouping bucket.

              For example, when grouping by `HOUR`, you can shift by 30 minutes to change
              what minute-of-hour hours are considered to start on.
            EOS

            t.field names.amount, "Int!" do |f|
              f.documentation "Number (positive or negative) of the given `#{names.unit}` to offset the boundaries of the `LocalTime` groupings."
            end

            t.field names.unit, "LocalTimeUnit!" do |f|
              f.documentation "Unit of offsetting to apply to the boundaries of the `LocalTime` groupings."
            end

            register_input_type(t)
          end

          schema_def_api.factory.new_aggregated_values_type_for_index_leaf_type "NonNumeric" do |t|
            t.documentation "A return type used from aggregations to provided aggregated values over non-numeric fields."
            schema_def_api.state.register_object_interface_or_union_type(t)
          end

          register_framework_object_type "AggregationCountDetail" do |t|
            t.documentation "Provides detail about an aggregation `#{names.count}`."
            t.resolve_fields_with :object_without_lookahead

            t.field names.approximate_value, "JsonSafeLong!", graphql_only: true do |f|
              f.documentation <<~EOS
                The (approximate) count of documents in this aggregation bucket.

                When documents in an aggregation bucket are sourced from multiple shards, the count may be only
                approximate. The `#{names.upper_bound}` indicates the maximum value of the true count, but usually
                the true count is much closer to this approximate value (which also provides a lower bound on the
                true count).

                When this approximation is known to be exact, the same value will be available from `#{names.exact_value}`
                and `#{names.upper_bound}`.
              EOS
            end

            t.field names.exact_value, "JsonSafeLong", graphql_only: true do |f|
              f.documentation <<~EOS
                The exact count of documents in this aggregation bucket, if an exact value can be determined.

                When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
                efficiently determine an exact value. When no exact value can be determined, this field will be `null`.
                The `#{names.approximate_value}` field--which will never be `null`--can be used to get an approximation
                for the count.
              EOS
            end

            t.field names.upper_bound, "JsonSafeLong!", graphql_only: true do |f|
              f.documentation <<~EOS
                An upper bound on how large the true count of documents in this aggregation bucket could be.

                When documents in an aggregation bucket are sourced from multiple shards, it may not be possible to
                efficiently determine an exact value. The `#{names.approximate_value}` field provides an approximation,
                and this field puts an upper bound on the true count.
              EOS
            end
          end
        end

        # Registers the standard GraphQL scalar types. Note that the SDL for the scalar type itself isn't
        # included in the dumped SDL, but registering it allows us to derive a filter for each,
        # which we need. In addition, this lets us define the mapping and JSON schema for each standard
        # scalar type.
        def register_standard_graphql_scalars
          schema_def_api.scalar_type "Boolean" do |t|
            t.mapping type: "boolean"
            t.json_schema type: "boolean"
          end

          schema_def_api.scalar_type "Float" do |t|
            t.mapping type: "double"
            t.json_schema type: "number"

            t.customize_aggregated_values_type do |avt|
              # not nullable, since sum(empty_set) == 0
              avt.field names.approximate_sum, "Float!", graphql_only: true do |f|
                f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :sum

                f.documentation <<~EOS
                  The sum of the field values within this grouping.

                  As with all double-precision `Float` values, operations are subject to floating-point loss
                  of precision, so the value may be approximate.
                EOS
              end

              define_exact_min_and_max_on_aggregated_values(avt, "Float") do |adjective:, full_name:|
                <<~EOS
                  The value will be "exact" in that the aggregation computation will return
                  the exact value of the #{adjective} float that has been indexed, without
                  introducing any new imprecision. However, floats by their nature are
                  naturally imprecise since they cannot precisely represent all real numbers.
                EOS
              end

              avt.field names.approximate_avg, "Float", graphql_only: true do |f|
                f.runtime_metadata_computation_detail empty_bucket_value: nil, function: :avg

                f.documentation <<~EOS
                  The average (mean) of the field values within this grouping.

                  The computation of this value may introduce additional imprecision (on top of the
                  natural imprecision of floats) when it deals with intermediary values that are
                  outside the `JsonSafeLong` range (#{format_number(JSON_SAFE_LONG_MIN)} to #{format_number(JSON_SAFE_LONG_MAX)}).
                EOS
              end
            end
          end

          schema_def_api.scalar_type "ID" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"
          end

          schema_def_api.scalar_type "Int" do |t|
            t.mapping type: "integer"
            t.json_schema type: "integer", minimum: INT_MIN, maximum: INT_MAX

            t.prepare_for_indexing_with "ElasticGraph::Indexer::IndexingPreparers::Integer",
              defined_at: "elastic_graph/indexer/indexing_preparers/integer"

            define_integral_aggregated_values_for(t)
          end

          schema_def_api.scalar_type "String" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"

            t.customize_filter_input_type do |fit|
              fit.field names.contains, schema_def_state.type_ref("StringContains").as_filter_input.name do |f|
                f.documentation <<~EOS
                  Matches documents using substring filtering.

                  When `null` is passed, matches all documents.
                EOS
              end

              fit.field names.starts_with, schema_def_state.type_ref("StringStartsWith").as_filter_input.name do |f|
                f.documentation <<~EOS
                  Matches documents using prefix filtering.

                  When `null` is passed, matches all documents.
                EOS
              end
            end
          end
        end

        def register_custom_elastic_graph_scalars
          schema_def_api.scalar_type "Cursor" do |t|
            # Technically, we don't use the mapping or json_schema on this type since it's a return-only
            # type and isn't indexed. However, `scalar_type` requires them to be set (since custom scalars
            # defined by users will need those set) so we set them here to what they would be if we actually
            # used them.
            t.mapping type: "keyword"
            t.json_schema type: "string"
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::Cursor",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/cursor"

            t.documentation <<~EOS
              An opaque string value representing a specific location in a paginated connection type.
              Returned cursors can be passed back in the next query via the `before` or `after`
              arguments to continue paginating from that point.
            EOS
          end

          schema_def_api.scalar_type "Date" do |t|
            t.mapping type: "date", format: DATASTORE_DATE_FORMAT
            t.json_schema type: "string", format: "date"
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::Date",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/date"

            t.documentation <<~EOS
              A date, represented as an [ISO 8601 date string](https://en.wikipedia.org/wiki/ISO_8601).
            EOS

            t.customize_aggregated_values_type do |avt|
              define_exact_min_max_and_approx_avg_on_aggregated_values(avt, "Date") do |adjective:, full_name:|
                <<~EOS
                  So long as the grouping contains at least one non-null value for the
                  underlying indexed field, this will return an exact non-null value.
                EOS
              end
            end
          end

          schema_def_api.scalar_type "DateTime" do |t|
            t.mapping type: "date", format: DATASTORE_DATE_TIME_FORMAT
            t.json_schema type: "string", format: "date-time"
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::DateTime",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/date_time"

            t.documentation <<~EOS
              A timestamp, represented as an [ISO 8601 time string](https://en.wikipedia.org/wiki/ISO_8601).
            EOS

            date_time_time_of_day_ref = schema_def_state.type_ref("#{t.type_ref}TimeOfDay")

            t.customize_derived_types(
              t.type_ref.as_filter_input.to_final_form(as_input: true).name,
              t.type_ref.as_list_element_filter_input.to_final_form(as_input: true).name
            ) do |ft|
              ft.field names.time_of_day, date_time_time_of_day_ref.as_filter_input.name do |f|
                f.documentation <<~EOS
                  Matches records based on the time-of-day of the `DateTime` values.

                  When `null` is passed, matches all documents.
                EOS
              end
            end

            t.customize_aggregated_values_type do |avt|
              define_exact_min_max_and_approx_avg_on_aggregated_values(avt, "DateTime") do |adjective:, full_name:|
                <<~EOS
                  So long as the grouping contains at least one non-null value for the
                  underlying indexed field, this will return an exact non-null value.
                EOS
              end
            end

            register_filter date_time_time_of_day_ref.name do |t|
              t.documentation <<~EOS
                Input type used to specify filters on the time-of-day of `DateTime` fields.

                Will match all documents if passed as an empty object (or as `null`).
              EOS

              fixup_doc = ->(doc_string) do
                doc_string.sub("the field value", "the time of day of the `DateTime` field value")
              end

              # Unlike a normal `equal_to_any_of` (which allows nullable elements to allow filtering to null values), we make
              # it non-nullable here because it's nonsensical to filter to where a DateTime's time-of-day is null.
              t.field names.equal_to_any_of, "[LocalTime!]" do |f|
                f.documentation fixup_doc.call(ScalarType::EQUAL_TO_ANY_OF_DOC)
              end

              t.field names.gt, "LocalTime" do |f|
                f.documentation fixup_doc.call(ScalarType::GT_DOC)
              end

              t.field names.gte, "LocalTime" do |f|
                f.documentation fixup_doc.call(ScalarType::GTE_DOC)
              end

              t.field names.lt, "LocalTime" do |f|
                f.documentation fixup_doc.call(ScalarType::LT_DOC)
              end

              t.field names.lte, "LocalTime" do |f|
                f.documentation fixup_doc.call(ScalarType::LTE_DOC)
              end

              t.field names.time_zone, "TimeZone!" do |f|
                f.documentation "TimeZone to use when comparing the `DateTime` values against the provided `LocalTime` values."
                f.default "UTC"
              end

              # With our initial implementation of `time_of_day` filtering, it's tricky to support `any_of`/`all_of`/`not` within
              # the `time_of_day: {...}` input object. They are still supported outside of `time_of_day` (on the parent
              # input object) so no functionality is losts by omitting these. Also, this aligns with our `GeoLocationDistanceFilterInput`
              # which is a similarly complex filter where we didn't include them.
              remove_any_of_and_all_of_and_not_filter_operators_on(t)
            end
          end

          schema_def_api.scalar_type "LocalTime" do |t|
            t.documentation <<~EOS
              A local time such as `"23:59:33"` or `"07:20:47.454"` without a time zone or offset, formatted based on the
              [partial-time portion of RFC3339](https://datatracker.ietf.org/doc/html/rfc3339#section-5.6).
            EOS

            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::LocalTime",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/local_time"

            t.mapping type: "date", format: "HH:mm:ss||HH:mm:ss.S||HH:mm:ss.SS||HH:mm:ss.SSS"

            t.json_schema type: "string", pattern: VALID_LOCAL_TIME_JSON_SCHEMA_PATTERN

            t.customize_aggregated_values_type do |avt|
              define_exact_min_max_and_approx_avg_on_aggregated_values(avt, "LocalTime") do |adjective:, full_name:|
                <<~EOS
                  So long as the grouping contains at least one non-null value for the
                  underlying indexed field, this will return an exact non-null value.
                EOS
              end
            end
          end

          schema_def_api.scalar_type "TimeZone" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string", enum: GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::TimeZone",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/time_zone"

            t.documentation <<~EOS
              An [IANA time zone identifier](https://www.iana.org/time-zones), such as `America/Los_Angeles` or `UTC`.

              For a full list of valid identifiers, see the [wikipedia article](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).
            EOS
          end

          schema_def_api.scalar_type "Untyped" do |t|
            # Allow any JSON for this type. The list of supported types is taken from:
            #
            # https://github.com/json-schema-org/json-schema-spec/blob/draft-07/schema.json#L23-L29
            #
            # ...except we are omitting `null` here; it'll be added by the nullability decorator if the field is defined as nullable.
            t.json_schema type: ["array", "boolean", "integer", "number", "object", "string"]

            # In the index we store this as a JSON string in a `keyword` field.
            t.mapping type: "keyword"

            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::Untyped",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/untyped"

            t.prepare_for_indexing_with "ElasticGraph::Indexer::IndexingPreparers::Untyped",
              defined_at: "elastic_graph/indexer/indexing_preparers/untyped"

            t.documentation <<~EOS
              A custom scalar type that allows any type of data, including:

              - strings
              - numbers
              - objects and arrays (nested as deeply as you like)
              - booleans

              Note: fields of this type are effectively untyped. We recommend it only be used for
              parts of your schema that can't be statically typed.
            EOS
          end

          schema_def_api.scalar_type "JsonSafeLong" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::JsonSafeLong",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/longs"

            t.prepare_for_indexing_with "ElasticGraph::Indexer::IndexingPreparers::Integer",
              defined_at: "elastic_graph/indexer/indexing_preparers/integer"

            t.documentation <<~EOS
              A numeric type for large integer values that can serialize safely as JSON.

              While JSON itself has no hard limit on the size of integers, the RFC-7159 spec
              mentions that values outside of the range #{format_number(JSON_SAFE_LONG_MIN)} (-(2^53) + 1)
              to #{format_number(JSON_SAFE_LONG_MAX)} (2^53 - 1) may not be interopable with all JSON
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
            EOS

            define_integral_aggregated_values_for(t)
          end

          schema_def_api.scalar_type "LongString" do |t|
            # Note: while this type is returned from GraphQL queries as a string, we still
            # require it to be an integer in the JSON documents we index. We want min/max
            # validation on input (to avoid ingesting values that are larger than we can
            # handle). This is easy to do if we ingest these values as numbers, but hard
            # to do if we ingest them as strings. (The `pattern` regex to validate the range
            # would be *extremely* complicated).
            t.mapping type: "long"
            t.json_schema type: "integer", minimum: LONG_STRING_MIN, maximum: LONG_STRING_MAX
            t.coerce_with "ElasticGraph::GraphQL::ScalarCoercionAdapters::LongString",
              defined_at: "elastic_graph/graphql/scalar_coercion_adapters/longs"
            t.prepare_for_indexing_with "ElasticGraph::Indexer::IndexingPreparers::Integer",
              defined_at: "elastic_graph/indexer/indexing_preparers/integer"

            t.documentation <<~EOS
              A numeric type for large integer values in the inclusive range -2^63
              (#{format_number(LONG_STRING_MIN)}) to (2^63 - 1) (#{format_number(LONG_STRING_MAX)}).

              Note that `LongString` values are serialized as strings within JSON, to avoid
              interopability problems with JavaScript. If you want a large integer type that
              serializes within JSON as a number, use `JsonSafeLong`.
            EOS

            t.customize_aggregated_values_type do |avt|
              # not nullable, since sum(empty_set) == 0
              avt.field names.approximate_sum, "Float!", graphql_only: true do |f|
                f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :sum

                f.documentation <<~EOS
                  The (approximate) sum of the field values within this grouping.

                  Sums of large `LongString` values can result in overflow, where the exact sum cannot
                  fit in a `LongString` return value. This field, as a double-precision `Float`, can
                  represent larger sums, but the value may only be approximate.
                EOS
              end

              avt.field names.exact_sum, "JsonSafeLong", graphql_only: true do |f|
                f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :sum

                f.documentation <<~EOS
                  The exact sum of the field values within this grouping, if it fits in a `JsonSafeLong`.

                  Sums of large `LongString` values can result in overflow, where the exact sum cannot
                  fit in a `JsonSafeLong`. In that case, `null` will be returned, and `#{names.approximate_sum}`
                  can be used to get an approximate value.
                EOS
              end

              define_exact_min_and_max_on_aggregated_values(avt, "JsonSafeLong") do |adjective:, full_name:|
                approx_name = (full_name == "minimum") ? names.approximate_min : names.approximate_max

                <<~EOS
                  So long as the grouping contains at least one non-null value, and no values exceed the
                  `JsonSafeLong` range in the underlying indexed field, this will return an exact non-null value.

                  If no non-null values are available, or if the #{full_name} value is outside the `JsonSafeLong`
                  range, `null` will be returned. `#{approx_name}` can be used to differentiate between these
                  cases and to get an approximate value.
                EOS
              end

              {
                names.exact_min => [:min, "minimum", names.approximate_min, "smallest"],
                names.exact_max => [:max, "maximum", names.approximate_max, "largest"]
              }.each do |exact_name, (func, full_name, approx_name, adjective)|
                avt.field approx_name, "LongString", graphql_only: true do |f|
                  f.runtime_metadata_computation_detail empty_bucket_value: nil, function: func

                  f.documentation <<~EOS
                    The #{full_name} of the field values within this grouping.

                    The aggregation computation performed to identify the #{adjective} value is not able
                    to maintain exact precision when dealing with values that are outside the `JsonSafeLong`
                    range (#{format_number(JSON_SAFE_LONG_MIN)} to #{format_number(JSON_SAFE_LONG_MAX)}).
                    In that case, the `#{exact_name}` field will return `null`, but this field will provide
                    a value which may be approximate.
                  EOS
                end
              end

              avt.field names.approximate_avg, "Float", graphql_only: true do |f|
                f.runtime_metadata_computation_detail empty_bucket_value: nil, function: :avg

                f.documentation <<~EOS
                  The average (mean) of the field values within this grouping.

                  Note that the returned value is approximate. Imprecision can be introduced by the computation if
                  any intermediary values fall outside the `JsonSafeLong` range (#{format_number(JSON_SAFE_LONG_MIN)}
                  to #{format_number(JSON_SAFE_LONG_MAX)}).
                EOS
              end
            end
          end
        end

        def register_enum_types
          # Elasticsearch and OpenSearch treat weeks as beginning on Monday for date histogram aggregations.
          # Note that I can't find clear documentation on this.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/search-aggregations-bucket-datehistogram-aggregation.html#calendar_intervals
          #
          # > One week is the interval between the start day_of_week:hour:minute:second and
          # > the same day of the week and time of the following week in the specified time zone.
          #
          # However, we have observed that this is how it behaves. We verify it in this test:
          # elasticgraph-graphql/spec/acceptance/elasticgraph_graphql_spec.rb
          es_first_day_of_week = "Monday"

          schema_def_api.enum_type "DateGroupingTruncationUnit" do |t|
            t.documentation <<~EOS
              Enumerates the supported truncation units of a `Date`.
            EOS

            t.value "YEAR" do |v|
              v.documentation "The year a `Date` falls in."
              v.update_runtime_metadata datastore_value: "year"
            end

            t.value "QUARTER" do |v|
              v.documentation "The quarter a `Date` falls in."
              v.update_runtime_metadata datastore_value: "quarter"
            end

            t.value "MONTH" do |v|
              v.documentation "The month a `Date` falls in."
              v.update_runtime_metadata datastore_value: "month"
            end

            t.value "WEEK" do |v|
              v.documentation "The week, beginning on #{es_first_day_of_week}, a `Date` falls in."
              v.update_runtime_metadata datastore_value: "week"
            end

            t.value "DAY" do |v|
              v.documentation "The exact day of a `Date`."
              v.update_runtime_metadata datastore_value: "day"
            end
          end

          schema_def_api.enum_type "DateTimeGroupingTruncationUnit" do |t|
            t.documentation <<~EOS
              Enumerates the supported truncation units of a `DateTime`.
            EOS

            t.value "YEAR" do |v|
              v.documentation "The year a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "year"
            end

            t.value "QUARTER" do |v|
              v.documentation "The quarter a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "quarter"
            end

            t.value "MONTH" do |v|
              v.documentation "The month a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "month"
            end

            t.value "WEEK" do |v|
              v.documentation "The week, beginning on #{es_first_day_of_week}, a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "week"
            end

            t.value "DAY" do |v|
              v.documentation "The day a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "day"
            end

            t.value "HOUR" do |v|
              v.documentation "The hour a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "hour"
            end

            t.value "MINUTE" do |v|
              v.documentation "The minute a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "minute"
            end

            t.value "SECOND" do |v|
              v.documentation "The second a `DateTime` falls in."
              v.update_runtime_metadata datastore_value: "second"
            end
          end

          schema_def_api.enum_type "LocalTimeGroupingTruncationUnit" do |t|
            t.documentation <<~EOS
              Enumerates the supported truncation units of a `LocalTime`.
            EOS

            t.value "HOUR" do |v|
              v.documentation "The hour a `LocalTime` falls in."
              v.update_runtime_metadata datastore_value: "hour"
            end

            t.value "MINUTE" do |v|
              v.documentation "The minute a `LocalTime` falls in."
              v.update_runtime_metadata datastore_value: "minute"
            end

            t.value "SECOND" do |v|
              v.documentation "The second a `LocalTime` falls in."
              v.update_runtime_metadata datastore_value: "second"
            end
          end

          schema_def_api.enum_type "DistanceUnit" do |t|
            t.documentation "Enumerates the supported distance units."

            # Values here are taken from: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/common-options.html#distance-units
            t.value "MILE" do |v|
              v.documentation "A United States customary unit of 5,280 feet."
              v.update_runtime_metadata datastore_abbreviation: :mi
            end

            t.value "YARD" do |v|
              v.documentation "A United States customary unit of 3 feet."
              v.update_runtime_metadata datastore_abbreviation: :yd
            end

            t.value "FOOT" do |v|
              v.documentation "A United States customary unit of 12 inches."
              v.update_runtime_metadata datastore_abbreviation: :ft
            end

            t.value "INCH" do |v|
              v.documentation "A United States customary unit equal to 1/12th of a foot."
              v.update_runtime_metadata datastore_abbreviation: :in
            end

            t.value "KILOMETER" do |v|
              v.documentation "A metric system unit equal to 1,000 meters."
              v.update_runtime_metadata datastore_abbreviation: :km
            end

            t.value "METER" do |v|
              v.documentation "The base unit of length in the metric system."
              v.update_runtime_metadata datastore_abbreviation: :m
            end

            t.value "CENTIMETER" do |v|
              v.documentation "A metric system unit equal to 1/100th of a meter."
              v.update_runtime_metadata datastore_abbreviation: :cm
            end

            t.value "MILLIMETER" do |v|
              v.documentation "A metric system unit equal to 1/1,000th of a meter."
              v.update_runtime_metadata datastore_abbreviation: :mm
            end

            t.value "NAUTICAL_MILE" do |v|
              v.documentation "An international unit of length used for air, marine, and space navigation. Equivalent to 1,852 meters."
              v.update_runtime_metadata datastore_abbreviation: :nmi
            end
          end

          schema_def_api.enum_type "DateTimeUnit" do |t|
            t.documentation "Enumeration of `DateTime` units."

            # Values here are taken from: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/common-options.html#time-units
            t.value "DAY" do |v|
              v.documentation "The time period of a full rotation of the Earth with respect to the Sun."
              v.update_runtime_metadata datastore_abbreviation: :d, datastore_value: 86_400_000
            end

            t.value "HOUR" do |v|
              v.documentation "1/24th of a day."
              v.update_runtime_metadata datastore_abbreviation: :h, datastore_value: 3_600_000
            end

            t.value "MINUTE" do |v|
              v.documentation "1/60th of an hour."
              v.update_runtime_metadata datastore_abbreviation: :m, datastore_value: 60_000
            end

            t.value "SECOND" do |v|
              v.documentation "1/60th of a minute."
              v.update_runtime_metadata datastore_abbreviation: :s, datastore_value: 1_000
            end

            t.value "MILLISECOND" do |v|
              v.documentation "1/1000th of a second."
              v.update_runtime_metadata datastore_abbreviation: :ms, datastore_value: 1
            end

            # These units, which Elasticsearch and OpenSearch support, only make sense to use when using the
            # Date nanoseconds type:
            #
            # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/date_nanos.html
            #
            # However, we currently only use the standard `Date` type, which has millisecond granularity,
            # For now these sub-millisecond granularities aren't useful to support, so we're not including
            # them at this time.
            #
            # t.value "MICROSECOND" do |v|
            #   v.documentation "1/1000th of a millisecond."
            #   v.update_runtime_metadata datastore_abbreviation: :micros
            # end
            #
            # t.value "NANOSECOND" do |v|
            #   v.documentation "1/1000th of a microsecond."
            #   v.update_runtime_metadata datastore_abbreviation: :nanos
            # end
          end

          schema_def_api.enum_type "DateUnit" do |t|
            t.documentation "Enumeration of `Date` units."

            # Values here are taken from: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/common-options.html#time-units
            t.value "DAY" do |v|
              v.documentation "The time period of a full rotation of the Earth with respect to the Sun."
              v.update_runtime_metadata datastore_abbreviation: :d, datastore_value: 86_400_000
            end
          end

          schema_def_api.enum_type "LocalTimeUnit" do |t|
            t.documentation "Enumeration of `LocalTime` units."

            # Values here are taken from: https://www.elastic.co/guide/en/elasticsearch/reference/7.10/common-options.html#time-units
            t.value "HOUR" do |v|
              v.documentation "1/24th of a day."
              v.update_runtime_metadata datastore_abbreviation: :h, datastore_value: 3_600_000
            end

            t.value "MINUTE" do |v|
              v.documentation "1/60th of an hour."
              v.update_runtime_metadata datastore_abbreviation: :m, datastore_value: 60_000
            end

            t.value "SECOND" do |v|
              v.documentation "1/60th of a minute."
              v.update_runtime_metadata datastore_abbreviation: :s, datastore_value: 1_000
            end

            t.value "MILLISECOND" do |v|
              v.documentation "1/1000th of a second."
              v.update_runtime_metadata datastore_abbreviation: :ms, datastore_value: 1
            end
          end

          schema_def_api.enum_type "MatchesQueryAllowedEditsPerTerm" do |t|
            t.documentation "Enumeration of allowed values for the `#{names.matches_query}: {#{names.allowed_edits_per_term}: ...}` filter option."

            t.value "NONE" do |v|
              v.documentation "No allowed edits per term."
              v.update_runtime_metadata datastore_abbreviation: :"0"
            end

            t.value "ONE" do |v|
              v.documentation "One allowed edit per term."
              v.update_runtime_metadata datastore_abbreviation: :"1"
            end

            t.value "TWO" do |v|
              v.documentation "Two allowed edits per term."
              v.update_runtime_metadata datastore_abbreviation: :"2"
            end

            t.value "DYNAMIC" do |v|
              v.documentation "Allowed edits per term is dynamically chosen based on the length of the term."
              v.update_runtime_metadata datastore_abbreviation: :AUTO
            end
          end
        end

        def register_date_and_time_grouped_by_types
          # DateGroupedBy
          date = schema_def_state.type_ref("Date")
          register_framework_object_type date.as_grouped_by.name do |t|
            t.documentation "Allows for grouping `Date` values based on the desired return type."
            t.resolve_fields_with :object_with_lookahead
            t.override_runtime_metadata(elasticgraph_category: :date_grouped_by_object)

            t.field names.as_date, "Date", graphql_only: true do |f|
              f.documentation "Used when grouping on the full `Date` value."
              define_date_grouping_arguments(f, omit_timezone: true)
            end

            t.field names.as_day_of_week, "DayOfWeek", graphql_only: true do |f|
              f.documentation "An alternative to `#{names.as_date}` for when grouping on the day-of-week is desired."
              define_day_of_week_grouping_arguments(f, omit_timezone: true)
            end
          end

          # DateTimeGroupedBy
          date_time = schema_def_state.type_ref("DateTime")
          register_framework_object_type date_time.as_grouped_by.name do |t|
            t.documentation "Allows for grouping `DateTime` values based on the desired return type."
            t.resolve_fields_with :object_with_lookahead
            t.override_runtime_metadata(elasticgraph_category: :date_grouped_by_object)

            t.field names.as_date_time, "DateTime", graphql_only: true do |f|
              f.documentation "Used when grouping on the full `DateTime` value."
              define_date_time_grouping_arguments(f)
            end

            t.field names.as_date, "Date", graphql_only: true do |f|
              f.documentation "An alternative to `#{names.as_date_time}` for when grouping on just the date is desired."
              define_date_grouping_arguments(f)
            end

            t.field names.as_time_of_day, "LocalTime", graphql_only: true do |f|
              f.documentation "An alternative to `#{names.as_date_time}` for when grouping on just the time-of-day is desired."
              define_local_time_grouping_arguments(f)
            end

            t.field names.as_day_of_week, "DayOfWeek", graphql_only: true do |f|
              f.documentation "An alternative to `#{names.as_date_time}` for when grouping on the day-of-week is desired."
              define_day_of_week_grouping_arguments(f)
            end
          end

          schema_def_api.enum_type "DayOfWeek" do |t|
            t.documentation "Indicates the specific day of the week."

            t.value "MONDAY" do |v|
              v.documentation "Monday."
            end

            t.value "TUESDAY" do |v|
              v.documentation "Tuesday."
            end

            t.value "WEDNESDAY" do |v|
              v.documentation "Wednesday."
            end

            t.value "THURSDAY" do |v|
              v.documentation "Thursday."
            end

            t.value "FRIDAY" do |v|
              v.documentation "Friday."
            end

            t.value "SATURDAY" do |v|
              v.documentation "Saturday."
            end

            t.value "SUNDAY" do |v|
              v.documentation "Sunday."
            end
          end
        end

        def register_standard_graphql_resolvers
          require(require_path = "elastic_graph/graphql/resolvers/get_record_field_value")
          schema_def_api.register_graphql_resolver :get_record_field_value,
            GraphQL::Resolvers::GetRecordFieldValue,
            defined_at: require_path

          require(require_path = "elastic_graph/graphql/resolvers/list_records")
          schema_def_api.register_graphql_resolver :list_records,
            GraphQL::Resolvers::ListRecords,
            defined_at: require_path

          require(require_path = "elastic_graph/graphql/resolvers/nested_relationships")
          schema_def_api.register_graphql_resolver :nested_relationships,
            GraphQL::Resolvers::NestedRelationships,
            defined_at: require_path

          require(require_path = "elastic_graph/graphql/resolvers/object")
          schema_def_api.register_graphql_resolver :object_with_lookahead,
            GraphQL::Resolvers::Object::WithLookahead,
            defined_at: require_path
          schema_def_api.register_graphql_resolver :object_without_lookahead,
            GraphQL::Resolvers::Object::WithoutLookahead,
            defined_at: require_path
        end

        def define_date_grouping_arguments(grouping_field, omit_timezone: false)
          define_calendar_type_grouping_arguments(grouping_field, schema_def_state.type_ref("Date"), <<~EOS, omit_timezone: omit_timezone)
            For example, when grouping by `WEEK`, you can shift by 1 day to change what day-of-week weeks are considered to start on.
          EOS
        end

        def define_date_time_grouping_arguments(grouping_field)
          define_calendar_type_grouping_arguments(grouping_field, schema_def_state.type_ref("DateTime"), <<~EOS)
            For example, when grouping by `WEEK`, you can shift by 1 day to change what day-of-week weeks are considered to start on.
          EOS
        end

        def define_local_time_grouping_arguments(grouping_field)
          define_calendar_type_grouping_arguments(grouping_field, schema_def_state.type_ref("LocalTime"), <<~EOS)
            For example, when grouping by `HOUR`, you can apply an offset of -5 minutes to shift `LocalTime`
            values to the prior hour when they fall between the the top of an hour and 5 after.
          EOS
        end

        def define_day_of_week_grouping_arguments(grouping_field, omit_timezone: false)
          define_calendar_type_grouping_arguments(grouping_field, schema_def_state.type_ref("DayOfWeek"), <<~EOS, omit_timezone: omit_timezone, omit_truncation_unit: true)
            For example, you can apply an offset of -2 hours to shift `DateTime` values to the prior `DayOfWeek`
            when they fall between midnight and 2 AM.
          EOS
        end

        def define_calendar_type_grouping_arguments(grouping_field, calendar_type, offset_example_description, omit_timezone: false, omit_truncation_unit: false)
          define_grouping_argument_offset(grouping_field, calendar_type, offset_example_description)
          define_grouping_argument_time_zone(grouping_field, calendar_type) unless omit_timezone
          define_grouping_argument_truncation_unit(grouping_field, calendar_type) unless omit_truncation_unit
        end

        def define_grouping_argument_offset(grouping_field, calendar_type, example_description)
          grouping_field.argument schema_def_state.schema_elements.offset, "#{calendar_type.name}GroupingOffsetInput" do |a|
            a.documentation <<~EOS
              Amount of offset (positive or negative) to shift the `#{calendar_type.name}` boundaries of each grouping bucket.

              #{example_description.strip}
            EOS
          end
        end

        def define_grouping_argument_time_zone(grouping_field, calendar_type)
          grouping_field.argument schema_def_state.schema_elements.time_zone, "TimeZone!" do |a|
            a.documentation "The time zone to use when determining which grouping a `#{calendar_type.name}` value falls in."
            a.default "UTC"
          end
        end

        def define_grouping_argument_truncation_unit(grouping_field, calendar_type)
          grouping_field.argument schema_def_state.schema_elements.truncation_unit, "#{calendar_type.name}GroupingTruncationUnit!" do |a|
            a.documentation "Determines the grouping truncation unit for this field."
          end
        end

        def define_integral_aggregated_values_for(scalar_type, long_type: "JsonSafeLong")
          scalar_type_name = scalar_type.name
          scalar_type.customize_aggregated_values_type do |t|
            # not nullable, since sum(empty_set) == 0
            t.field names.approximate_sum, "Float!", graphql_only: true do |f|
              f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :sum

              f.documentation <<~EOS
                The (approximate) sum of the field values within this grouping.

                Sums of large `#{scalar_type_name}` values can result in overflow, where the exact sum cannot
                fit in a `#{long_type}` return value. This field, as a double-precision `Float`, can
                represent larger sums, but the value may only be approximate.
              EOS
            end

            t.field names.exact_sum, long_type, graphql_only: true do |f|
              f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :sum

              f.documentation <<~EOS
                The exact sum of the field values within this grouping, if it fits in a `#{long_type}`.

                Sums of large `#{scalar_type_name}` values can result in overflow, where the exact sum cannot
                fit in a `#{long_type}`. In that case, `null` will be returned, and `#{names.approximate_sum}`
                can be used to get an approximate value.
              EOS
            end

            define_exact_min_and_max_on_aggregated_values(t, scalar_type_name) do |adjective:, full_name:|
              <<~EOS
                So long as the grouping contains at least one non-null value for the
                underlying indexed field, this will return an exact non-null value.
              EOS
            end

            t.field names.approximate_avg, "Float", graphql_only: true do |f|
              f.runtime_metadata_computation_detail empty_bucket_value: nil, function: :avg

              f.documentation <<~EOS
                The average (mean) of the field values within this grouping.

                Note that the returned value is approximate. Imprecision can be introduced by the computation if
                any intermediary values fall outside the `JsonSafeLong` range (#{format_number(JSON_SAFE_LONG_MIN)}
                to #{format_number(JSON_SAFE_LONG_MAX)}).
              EOS
            end
          end
        end

        def define_exact_min_max_and_approx_avg_on_aggregated_values(aggregated_values_type, scalar_type, &block)
          define_exact_min_and_max_on_aggregated_values(aggregated_values_type, scalar_type, &block)

          aggregated_values_type.field names.approximate_avg, scalar_type, graphql_only: true do |f|
            f.runtime_metadata_computation_detail empty_bucket_value: nil, function: :avg

            f.documentation <<~EOS
              The average (mean) of the field values within this grouping.
              The returned value will be rounded to the nearest `#{scalar_type}` value.
            EOS
          end
        end

        def define_exact_min_and_max_on_aggregated_values(aggregated_values_type, scalar_type)
          {
            names.exact_min => [:min, "minimum", "smallest"],
            names.exact_max => [:max, "maximum", "largest"]
          }.each do |name, (func, full_name, adjective)|
            discussion = yield(adjective: adjective, full_name: full_name)

            aggregated_values_type.field name, scalar_type, graphql_only: true do |f|
              f.runtime_metadata_computation_detail empty_bucket_value: nil, function: func

              f.documentation ["The #{full_name} of the field values within this grouping.", discussion].compact.join("\n\n")
            end
          end
        end

        def register_framework_object_type(name)
          schema_def_api.object_type(name) do |t|
            t.graphql_only true
            yield t
          end
        end

        def format_number(num)
          abs_value_formatted = num.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
          (num < 0) ? "-#{abs_value_formatted}" : abs_value_formatted
        end

        def register_filter(type, &block)
          register_input_type(schema_def_state.factory.new_filter_input_type(type, &block))
        end

        def register_input_type(input_type)
          schema_def_state.register_input_type(input_type)
        end

        def remove_any_of_and_all_of_and_not_filter_operators_on(type)
          type.graphql_fields_by_name.delete(names.any_of)
          type.graphql_fields_by_name.delete(names.all_of)
          type.graphql_fields_by_name.delete(names.not)
        end
      end
    end
  end
end

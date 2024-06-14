# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_search_router"
require "elastic_graph/schema_definition/schema_elements/type_namer"
require "elastic_graph/spec_support/builds_admin"
require "graphql"
require "support/graphql"

module ElasticGraph
  class << self
    attr_accessor :camel_case_cluster_configured
  end

  self.camel_case_cluster_configured = false

  RSpec.shared_context "ElasticGraph GraphQL acceptance support", :factories, :uses_datastore, :capture_logs, :builds_indexer, :builds_admin do
    include GraphQLSupport
    include PreventSearchesFromUsingWriteRequests

    let(:graphql) { build_graphql }
    let(:indexer) { build_indexer(datastore_core: graphql.datastore_core) }
    let(:admin) { build_admin(datastore_core: graphql.datastore_core) }

    # Need to use a local variable instead of an instance variable for the context state,
    # to avoid issues related to VCR re-recording that is implemented using `rspec-retry`
    # (which clears instance variables between attempts).
    raw_schema_def_string = nil
    define_method(:raw_schema_def_string) { raw_schema_def_string }

    before(:context) do
      raw_schema_def_string = %w[schema/teams.rb schema/widgets.rb].map do |file|
        File.read(File.join(CommonSpecHelpers::REPO_ROOT, "config", file))
      end.join("\n\n")
    end

    before do
      # Perform any cached calls to the datastore to happen before our `perform_datastore_msearch`
      # matcher in some tests which tries to assert which specific requests get made, since index definitions
      # have caching behavior that can make the presence or absence of that request slightly non-deterministic.
      pre_cache_index_state(graphql)
    end

    def expect_indices_not_configured_error
      expect {
        response = yield
        expect(response.dig("errors").first).to include({"message" => GraphQL::DatastoreSearchRouter::INDICES_NOT_CONFIGURED_MESSAGE})
      }.to log_warning(a_string_including(GraphQL::DatastoreSearchRouter::INDICES_NOT_CONFIGURED_MESSAGE))
    end

    def self.with_both_casing_forms(&block)
      context "with a snake_case schema" do
        include SnakeCaseGraphQLAcceptanceAdapter
        module_exec(&block)
      end

      context "with a camelCase schema, alternate derived type naming, and enum value overrides" do
        include CamelCaseGraphQLAcceptanceAdapter

        # Need to use a local variable instead of an instance variable for the context state,
        # to avoid issues related to VCR re-recording that is implemented using `rspec-retry`
        # (which clears instance variables between attempts).
        extra_build_options = nil

        before(:context) do
          enum_types = ::GraphQL::Schema.from_definition(
            stock_schema_artifacts.graphql_schema_string
          ).types.values.select { |t| t.kind.enum? }

          # For each enum type, we want to override the values to be different, as a forcing function to make
          # sure our GraphQL implementation works with any overrides.
          enum_value_overrides_by_type = enum_types.to_h do |enum_type|
            value_overrides = enum_type.values.keys.to_h { |v| [v, "#{v}2"] }
            [enum_type.graphql_name, value_overrides]
          end

          derived_type_name_formats = SchemaDefinition::SchemaElements::TypeNamer::DEFAULT_FORMATS.transform_values do |format|
            apply_derived_type_customizations(format)
          end

          # replace `snake_case` schema field names with `camelCase` names.
          camel_case_schema_def = case_schema_def_correctly(raw_schema_def_string)
          extra_build_options = {
            datastore_backend: datastore_backend,
            schema_element_name_form: :camelCase,
            derived_type_name_formats: derived_type_name_formats,
            enum_value_overrides_by_type: enum_value_overrides_by_type,
            schema_definition: ->(schema) do
              # standard:disable Security/Eval -- it's ok here in a test.
              schema.as_active_instance { eval(camel_case_schema_def) }
              # standard:enable Security/Eval
            end
          }

          # Ensure the cluster isn't configured for a camelCase schema more than once.
          unless ElasticGraph.camel_case_cluster_configured
            ElasticGraph.camel_case_cluster_configured = true

            admin = BuildsAdmin.build_admin(**extra_build_options) do |config|
              configure_for_camel_case(config)
            end

            manage_cluster_for(admin: admin, state_file_name: "camelCase_indices.yaml")
          end
        end

        define_method :build_graphql do |**options, &method_block|
          super(**extra_build_options.merge(options)) do |config|
            config = configure_for_camel_case(config)
            config = method_block.call(config) if method_block
            config
          end
        end

        module_exec(&block)
      end
    end
  end

  # Our IAM policies in AWS grant GET/HEAD permissions but not POST permissions to
  # IAM users/roles that are intended to only read but not write to the datastore.
  # In elasticsearch-ruby 7.9.0, they changed it to use POST instead of GET with
  # msearch due to the request body. This broke our lambdas when we deployed with
  # the gem upgraded. Since our GraphQL lambda lacks POST/PUT/DELETE permissions we
  # want to enforce that those HTTP verbs are not used while handling GraphQL queries,
  # so we enforce that here.
  module PreventSearchesFromUsingWriteRequests
    def call_graphql_query(query, gql: graphql, **options)
      response = nil

      expect {
        response = super(query, gql: gql, **options)
      }.to make_no_datastore_write_calls("main")

      response
    end
  end

  module SnakeCaseGraphQLAcceptanceAdapter
    def enum_value(value)
      value
    end

    def case_correctly(word)
      ::ElasticGraph::SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition::SnakeCaseConverter.normalize_case(word)
    end

    def index_definition_name_for(snake_case_name)
      snake_case_name
    end

    def case_schema_def_correctly(snake_case_schema_def)
      snake_case_schema_def
    end

    def apply_derived_type_customizations(type_name)
      # In the snake_case context we don't want to customize derived types, so return `type_name` as-is.
      type_name
    end

    # For parity with our `camelCase` context, also roundtrip factory-built records through JSON.
    # Otherwise we can have subtle, surprising differences between the two casing contexts. For
    # example, if the factory puts a `Date` object in a record, the JSON roundtripping will convert
    # it to an ISO8601 date string, but it would be left as a `Date` object if we did not roundtrip
    # it here.
    def build(*args, **opts)
      JSON.parse(JSON.generate(super), symbolize_names: true)
    end
  end

  module CamelCaseGraphQLAcceptanceAdapter
    def enum_value(value)
      case value
      when ::Symbol
        :"#{value}2"
      else
        "#{value}2"
      end
    end

    def configure_for_camel_case(config)
      # Provide the same index definition settings, but for the `_camel` indices.
      original_index_defs = config.index_definitions
      config.with(index_definitions: Hash.new do |hash, index_def_name|
        hash[index_def_name] = original_index_defs[index_def_name.delete_suffix("_camel")]
      end)
    end

    def case_schema_def_correctly(snake_case_schema_def)
      # replace `snake_case` schema field names with `camelCase` names.
      camel_case_schema_def = to_camel_case(snake_case_schema_def, only_quoted_strings: true)
      # However, the datastore does not support `camelCase` index names (using one
      # yields an "Invalid index name, must be lowercased" error). In addition, we
      # want to use a different index for this context than for the `snake_case`
      # context, so that the datastore does not use the same mapping for both. So,
      # here we replace a string like `index: "mechanicalParts"` with `index: "mechanical_parts_camel"`.
      camel_case_schema_def.gsub(/(\.index\s+")(\w+)(")/) do
        "#{$1}#{index_definition_name_for(word_to_snake_case($2))}#{$3}"
      end
        # `geo_shape` needs to stay in snake_case because it's a datastore mapping type, and cannot be in camelCase
        .gsub("geoShape", "geo_shape")
    end

    DERIVED_NAME_PARTS = [
      "Connection",
      "Edge",
      "Filter",
      "Sort", # for SortOrder
      "Aggregated", # for AggregatedValues
      "Grouped", # for GroupedBy
      "Aggregation", # for Aggregation and SubAggregation
      "Aggregations" # for SubAggregations
    ].to_set

    def apply_derived_type_customizations(type_name)
      # `AggregationCountDetail` has "Aggregation" in it, but is _not_ a derived type,
      # so we need to return it as-is.
      return type_name if type_name == "AggregationCountDetail"

      # These have the `Input` suffix, but not due to a naming format (they're not derived types), so we leave them alone.
      return type_name if type_name == "DateTimeGroupingOffsetInput"
      return type_name if type_name == "DateGroupingOffsetInput"
      return type_name if type_name == "DayOfWeekGroupingOffsetInput"
      return type_name if type_name == "LocalTimeGroupingOffsetInput"

      # We want to test _not_ using separate input and output enum types, so we remove the `Input` suffix used for input enums by default.
      type_name = type_name.delete_suffix("Input")

      # Here we split on capital letters (without "consuming" them in the regex) to convert
      # a type like `WidgetSubAggregations` to ["Widget", "Sub", "Aggregations"]
      name_parts = type_name.split(/(?=[A-Z])/).to_set

      # Some derived types are "compound" types. For example, type like `Widget` gets
      # a derived type like `WidgetAggregation`, and that then gets a derived type like
      # `WidgetAggregationConnection`.
      #
      # For each derived name part, we want to apply our customizations:
      # - Prefix it with `Pre`
      # - Suffix it with `Post`
      # - Reverse it (e.g. `Filter` -> `Retlif`)
      #
      # We want all 3 of these customizations as a forcing function to make sure that we don't take any incorrect
      # short cuts when working with derived types:
      #
      # - The prefix ensures that `start_with?` can't be used to detect a derived type
      # - The suffix ensures that `ends_with?` can't be used to detect a derived type
      # - The reversing ensures that `include?` can't be used to detect a derived type
      parts_needing_adjustment = name_parts.intersection(DERIVED_NAME_PARTS)
      parts_needing_adjustment.reduce(type_name) do |adjusted_type_name, part|
        "Pre#{adjusted_type_name.sub(/#{part}(?=\z|[A-Z])/) { |p| "#{p.reverse.downcase.capitalize}Post" }}"
      end
    end

    def index_definition_name_for(snake_case_name)
      if snake_case_name.include?("_rollover__")
        template_name, suffix = snake_case_name.split("_rollover__")
        "#{template_name}_camel_rollover__#{suffix}"
      else
        "#{snake_case_name}_camel"
      end
    end

    # Override `build` to have it build hashes with camelCase key names, and to update enum values
    # according to our overrides.
    def build(*args, **opts)
      raw_data = super

      schema_artifacts = stock_schema_artifacts
      json_schema_defs = schema_artifacts.json_schemas_for(schema_artifacts.latest_json_schema_version).fetch("$defs")

      if (typename = raw_data[:__typename])
        raw_data = update_enum_values_in(raw_data, json_schema_defs, typename)
      end

      JSON.parse(to_camel_case(JSON.generate(raw_data)), symbolize_names: true)
    end

    def update_enum_values_in(data, json_schema_defs, type_name)
      # There's nothing to do with the `Untyped` type, but it's non-standard and leads to errors if we try to
      # handle it with the standard logic below.
      return data if type_name == "Untyped"

      case data
      when Hash
        json_schema_def = json_schema_defs.fetch(type_name)
        if json_schema_def["required"] == ["__typename"] && (data_type_name = data[:__typename])
          # `type_name` contains an abstract type. Lookup the concrete type and use that instead.
          update_enum_values_in(data, json_schema_defs, data_type_name)
        else
          props = json_schema_def.fetch("properties")
          data.to_h do |field_name, field_value|
            unless [:__version, :__typename, :__json_schema_version].include?(field_name)
              field_type = props.fetch(word_to_snake_case(field_name.to_s)).fetch("ElasticGraph").fetch("type")[/\w+/]
              field_value = update_enum_values_in(field_value, json_schema_defs, field_type)
            end

            [field_name, field_value]
          end
        end
      when Array
        data.map { |v| update_enum_values_in(v, json_schema_defs, type_name) }
      else
        if (enum = json_schema_defs.fetch(type_name)["enum"])
          # We append a `2` conditionally because it's possible it's already been appended. In particular,
          # in a case like `build(:widget, options: build(:widget_options, ...))`, the update will have already
          # been applied to the `widget_options` hash, and we don't want to apply it a second time when processing
          # the `widget` hash here.
          data = "#{data}2" if enum.include?(data)
        end

        data
      end
    end

    # Override `string_hash_of` to have it convert key names to camelCase as
    # it plucks values out of the source hash.
    def string_hash_of(source_hash, *direct_fields, **fields_with_values)
      direct_fields = direct_fields.map { |f| word_to_camel_case(f.to_s).to_sym }
      fields_with_values = fields_with_values.map { |k, v| [word_to_camel_case(k.to_s).to_sym, v] }.to_h
      super(source_hash, *direct_fields, **fields_with_values)
    end

    # Override `call_graphql_query` so that the query is converted to camelCase
    # before we send it to ElasticGraph.
    def call_graphql_query(query, gql: graphql, allow_errors: false, **options)
      # Here we convert the query to its camelCase form before executing it.
      # However, orderBy options require special handling:
      #
      # - orderBy enum values have an `_ASC` or `_DESC` suffix which prevents the `to_camel_case`
      #   translation from working automatically for it.
      # - Both orderBy and groupBy enum values use `_` as a separator between parent and child
      #   field names when referencing a nested field--e.g. `cost.amountCents` has an enum
      #   option of `cost_amountCents` for a camelCase schema and `cost_amount_cents` in a snake_case
      #   schema. There are no uniform translation rules that would allow us to translate from
      #   `cost_amount_cents` to `cost_amountCents` here, so we just special case it with the below
      #   hash.
      special_cases_source = "#{__FILE__}:#{__LINE__ + 1}"
      special_cases = {
        # orderBy enum values
        "amount_cents" => "amountCents",
        "amount_cents2" => "amountCents2",
        "cost_amount_cents" => "cost_amountCents",
        "created_at_time_of_day" => "createdAtTimeOfDay",
        "created_at" => "createdAt",
        "created_on" => "createdOn",
        "full_address" => "fullAddress",
        "weight_in_ng_str" => "weightInNgStr",
        "weight_in_ng" => "weightInNg"
      }

      query = to_camel_case(query).gsub(/#{Regexp.union(special_cases.keys)}/, special_cases)

      super(query, gql: gql, allow_errors: allow_errors, **options).tap do |response|
        unless allow_errors
          expect(response["errors"]).to eq([]).or(eq(nil)), <<~EOS
            #{"=" * 80}
            camelCase query[1] failed with errors[2]:

            [1]
            #{query}"

            [2]
            #{::JSON.pretty_generate(response["errors"])}

            Note that camelCase queries need some special case translation to deal with orderBy
            enum options (since they use `_` to denote parent-child field nesting). If you've uncovered
            the need for an additional special case, register in the `special_cases` hash at
            #{special_cases_source}.
            #{"=" * 80}
          EOS
        end
      end
    end

    # Helper method to convert `snake_case` identifiers in a string
    # to `camelCase` identifiers.
    def to_camel_case(string, only_quoted_strings: false)
      # https://rubular.com/r/9R8CG8wHD08mM8
      inner_regex = "[a-z][a-z.]*+_[a-z_0-9.]+"
      regex = only_quoted_strings ? /"#{inner_regex}"/ : /\b#{inner_regex}\b/

      string.gsub(regex) do |snake_case_word|
        word_to_camel_case(snake_case_word)
      end
    end

    def word_to_camel_case(word)
      ::ElasticGraph::SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition::CamelCaseConverter.normalize_case(word)
    end
    alias_method :case_correctly, :word_to_camel_case

    def word_to_snake_case(word)
      ::ElasticGraph::SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition::SnakeCaseConverter.normalize_case(word)
    end
  end

  RSpec.shared_context "ElasticGraph GraphQL acceptance aggregation support" do
    include_context "ElasticGraph GraphQL acceptance support"

    # To ensure that aggregation queries are as efficient as possible, we want these hold true for all aggregation queries:
    #
    # - `size: 0` should be passed to avoid requesting individual documents.
    # - No `sort` option should be passed since we're not requesting individual documents.
    # - `_source: false` should be passed to disable the fetching of any `_source` fields.
    #
    # Here we check all `_msearch` requests executed as part of the example to verify that these things held true.
    after(:example) do
      datastore_msearch_requests("main").each do |req|
        req.body.split("\n").each_slice(2) do |(_header_line, body_line)|
          search_body = ::JSON.parse(body_line)
          if search_body.key?("aggs")
            problems = []
            # :nocov: -- the branches below are only fully covered when we have a regression.
            problems << "Search body has `size: #{search_body["size"]}` but it should be `size: 0`." unless search_body["size"] == 0
            problems << "Search body has `sort` but it is not needed." if search_body.key?("sort")
            problems << "Search body has `_source:  #{search_body["_source"]}` but it should be `_source: false`." unless search_body["_source"] == false

            unless problems.empty?
              fail "Aggregation query[1] included some inefficiencies in its search body parameters: \n\n" \
                "#{problems.map { |prob| " - #{prob} " }.join("\n")}\n\n" \
                "[1] #{::JSON.pretty_generate(search_body)}"
            end
            # :nocov:
          end
        end
      end
    end
  end
end

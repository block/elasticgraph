# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "did_you_mean"
require "elastic_graph/constants"
require "elastic_graph/errors"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Abstraction for generating derived GraphQL type names based on a collection of formats. A default set of formats is included, and
      # overrides can be provided to customize the format we use for naming derived types.
      class TypeNamer < ::Struct.new(:formats, :regexes, :name_overrides, :reverse_overrides)
        # Initializes a new `TypeNamer` with the provided format overrides.
        # The keys in `overrides` must match the keys in `DEFAULT_FORMATS` and the values must have
        # the same placeholders as are present in the default formats.
        #
        # @private
        def initialize(format_overrides: {}, name_overrides: {})
          @used_names = []
          name_overrides = name_overrides.transform_keys(&:to_s)

          validate_format_overrides(format_overrides)
          validate_name_overrides(name_overrides)

          formats = DEFAULT_FORMATS.merge(format_overrides)
          regexes = formats.transform_values { |format| /\A#{format.gsub(PLACEHOLDER_REGEX, "(\\w+)")}\z/ }
          reverse_overrides = name_overrides.to_h { |k, v| [v, k] }

          super(formats: formats, regexes: regexes, name_overrides: name_overrides, reverse_overrides: reverse_overrides)
        end

        # Returns the configured name for the given `standard_name`.
        #
        # By default, the returned name will just be the string form of the given `standard_name`, but if
        # the `TypeNamer` was instantiated with an override for the given `standard_name`, that will be
        # returned instead.
        #
        # @private
        def name_for(standard_name)
          string_name = standard_name.to_s
          @used_names << string_name
          name_overrides.fetch(string_name, string_name)
        end

        # If the given `potentially_overriden_name` is an overridden name, returns the name from before the
        # override was applied. Note: this may not be the true "original" name that ElasticGraph would have
        # have used (e.g. it could still be customized by `formats`) but it will be the name that would
        # be used without any `name_overrides`.
        #
        # @private
        def revert_override_for(potentially_overriden_name)
          reverse_overrides.fetch(potentially_overriden_name, potentially_overriden_name)
        end

        # Generates a derived type name based on the provided format name and arguments. The given arguments must match
        # the placeholders in the format. If the format name is unknown or the arguments are invalid, a `Errors::ConfigError` is raised.
        #
        # Note: this does not apply any configured `name_overrides`. It's up to the caller to apply that when desired.
        #
        # @private
        def generate_name_for(format_name, **args)
          format = formats.fetch(format_name) do
            suggestions = FORMAT_SUGGESTER.correct(format_name).map(&:inspect)
            raise Errors::ConfigError, "Unknown format name: #{format_name.inspect}. Possible alternatives: #{suggestions.join(", ")}."
          end

          expected_placeholders = REQUIRED_PLACEHOLDERS.fetch(format_name)
          if (missing_placeholders = expected_placeholders - args.keys).any?
            raise Errors::ConfigError, "The arguments (#{args.inspect}) provided for `#{format_name}` format (#{format.inspect}) omits required key(s): #{missing_placeholders.join(", ")}."
          end

          if (extra_placeholders = args.keys - expected_placeholders).any?
            raise Errors::ConfigError, "The arguments (#{args.inspect}) provided for `#{format_name}` format (#{format.inspect}) contains extra key(s): #{extra_placeholders.join(", ")}."
          end

          format % args
        end

        # Given a `name` that has been generated for the given `format`, extracts the `base` parameter value that was used
        # to generate `name`.
        #
        # Raises an error if the given `format` does not support `base` extraction. (To extract `base`, it's required that
        # `base` is the only placeholder in the format.)
        #
        # Returns `nil` if the given `format` does support `base` extraction but `name` does not match the `format`.
        #
        # @private
        def extract_base_from(name, format:)
          unless REQUIRED_PLACEHOLDERS.fetch(format) == [:base]
            raise Errors::InvalidArgumentValueError, "The `#{format}` format does not support base extraction."
          end

          regexes.fetch(format).match(name)&.captures&.first
        end

        # Indicates if the given `name` matches the format for the provided `format_name`.
        #
        # Note: our formats are not "mutually exclusive"--some names can match more than one format, so the
        # fact that a name matches a format does not guarantee it was generated by that format.
        #
        # @private
        def matches_format?(name, format_name)
          regexes.fetch(format_name).match?(name)
        end

        # Returns a hash containing the entries of `name_overrides` which have not been used.
        # These are likely to be typos, and they can be used to warn the user.
        #
        # @private
        def unused_name_overrides
          name_overrides.except(*@used_names.uniq)
        end

        # Returns a set containing all names that got passed to `name_for`: essentially, these are the
        # candidates for valid name overrides.
        #
        # Can be used (in conjunction with `unused_name_overrides`) to provide suggested
        # alternatives to the user.
        #
        # @private
        def used_names
          @used_names.to_set
        end

        # Extracts the names of the placeholders from the provided format.
        #
        # @private
        def self.placeholders_in(format)
          format.scan(PLACEHOLDER_REGEX).flatten.map(&:to_sym)
        end

        # The default formats used for derived GraphQL type names. These formats can be customized by providing `derived_type_name_formats`
        # to {RakeTasks} or {Local::RakeTasks}.
        #
        # @return [Hash<Symbol, String>]
        DEFAULT_FORMATS = {
          AggregatedValues: "%{base}AggregatedValues",
          Aggregation: "%{base}Aggregation",
          Connection: "%{base}Connection",
          Edge: "%{base}Edge",
          FieldsListFilterInput: "%{base}FieldsListFilterInput",
          FilterInput: "%{base}FilterInput",
          GroupedBy: "%{base}GroupedBy",
          Highlights: "%{base}Highlights",
          InputEnum: "%{base}Input",
          ListElementFilterInput: "%{base}ListElementFilterInput",
          ListFilterInput: "%{base}ListFilterInput",
          SortOrder: "%{base}SortOrder",
          SubAggregation: "%{parent_types}%{base}SubAggregation",
          SubAggregations: "%{parent_agg_type}%{field_path}SubAggregations"
        }.freeze

        private

        # https://rubular.com/r/EJMY0zHZiC5HQm
        PLACEHOLDER_REGEX = /%\{(\w+)\}/

        REQUIRED_PLACEHOLDERS = DEFAULT_FORMATS.transform_values { |format| placeholders_in(format) }
        FORMAT_SUGGESTER = ::DidYouMean::SpellChecker.new(dictionary: DEFAULT_FORMATS.keys)
        DEFINITE_ENUM_FORMATS = [:SortOrder].to_set
        DEFINITE_OBJECT_FORMATS = DEFAULT_FORMATS.keys.to_set - DEFINITE_ENUM_FORMATS - [:InputEnum].to_set
        TYPES_THAT_CANNOT_BE_OVERRIDDEN = STOCK_GRAPHQL_SCALARS.union(["Query"]).freeze

        def validate_format_overrides(format_overrides)
          format_problems = format_overrides.flat_map do |format_name, format|
            validate_format(format_name, format)
          end

          notify_problems(format_problems, "Provided derived type name formats")
        end

        def validate_format(format_name, format)
          if (required_placeholders = REQUIRED_PLACEHOLDERS[format_name])
            placeholders = self.class.placeholders_in(format)
            placeholder_problems = [] # : ::Array[String]

            if (missing_placeholders = required_placeholders - placeholders).any?
              placeholder_problems << "The #{format_name} format #{format.inspect} is missing required placeholders: #{missing_placeholders.join(", ")}. " \
                "Example valid format: #{DEFAULT_FORMATS.fetch(format_name).inspect}."
            end

            if (extra_placeholders = placeholders - required_placeholders).any?
              placeholder_problems << "The #{format_name} format #{format.inspect} has excess placeholders: #{extra_placeholders.join(", ")}. " \
                "Example valid format: #{DEFAULT_FORMATS.fetch(format_name).inspect}."
            end

            example_name = format % placeholders.to_h { |placeholder| [placeholder.to_sym, placeholder.capitalize] }
            unless GRAPHQL_NAME_PATTERN.match(example_name)
              placeholder_problems << "The #{format_name} format #{format.inspect} does not produce a valid GraphQL type name. " +
                GRAPHQL_NAME_VALIDITY_DESCRIPTION
            end

            placeholder_problems
          else
            suggestions = FORMAT_SUGGESTER.correct(format_name).map(&:inspect)
            ["Unknown format name: #{format_name.inspect}. Possible alternatives: #{suggestions.join(", ")}."]
          end
        end

        def validate_name_overrides(name_overrides)
          duplicate_problems = name_overrides
            .group_by { |k, v| v }
            .transform_values { |kv_pairs| kv_pairs.map(&:first) }
            .select { |_, v| v.size > 1 }
            .map do |override, source_names|
              "Multiple names (#{source_names.sort.join(", ")}) map to the same override: #{override}, which is not supported."
            end

          invalid_name_problems = name_overrides.filter_map do |source_name, override|
            unless GRAPHQL_NAME_PATTERN.match(override)
              "`#{override}` (the override for `#{source_name}`) is not a valid GraphQL type name. " +
                GRAPHQL_NAME_VALIDITY_DESCRIPTION
            end
          end

          cant_override_problems = TYPES_THAT_CANNOT_BE_OVERRIDDEN.intersection(name_overrides.keys).map do |type_name|
            "`#{type_name}` cannot be overridden because it is part of the GraphQL spec."
          end

          notify_problems(duplicate_problems + invalid_name_problems + cant_override_problems, "Provided type name overrides")
        end

        def notify_problems(problems, source_description)
          return if problems.empty?

          raise Errors::ConfigError, "#{source_description} have #{problems.size} problem(s):\n\n" \
            "#{problems.map.with_index(1) { |problem, i| "#{i}. #{problem}" }.join("\n\n")}"
        end
      end
    end
  end
end

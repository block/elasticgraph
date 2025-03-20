# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_schema/meta_schema_validator"
require "elastic_graph/json_schema/validator_factory"
require "json"

RSpec::Matchers.define :have_json_schema_like do |type, expected_schema, options = {}|
  # RSpec 3.13 has a regression related to keyword args that we work around here with an `options` hash.
  # TODO: Switch back to an `include_typename` keyword arg once we upgrade to a version that fixes the regression.
  # https://github.com/rspec/rspec-expectations/issues/1451
  include_typename = options.fetch(:include_typename, true)

  diffable

  attr_reader :actual, :expected

  chain :which_matches do |*expected_matches|
    @expected_matches = expected_matches
  end

  chain :and_fails_to_match do |*expected_non_matches|
    @expected_non_matches = expected_non_matches
  end

  match do |full_schema|
    modified_expected_schema = if include_typename && expected_schema.key?("properties")
      with_typename(type, expected_schema)
    else
      expected_schema
    end
      .then { |schema| normalize(schema) }

    @expected = JSON.pretty_generate(modified_expected_schema)

    actual_schema = normalize(full_schema.fetch("$defs").fetch(type))
    @actual = JSON.pretty_generate(actual_schema)

    @validator_factory = ElasticGraph::JSONSchema::ValidatorFactory.new(schema: full_schema, sanitize_pii: false)

    @meta_schema_validation_errors = ElasticGraph::JSONSchema.elastic_graph_internal_meta_schema_validator.validate(modified_expected_schema)

    if @meta_schema_validation_errors.empty? && actual_schema == modified_expected_schema
      validator = @validator_factory.validator_for(type)

      @match_failures = (@expected_matches || []).filter_map.with_index do |payload, index|
        if (failure = validator.validate_with_error_message(payload))
          match_failure_description(payload, index, failure)
        end
      end

      @non_match_failures = (@expected_non_matches || []).filter_map.with_index do |payload, index|
        if validator.valid?(payload)
          non_match_failure_description(payload, index)
        end
      end

      @match_failures.empty? && @non_match_failures.empty?
    else
      @match_failures = @non_match_failures = []
      false
    end
  end

  failure_message do |_actual_schema|
    if @meta_schema_validation_errors.any?
      <<~EOS
        expected valid JSON schema[1] but got validation errors on the expected schema and got JSON schema[2]:

        #{@meta_schema_validation_errors.map { |e| JSON.pretty_generate(e) }.join("\n\n")}


        [1] The expected schema:
        #{expected}

        [2] Actual schema:
        #{actual}
      EOS
    elsif @match_failures.any?
      <<~EOS
        expected given JSON payloads matched the JSON schema, but one or more did not.

        #{@match_failures.join("\n\n")}
      EOS
    elsif @non_match_failures.any?
      <<~EOS
        expected given JSON payloads to not match the JSON schema, but one or more did.

        #{@non_match_failures.join("\n\n")}
      EOS
    else
      <<~EOS
        expected valid JSON schema[1] but got JSON schema[2].

        [1] Expected schema:
        #{expected}

        [2] Actual schema:
        #{actual}
      EOS
    end
  end

  def match_failure_description(payload, index, failure)
    <<~EOS
      Failure at index #{index} from payload:

      #{JSON.pretty_generate(payload)}

      #{failure}
    EOS
  end

  def non_match_failure_description(payload, index)
    <<~EOS
      Failure at index #{index} from payload:

      #{JSON.pretty_generate(payload)}
    EOS
  end

  def normalize(schema)
    ::JSON.parse(::JSON.generate(schema.sort.to_h))
  end

  def with_typename(type, schema)
    new_schema = schema.dup
    new_schema["properties"] = schema["properties"].merge({
      "__typename" => {
        "type" => "string",
        "const" => type,
        "default" => type
      }
    })
    new_schema
  end
end

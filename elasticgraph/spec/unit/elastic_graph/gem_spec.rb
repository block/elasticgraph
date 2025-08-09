# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../../../../script/list_eg_gems"
require "elastic_graph/support/json_schema/meta_schema_validator"
require "elastic_graph/support/json_schema/validator"

module ElasticGraph
  RSpec.describe "ElasticGraph gems" do
    gemspecs_by_gem_name = ::Hash.new do |hash, gem_name|
      hash[gem_name] = begin
        gemspec_file = ::File.join(CommonSpecHelpers::REPO_ROOT, gem_name, "#{gem_name}.gemspec")
        eval(::File.read(gemspec_file), ::TOPLEVEL_BINDING.dup, gemspec_file) # standard:disable Security/Eval
      end
    end

    config_paths = []
    meta_schema_validator = Support::JSONSchema.strict_meta_schema_validator

    after :context do
      duplicate_config_paths = config_paths.tally.select { |k, v| v > 1 }.keys
      expect(duplicate_config_paths).to be_empty
    end

    shared_examples_for "an ElasticGraph gem" do |gem_name, config_pending: false|
      around do |ex|
        ::Dir.chdir(::File.join(CommonSpecHelpers::REPO_ROOT, gem_name), &ex)
      end

      let(:gemspec) { gemspecs_by_gem_name[gem_name] }
      let(:config_definition_lines) do
        `git grep "Config =" -- lib`.strip.lines + `git grep "class Config\\b" -- lib`.strip.lines
      end

      it "has the correct name" do
        expect(gemspec.name).to eq gem_name
      end

      it "has no symlinked files included in the gem since they do not work correctly when the gem is packaged" do
        symlink_files = gemspec.files.select { |f| ::File.exist?(f) && ::File.ftype(f) == "link" }
        expect(symlink_files).to be_empty
      end

      %w[.yardopts Gemfile .rspec].each do |file|
        it "has a symlinked `#{file}` file" do
          expect(::File.exist?(file)).to be true
          expect(::File.ftype(file)).to eq "link"
        end
      end

      it "has a non-symlinked `LICENSE.txt` file" do
        expect(::File.exist?("LICENSE.txt")).to be true
        expect(::File.ftype("LICENSE.txt")).to eq "file"
        expect(::File.read("LICENSE.txt")).to include("MIT License", /Copyright .* Block, Inc/)
      end

      it "uses `ElasticGraph::Config` for its configuration, if it has it" do
        pending "Not yet implemented" if config_pending

        expect(config_definition_lines).to all include("ElasticGraph::Config.define")

        files = config_definition_lines.map { |line| line.split(":").first }
        expect(files).to all satisfy { |f| ::File.read(f).include?('require "elastic_graph/config"') }
      end

      it "has a valid, complete JSON schema for all `ElasticGraph::Config` classes" do
        pending "Not yet implemented" if config_pending

        config_definition_lines.each do |config_def_line|
          config_class = load_config_class_for(config_def_line)
          config_paths << config_class.path
          json_schema = config_class.validator.schema.value

          expect(meta_schema_validator.validate_with_error_message(json_schema)).to eq nil

          # Recursively validate all properties have required attributes
          validate_schema_properties_recursively(json_schema, config_class.name)
        end
      end

      def load_config_class_for(config_def_line)
        file_name = config_def_line.split(":").first
        file_contents = ::File.read(file_name)

        enclosing_module_name = file_contents
          .scan(/module ElasticGraph.*(?:(?:class Config\b)|(?:Config =))/m)
          .first
          .scan(/(?:module|class) (\w+)/)
          .flatten
          .join("::")
          .delete_suffix("::Config")

        require "./#{file_name}"
        ::Object.const_get("#{enclosing_module_name}::Config")
      end

      def validate_schema_properties_recursively(schema, config_class_name, path = "")
        properties = schema["properties"] || {}
        required_properties = schema["required"] || []

        properties.each do |property_name, property_schema|
          # :nocov: -- we don't yet have a nested config schema
          current_path = path.empty? ? property_name : "#{path}.#{property_name}"
          # :nocov:

          # Check if property is required or has a default
          expect(required_properties.include?(property_name) || property_schema.key?("default")).to be(true),
            "Property '#{current_path}' in #{config_class_name} schema must be required or have a default value"

          # Check if property has examples
          expect(property_schema.key?("examples")).to be(true),
            "Property '#{current_path}' in #{config_class_name} schema must have examples"

          # Check if property has a description
          expect(property_schema.key?("description")).to be(true),
            "Property '#{current_path}' in #{config_class_name} schema must have a description"

          # Validate examples against the property schema
          property_schema.fetch("examples", []).each_with_index do |example, index|
            validation_error = validate_value_against_schema(example, property_schema)
            expect(validation_error).to be_nil,
              "Example #{index} for property '#{current_path}' in #{config_class_name} schema is invalid: #{validation_error}"
          end

          # Validate default value against the property schema
          # :nocov: -- all properties have defaults so far
          if (default = property_schema["default"])
            validation_errors = validate_value_against_schema(default, property_schema)
            expect(validation_errors).to be_nil,
              "Default value for property '#{current_path}' in #{config_class_name} schema is invalid. #{validation_errors}"
          end
          # :nocov:

          # Recursively validate nested object properties
          if property_schema["type"] == "object"
            # :nocov: -- we don't yet have a nested config schema
            validate_schema_properties_recursively(property_schema, config_class_name, current_path)
            # :nocov:
          elsif property_schema["type"] == "array" && property_schema["items"].is_a?(::Hash)
            # :nocov: -- we don't yet have a config schema with an array property
            # Validate array item schemas if they are objects
            validate_schema_properties_recursively(property_schema["items"], config_class_name, "#{current_path}[]")
            # :nocov:
          end
        end
      end

      def validate_value_against_schema(value, schema)
        temp_schema = {"type" => "object", "properties" => {"temp_property" => schema}}
        validator = Support::JSONSchema::Validator.new(schema: ::JSONSchemer.schema(temp_schema), sanitize_pii: false)
        validator.validate_with_error_message({"temp_property" => value})
      end
    end

    ::ElasticGraphGems.list.each do |gem_name|
      describe gem_name do
        include_examples "an ElasticGraph gem", gem_name, config_pending: %w[
          elasticgraph-datastore_core
          elasticgraph-graphql
          elasticgraph-health_check
          elasticgraph-indexer
          elasticgraph-query_interceptor
          elasticgraph-query_registry
        ].include?(gem_name)
      end
    end

    # We don't expect any variation in these gemspec attributes.
    %i[authors email homepage license required_ruby_version version].each do |gemspec_attribute|
      it "has the same value for `#{gemspec_attribute}` in all ElasticGraph gemspecs" do
        all_gemspec_values = ::ElasticGraphGems.list.to_h do |gem_name|
          [gem_name, gemspecs_by_gem_name[gem_name].public_send(gemspec_attribute)]
        end

        most_common_value = all_gemspec_values.values.tally.max_by { |_, count| count }.first
        nonstandard_gemspec_values = all_gemspec_values.select { |_, value| value != most_common_value }

        expect(nonstandard_gemspec_values).to be_empty
      end
    end
  end
end

# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/json_schema/validator_factory"
require "json"
require "pathname"
require "time"
require "yaml"

module ElasticGraph
  # Generates markdown documentation for ElasticGraph configuration based on the JSON schema
  class ConfigDocGenerator
    def initialize(schema_path, markdown_output_dir, raw_output_dir)
      @schema_path = Pathname.new(schema_path)
      @markdown_output_dir = Pathname.new(markdown_output_dir)
      @raw_output_dir = Pathname.new(raw_output_dir)
      @schema = YAML.load_file(@schema_path)
    end

    def generate!
      generate_schema_files!
      generate_example_config!
      generate_main_documentation!
    end

    private

    def generate_schema_files!
      # Place schema file in a subdirectory that won't be processed by YARD
      FileUtils.mkdir_p(@raw_output_dir)

      # Generate YAML version
      yaml_output_path = @raw_output_dir / "elasticgraph-config-schema.yaml"
      yaml_content = File.read(@schema_path)
      File.write(yaml_output_path, yaml_content)
      puts "Generated configuration schema YAML file at #{yaml_output_path}"

      # Generate JSON version
      json_output_path = @raw_output_dir / "elasticgraph-config-schema.json"
      json_content = JSON.pretty_generate(@schema)
      File.write(json_output_path, json_content)
      puts "Generated configuration schema JSON file at #{json_output_path}"
    end

    def generate_example_config!
      FileUtils.mkdir_p(@raw_output_dir)

      example_config = build_example_config_from_schema(@schema)
      content = "---\n" + build_commented_yaml(example_config, @schema)

      # Validate the generated example config against the schema
      validate_example_config!(::YAML.load(content))

      # Write only to raw_output_dir for download - no YARD-rendered version needed
      raw_example_path = @raw_output_dir / "elasticgraph-config-example.yaml"
      File.write(raw_example_path, content)
      puts "Generated example configuration file for download at #{raw_example_path}"
    end

    def generate_main_documentation!
      config_output_path = @markdown_output_dir / "Configuration.md"
      content = build_markdown_content
      File.write(config_output_path, content)
      puts "Generated configuration documentation at #{config_output_path}"
    end

    def build_markdown_content
      schema_yaml_content = File.read(@raw_output_dir / "elasticgraph-config-schema.yaml")
      example_yaml_content = File.read(@raw_output_dir / "elasticgraph-config-example.yaml")

      <<~MARKDOWN
        # ElasticGraph Configuration Settings Reference

        ElasticGraph has an extensive configuration system. Configuration settings files conventionally go in `config/settings`:

        ```
        config
        └── settings
            ├── local.yaml
            ├── production.yaml
            └── staging.yaml
        ```

        Different configuration settings files can then be used in different environments.

        This document provides a comprehensive reference for configuring ElasticGraph applications.

        ## Example Configuration Settings

        Here's a complete example configuration settings file with inline comments explaining each section. Alternately, you can
        <a href="elasticgraph-config-example.yaml" download="elasticgraph-config-example.yaml">download this example</a>.

        ```yaml
        #{example_yaml_content}
        ```

        ## Configuration Settings Schema

        ElasticGraph validates configuration settings using the JSON schema shown below. It can also be downloaded as
        <a href="elasticgraph-config-schema.yaml" download="elasticgraph-config-schema.yaml">YAML</a> or
        <a href="elasticgraph-config-schema.json" download="elasticgraph-config-schema.json">JSON</a> for local
        usage (e.g. in an IDE).

        ```yaml
        #{schema_yaml_content}
        ```
      MARKDOWN
    end

    def build_example_config_from_schema(schema, path = [])
      examples = schema.fetch("examples") do
        if schema["type"] == "object" || schema["properties"]
          [build_object_example(schema, path)]
        else
          raise "Missing 'examples' field in schema at path: #{path.join(".")}"
        end
      end

      # Pick the most complete example (treating the size of the example asn indication of its completeness).
      examples.max_by { |e| e.respond_to?(:size) ? e.size : 0 }
    end

    def build_object_example(schema, path)
      if schema.key?("patternProperties")
        raise "Schema at `#{path}` contains `patternProperties`, which we cannot generate an example for. To fix, add `examples` to the parent."
      end

      schema.fetch("properties").to_h do |prop_name, prop_config|
        example_value = build_example_config_from_schema(prop_config, path + [prop_name])
        [prop_name, example_value]
      end
    end

    def build_commented_yaml(config, schema, indent = 0)
      lines = []

      case config
      when Hash
        build_commented_hash(config, schema, lines, indent)
      when Array
        build_commented_array(config, schema, lines, indent)
      else
        lines << "#{" " * indent}#{config.inspect}"
      end

      lines.join("\n")
    end

    def build_commented_hash(config, schema, lines, indent)
      config.each do |key, value|
        prop_schema = find_property_schema(schema, key)

        # Add comment for this property
        if prop_schema
          comment_parts = []

          # Check if this is a required property
          parent_required = find_parent_required_fields(schema, key)
          is_required = parent_required&.include?(key)

          # Add description with optional "Required:" prefix
          if prop_schema["description"]
            description = prop_schema["description"]
            description = "Required. #{description}" if is_required
            comment_parts << description
          elsif is_required
            comment_parts << "Required."
          end

          # Add default value if present
          if prop_schema.key?("default")
            default_value = prop_schema["default"].nil? ? "null" : prop_schema["default"].inspect
            comment_parts << "Default: #{default_value}"
          end

          # Output all comment parts with text wrapping
          comment_parts.each do |comment_part|
            wrapped_lines = wrap_text(comment_part, 100 - indent - 2) # Account for indent and "# "
            wrapped_lines.each do |comment_line|
              lines << "#{" " * indent}# #{comment_line}"
            end
          end
        end

        # Avoid YAML loading errors when dealing with keys that are timestamps: `Tried to load unspecified class: Time`.
        key = "'#{key}'" if timestamp?(key)

        # Add the key-value pair
        if value.is_a?(Hash) && !value.empty?
          lines << "#{" " * indent}#{key}:"
          nested_yaml = build_commented_yaml(value, prop_schema || {}, indent + 2)
          lines.concat(nested_yaml.split("\n").reject(&:empty?))
        elsif value.is_a?(Array) && !value.empty?
          lines << "#{" " * indent}#{key}:"
          nested_yaml = build_commented_yaml(value, prop_schema || {}, indent + 2)
          lines.concat(nested_yaml.split("\n").reject(&:empty?))
        else
          lines << "#{" " * indent}#{key}: #{value.inspect}"
        end

        lines << "" # Add blank line between sections
      end
    end

    def timestamp?(key)
      ::Time.iso8601(key)
      true
    rescue ::ArgumentError
      false
    end

    def build_commented_array(config, schema, lines, indent)
      config.each_with_index do |item, index|
        item_schema = schema.dig("items") || {}

        if item.is_a?(Hash)
          lines << "#{" " * indent}- # Array item #{index + 1}"
          nested_yaml = build_commented_yaml(item, item_schema, indent + 2)
          lines.concat(nested_yaml.split("\n").reject(&:empty?))
        else
          lines << "#{" " * indent}- #{item.inspect}"
        end
      end
    end

    def find_property_schema(schema, key)
      return nil unless schema.is_a?(Hash)

      # Check regular properties first
      if schema.dig("properties", key)
        return schema["properties"][key]
      end

      # Check pattern properties
      schema["patternProperties"]&.each do |pattern, pattern_schema|
        if key.match?(Regexp.new(pattern))
          return pattern_schema
        end
      end

      nil
    end

    def find_parent_required_fields(schema, key)
      return nil unless schema.is_a?(Hash)

      # Check if this key is in the required array at this level
      return schema["required"] if schema["required"]

      # For pattern properties, we need to check if the pattern itself has required fields
      schema["patternProperties"]&.each do |pattern, pattern_schema|
        if key.match?(Regexp.new(pattern))
          return pattern_schema["required"]
        end
      end

      nil
    end

    def wrap_text(text, max_width)
      return [text] if text.length <= max_width

      words = text.split(/\s+/)
      lines = []
      current_line = ""

      words.each do |word|
        # If adding this word would exceed the max width, start a new line
        if !current_line.empty? && (current_line.length + 1 + word.length) > max_width
          lines << current_line
          current_line = word
        else
          current_line = current_line.empty? ? word : "#{current_line} #{word}"
        end
      end

      # Add the last line if it's not empty
      lines << current_line unless current_line.empty?
      lines
    end

    def validate_example_config!(example_config)
      validator = Support::JSONSchema::Validator.new(
        schema: ::JSONSchemer.schema(@schema, meta_schema: @schema.fetch("$schema")),
        sanitize_pii: false
      )

      if (error_message = validator.validate_with_error_message(example_config))
        raise "Generated example configuration is invalid according to the JSON schema:\n\n#{error_message}"
      end

      puts "✓ Generated example configuration is valid according to the JSON schema"
    end
  end
end

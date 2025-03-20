# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "digest/md5"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"
require "elastic_graph/schema_definition/test_support"
require "support/validate_script_support"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.shared_context "ScriptSupport" do
      include TestSupport
      include ValidateScriptSupport

      def expect_script(script_id, prefix, payload, expected_source)
        expect(script_id).to eq("#{prefix}_#{Digest::MD5.hexdigest(expected_source)}")

        expect(payload.fetch("context")).to eq("update")
        expect(payload.fetch("script")).to match("lang" => "painless", "source" => an_instance_of(::String))
        expect(payload.dig("script", "source")).to eq(expected_source)
      end

      def generate_script_artifacts(source_type, target_type, prefix: "update_#{target_type}_from_#{source_type}", &schema_definition)
        results = define_schema(&schema_definition)
        scripts = results.datastore_scripts.select { |id, payload| payload.fetch("context") == "update" }
        scripts.each { |id, payload| validate_script(id, payload) }

        update_targets_by_type = results.runtime_metadata
          .object_types_by_name
          .transform_values(&:update_targets)

        # Filter scripts to just the one for the given destination_type and source_type, so that we ignore other scripts.
        scripts = scripts.select { |k, v| k.start_with?(prefix) }
        update_targets = update_targets_by_type.fetch(source_type).select { |ut| ut.type == target_type }

        expect(scripts.size).to be < 2
        expect(update_targets.size).to be < 2

        script_id, script_contents = scripts.first
        [script_id, script_contents, update_targets.first]
      end

      def define_schema(&block)
        super(schema_element_name_form: "snake_case")
      end
    end

    RSpec.shared_context "widget currency script support", :uses_datastore do |expected_function_defs: []|
      include_context "ScriptSupport"

      define_method :expect_widget_currency_script do |script_id, payload, expected_source_except_functions|
        parts = expected_function_defs + [Indexing::DerivedIndexedType::STATIC_SETUP_STATEMENTS + "\n" + expected_source_except_functions]
        expected_source = parts.map(&:strip).join("\n\n")
        expect_script(script_id, "update_WidgetCurrency_from_Widget", payload, expected_source)
      end

      def script_artifacts_for_widget_currency_from(type_name, ...)
        generate_script_artifacts("Widget", "WidgetCurrency") do |schema|
          # Ensure `WidgetCurrency` is defined as the caller defines deriviation rules for it.
          schema.object_type "WidgetCurrency" do |t|
            t.field "id", "ID!"
            t.index "widget_currencies"
          end

          schema.object_type(type_name, ...)
        end
      end
    end
  end
end

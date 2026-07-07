# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/config"
require "yaml"

module ElasticGraph
  class Indexer
    RSpec.describe Config do
      it "raises an error when given an unrecognized config setting" do
        expect {
          Config.from_parsed_yaml("indexer" => {
            "latency_slo_thresholds_by_timestamp_in_ms" => {},
            "fake_setting" => 23
          })
        }.to raise_error Errors::ConfigError, a_string_including("fake_setting")
      end

      it "converts the values of `skip_derived_indexing_type_updates` to a set" do
        config = Config.from_parsed_yaml("indexer" => {
          "latency_slo_thresholds_by_timestamp_in_ms" => {},
          "skip_derived_indexing_type_updates" => {
            "WidgetCurrency" => ["USD"]
          }
        })

        expect(config.skip_derived_indexing_type_updates).to eq("WidgetCurrency" => ["USD"].to_set)
      end

      describe "#extension_modules", :in_temp_dir do
        it "loads the extension modules from disk" do
          File.write("eg_extension_module1.rb", <<~EOS)
            module EgExtensionModule1
            end
          EOS

          File.write("eg_extension_module2.rb", <<~EOS)
            module EgExtensionModule2
            end
          EOS

          extension_modules = extension_modules_from(<<~YAML)
            extension_modules:
              - require_path: ./eg_extension_module1
                name: EgExtensionModule1
              - require_path: ./eg_extension_module2
                name: EgExtensionModule2
          YAML

          expect(extension_modules).to eq([::EgExtensionModule1, ::EgExtensionModule2])
        end

        it "raises a clear error if the config is malformed" do
          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require: ./not_real
                  name: NotReal
            YAML
          }.to raise_error a_string_including("require_path")

          File.write("eg_extension_module1.rb", <<~EOS)
            module EgExtensionModule1
            end
          EOS

          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require_path: ./eg_extension_module1
                  extension: EgExtensionModule1
            YAML
          }.to raise_error a_string_including("name")
        end

        def extension_modules_from(yaml)
          Config.from_parsed_yaml("indexer" => ::YAML.safe_load(yaml)).extension_modules
        end
      end
    end
  end
end

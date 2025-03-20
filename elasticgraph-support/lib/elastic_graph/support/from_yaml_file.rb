# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "yaml"

module ElasticGraph
  # Provides support utilities for the rest of the ElasticGraph gems. As such, it is not intended
  # to provide public APIs for ElasticGraph users.
  module Support
    # @private
    module FromYamlFile
      # Factory method that will build an instance from the provided `yaml_file`.
      # `datastore_client_customization_block:` can be passed to customize the datastore clients.
      # In addition, a block is accepted that can prepare the settings before the object is built
      # (e.g. to override specific settings).
      def from_yaml_file(yaml_file, datastore_client_customization_block: nil)
        parsed_yaml = ::YAML.safe_load_file(yaml_file, aliases: true)
        parsed_yaml = yield(parsed_yaml) if block_given?
        from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      end

      # An extension module that provides a `from_yaml_file` factory method on a `RakeTasks` class.
      #
      # This is designed for a `RakeTasks` class that needs an ElasticGraph component (e.g. an
      # `ElasticGraph::GraphQL`, `ElasticGraph::Admin`, or `ElasticGraph::Indexer` instance).
      # When the schema artifacts are out of date, loading those components can fail. This gracefully
      # handles that for you, giving you clear instructions of what to do when this happens.
      #
      # This requires the `RakeTasks` class to accept the ElasticGraph component instance via a block
      # so that it happens lazily.
      class ForRakeTasks < ::Module
        # @dynamic from_yaml_file

        def initialize(component_class)
          define_method :from_yaml_file do |yaml_file, *args, **options|
            __skip__ = new(*args, **options) do
              component_class.from_yaml_file(yaml_file)
            rescue => e
              raise <<~EOS
                Failed to load `#{component_class}` with `#{yaml_file}`. This can happen if the schema artifacts are out of date.
                Run `rake schema_artifacts:dump` and try again.

                #{e.class}: #{e.message}
              EOS
            end
          end
        end
      end
    end
  end
end

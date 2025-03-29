# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/interface_verifier"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Responsible for loading extensions. This loader requires an interface definition
      # (a class or module with empty method definitions that just serves to define what
      # loaded extensions must implement). That allows us to verify the extension implements
      # the interface correctly at load time, rather than deferring exceptions to when the
      # extension is later used.
      #
      # Note, however, that this does not guarantee no runtime exceptions from the use of the
      # extension: the extension may return invalid return values, or throw exceptions when
      # called. But this verifies the interface to the extent that we can.
      class ExtensionLoader
        def initialize(interface_def)
          @interface_def = interface_def
          @loaded_by_name = {}
        end

        # Loads the extension using the provided constant name, after requiring the `from` path.
        # Memoizes the result.
        def load(constant_name, from:, config:)
          (@loaded_by_name[constant_name] ||= load_extension(constant_name, from)).tap do |extension|
            if extension.require_path != from
              raise Errors::InvalidExtensionError, "Extension `#{constant_name}` cannot be loaded from `#{from}`, " \
                "since it has already been loaded from `#{extension.require_path}`."
            end
          end.with(extension_config: config)
        end

        private

        def load_extension(constant_name, require_path)
          require require_path
          extension_class = ::Object.const_get(constant_name)
          Extension.new(extension_class, require_path, {}, constant_name.delete_prefix("::")).tap do |ext|
            ext.verify_against!(@interface_def)
          end
        end
      end
    end
  end
end

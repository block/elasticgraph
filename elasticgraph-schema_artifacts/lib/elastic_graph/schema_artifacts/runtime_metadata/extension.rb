# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/interface_verifier"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Represents an extension--a class or module (potentially from outside the ElasticGraph
      # code base) that implements a standard interface to plug in custom functionality.
      #
      # Extensions are serialized using two fields:
      # - `extension_name`: the Ruby constant of the extension
      # - `require_path`: file path to `require` to load the extension
      #
      # However, an `Extension` instance represents a loaded, resolved extension.
      # We eagerly load extensions (and validate them in the `ExtensionLoader`) in
      # order to surface any issues with the extension as soon as possible. We don't
      # want to defer errors if we can detect any issues with the extension at boot time.
      Extension = ::Data.define(:extension_class, :require_path, :extension_config, :extension_name) do
        # @implements Extension
        def initialize(extension_class:, require_path:, extension_config:, extension_name: extension_class.name.to_s)
          super(extension_class:, require_path:, extension_config:, extension_name:)
        end

        # Loads an extension using a serialized hash, via the provided `ExtensionLoader`.
        def self.load_from_hash(hash, via:)
          config = Support::HashUtil.symbolize_keys(hash["extension_config"] || {}) # : ::Hash[::Symbol, untyped]
          via.load(hash.fetch("extension_name"), from: hash.fetch("require_path"), config: config)
        end

        # The serialized form of an extension.
        def to_dumpable_hash
          # Keys here are ordered alphabetically; please keep them that way.
          {
            "extension_config" => Support::HashUtil.stringify_keys(extension_config),
            "extension_name" => extension_name,
            "require_path" => require_path
          }.reject { |_, v| v.empty? }
        end

        def verify_against(interface_def)
          InterfaceVerifier.verify(extension_class, against: interface_def, constant_name: extension_name)
        end
      end
    end
  end
end

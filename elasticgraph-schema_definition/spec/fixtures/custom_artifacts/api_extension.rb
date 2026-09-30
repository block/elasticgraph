# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "provider"

module CustomArtifactsExample
  module APIExtension
    def self.extended(api)
      api.register_schema_artifact_extension "example/custom", Artifacts,
        defined_at: File.expand_path("provider.rb", __dir__), label: "custom format"
      api.factory.extend(FactoryExtension)
    end
  end

  module FactoryExtension
    def new_schema_artifact_manager(...)
      super.tap { |manager| manager.extend(ArtifactManagerExtension) }
    end
  end

  module ArtifactManagerExtension
    def artifacts_from_schema_def
      provider = schema_definition_results.extension_artifacts.fetch("example/custom")
      super + [new_yaml_artifact("custom_types.yaml", provider.type_names)]
    end
  end
end

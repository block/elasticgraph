# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::SchemaArtifact} that replaces the standard
      # "DO NOT EDIT BY HAND" preamble on `proto_field_numbers.yaml`. Unlike the proper schema artifacts,
      # the file is an input to schema generation: it may be updated by hand and, after generated protos
      # have been used, must not be deleted and regenerated.
      #
      # @private
      module SchemaArtifactExtension
        private

        def comment_preamble
          [
            "This file is part of your schema definition--not a regenerable schema artifact. It is an",
            "input to `schema.proto` generation: ElasticGraph reads it to keep protobuf field and enum",
            "value numbers stable as your schema evolves, and `rake schema_artifacts:dump` maintains it",
            "for you.",
            "",
            "You may update it by hand (e.g. to assign a specific number). While prototyping, you may",
            "delete this file and regenerate it to reset the number assignments.",
            "",
            "Once generated protos have been used to serialize data or consumed by another codebase,",
            "you must NOT delete this file and regenerate it. The original number assignments would be",
            "lost, and previously serialized protobuf messages would be misread."
          ].map { |line| "#{comment_prefix} #{line}".rstrip }.join("\n")
        end
      end
    end
  end
end

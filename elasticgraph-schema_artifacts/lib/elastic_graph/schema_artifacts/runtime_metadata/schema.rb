# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/enum"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"
require "elastic_graph/schema_artifacts/runtime_metadata/hash_dumper"
require "elastic_graph/schema_artifacts/runtime_metadata/index_definition"
require "elastic_graph/schema_artifacts/runtime_metadata/object_type"
require "elastic_graph/schema_artifacts/runtime_metadata/scalar_type"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Entry point for runtime metadata for an entire schema.
      class Schema < ::Data.define(
        :object_types_by_name,
        :scalar_types_by_name,
        :enum_types_by_name,
        :index_definitions_by_name,
        :schema_element_names,
        :graphql_extension_modules,
        :graphql_resolvers_by_name,
        :static_script_ids_by_scoped_name
      )
        OBJECT_TYPES_BY_NAME = "object_types_by_name"
        SCALAR_TYPES_BY_NAME = "scalar_types_by_name"
        ENUM_TYPES_BY_NAME = "enum_types_by_name"
        INDEX_DEFINITIONS_BY_NAME = "index_definitions_by_name"
        SCHEMA_ELEMENT_NAMES = "schema_element_names"
        GRAPHQL_EXTENSION_MODULES = "graphql_extension_modules"
        GRAPHQL_RESOLVERS_BY_NAME = "graphql_resolvers_by_name"
        STATIC_SCRIPT_IDS_BY_NAME = "static_script_ids_by_scoped_name"

        def self.from_hash(hash, for_context:)
          object_types_by_name = hash[OBJECT_TYPES_BY_NAME]&.transform_values do |type_hash|
            ObjectType.from_hash(type_hash)
          end || {}

          scalar_types_by_name = hash[SCALAR_TYPES_BY_NAME]&.then do |subhash|
            ScalarType.load_many(subhash)
          end || {}

          enum_types_by_name = hash[ENUM_TYPES_BY_NAME]&.transform_values do |type_hash|
            Enum::Type.from_hash(type_hash)
          end || {}

          index_definitions_by_name = hash[INDEX_DEFINITIONS_BY_NAME]&.transform_values do |index_hash|
            IndexDefinition.from_hash(index_hash)
          end || {}

          schema_element_names = SchemaElementNames.from_hash(hash.fetch(SCHEMA_ELEMENT_NAMES))

          extension_loader = ExtensionLoader.new(Module.new)
          graphql_extension_modules =
            if for_context == :graphql
              hash[GRAPHQL_EXTENSION_MODULES]&.map do |ext_mod_hash|
                Extension.load_from_hash(ext_mod_hash, via: extension_loader)
              end || []
            else
              # Avoid loading GraphQL extension modules if we're not in a GraphQL context. We can't count
              # on the extension modules even being available to load in other contexts.
              [] # : ::Array[Extension]
            end

          graphql_resolvers_by_name =
            if for_context == :graphql
              require "elastic_graph/graphql/resolvers/interface"
              resolver_loader = ExtensionLoader.new(GraphQL::Resolvers::Interface)
              hash[GRAPHQL_RESOLVERS_BY_NAME]&.to_h do |name, resolver_hash|
                [name.to_sym, Extension.load_from_hash(resolver_hash, via: resolver_loader)]
              end || {}
            else
              # Avoid loading GraphQL resolvers if we're not in a GraphQL context. We can't count
              # on the resolvers even being available to load in other contexts.
              {} # : ::Hash[::Symbol, Extension]
            end

          static_script_ids_by_scoped_name = hash[STATIC_SCRIPT_IDS_BY_NAME] || {}

          new(
            object_types_by_name: object_types_by_name,
            scalar_types_by_name: scalar_types_by_name,
            enum_types_by_name: enum_types_by_name,
            index_definitions_by_name: index_definitions_by_name,
            schema_element_names: schema_element_names,
            graphql_extension_modules: graphql_extension_modules,
            graphql_resolvers_by_name: graphql_resolvers_by_name,
            static_script_ids_by_scoped_name: static_script_ids_by_scoped_name
          )
        end

        def to_dumpable_hash
          Support::HashUtil.recursively_prune_nils_and_empties_from({
            # Keys here are ordered alphabetically; please keep them that way.
            ENUM_TYPES_BY_NAME => HashDumper.dump_hash(enum_types_by_name, &:to_dumpable_hash),
            GRAPHQL_EXTENSION_MODULES => graphql_extension_modules.map(&:to_dumpable_hash),
            GRAPHQL_RESOLVERS_BY_NAME => HashDumper.dump_hash(graphql_resolvers_by_name.transform_keys(&:to_s), &:to_dumpable_hash),
            INDEX_DEFINITIONS_BY_NAME => HashDumper.dump_hash(index_definitions_by_name, &:to_dumpable_hash),
            OBJECT_TYPES_BY_NAME => HashDumper.dump_hash(object_types_by_name, &:to_dumpable_hash),
            SCALAR_TYPES_BY_NAME => HashDumper.dump_hash(scalar_types_by_name, &:to_dumpable_hash),
            SCHEMA_ELEMENT_NAMES => schema_element_names.to_dumpable_hash,
            STATIC_SCRIPT_IDS_BY_NAME => static_script_ids_by_scoped_name
          })
        end
      end
    end
  end
end

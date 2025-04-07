# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Provides runtime metadata related to scalar types.
      class ScalarType < ::Data.define(:coercion_adapter_ref, :indexing_preparer_ref)
        def self.coercion_adapter_extension_loader
          @coercion_adapter_extension_loader ||= ExtensionLoader.new(ScalarCoercionAdapterInterface)
        end

        def self.indexing_preparer_extension_loader
          @indexing_preparer_extension_loader ||= ExtensionLoader.new(ScalarIndexingPreparerInterface)
        end

        DEFAULT_COERCION_ADAPTER_REF = {
          "name" => "ElasticGraph::GraphQL::ScalarCoercionAdapters::NoOp",
          "require_path" => "elastic_graph/graphql/scalar_coercion_adapters/no_op"
        }

        DEFAULT_INDEXING_PREPARER_REF = {
          "name" => "ElasticGraph::Indexer::IndexingPreparers::NoOp",
          "require_path" => "elastic_graph/indexer/indexing_preparers/no_op"
        }

        # Loads multiple `ScalarType`s from a hash mapping a scalar type name to its
        # serialized hash form (matching what `to_dumpable_hash` returns). We expose a method
        # this way because we want to use a single loader for all `ScalarType`s that
        # need to get loaded, as it performs some caching for efficiency.
        def self.load_many(scalar_type_hashes_by_name)
          scalar_type_hashes_by_name.transform_values do |hash|
            new(
              coercion_adapter_ref: hash.fetch("coercion_adapter"),
              # `indexing_preparer` is new as of Q4 2022, and as such is not present in schema artifacts
              # dumped before then. Therefore, we allow for the key to not be present in the runtime
              # metadata--important so that we don't have a "chicken and egg" problem where the rake tasks
              # that need to be loaded to dump new schema artifacts fail at load time due to the missing key.
              indexing_preparer_ref: hash.fetch("indexing_preparer", DEFAULT_INDEXING_PREPARER_REF)
            )
          end
        end

        # Loads the coercion adapter. This is done lazily on first access (rather than eagerly in `load_many`)
        # to allow us to remove a runtime dependency of `elasticgraph-schema_artifacts` on `elasticgraph-graphql`.
        # The built-in coercion adapters are defined in `elasticgraph-graphql`, and we want to be able to load
        # runtime metadata without requiring the `elasticgraph-graphql` gem (and its dependencies) to be available.
        # For example, we use runtime metadata from `elasticgraph-indexer` but do not want `elasticgraph-graphql`
        # to be loaded as part of that.
        #
        # elasticgraph-graphql provides the one caller that calls this method, ensuring that the adapters are
        # available to be loaded.
        def load_coercion_adapter
          Extension.load_from_hash(coercion_adapter_ref, via: self.class.coercion_adapter_extension_loader)
        end

        def load_indexing_preparer
          Extension.load_from_hash(indexing_preparer_ref, via: self.class.indexing_preparer_extension_loader)
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            "coercion_adapter" => load_coercion_adapter.to_dumpable_hash,
            "indexing_preparer" => load_indexing_preparer.to_dumpable_hash
          }
        end

        # `to_h` is used internally by `Value#with` and we want `#to_dumpable_hash` to be the public API.
        private :to_h
      end

      class ScalarCoercionAdapterInterface
        def self.coerce_input(value, ctx)
        end

        def self.coerce_result(value, ctx)
        end
      end

      class ScalarIndexingPreparerInterface
        def self.prepare_for_indexing(value)
        end
      end
    end
  end
end
